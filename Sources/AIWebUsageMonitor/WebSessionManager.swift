import AppKit
import Foundation
import WebKit

enum WebSessionManagerError: LocalizedError {
    case missingSession
    case navigationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "웹 세션을 찾지 못했습니다."
        case .navigationFailed(let message):
            return "웹 페이지 로드 실패: \(message)"
        }
    }
}

@MainActor
final class WebSessionManager {
    private static let hiddenViewport = CGRect(x: 0, y: 0, width: 1440, height: 960)
    private static let backgroundHostWindow: NSWindow = {
        let window = NSWindow(
            contentRect: hiddenViewport,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.001
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderOut(nil)
        return window
    }()

    private static func attachToBackgroundHost(_ webView: WKWebView) {
        guard let contentView = backgroundHostWindow.contentView else {
            return
        }

        if webView.superview !== contentView {
            webView.removeFromSuperview()
            webView.frame = hiddenViewport
            webView.autoresizingMask = [.width, .height]
            contentView.addSubview(webView)
        }
    }

    @MainActor
    private final class ManagedWebSession {
        let account: WebAccountSession
        let dataStore: WKWebsiteDataStore
        let backgroundWebView: WKWebView
        let navigationDelegate = WebNavigationDelegate()
        var loginWindowController: LoginWindowController?

        init(account: WebAccountSession) {
            self.account = account
            self.dataStore = WKWebsiteDataStore(forIdentifier: account.dataStoreID)

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            configuration.userContentController = WKUserContentController()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: PlatformScraper.bootstrapJavaScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
            )

            self.backgroundWebView = WKWebView(
                frame: WebSessionManager.hiddenViewport,
                configuration: configuration
            )
            self.backgroundWebView.navigationDelegate = navigationDelegate
            WebSessionManager.attachToBackgroundHost(self.backgroundWebView)
        }
    }

    @MainActor
    private final class WebNavigationDelegate: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func prepare(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private var sessions: [UUID: ManagedWebSession] = [:]

    func register(account: WebAccountSession) {
        guard sessions[account.id] == nil else {
            return
        }

        sessions[account.id] = ManagedWebSession(account: account)
    }

    func presentLoginWindow(
        for account: WebAccountSession,
        onAuthenticated: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) throws {
        guard let session = sessions[account.id] else {
            throw WebSessionManagerError.missingSession
        }

        if let windowController = session.loginWindowController {
            windowController.onAuthenticated = onAuthenticated
            windowController.onClose = onClose
            windowController.present()
            return
        }

        let windowController = LoginWindowController(account: account, dataStore: session.dataStore)
        windowController.onAuthenticated = onAuthenticated
        windowController.onClose = { [weak self, weak windowController] in
            onClose()
            guard let self else { return }
            if let current = self.sessions[account.id], current.loginWindowController === windowController {
                current.loginWindowController = nil
            }
        }
        session.loginWindowController = windowController
        windowController.present()
    }

    func unregister(accountID: UUID, dataStoreID: UUID, removeDataStore: Bool) async {
        if let session = sessions.removeValue(forKey: accountID) {
            session.loginWindowController?.close()
        }

        guard removeDataStore else {
            return
        }

        do {
            try await WKWebsiteDataStore.remove(forIdentifier: dataStoreID)
        } catch {
            // 데이터스토어 정리 실패는 사용자 동작을 막지 않는다.
        }
    }

    func refreshUsage(for account: WebAccountSession) async throws -> PlatformScrapePayload {
        guard let session = sessions[account.id] else {
            throw WebSessionManagerError.missingSession
        }

        let adapter = PlatformRegistry.adapter(for: account.platform)
        let scraper = adapter.makeScraper()
        WebSessionManager.attachToBackgroundHost(session.backgroundWebView)
        try await load(url: adapter.dashboardURL, in: session)

        _ = try await evaluateJavaScript(PlatformScraper.bootstrapJavaScript, in: session.backgroundWebView)
        try await waitForMeaningfulContent(
            hints: adapter.usageTextHints,
            in: session.backgroundWebView
        )
        try await performPreExtractionInteractions(
            scripts: adapter.preExtractionScripts,
            in: session.backgroundWebView
        )

        var payload = try await scrapePayload(with: scraper, in: session.backgroundWebView)
        if payload.looksLikePlaceholderContent {
            try await Task.sleep(for: .seconds(2))
            payload = try await scrapePayload(with: scraper, in: session.backgroundWebView)
        }

        payload = try await waitForUsageData(
            initialPayload: payload,
            scraper: scraper,
            usageHints: adapter.usageTextHints,
            webView: session.backgroundWebView
        )

        if payload.quotaEntries.isEmpty, let loginWebView = session.loginWindowController?.webView {
            payload = try await fallbackToVisibleWebView(
                initialPayload: payload,
                scraper: scraper,
                usageHints: adapter.usageTextHints,
                webView: loginWebView
            )
        }

        return payload
    }

    private func load(url: URL, in session: ManagedWebSession) async throws {
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )

        try await withCheckedThrowingContinuation { continuation in
            session.navigationDelegate.prepare(continuation)
            session.backgroundWebView.load(request)
        }
    }

    private func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    private func scrapePayload(with scraper: PlatformScraper, in webView: WKWebView) async throws -> PlatformScrapePayload {
        let rawValue = try await evaluateJavaScript(scraper.extractionJavaScript, in: webView)
        return try scraper.decodePayload(from: rawValue)
    }

    private func performPreExtractionInteractions(
        scripts: [String],
        in webView: WKWebView
    ) async throws {
        guard !scripts.isEmpty else {
            return
        }

        for script in scripts {
            _ = try await evaluateJavaScript(script, in: webView)
            try await Task.sleep(for: .milliseconds(700))
        }
    }

    private func waitForUsageData(
        initialPayload: PlatformScrapePayload,
        scraper: PlatformScraper,
        usageHints: [String],
        webView: WKWebView
    ) async throws -> PlatformScrapePayload {
        var payload = initialPayload
        let deadline = Date().addingTimeInterval(15)

        while Date() < deadline {
            if !payload.quotaEntries.isEmpty && !payload.isLoadingUsageData {
                return payload
            }

            try await stimulateUsageRendering(hints: usageHints, in: webView)
            try await Task.sleep(for: .seconds(1))
            payload = try await scrapePayload(with: scraper, in: webView)
        }

        return payload
    }

    private func fallbackToVisibleWebView(
        initialPayload: PlatformScrapePayload,
        scraper: PlatformScraper,
        usageHints: [String],
        webView: WKWebView
    ) async throws -> PlatformScrapePayload {
        try await stimulateUsageRendering(hints: usageHints, in: webView)
        try await Task.sleep(for: .milliseconds(600))
        let visiblePayload = try await scrapePayload(with: scraper, in: webView)
        return visiblePayload.quotaEntries.isEmpty ? initialPayload : visiblePayload
    }

    private func stimulateUsageRendering(hints: [String], in webView: WKWebView) async throws {
        let hintData = try? JSONSerialization.data(withJSONObject: hints)
        let hintJSON = String(data: hintData ?? Data("[]".utf8), encoding: .utf8) ?? "[]"

        let script = #"""
        (() => {
          const hints = \#(hintJSON);
          const elements = Array.from(document.querySelectorAll("section, article, div, li"));
          const target = elements.find((element) => {
            const text = (element.innerText || "").replace(/\s+/g, " ").trim().toLowerCase();
            return hints.some((hint) => text.includes(String(hint).toLowerCase()));
          });

          window.dispatchEvent(new Event("resize"));
          document.dispatchEvent(new Event("visibilitychange"));

          if (target) {
            target.scrollIntoView({ block: "center" });
            return true;
          }

          const height = Math.max(
            document.body?.scrollHeight || 0,
            document.documentElement?.scrollHeight || 0
          );
          if (height > 0) {
            window.scrollTo(0, Math.min(height * 0.35, Math.max(0, height - 600)));
          }
          return false;
        })();
        """#

        _ = try await evaluateJavaScript(script, in: webView)
    }

    private func waitForMeaningfulContent(
        hints: [String],
        in webView: WKWebView
    ) async throws {
        let hintData = try? JSONSerialization.data(withJSONObject: hints)
        let hintJSON = String(data: hintData ?? Data("[]".utf8), encoding: .utf8) ?? "[]"

        let readinessScript = #"""
        (() => {
          const hints = \#(hintJSON);
          const text = (document.body?.innerText || "").replace(/\s+/g, " ").trim();
          const lowered = text.toLowerCase();
          const responses = (window.__aiUsageMonitor?.responses || []).length;
          const placeholders = [
            "skip to content",
            "open sidebar",
            "콘텐츠로 건너뛰기",
            "사이드바 열기"
          ];
          const reduced = placeholders.reduce(
            (current, item) => current.split(item).join(" "),
            lowered
          ).replace(/\s+/g, " ").trim();
          const placeholderOnly = text.length > 0 && reduced.length === 0;
          const hasHints = hints.some((hint) => lowered.includes(String(hint).toLowerCase()));

          return {
            readyState: document.readyState,
            textLength: text.length,
            responseCount: responses,
            placeholderOnly,
            hasHints
          };
        })();
        """#

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            guard let dictionary = try await evaluateJavaScript(readinessScript, in: webView) as? [String: Any] else {
                try await Task.sleep(for: .milliseconds(500))
                continue
            }

            let readyState = dictionary["readyState"] as? String ?? ""
            let textLength = dictionary["textLength"] as? Int ?? 0
            let responseCount = dictionary["responseCount"] as? Int ?? 0
            let placeholderOnly = dictionary["placeholderOnly"] as? Bool ?? false
            let hasHints = dictionary["hasHints"] as? Bool ?? false

            if readyState == "complete", !placeholderOnly, (hasHints || textLength >= 120 || responseCount > 2) {
                return
            }

            try await Task.sleep(for: .milliseconds(750))
        }
    }
}
