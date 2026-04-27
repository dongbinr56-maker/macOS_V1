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
                title: "유휴",
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
            "current session",
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

struct WebAccountSession: Identifiable, Codable, Equatable {
    var id: UUID
    var platform: AIPlatform
    var displayName: String
    var profileName: String?
    var usesAutoDisplayName: Bool
    var dataStoreID: UUID
    var createdAt: Date
    var refreshState: AccountRefreshState
    var lastCheckedAt: Date?
    var snapshot: UsageSnapshot?
    var lastErrorDescription: String?

    init(
        id: UUID = UUID(),
        platform: AIPlatform,
        displayName: String,
        profileName: String? = nil,
        usesAutoDisplayName: Bool = true,
        dataStoreID: UUID = UUID(),
        createdAt: Date = Date(),
        refreshState: AccountRefreshState = .idle,
        lastCheckedAt: Date? = nil,
        snapshot: UsageSnapshot? = nil,
        lastErrorDescription: String? = nil
    ) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
        self.profileName = profileName
        self.usesAutoDisplayName = usesAutoDisplayName
        self.dataStoreID = dataStoreID
        self.createdAt = createdAt
        self.refreshState = refreshState
        self.lastCheckedAt = lastCheckedAt
        self.snapshot = snapshot
        self.lastErrorDescription = lastErrorDescription
    }
}

extension UsageSnapshot {
    func primaryQuotaEntries(for platform: AIPlatform) -> [UsageQuotaEntry] {
        platform.primaryQuotaGroups.compactMap { group in
            quota.entries.first { entry in
                group.aliases.contains { alias in
                    normalizeQuotaLabel(alias) == normalizeQuotaLabel(entry.label)
                }
            }
        }
    }

    func hasUsableQuotaData(for platform: AIPlatform) -> Bool {
        primaryQuotaEntries(for: platform).count == platform.primaryQuotaGroups.count
    }

    func primaryResetSummary(for platform: AIPlatform) -> String? {
        primaryQuotaEntries(for: platform)
            .compactMap(\.resetText)
            .first { !$0.isEmpty }
    }

    func availability(for platform: AIPlatform, lowThreshold: Double) -> SessionAvailability {
        let entries = primaryQuotaEntries(for: platform)
        guard !entries.isEmpty else {
            return .unknown
        }

        let progresses = entries.compactMap(\.progress)
        guard !progresses.isEmpty else {
            return .unknown
        }

        if progresses.contains(where: { $0 <= 0 }) {
            return .blocked
        }

        if progresses.contains(where: { $0 <= lowThreshold }) {
            return .low
        }

        return .available
    }
}

extension WebAccountSession {
    func availability(lowQuotaThreshold: Double) -> SessionAvailability {
        snapshot?.availability(for: platform, lowThreshold: lowQuotaThreshold) ?? .unknown
    }

    func activityState(
        now: Date = Date(),
        idleThreshold: TimeInterval,
        staleThreshold: TimeInterval
    ) -> SessionActivityState {
        let transientActivityThreshold: TimeInterval = 12

        if refreshState == .loading {
            return .loading
        }

        guard let snapshot else {
            return .unknown
        }

        if let lastCheckedAt, now.timeIntervalSince(lastCheckedAt) >= staleThreshold {
            return .stale
        }

        let recentNetwork = isRecent(snapshot.activity.lastNetworkAt, now: now, threshold: transientActivityThreshold)
        let recentDOMMutation = isRecent(snapshot.activity.lastDOMMutationAt, now: now, threshold: transientActivityThreshold)

        if snapshot.activity.inFlightRequestCount > 0 {
            return .active
        }

        if let busyState = snapshot.activity.pageBusyState?.lowercased(),
           (busyState.contains("load") || busyState.contains("busy")),
           recentNetwork || recentDOMMutation {
            return .waiting
        }

        if snapshot.activity.recentRequestCount > 0 && (recentNetwork || recentDOMMutation) {
            return .active
        }

        let recentActivity = [snapshot.activity.lastNetworkAt, snapshot.activity.lastDOMMutationAt]
            .compactMap { $0 }
            .max()

        guard let recentActivity else {
            return .idle
        }

        if now.timeIntervalSince(recentActivity) >= idleThreshold {
            return .idle
        }

        return .idle
    }

    private func isRecent(_ timestamp: Date?, now: Date, threshold: TimeInterval) -> Bool {
        guard let timestamp else {
            return false
        }

        return now.timeIntervalSince(timestamp) <= threshold
    }

    func hasReliableQuotaData() -> Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.hasUsableQuotaData(for: platform)
    }
}

struct SessionSearchFilter {
    let query: String

    private var normalizedTerms: [String] {
        query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isActive: Bool {
        !normalizedTerms.isEmpty
    }

    func apply(to sessions: [WebAccountSession]) -> [WebAccountSession] {
        guard isActive else {
            return sessions
        }

        return sessions.filter(matches)
    }

    func matches(_ session: WebAccountSession) -> Bool {
        guard isActive else {
            return true
        }

        let haystack = searchableTokens(for: session)
            .joined(separator: "\n")
            .lowercased()

        return normalizedTerms.allSatisfy { haystack.contains($0) }
    }

    private func searchableTokens(for session: WebAccountSession) -> [String] {
        var tokens: [String?] = [
            session.displayName,
            session.profileName,
            session.platform.displayName,
            session.platform.shortDisplayName,
            session.lastErrorDescription,
            session.snapshot?.headline,
            session.snapshot?.sourceURL?.host(),
            session.snapshot?.taskSignals.meaningfulConversationTitle,
            session.snapshot?.taskSignals.normalizedLatestUserPromptPreview,
            session.snapshot?.taskSignals.normalizedLatestAssistantPreview,
            session.snapshot?.taskSignals.normalizedBusyIndicatorText
        ]

        if let snapshot = session.snapshot {
            tokens.append(contentsOf: snapshot.quota.entries.flatMap { [$0.label, $0.valueText, $0.resetText] })
        }

        return tokens.compactMap { value in
            guard let value else {
                return nil
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

struct PlatformScrapePayload {
    var isLoggedIn: Bool
    var pageTitle: String
    var pageURL: URL?
    var profileName: String?
    var headline: String
    var debugExcerpt: String
    var quotaEntries: [UsageQuotaEntry]
    var activity: ActivitySnapshot
    var taskSignals: PlatformTaskSignals

    var isLoadingUsageData: Bool {
        let combined = [headline, debugExcerpt, activity.pageBusyState]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        return combined.contains("사용량 데이터 불러오는 중")
            || combined.contains("loading usage")
            || combined.contains("loading data")
            || combined.contains("loading")
    }

    var looksLikePlaceholderContent: Bool {
        let combined = debugExcerpt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !combined.isEmpty else {
            return true
        }

        let placeholders = [
            "skip to content",
            "open sidebar",
            "콘텐츠로 건너뛰기",
            "사이드바 열기"
        ]

        if combined.count < 40 {
            return placeholders.contains { combined.contains($0) }
        }

        return false
    }
}

func normalizeQuotaLabel(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

func quotaTextUsesConsumedWording(_ valueText: String) -> Bool {
    let normalized = valueText.lowercased()
    let hasConsumed = normalized.contains("사용됨")
        || normalized.contains("used")
        || normalized.contains("consumed")
    let hasRemaining = normalized.contains("남음")
        || normalized.contains("remaining")
        || normalized.contains("left")
    return hasConsumed && !hasRemaining
}

func extractQuotaPercent(from valueText: String) -> Double? {
    guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#),
          let match = regex.firstMatch(
              in: valueText,
              range: NSRange(valueText.startIndex..<valueText.endIndex, in: valueText)
          ),
          let valueRange = Range(match.range(at: 1), in: valueText),
          let value = Double(valueText[valueRange])
    else {
        return nil
    }

    let normalized = min(max(value / 100, 0), 1)
    if quotaTextUsesConsumedWording(valueText) {
        return 1 - normalized
    }

    return normalized
}

func displayQuotaValueText(_ valueText: String, progress: Double?) -> String {
    guard quotaTextUsesConsumedWording(valueText) else {
        return valueText
    }

    guard let remaining = progress ?? extractQuotaPercent(from: valueText) else {
        return valueText
    }

    return "\(Int((remaining * 100).rounded()))% 남음"
}
