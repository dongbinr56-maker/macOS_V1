import Foundation

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
