import Foundation

enum PlatformScraperError: LocalizedError {
    case invalidJavaScriptResult

    var errorDescription: String? {
        switch self {
        case .invalidJavaScriptResult:
            return "스크래핑 결과를 해석하지 못했습니다."
        }
    }
}

protocol PlatformAdapter {
    var platform: AIPlatform { get }
    var loginURL: URL { get }
    var dashboardURL: URL { get }
    var loginHints: [String] { get }
    var usageTextHints: [String] { get }
    var primaryQuotaGroups: [QuotaLabelGroup] { get }
    var preExtractionScripts: [String] { get }

    func makeScraper() -> PlatformScraper
    func isReliableSnapshot(_ snapshot: UsageSnapshot) -> Bool
}

struct PlatformRegistry {
    static func adapter(for platform: AIPlatform) -> any PlatformAdapter {
        switch platform {
        case .codex:
            return CodexPlatformAdapter()
        case .claude:
            return ClaudePlatformAdapter()
        case .cursor:
            return CursorPlatformAdapter()
        }
    }
}

struct CodexPlatformAdapter: PlatformAdapter {
    let platform: AIPlatform = .codex
    var loginURL: URL { platform.loginURL }
    var dashboardURL: URL { platform.dashboardURL }
    var loginHints: [String] { platform.loginHints }
    var usageTextHints: [String] { platform.usageTextHints }
    var primaryQuotaGroups: [QuotaLabelGroup] { platform.primaryQuotaGroups }
    var preExtractionScripts: [String] { [] }

    func makeScraper() -> PlatformScraper {
        PlatformScraper(
            platform: platform,
            extractionJavaScript: PlatformScraper.makeExtractionJavaScript(
                platform: platform,
                labelGroups: primaryQuotaGroups
            )
        )
    }

    func isReliableSnapshot(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.hasUsableQuotaData(for: platform)
    }
}

struct ClaudePlatformAdapter: PlatformAdapter {
    let platform: AIPlatform = .claude
    var loginURL: URL { platform.loginURL }
    var dashboardURL: URL { platform.dashboardURL }
    var loginHints: [String] { platform.loginHints }
    var usageTextHints: [String] { platform.usageTextHints }
    var primaryQuotaGroups: [QuotaLabelGroup] { platform.primaryQuotaGroups }
    var preExtractionScripts: [String] { [] }

    func makeScraper() -> PlatformScraper {
        PlatformScraper(
            platform: platform,
            extractionJavaScript: PlatformScraper.makeExtractionJavaScript(
                platform: platform,
                labelGroups: primaryQuotaGroups
            )
        )
    }

    func isReliableSnapshot(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.hasUsableQuotaData(for: platform)
    }
}

struct CursorPlatformAdapter: PlatformAdapter {
    let platform: AIPlatform = .cursor
    var loginURL: URL { platform.loginURL }
    var dashboardURL: URL { platform.dashboardURL }
    var loginHints: [String] { platform.loginHints }
    var usageTextHints: [String] { platform.usageTextHints }
    var primaryQuotaGroups: [QuotaLabelGroup] { platform.primaryQuotaGroups }
    var preExtractionScripts: [String] { [] }

    func makeScraper() -> PlatformScraper {
        PlatformScraper(
            platform: platform,
            extractionJavaScript: PlatformScraper.makeExtractionJavaScript(
                platform: platform,
                labelGroups: primaryQuotaGroups
            )
        )
    }

    func isReliableSnapshot(_ snapshot: UsageSnapshot) -> Bool {
        !snapshot.quota.entries.isEmpty
    }
}

struct PlatformScraper {
    let platform: AIPlatform
    let extractionJavaScript: String

    static let bootstrapJavaScript = #"""
    (() => {
      if (window.__aiUsageMonitorInstalled) {
        return true;
      }

      const nowISO = () => new Date().toISOString();
      const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();

      window.__aiUsageMonitorInstalled = true;
      window.__aiUsageMonitor = {
        responses: [],
        requests: [],
        inFlightRequestCount: 0,
        lastNetworkAt: null,
        lastDOMMutationAt: null,
        pageBusyState: document.readyState === "complete" ? "ready" : "loading",
        markRequest(url, body) {
          try {
            this.lastNetworkAt = nowISO();
            this.requests.push(nowISO());
            this.responses.push({
              url: String(url || ""),
              body: String(body || "").slice(0, 4000),
              capturedAt: nowISO()
            });
            this.requests = this.requests.slice(-50);
            this.responses = this.responses.slice(-20);
          } catch (_) {}
        },
        setBusyState(nextState) {
          this.pageBusyState = String(nextState || "unknown");
        }
      };

      const observer = new MutationObserver(() => {
        window.__aiUsageMonitor.lastDOMMutationAt = nowISO();
      });

      const startObserving = () => {
        if (document.body) {
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true
          });
        }
      };

      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", startObserving, { once: true });
      } else {
        startObserving();
      }

      const originalFetch = window.fetch.bind(window);
      window.fetch = async (...args) => {
        window.__aiUsageMonitor.inFlightRequestCount += 1;
        window.__aiUsageMonitor.setBusyState("loading");
        try {
          const response = await originalFetch(...args);
          try {
            const clone = response.clone();
            const body = await clone.text();
            window.__aiUsageMonitor.markRequest(response.url || String(args[0] || ""), body);
          } catch (_) {}
          return response;
        } finally {
          window.__aiUsageMonitor.inFlightRequestCount = Math.max(0, window.__aiUsageMonitor.inFlightRequestCount - 1);
          if (window.__aiUsageMonitor.inFlightRequestCount === 0) {
            window.__aiUsageMonitor.setBusyState(document.readyState === "complete" ? "ready" : "waiting");
          }
        }
      };

      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;

      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__aiUsageMonitorURL = url;
        return originalOpen.call(this, method, url, ...rest);
      };

      XMLHttpRequest.prototype.send = function(...args) {
        window.__aiUsageMonitor.inFlightRequestCount += 1;
        window.__aiUsageMonitor.setBusyState("loading");
        this.addEventListener("loadend", () => {
          try {
            const body = typeof this.responseText === "string" ? this.responseText : "";
            const url = this.responseURL || this.__aiUsageMonitorURL || "";
            window.__aiUsageMonitor.markRequest(url, body);
          } catch (_) {}
          window.__aiUsageMonitor.inFlightRequestCount = Math.max(0, window.__aiUsageMonitor.inFlightRequestCount - 1);
          if (window.__aiUsageMonitor.inFlightRequestCount === 0) {
            window.__aiUsageMonitor.setBusyState(document.readyState === "complete" ? "ready" : "waiting");
          }
        });
        return originalSend.apply(this, args);
      };

      window.addEventListener("load", () => {
        window.__aiUsageMonitor.setBusyState("ready");
      });

      document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible" && window.__aiUsageMonitor.inFlightRequestCount === 0) {
          window.__aiUsageMonitor.setBusyState("ready");
        }
      });

      return true;
    })();
    """#

    func decodePayload(from rawValue: Any?) throws -> PlatformScrapePayload {
        guard let dictionary = rawValue as? [String: Any] else {
            throw PlatformScraperError.invalidJavaScriptResult
        }

        let isLoggedIn = !(dictionary["requiresLogin"] as? Bool ?? false)
        let pageTitle = dictionary["pageTitle"] as? String ?? ""
        let pageURL = (dictionary["pageURL"] as? String).flatMap(URL.init(string:))
        let profileName = dictionary["profileName"] as? String
        let headline = dictionary["summaryText"] as? String ?? ""
        let debugExcerpt = dictionary["debugText"] as? String ?? ""
        let quotaEntries = Self.decodeQuotaEntries(dictionary["quotaEntries"])
        let activity = ActivitySnapshot(
            lastNetworkAt: Self.dateValue(dictionary["lastNetworkAt"]),
            lastDOMMutationAt: Self.dateValue(dictionary["lastDOMMutationAt"]),
            recentRequestCount: Self.intValue(dictionary["recentRequestCount"]) ?? 0,
            inFlightRequestCount: Self.intValue(dictionary["inFlightRequestCount"]) ?? 0,
            pageBusyState: dictionary["pageBusyState"] as? String
        )
        let taskSignals = PlatformTaskSignals(
            conversationTitle: dictionary["conversationTitle"] as? String,
            latestUserPromptPreview: dictionary["latestUserPromptPreview"] as? String,
            latestAssistantPreview: dictionary["latestAssistantPreview"] as? String,
            isStreaming: Self.boolValue(dictionary["isStreaming"]) ?? false,
            isWaitingForAssistant: Self.boolValue(dictionary["isWaitingForAssistant"]) ?? false,
            hasBlockingError: Self.boolValue(dictionary["hasBlockingError"]) ?? false,
            requiresLogin: Self.boolValue(dictionary["requiresLogin"]) ?? false,
            busyIndicatorText: dictionary["busyIndicatorText"] as? String,
            confidence: Self.doubleValue(dictionary["taskConfidence"]) ?? 0
        )

        return PlatformScrapePayload(
            isLoggedIn: isLoggedIn,
            pageTitle: pageTitle,
            pageURL: pageURL,
            profileName: profileName,
            headline: headline,
            debugExcerpt: debugExcerpt,
            quotaEntries: quotaEntries,
            activity: activity,
            taskSignals: taskSignals
        )
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int {
            return value
        }

        if let value = any as? NSNumber {
            return value.intValue
        }

        if let value = any as? String {
            return Int(value)
        }

        return nil
    }

    private static func dateValue(_ any: Any?) -> Date? {
        guard let string = any as? String else {
            return nil
        }

        return ISO8601DateFormatter().date(from: string)
    }

    private static func boolValue(_ any: Any?) -> Bool? {
        if let value = any as? Bool {
            return value
        }

        if let value = any as? NSNumber {
            return value.boolValue
        }

        if let value = any as? String {
            switch value.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    private static func decodeQuotaEntries(_ any: Any?) -> [UsageQuotaEntry] {
        guard let rows = any as? [[String: Any]] else {
            return []
        }

        return rows.compactMap { row in
            guard let label = row["label"] as? String, !label.isEmpty else {
                return nil
            }

            let valueText = row["valueText"] as? String ?? ""
            let resetText = row["resetText"] as? String
            let progress = doubleValue(row["progress"])
            return UsageQuotaEntry(
                label: label,
                valueText: valueText,
                resetText: resetText,
                progress: progress
            )
        }
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let value = any as? Double {
            return value
        }

        if let value = any as? NSNumber {
            return value.doubleValue
        }

        if let value = any as? String {
            return Double(value)
        }

        return nil
    }

    static func makeExtractionJavaScript(
        platform: AIPlatform,
        labelGroups: [QuotaLabelGroup]
    ) -> String {
        let groupsPayload = labelGroups.map { group in
            [
                "canonicalLabel": group.canonicalLabel,
                "aliases": group.aliases
            ]
        }
        let groupData = try? JSONSerialization.data(withJSONObject: groupsPayload)
        let groupsJSON = String(data: groupData ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        let platformID = platform.rawValue

        return #"""
        (() => {
          try {
            const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
            const lower = (value) => normalize(value).toLowerCase();
            const splitLines = (value) => String(value || "")
              .split(/\n+/)
              .map((line) => normalize(line))
              .filter(Boolean);
            const groups = \#(groupsJSON);
            const allAliases = groups.flatMap(group => group.aliases || []);
            const bodyText = document.body?.innerText || "";
            const bodyLines = splitLines(bodyText);
            const normalizedBodyText = normalize(bodyText);
            const platform = "\#(platformID)";
            const networkText = Array.isArray(window.__aiUsageMonitor?.responses)
              ? window.__aiUsageMonitor.responses
                  .map((response) => normalize(response?.body || ""))
                  .filter(Boolean)
                  .join("\n")
              : "";
            const looksLikeAuthURL = /\/(login|signin|auth|verify)(?:\/|$)|[?&](?:returnTo|redirect)=/i.test(location.href);
            const authPromptRegex = /log in|sign in|continue with|verify your email|check your email|use another account|continue with google|continue with email|로그인/;
            const rawLoginHint = authPromptRegex.test(lower(normalizedBodyText));
            const authPromptCount = Array.from(document.querySelectorAll("h1, h2, p, button, a, label, span"))
              .map((element) => normalize(element.textContent || element.innerText || ""))
              .filter(Boolean)
              .filter((text) => authPromptRegex.test(lower(text)))
              .slice(0, 8)
              .length;
            const hasAuthForm = Boolean(
              document.querySelector(
                "input[type='password'], input[name*='password' i], input[autocomplete='current-password'], form[action*='login' i], form[action*='signin' i]"
              )
            );
            const apiAuthFalse = /"is_authenticated"\s*:\s*false/.test(networkText);

            const selectorGroups = {
              codex: {
                conversation: ["main h1", "header h1", "main h2", "[data-testid*='conversation'] h1", "[data-testid*='thread'] h1"],
                user: ["[data-message-author-role='user']", "[data-role='user']", "[data-testid*='user']", "[data-testid*='human-message']", "article[data-role='user']"],
                assistant: ["[data-message-author-role='assistant']", "[data-role='assistant']", "[data-testid*='assistant']", "article[data-role='assistant']"],
                streamIndicators: ["button[aria-label*='Stop']", "button[aria-label*='stop']", "[data-testid*='stop']", "[aria-busy='true']", "[data-state*='stream']", "[data-state*='generat']"],
                error: ["[role='alert']", "[data-testid*='error']", ".text-red-500", ".text-danger", "[data-state='error']"],
                composer: ["textarea", "[contenteditable='true']"]
              },
              claude: {
                conversation: ["main h1", "header h1", "main h2", "[data-testid='conversation-title']", "[data-testid*='chat-title']"],
                user: ["[data-testid*='user-message']", "[data-testid*='human-message']", "[data-message-author-role='human']", "[data-message-author-role='user']"],
                assistant: ["[data-testid*='assistant-message']", "[data-message-author-role='assistant']", "[data-is-streaming']", "[data-testid*='assistant-turn']"],
                streamIndicators: ["button[aria-label*='Stop']", "button[aria-label*='stop']", "[data-testid*='stop-generation']", "[aria-busy='true']", "[data-state*='stream']", "[data-state*='generat']"],
                error: ["[role='alert']", "[data-testid*='error']", ".text-danger", "[data-state='error']"],
                composer: ["textarea", "[contenteditable='true']"]
              },
              cursor: {
                conversation: ["main h1", "header h1", "main h2", "[data-testid*='chat-title']", "[data-testid*='conversation-title']"],
                user: ["[data-testid*='user-message']", "[data-message-author-role='user']", ".message.user", "[data-testid*='human-message']"],
                assistant: ["[data-testid*='assistant-message']", "[data-message-author-role='assistant']", ".message.assistant", "[data-testid*='assistant-turn']"],
                streamIndicators: ["button[aria-label*='Stop']", "button[aria-label*='stop']", "[data-testid*='stop']", "[aria-busy='true']", "[data-state*='stream']", "[data-state*='generat']"],
                error: ["[role='alert']", "[data-testid*='error']", ".text-red-500", ".text-danger", "[data-state='error']"],
                composer: ["textarea", "[contenteditable='true']"]
              }
            };

            const genericSelectors = {
              conversation: ["main h1", "header h1", "main h2", "[role='heading'][aria-level='1']", "[role='heading'][aria-level='2']"],
              user: ["[data-message-author-role='user']", "[data-message-author-role='human']", "[data-role='user']", "[data-testid*='user-message']", "[data-testid*='human-message']", "article[data-role='user']", ".message.user"],
              assistant: ["[data-message-author-role='assistant']", "[data-role='assistant']", "[data-testid*='assistant-message']", "[data-testid*='assistant-turn']", "article[data-role='assistant']", ".message.assistant"],
              streamIndicators: ["button[aria-label*='Stop']", "button[aria-label*='stop']", "[data-testid*='stop']", "[data-testid*='stop-generation']", "[aria-busy='true']", "[data-state*='stream']", "[data-state*='generat']"],
              error: ["[role='alert']", "[data-testid*='error']", ".text-red-500", ".text-danger", "[data-state='error']"],
              composer: ["textarea", "[contenteditable='true']"]
            };
            const mergeUnique = (primary, fallback) => Array.from(new Set([...(primary || []), ...(fallback || [])]));
            const chosenSelectors = selectorGroups[platform] || selectorGroups.codex;
            const activeSelectors = {
              conversation: mergeUnique(chosenSelectors.conversation, genericSelectors.conversation),
              user: mergeUnique(chosenSelectors.user, genericSelectors.user),
              assistant: mergeUnique(chosenSelectors.assistant, genericSelectors.assistant),
              streamIndicators: mergeUnique(chosenSelectors.streamIndicators, genericSelectors.streamIndicators),
              error: mergeUnique(chosenSelectors.error, genericSelectors.error),
              composer: mergeUnique(chosenSelectors.composer, genericSelectors.composer)
            };
            const safeQuerySelector = (selector) => {
              try {
                return document.querySelector(selector);
              } catch (_) {
                return null;
              }
            };
            const safeQuerySelectorAll = (selector) => {
              try {
                return Array.from(document.querySelectorAll(selector));
              } catch (_) {
                return [];
              }
            };
            const queryText = (selectors) => {
              for (const selector of selectors || []) {
                const element = safeQuerySelector(selector);
                const text = normalize(element?.textContent || element?.innerText || "");
                if (text) return text;
              }
              return "";
            };
            const queryLastText = (selectors) => {
              for (const selector of selectors || []) {
                const elements = safeQuerySelectorAll(selector);
                for (let index = elements.length - 1; index >= 0; index -= 1) {
                  const text = normalize(elements[index]?.textContent || elements[index]?.innerText || "");
                  if (text) return text;
                }
              }
              return "";
            };
            const queryAny = (selectors) => (selectors || []).some((selector) => Boolean(safeQuerySelector(selector)));
            const truncate = (value, length = 140) => {
              const text = normalize(value);
              return text.length > length ? `${text.slice(0, length - 1)}…` : text;
            };
            const conversationTitle = truncate(queryText(activeSelectors.conversation));
            const latestUserPromptPreview = truncate(queryLastText(activeSelectors.user));
            const latestAssistantPreview = truncate(queryLastText(activeSelectors.assistant));
            const busyIndicatorText = truncate(
              queryText(["[aria-live='polite']", "[role='status']", "[aria-busy='true']", "[data-state*='stream']", "[data-state*='generat']"])
                || queryText(activeSelectors.streamIndicators)
            );
            const hasBlockingError = queryAny(activeSelectors.error) || /error|failed|문제가 발생|오류|try again/.test(lower(normalizedBodyText));
            const isStreaming = queryAny(activeSelectors.streamIndicators)
              || /generating|thinking|streaming|responding|작성 중|생성 중/.test(lower(busyIndicatorText));
            const composerElements = (activeSelectors.composer || []).flatMap((selector) => safeQuerySelectorAll(selector));
            const composerBlocked = composerElements
              .some((element) => element.hasAttribute("disabled") || element.getAttribute("aria-disabled") === "true");
            const isWaitingForAssistant = Boolean(latestUserPromptPreview) && (isStreaming || composerBlocked || !latestAssistantPreview);
            const taskConfidence = Math.min(
              1,
              (conversationTitle ? 0.25 : 0)
                + (latestUserPromptPreview ? 0.25 : 0)
                + (latestAssistantPreview ? 0.2 : 0)
                + (isStreaming ? 0.2 : 0)
                + (busyIndicatorText ? 0.1 : 0)
            );

            const normalizeProgress = (value, contextText) => {
              if (value === null || value === undefined) {
                return null;
              }

              const context = lower(contextText);
              const looksUsed = /사용됨|used|consumed/.test(context);
              const looksRemaining = /남음|remaining|left/.test(context);
              if (looksUsed && !looksRemaining) {
                return Math.min(1, Math.max(0, 1 - value));
              }

              return Math.min(1, Math.max(0, value));
            };

            const parsePercent = (value, contextText) => {
              const match = normalize(value).match(/(\d+(?:\.\d+)?)\s*%/);
              if (!match) {
                return null;
              }

              return normalizeProgress(Number.parseFloat(match[1]) / 100, contextText || value);
            };

            const parseResetText = (value) => {
              const normalized = normalize(value);
              const ko = normalized.match(/(\d{4}\.\s*\d{1,2}\.\s*\d{1,2}\.\s*(?:오전|오후)\s*\d{1,2}:\d{2}\s*초기화)/);
              if (ko) {
                return normalize(ko[1]);
              }

              const koReset = normalized.match(/(\d+\s*(?:분|시간)\s*후\s*재설정|\([^)]+\)\s*(?:오전|오후)\s*\d{1,2}:\d{2}\s*에\s*재설정|[A-Za-z]{3,9}\s+\d{1,2}\s*에\s*재설정)/i);
              if (koReset) {
                return normalize(koReset[1]);
              }

              const en = normalized.match(/(resets?\s+[^.]+|reset\s+on\s+[^.]+|available\s+again\s+[^.]+)/i);
              if (en) {
                return normalize(en[1]);
              }

              const billing = normalized.match(/((?:renews?|refreshes?)\s+(?:on\s+)?[A-Za-z]{3,9}\s+\d{1,2}(?:,\s*\d{4})?)/i);
              if (billing) {
                return normalize(billing[1]);
              }

              const monthDay = normalized.match(/([A-Za-z]{3,9}\s+\d{1,2}(?:,\s*\d{4})?)/);
              return monthDay ? normalize(monthDay[1]) : null;
            };

            const parseValueText = (text) => {
              const normalized = normalize(text);
              const currencyMatch = normalized.match(/((?:US\$|\$)\s*\d[\d,]*(?:\.\d+)?(?:\s*(?:used|remaining|left|limit|balance|spent|usage|included|credit))?)/i);
              if (currencyMatch) {
                return normalize(currencyMatch[1]);
              }

              const currencyLeadingWordMatch = normalized.match(/((?:used|remaining|left|limit|balance|spent|usage|included|credit)\s*(?:US\$|\$)\s*\d[\d,]*(?:\.\d+)?)/i);
              if (currencyLeadingWordMatch) {
                return normalize(currencyLeadingWordMatch[1]);
              }

              const percentMatch = normalized.match(/(\d+(?:\.\d+)?)\s*%\s*(remaining|left|남음|used|사용됨)?/i);
              if (percentMatch) {
                return normalize(percentMatch[0]);
              }

              const fractionMatch = normalized.match(/(\d+)\s*\/\s*(\d+)/);
              if (fractionMatch) {
                return normalize(fractionMatch[0]);
              }

              const tokenMatch = normalized.match(/(\d[\d,.]*\s*(?:k|m|b)?\s*(?:tokens?|requests?))/i);
              if (tokenMatch) {
                return normalize(tokenMatch[1]);
              }

              const numericMatch = normalized.match(/\b\d+\b/);
              return numericMatch ? normalize(numericMatch[0]) : "";
            };

            const parseProgressFromElement = (element, fallbackText, contextText) => {
              const textProgress = parsePercent(fallbackText, contextText);
              if (textProgress !== null) {
                return textProgress;
              }

              let node = null;
              try {
                node = element?.querySelector("[role='progressbar'], [aria-valuenow], div[style*='width'], div[style*='transform']");
              } catch (_) {
                node = null;
              }
              if (!node) {
                return null;
              }

              const ariaValue = node.getAttribute("aria-valuenow");
              if (ariaValue && !Number.isNaN(Number(ariaValue))) {
                const numericValue = Number(ariaValue);
                const normalizedValue = numericValue > 1 ? numericValue / 100 : numericValue;
                return normalizeProgress(normalizedValue, contextText);
              }

              const style = node.getAttribute("style") || "";
              const styleMatch = style.match(/(\d+(?:\.\d+)?)%/);
              if (styleMatch) {
                return normalizeProgress(Number(styleMatch[1]) / 100, contextText);
              }

              return null;
            };

            const textContainsAlias = (text, aliases) =>
              (aliases || []).some((alias) => lower(text).includes(lower(alias)));
            const parseValueFromLines = (lines) => {
              const preferredLine = (lines || []).find((line) =>
                /(\d+(?:\.\d+)?)\s*%|(?:US\$|\$)\s*\d|\d+\s*\/\s*\d|\d[\d,.]*\s*(?:tokens?|requests?)/i.test(line)
              );
              const joined = normalize((lines || []).join(" "));
              return parseValueText(preferredLine || joined);
            };
            const parseResetFromLines = (lines) => {
              for (const line of lines || []) {
                const reset = parseResetText(line);
                if (reset) {
                  return reset;
                }
              }
              return parseResetText(normalize((lines || []).join(" ")));
            };
            const parseProgressFromLines = (lines, contextText) => {
              for (const line of lines || []) {
                const progress = parsePercent(line, contextText);
                if (progress !== null) {
                  return progress;
                }
              }
              return parsePercent(contextText, contextText);
            };

            const elementCandidates = Array.from(document.querySelectorAll("section, article, div, li"))
              .map((element) => {
                const text = normalize(element.innerText || "");
                if (!text) {
                  return null;
                }

                const matchedGroups = groups.filter((group) =>
                  (group.aliases || []).some((alias) => lower(text).includes(lower(alias)))
                );
                if (matchedGroups.length === 0) {
                  return null;
                }

                const score =
                  (/(\d+(?:\.\d+)?)\s*%/.test(text) ? 100 : 0) +
                  (/reset|초기화|left|remaining/i.test(text) ? 20 : 0) +
                  (() => {
                    try {
                      return element.querySelector("[role='progressbar'], [aria-valuenow]") ? 18 : 0;
                    } catch (_) {
                      return 0;
                    }
                  })() -
                  Math.min(text.length, 600) / 7;

                return { element, text, matchedGroups, score };
              })
              .filter(Boolean)
              .sort((left, right) => right.score - left.score);

            const parseEntry = (group, rawText, element, preferredLines = null) => {
              const combinedText = normalize(rawText);
              const aliases = group.aliases || [];
              const hasAlias = aliases.some((alias) => lower(combinedText).includes(lower(alias)));
              if (!hasAlias) {
                return null;
              }

              const valueText = preferredLines ? parseValueFromLines(preferredLines) : parseValueText(combinedText);
              if (!valueText) {
                return null;
              }

              return {
                label: group.canonicalLabel,
                valueText,
                resetText: preferredLines ? parseResetFromLines(preferredLines) : parseResetText(combinedText),
                progress: preferredLines
                  ? parseProgressFromLines(preferredLines, combinedText)
                  : parseProgressFromElement(element, valueText, combinedText)
              };
            };

            const claudeLineEntries = platform === "claude"
              ? groups.map((group) => {
                  for (let index = 0; index < bodyLines.length; index += 1) {
                    if (!textContainsAlias(bodyLines[index], group.aliases || [])) {
                      continue;
                    }

                    const windowLines = bodyLines.slice(index, Math.min(bodyLines.length, index + 6));
                    const windowText = normalize(windowLines.join(" "));
                    const entry = parseEntry(group, windowText, null, windowLines);
                    if (entry) {
                      return entry;
                    }
                  }
                  return null;
                }).filter(Boolean)
              : [];

            const quotaEntries = [...claudeLineEntries];
            for (const group of groups) {
              if (quotaEntries.some((entry) => entry.label === group.canonicalLabel)) {
                continue;
              }

              const elementCandidate = elementCandidates.find((candidate) =>
                candidate.matchedGroups.some((matched) => matched.canonicalLabel === group.canonicalLabel)
              );

              if (elementCandidate) {
                const entry = parseEntry(group, elementCandidate.text, elementCandidate.element);
                if (entry) {
                  quotaEntries.push(entry);
                  continue;
                }
              }

              const fallbackSources = [normalizedBodyText, networkText].filter(Boolean);
              for (const sourceText of fallbackSources) {
                const entry = parseEntry(group, sourceText, null);
                if (entry) {
                  quotaEntries.push(entry);
                  break;
                }
              }
            }

            const uniqueQuotaEntries = quotaEntries.filter((entry, index, entries) =>
              entries.findIndex((candidate) => candidate.label === entry.label) === index
            );
            const hasUsageSurface = uniqueQuotaEntries.length > 0
              || allAliases.some((alias) => lower(normalizedBodyText).includes(lower(alias)))
              || /usage|limits|현재 세션|주간 한도|추가 사용량|월간 지출 한도|additional usage|spending limit/.test(lower(normalizedBodyText));
            const requiresLogin = uniqueQuotaEntries.length === 0 && (
              looksLikeAuthURL
              || hasAuthForm
              || authPromptCount >= 2
              || (rawLoginHint && !hasUsageSurface)
              || (apiAuthFalse && !hasUsageSurface)
            );

            const headline = uniqueQuotaEntries.length > 0
              ? uniqueQuotaEntries.map((entry) => `${entry.label} ${entry.valueText}`).join(" · ")
              : "\#(platform.displayName) 사용량 정보를 아직 찾지 못했습니다.";

            const debugText = [
              normalize(document.title || ""),
              `auth url=${looksLikeAuthURL} form=${hasAuthForm} prompts=${authPromptCount} apiFalse=${apiAuthFalse} quotaCount=${uniqueQuotaEntries.length}`,
              normalizedBodyText.slice(0, 3000),
              networkText.slice(0, 1000)
            ]
              .filter(Boolean)
              .join("\n\n---\n\n");

            const now = Date.now();
            const requestTimestamps = Array.isArray(window.__aiUsageMonitor?.requests)
              ? window.__aiUsageMonitor.requests
              : [];
            const recentRequestCount = requestTimestamps.filter((value) => {
              const timestamp = Date.parse(value);
              return Number.isFinite(timestamp) && (now - timestamp) <= 10 * 60 * 1000;
            }).length;

            return {
              platform: "\#(platform.rawValue)",
              pageTitle: document.title || "",
              pageURL: location.href,
              requiresLogin,
              profileName: null,
              summaryText: headline,
              debugText,
              quotaEntries: uniqueQuotaEntries,
              lastNetworkAt: window.__aiUsageMonitor?.lastNetworkAt || null,
              lastDOMMutationAt: window.__aiUsageMonitor?.lastDOMMutationAt || null,
              recentRequestCount,
              inFlightRequestCount: window.__aiUsageMonitor?.inFlightRequestCount || 0,
              pageBusyState: window.__aiUsageMonitor?.pageBusyState || document.readyState,
              conversationTitle: conversationTitle || null,
              latestUserPromptPreview: latestUserPromptPreview || null,
              latestAssistantPreview: latestAssistantPreview || null,
              isStreaming,
              isWaitingForAssistant,
              hasBlockingError,
              busyIndicatorText: busyIndicatorText || null,
              taskConfidence
            };
          } catch (error) {
            const message = String(error?.message || error || "unknown error");
            return {
              platform: "\#(platform.rawValue)",
              pageTitle: document.title || "",
              pageURL: location.href,
              requiresLogin: false,
              profileName: null,
              summaryText: "\#(platform.displayName) extractor error",
              debugText: `JavaScript extraction error: ${message}`,
              quotaEntries: [],
              lastNetworkAt: window.__aiUsageMonitor?.lastNetworkAt || null,
              lastDOMMutationAt: window.__aiUsageMonitor?.lastDOMMutationAt || null,
              recentRequestCount: 0,
              inFlightRequestCount: window.__aiUsageMonitor?.inFlightRequestCount || 0,
              pageBusyState: window.__aiUsageMonitor?.pageBusyState || document.readyState,
              conversationTitle: null,
              latestUserPromptPreview: null,
              latestAssistantPreview: null,
              isStreaming: false,
              isWaitingForAssistant: false,
              hasBlockingError: true,
              busyIndicatorText: message,
              taskConfidence: 0
            };
          }
        })();
        """#
    }
}
