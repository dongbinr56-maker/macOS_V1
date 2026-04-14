import AppKit
import WebKit

@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onClose: (() -> Void)?
    var onAuthenticated: (() -> Void)?

    private let account: WebAccountSession
    private var hasSentAuthenticatedEvent = false

    init(account: WebAccountSession, dataStore: WKWebsiteDataStore) {
        self.account = account

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController = WKUserContentController()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1180, height: 820),
            configuration: configuration
        )
        self.webView = webView

        let contentViewController = NSViewController()
        contentViewController.view = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(account.displayName) 로그인"
        window.contentViewController = contentViewController
        window.center()

        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: account.platform.loginURL))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluateAuthenticationState()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }

        return nil
    }

    private func evaluateAuthenticationState() {
        guard !hasSentAuthenticatedEvent else {
            return
        }

        let hintsData = try? JSONSerialization.data(withJSONObject: account.platform.loginHints)
        let hintsJSON = String(data: hintsData ?? Data("[]".utf8), encoding: .utf8) ?? "[]"

        let script = #"""
        (() => {
          const text = (document.body?.innerText || "").replace(/\s+/g, " ").toLowerCase();
          const hints = \#(hintsJSON);
          const hasLoginHint = hints.some(hint => text.includes(hint));
          const href = location.href.toLowerCase();
          const looksLikeAuth = /login|signin|auth|accounts/.test(href);
          return !(looksLikeAuth || hasLoginHint);
        })();
        """#

        Task { @MainActor in
            let result = try? await webView.evaluateJavaScript(script) as? Bool
            guard result == true else {
                return
            }

            hasSentAuthenticatedEvent = true
            onAuthenticated?()
        }
    }
}
