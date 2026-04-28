import Foundation

enum AIPlatform: String, CaseIterable, Codable, Identifiable {
    case codex
    case claude
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .cursor:
            return "Cursor"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .codex:
            return "CDX"
        case .claude:
            return "CLD"
        case .cursor:
            return "CUR"
        }
    }

    var loginURL: URL {
        switch self {
        case .codex:
            return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .claude:
            return URL(string: "https://claude.ai")!
        case .cursor:
            return URL(string: "https://cursor.com/dashboard")!
        }
    }

    var dashboardURL: URL {
        switch self {
        case .codex:
            return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .claude:
            return URL(string: "https://claude.ai/settings/usage")!
        case .cursor:
            return URL(string: "https://cursor.com/dashboard")!
        }
    }

    var loginHints: [String] {
        switch self {
        case .codex:
            return ["log in", "sign up", "continue with google", "continue with email", "welcome back"]
        case .claude:
            return ["log in", "sign in", "continue with google", "continue with email", "verify your email", "welcome back"]
        case .cursor:
            return ["log in", "sign in", "continue with google", "continue with github", "welcome back"]
        }
    }

    var usageTextHints: [String] {
        switch self {
        case .codex:
            return [
                "남은 요금 한도",
                "rate limits",
                "rate limit",
                "5시간",
                "1주",
                "usage",
                "quota",
                "remaining budget"
            ]
        case .claude:
            return [
                "usage",
                "limits",
                "5-hour",
                "weekly",
                "현재 세션",
                "주간 한도",
                "사용량",
                "재설정",
                "messages",
                "reset",
                "remaining"
            ]
        case .cursor:
            return [
                "usage",
                "dashboard",
                "token breakdown",
                "included usage",
                "monthly usage",
                "spending limit",
                "spend limit",
                "on-demand usage",
                "usage-based pricing",
                "billing"
            ]
        }
    }

    var primaryQuotaGroups: [QuotaLabelGroup] {
        switch self {
        case .codex:
            return [
                QuotaLabelGroup(
                    canonicalLabel: "5시간 사용 한도",
                    aliases: ["5시간 사용 한도", "5-hour usage limit", "current 5-hour usage limit"]
                ),
                QuotaLabelGroup(
                    canonicalLabel: "주간 사용 한도",
                    aliases: ["주간 사용 한도", "weekly usage limit", "current weekly usage limit"]
                )
            ]
        case .claude:
            return [
                QuotaLabelGroup(
                    canonicalLabel: "5-hour usage limit",
                    aliases: [
                        "current 5-hour usage limit",
                        "5-hour usage limit",
                        "5 hour usage limit",
                        "현재 세션",
                        "현재 세션 한도",
                        "현재 세션 사용량 한도"
                    ]
                ),
                QuotaLabelGroup(
                    canonicalLabel: "Weekly usage limit",
                    aliases: [
                        "current weekly usage limit",
                        "weekly usage limit",
                        "주간 한도",
                        "주간 사용량 한도",
                        "주간 사용 한도"
                    ]
                )
            ]
        case .cursor:
            return [
                QuotaLabelGroup(
                    canonicalLabel: "Included monthly usage",
                    aliases: [
                        "included monthly usage",
                        "included usage",
                        "monthly usage",
                        "monthly included usage",
                        "included agent usage",
                        "agent usage",
                        "usage and token breakdowns",
                        "token breakdown",
                        "request breakdown",
                        "requests",
                        "precommitted usage",
                        "included amount"
                    ]
                ),
                QuotaLabelGroup(
                    canonicalLabel: "Monthly spending limit",
                    aliases: [
                        "monthly spending limit",
                        "spending limit",
                        "monthly spend limit",
                        "spend limit",
                        "per-user limit",
                        "usage limit",
                        "usage-based pricing",
                        "on-demand usage",
                        "purchased usage"
                    ]
                )
            ]
        }
    }
}

struct QuotaLabelGroup: Codable, Equatable {
    var canonicalLabel: String
    var aliases: [String]
}

enum AccountRefreshState: String, Codable {
    case idle
    case loading
    case ready
    case requiresLogin
    case failed
}

enum SessionAvailability: String, Codable {
    case unknown
    case available
    case low
    case blocked
}

enum SessionActivityState: String, Codable {
    case unknown
    case loading
    case active
    case waiting
    case idle
    case stale
}

enum SessionTaskState: String, Codable {
    case working
    case responding
    case waiting
    case idle
    case needsLogin
    case quotaLow
    case blocked
    case stale
    case error
}

enum PresentationState: String, Codable, CaseIterable, Identifiable {
    case working
    case waiting
    case idle
    case atRisk
    case blocked

    var id: String { rawValue }
}

struct PresentationStateToken: Equatable {
    let state: PresentationState
    let title: String
    let shortTitle: String
    let priority: Int
}

extension PresentationState {
    var token: PresentationStateToken {
        switch self {
        case .working:
            return PresentationStateToken(
                state: .working,
                title: "작업 중",
                shortTitle: "WORK",
                priority: 2
            )
        case .waiting:
            return PresentationStateToken(
                state: .waiting,
                title: "응답 대기",
                shortTitle: "WAIT",
                priority: 1
            )
        case .idle:
            return PresentationStateToken(
                state: .idle,
                title: "모니터링",
                shortTitle: "IDLE",
                priority: 3
            )
        case .atRisk:
            return PresentationStateToken(
                state: .atRisk,
                title: "주의",
                shortTitle: "RISK",
                priority: 0
            )
        case .blocked:
            return PresentationStateToken(
                state: .blocked,
                title: "차단",
                shortTitle: "BLOCK",
                priority: -1
            )
        }
    }
}

enum AppHealth {
    case empty
    case checking
    case available
    case low
    case blocked
    case requiresLogin
    case failed
    case idle
    case stale
}

struct PlatformHealthSummary {
    var health: AppHealth
    var title: String
    var subtitle: String
    var symbolName: String
    var accessibilityLabel: String
}

struct ImmediateActionItem: Identifiable, Equatable {
    enum Action: String, Equatable {
        case login
        case refresh
        case open
    }

    let accountID: UUID
    let displayName: String
    let reason: String
    let actionTitle: String
    let action: Action

    var id: UUID { accountID }
}

struct UsageQuotaEntry: Codable, Equatable, Identifiable {
    var id: String { label }
    var label: String
    var valueText: String
    var resetText: String?
    var progress: Double?
}

struct QuotaSnapshot: Codable, Equatable {
    var entries: [UsageQuotaEntry]

    init(entries: [UsageQuotaEntry] = []) {
        self.entries = entries
    }
}

struct ActivitySnapshot: Codable, Equatable {
    var lastNetworkAt: Date?
    var lastDOMMutationAt: Date?
    var recentRequestCount: Int
    var inFlightRequestCount: Int
    var pageBusyState: String?

    init(
        lastNetworkAt: Date? = nil,
        lastDOMMutationAt: Date? = nil,
        recentRequestCount: Int = 0,
        inFlightRequestCount: Int = 0,
        pageBusyState: String? = nil
    ) {
        self.lastNetworkAt = lastNetworkAt
        self.lastDOMMutationAt = lastDOMMutationAt
        self.recentRequestCount = recentRequestCount
        self.inFlightRequestCount = inFlightRequestCount
        self.pageBusyState = pageBusyState
    }
}

struct PlatformTaskSignals: Codable, Equatable {
    var conversationTitle: String?
    var latestUserPromptPreview: String?
    var latestAssistantPreview: String?
    var isStreaming: Bool
    var isWaitingForAssistant: Bool
    var hasBlockingError: Bool
    var requiresLogin: Bool
    var busyIndicatorText: String?
    var confidence: Double

    init(
        conversationTitle: String? = nil,
        latestUserPromptPreview: String? = nil,
        latestAssistantPreview: String? = nil,
        isStreaming: Bool = false,
        isWaitingForAssistant: Bool = false,
        hasBlockingError: Bool = false,
        requiresLogin: Bool = false,
        busyIndicatorText: String? = nil,
        confidence: Double = 0
    ) {
        self.conversationTitle = conversationTitle
        self.latestUserPromptPreview = latestUserPromptPreview
        self.latestAssistantPreview = latestAssistantPreview
        self.isStreaming = isStreaming
        self.isWaitingForAssistant = isWaitingForAssistant
        self.hasBlockingError = hasBlockingError
        self.requiresLogin = requiresLogin
        self.busyIndicatorText = busyIndicatorText
        self.confidence = confidence
    }

    var normalizedConversationTitle: String? {
        Self.normalized(conversationTitle)
    }

    var meaningfulConversationTitle: String? {
        guard let title = normalizedConversationTitle else {
            return nil
        }

        return Self.isGenericConversationTitle(title) ? nil : title
    }

    var normalizedLatestUserPromptPreview: String? {
        Self.normalized(latestUserPromptPreview)
    }

    var normalizedLatestAssistantPreview: String? {
        Self.normalized(latestAssistantPreview)
    }

    var normalizedBusyIndicatorText: String? {
        Self.normalized(busyIndicatorText)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : String(trimmed.prefix(140))
    }

    private static func isGenericConversationTitle(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let exactMatches: Set<String> = [
            "settings",
            "setting",
            "usage",
            "limits",
            "limit",
            "dashboard",
            "billing",
            "chat",
            "home",
            "codex",
            "claude",
            "cursor",
            "설정",
            "사용량",
            "한도",
            "대시보드",
            "홈"
        ]

        if exactMatches.contains(normalized) {
            return true
        }

        let genericFragments = [
            "usage limit",
            "weekly usage",
            "rate limit",
            "analytics",
            "codex analytics",
            "claude analytics",
            "current session",
            "애널리틱스",
            "주간 한도",
            "현재 세션",
            "현재 사용량"
        ]

        if genericFragments.contains(where: { normalized.contains($0) }) {
            return true
        }

        return false
    }
}

struct SessionTaskContext: Codable, Equatable {
    var conversationTitle: String?
    var latestUserPromptPreview: String?
    var latestAssistantStateText: String?
    var isStreamingResponse: Bool
    var isUserWaitingForReply: Bool
    var lastMeaningfulActivityAt: Date?
    var sourceConfidence: Double

    var displayTitle: String? {
        conversationTitle ?? latestUserPromptPreview ?? latestAssistantStateText
    }

    var statusLine: String? {
        if isStreamingResponse {
            return "응답 생성 중"
        }
        if isUserWaitingForReply {
            return "응답 대기 중"
        }
        return latestAssistantStateText ?? latestUserPromptPreview
    }
}

struct UsageSnapshot: Codable, Equatable {
    var headline: String
    var sourceURL: URL?
    var debugExcerpt: String
    var quota: QuotaSnapshot
    var activity: ActivitySnapshot
    var taskSignals: PlatformTaskSignals
    var updatedAt: Date

    init(
        headline: String,
        sourceURL: URL? = nil,
        debugExcerpt: String,
        quota: QuotaSnapshot = QuotaSnapshot(),
        activity: ActivitySnapshot = ActivitySnapshot(),
        taskSignals: PlatformTaskSignals = PlatformTaskSignals(),
        updatedAt: Date
    ) {
        self.headline = headline
        self.sourceURL = sourceURL
        self.debugExcerpt = UsageSnapshot.trimDebugExcerpt(debugExcerpt)
        self.quota = quota
        self.activity = activity
        self.taskSignals = taskSignals
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case headline
        case sourceURL
        case debugExcerpt
        case quota
        case activity
        case taskSignals
        case updatedAt
        case rawExcerpt
        case quotaEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let headline = try container.decodeIfPresent(String.self, forKey: .headline) ?? ""
        let sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        let debugExcerpt = try container.decodeIfPresent(String.self, forKey: .debugExcerpt)
            ?? container.decodeIfPresent(String.self, forKey: .rawExcerpt)
            ?? ""
        let quota = try container.decodeIfPresent(QuotaSnapshot.self, forKey: .quota)
            ?? QuotaSnapshot(entries: try container.decodeIfPresent([UsageQuotaEntry].self, forKey: .quotaEntries) ?? [])
        let activity = try container.decodeIfPresent(ActivitySnapshot.self, forKey: .activity) ?? ActivitySnapshot()
        let taskSignals = try container.decodeIfPresent(PlatformTaskSignals.self, forKey: .taskSignals) ?? PlatformTaskSignals()
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        self.init(
            headline: headline,
            sourceURL: sourceURL,
            debugExcerpt: debugExcerpt,
            quota: quota,
            activity: activity,
            taskSignals: taskSignals,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(headline, forKey: .headline)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encode(debugExcerpt, forKey: .debugExcerpt)
        try container.encode(quota, forKey: .quota)
        try container.encode(activity, forKey: .activity)
        try container.encode(taskSignals, forKey: .taskSignals)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func trimDebugExcerpt(_ value: String) -> String {
        String(value.prefix(4_096))
    }
}
