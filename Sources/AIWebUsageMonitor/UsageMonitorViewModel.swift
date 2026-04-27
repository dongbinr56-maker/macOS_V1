import Foundation

@MainActor
final class UsageMonitorViewModel: ObservableObject {
    @Published private(set) var sessions: [WebAccountSession]
    @Published private(set) var isRefreshingAll = false
    @Published private(set) var lastFullRefreshAt: Date?
    @Published private(set) var launchAtLoginManager: LaunchAtLoginManager
    @Published private(set) var notificationAuthorizationState: UsageAlertManager.AuthorizationState = .notDetermined

    private let sessionManager: WebSessionManager
    private let accountStore: AccountStore
    private let alertManager: UsageAlertManager
    private let refreshInterval: TimeInterval
    private let lowQuotaThreshold: Double
    private let idleThreshold: TimeInterval
    private let staleThreshold: TimeInterval
    private let refreshConcurrencyLimit: Int
    private let localLogMonitor: LocalLogMonitor
    private var timer: Timer?
    private var refreshInFlight = Set<UUID>()
    private var localLogSnapshots: [AIPlatform: LocalLogSnapshot] = [:]
    private var lastLocalLogRefreshAt: Date?

    private struct SessionMetrics {
        var total = 0
        var available = 0
        var low = 0
        var blocked = 0
        var requiresLogin = 0
        var failed = 0
        var loading = 0
        var idle = 0
        var stale = 0
    }

    var overallStatusSummary: PlatformHealthSummary {
        let metrics = aggregateMetrics()

        guard metrics.total > 0 else {
            return PlatformHealthSummary(
                health: .empty,
                title: "세션 없음",
                subtitle: "Codex, Claude, Cursor 세션을 추가하면 상태를 모니터링할 수 있습니다.",
                symbolName: "circle.dashed",
                accessibilityLabel: "세션 없음"
            )
        }

        if metrics.loading == metrics.total || isRefreshingAll {
            return PlatformHealthSummary(
                health: .checking,
                title: "확인 중",
                subtitle: "웹 세션에서 최신 사용량과 활동 상태를 다시 읽고 있습니다.",
                symbolName: "arrow.triangle.2.circlepath.circle.fill",
                accessibilityLabel: "세션 상태 확인 중"
            )
        }

        if metrics.blocked == metrics.total {
            return PlatformHealthSummary(
                health: .blocked,
                title: "전체 사용 불가",
                subtitle: "연결된 모든 세션에서 주요 사용량 한도가 소진되었습니다.",
                symbolName: "xmark.circle.fill",
                accessibilityLabel: "전체 사용 불가"
            )
        }

        if metrics.requiresLogin == metrics.total {
            return PlatformHealthSummary(
                health: .requiresLogin,
                title: "로그인 필요",
                subtitle: "연결된 모든 세션에서 로그인 확인이 필요합니다.",
                symbolName: "person.crop.circle.badge.exclamationmark",
                accessibilityLabel: "전체 로그인 필요"
            )
        }

        if metrics.failed > 0 && (metrics.available + metrics.low + metrics.blocked == 0) {
            return PlatformHealthSummary(
                health: .failed,
                title: "확인 실패",
                subtitle: "사용량 카드 파싱 또는 세션 갱신에 실패한 계정이 있습니다.",
                symbolName: "exclamationmark.triangle.fill",
                accessibilityLabel: "세션 확인 실패"
            )
        }

        if metrics.stale == metrics.total {
            return PlatformHealthSummary(
                health: .stale,
                title: "세션 지연",
                subtitle: "모든 세션의 마지막 성공 갱신 시각이 오래되었습니다.",
                symbolName: "clock.badge.exclamationmark.fill",
                accessibilityLabel: "세션 지연"
            )
        }

        if metrics.idle == metrics.total {
            return PlatformHealthSummary(
                health: .available,
                title: "정상 모니터링",
                subtitle: "모든 세션이 안정적으로 연결되어 있습니다.",
                symbolName: "checkmark.circle.fill",
                accessibilityLabel: "정상 모니터링"
            )
        }

        if metrics.low > 0 || metrics.blocked > 0 || metrics.failed > 0 || metrics.requiresLogin > 0 || metrics.stale > 0 {
            return PlatformHealthSummary(
                health: .low,
                title: "주의 필요",
                subtitle: makeAttentionSubtitle(from: metrics),
                symbolName: "exclamationmark.circle.fill",
                accessibilityLabel: "주의 필요"
            )
        }

        return PlatformHealthSummary(
            health: .available,
            title: "정상 동작 중",
            subtitle: "\(metrics.available)개 세션을 안정적으로 모니터링 중입니다.",
            symbolName: "checkmark.circle.fill",
            accessibilityLabel: "정상 동작 중"
        )
    }

    var overviewText: String {
        let metrics = aggregateMetrics()
        guard metrics.total > 0 else {
            return "세션을 추가해 모니터링을 시작하세요."
        }

        let healthy = metrics.available + metrics.low
        if healthy > 0 {
            return "\(healthy) / \(metrics.total)개 세션 사용 가능"
        }

        if metrics.requiresLogin > 0 {
            return "로그인 필요 세션 \(metrics.requiresLogin)개"
        }

        if metrics.failed > 0 {
            return "확인 실패 세션 \(metrics.failed)개"
        }

        return "세션 상태를 다시 확인하는 중입니다."
    }

    convenience init() {
        let accountStore = AccountStore()
        self.init(
            sessionManager: WebSessionManager(),
            accountStore: accountStore,
            alertManager: UsageAlertManager(accountStore: accountStore),
            launchAtLoginManager: LaunchAtLoginManager(),
            refreshInterval: 60,
            lowQuotaThreshold: 0.20,
            idleThreshold: 10 * 60,
            staleThreshold: 15 * 60,
            refreshConcurrencyLimit: 2,
            localLogMonitor: LocalLogMonitor()
        )
    }

    init(
        sessionManager: WebSessionManager,
        accountStore: AccountStore,
        alertManager: UsageAlertManager,
        launchAtLoginManager: LaunchAtLoginManager,
        refreshInterval: TimeInterval,
        lowQuotaThreshold: Double,
        idleThreshold: TimeInterval,
        staleThreshold: TimeInterval,
        refreshConcurrencyLimit: Int,
        localLogMonitor: LocalLogMonitor = LocalLogMonitor()
    ) {
        self.sessionManager = sessionManager
        self.accountStore = accountStore
        self.alertManager = alertManager
        self.launchAtLoginManager = launchAtLoginManager
        self.refreshInterval = refreshInterval
        self.lowQuotaThreshold = lowQuotaThreshold
        self.idleThreshold = idleThreshold
        self.staleThreshold = staleThreshold
        self.refreshConcurrencyLimit = max(1, refreshConcurrencyLimit)
        self.localLogMonitor = localLogMonitor
        self.sessions = accountStore.loadAccounts()

        for account in sessions {
            sessionManager.register(account: account)
        }
    }

    func start() {
        refreshNotificationAuthorizationStatus()
        startAutoRefresh()
        Task {
            await refreshLocalLogSnapshotsIfNeeded(force: true)
        }

        guard !sessions.isEmpty else {
            return
        }

        Task {
            await refreshAll()
        }
    }

    func sessions(for platform: AIPlatform) -> [WebAccountSession] {
        sessions
            .filter { $0.platform == platform }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func addAccount(for platform: AIPlatform) {
        let nextIndex = sessions.filter { $0.platform == platform }.count + 1
        let account = WebAccountSession(
            platform: platform,
            displayName: "\(platform.displayName) \(nextIndex)"
        )

        sessions.append(account)
        sessionManager.register(account: account)
        persistAccounts()

        do {
            try sessionManager.presentLoginWindow(
                for: account,
                onAuthenticated: { [weak self] in
                    Task { @MainActor in
                        await self?.refresh(accountID: account.id)
                    }
                },
                onClose: { [weak self] in
                    Task { @MainActor in
                        await self?.refresh(accountID: account.id)
                    }
                }
            )
        } catch {
            updateAccount(account.id) {
                $0.refreshState = .failed
                $0.lastErrorDescription = error.localizedDescription
            }
            persistAccounts()
        }
    }

    func reopenLoginWindow(for accountID: UUID) {
        guard let account = sessions.first(where: { $0.id == accountID }) else {
            return
        }

        do {
            try sessionManager.presentLoginWindow(
                for: account,
                onAuthenticated: { [weak self] in
                    Task { @MainActor in
                        await self?.refresh(accountID: account.id)
                    }
                },
                onClose: { [weak self] in
                    Task { @MainActor in
                        await self?.refresh(accountID: account.id)
                    }
                }
            )
        } catch {
            updateAccount(account.id) {
                $0.refreshState = .failed
                $0.lastErrorDescription = error.localizedDescription
            }
            persistAccounts()
        }
    }

    func renameAccount(accountID: UUID, displayName: String) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        updateAccount(accountID) {
            $0.displayName = trimmed
            $0.usesAutoDisplayName = false
        }
        persistAccounts()
    }

    func removeAccount(accountID: UUID) {
        guard let account = sessions.first(where: { $0.id == accountID }) else {
            return
        }

        sessions.removeAll { $0.id == accountID }
        let shouldRemoveDataStore = !sessions.contains { $0.dataStoreID == account.dataStoreID }
        persistAccounts()

        Task {
            await sessionManager.unregister(
                accountID: account.id,
                dataStoreID: account.dataStoreID,
                removeDataStore: shouldRemoveDataStore
            )
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginManager.setEnabled(enabled)
        objectWillChange.send()
    }

    func sendTestNotification() {
        alertManager.sendTestNotification()
    }

    func requestNotificationAuthorization() {
        alertManager.requestAuthorization { [weak self] state in
            Task { @MainActor in
                self?.notificationAuthorizationState = state
            }
        }
    }

    func refreshNotificationAuthorizationStatus() {
        alertManager.fetchAuthorizationStatus { [weak self] state in
            Task { @MainActor in
                self?.notificationAuthorizationState = state
            }
        }
    }

    func openSystemNotificationSettings() {
        alertManager.openSystemNotificationSettings()
    }

    func refreshAll() async {
        guard !isRefreshingAll else {
            return
        }

        isRefreshingAll = true
        defer { isRefreshingAll = false }
        await refreshLocalLogSnapshotsIfNeeded()

        let accountIDs = sessions.map(\.id)
        guard !accountIDs.isEmpty else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            var iterator = accountIDs.makeIterator()
            let parallelCount = min(refreshConcurrencyLimit, accountIDs.count)

            for _ in 0..<parallelCount {
                guard let accountID = iterator.next() else {
                    break
                }
                group.addTask { [weak self] in
                    await self?.refresh(accountID: accountID)
                }
            }

            while await group.next() != nil {
                guard let accountID = iterator.next() else {
                    continue
                }

                group.addTask { [weak self] in
                    await self?.refresh(accountID: accountID)
                }
            }
        }

        lastFullRefreshAt = Date()
    }

    func refresh(accountIDs: [UUID]) async {
        let uniqueIDs = Array(NSOrderedSet(array: accountIDs)) as? [UUID] ?? accountIDs
        let filteredIDs = uniqueIDs.filter { id in
            sessions.contains(where: { $0.id == id })
        }

        guard !filteredIDs.isEmpty else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            var iterator = filteredIDs.makeIterator()
            let parallelCount = min(refreshConcurrencyLimit, filteredIDs.count)

            for _ in 0..<parallelCount {
                guard let accountID = iterator.next() else {
                    break
                }
                group.addTask { [weak self] in
                    await self?.refresh(accountID: accountID)
                }
            }

            while await group.next() != nil {
                guard let accountID = iterator.next() else {
                    continue
                }

                group.addTask { [weak self] in
                    await self?.refresh(accountID: accountID)
                }
            }
        }
    }

    func refresh(accountID: UUID) async {
        guard !refreshInFlight.contains(accountID) else {
            return
        }

        guard let account = sessions.first(where: { $0.id == accountID }) else {
            return
        }

        let adapter = PlatformRegistry.adapter(for: account.platform)
        refreshInFlight.insert(accountID)
        updateAccount(accountID) {
            $0.refreshState = .loading
            $0.lastErrorDescription = nil
        }
        persistAccounts()

        defer {
            refreshInFlight.remove(accountID)
            persistAccounts()
        }

        do {
            let payload = try await sessionManager.refreshUsage(for: account)
            applyRefreshPayload(
                payload,
                for: accountID,
                platform: account.platform,
                isReliableSnapshot: { snapshot in
                    adapter.isReliableSnapshot(snapshot)
                }
            )
        } catch {
            updateAccount(accountID) {
                $0.refreshState = .failed
                $0.lastCheckedAt = Date()
                $0.lastErrorDescription = error.localizedDescription
            }
        }

        if let updatedAccount = sessions.first(where: { $0.id == accountID }) {
            alertManager.evaluateAlerts(
                for: updatedAccount,
                lowQuotaThreshold: lowQuotaThreshold,
                idleThreshold: idleThreshold,
                staleThreshold: staleThreshold
            )
        }
    }

    func activityState(for session: WebAccountSession) -> SessionActivityState {
        session.activityState(idleThreshold: idleThreshold, staleThreshold: staleThreshold)
    }

    func availability(for session: WebAccountSession) -> SessionAvailability {
        session.availability(lowQuotaThreshold: lowQuotaThreshold)
    }

    func sessionTaskContext(for session: WebAccountSession) -> SessionTaskContext {
        taskContext(for: session)
    }

    func applyLocalLogSnapshot(_ snapshot: LocalLogSnapshot?, for platform: AIPlatform) {
        objectWillChange.send()
        if let snapshot {
            localLogSnapshots[platform] = snapshot
        } else {
            localLogSnapshots.removeValue(forKey: platform)
        }
        lastLocalLogRefreshAt = Date()
    }

    func sessionTaskState(for session: WebAccountSession) -> SessionTaskState {
        let availability = availability(for: session)
        let activity = activityState(for: session)
        let context = taskContext(for: session)
        return taskState(
            for: session,
            availability: availability,
            activity: activity,
            context: context
        )
    }

    func presentationState(for session: WebAccountSession) -> PresentationState {
        let taskState = sessionTaskState(for: session)
        switch taskState {
        case .working, .responding:
            return .working
        case .waiting:
            return .waiting
        case .idle:
            return .idle
        case .quotaLow, .stale:
            return .atRisk
        case .needsLogin, .blocked, .error:
            return .blocked
        }
    }

    private func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
    }

    private func updateAccount(_ accountID: UUID, mutate: (inout WebAccountSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == accountID }) else {
            return
        }

        mutate(&sessions[index])
    }

    func applyRefreshPayload(
        _ payload: PlatformScrapePayload,
        for accountID: UUID,
        platform: AIPlatform,
        isReliableSnapshot: (UsageSnapshot) -> Bool
    ) {
        if payload.isLoggedIn {
            let snapshot = UsageSnapshot(
                headline: payload.headline,
                sourceURL: payload.pageURL,
                debugExcerpt: payload.debugExcerpt,
                quota: QuotaSnapshot(entries: payload.quotaEntries),
                activity: payload.activity,
                taskSignals: payload.taskSignals,
                updatedAt: Date()
            )

            if isReliableSnapshot(snapshot) {
                updateAccount(accountID) {
                    $0.profileName = payload.profileName
                    if $0.usesAutoDisplayName, let profileName = payload.profileName, !profileName.isEmpty {
                        $0.displayName = profileName
                    }
                    $0.refreshState = .ready
                    $0.lastCheckedAt = Date()
                    $0.snapshot = snapshot
                    $0.lastErrorDescription = nil
                }
            } else {
                updateAccount(accountID) {
                    $0.profileName = payload.profileName
                    $0.refreshState = .failed
                    $0.lastCheckedAt = Date()
                    $0.snapshot = snapshot
                    $0.lastErrorDescription = "\(platform.displayName) 사용량 카드를 읽지 못했습니다. 로그인 창에서 usage 페이지가 정상적으로 보이는지 확인한 뒤 다시 새로고침해 주세요."
                }
            }
        } else {
            updateAccount(accountID) {
                $0.profileName = payload.profileName
                $0.refreshState = .requiresLogin
                $0.lastCheckedAt = Date()
                $0.snapshot = nil
                $0.lastErrorDescription = "로그인 상태를 확인하지 못했습니다. 로그인 창을 다시 열어 주세요."
            }
        }
    }

    private func persistAccounts() {
        accountStore.saveAccounts(sessions)
    }

    private func aggregateMetrics() -> SessionMetrics {
        var metrics = SessionMetrics(total: sessions.count)

        for session in sessions {
            switch session.refreshState {
            case .idle:
                break
            case .loading:
                metrics.loading += 1
            case .requiresLogin:
                metrics.requiresLogin += 1
            case .failed:
                metrics.failed += 1
                classifySnapshotMetrics(for: session, into: &metrics)
            case .ready:
                classifySnapshotMetrics(for: session, into: &metrics)
            }
        }

        return metrics
    }

    private func classifySnapshotMetrics(for session: WebAccountSession, into metrics: inout SessionMetrics) {
        switch session.availability(lowQuotaThreshold: lowQuotaThreshold) {
        case .available:
            metrics.available += 1
        case .low:
            metrics.low += 1
        case .blocked:
            metrics.blocked += 1
        case .unknown:
            break
        }

        switch session.activityState(idleThreshold: idleThreshold, staleThreshold: staleThreshold) {
        case .idle:
            metrics.idle += 1
        case .stale:
            metrics.stale += 1
        case .unknown, .loading, .active, .waiting:
            break
        }
    }

    private func makeAttentionSubtitle(from metrics: SessionMetrics) -> String {
        let segments = [
            metrics.low > 0 ? "한도 주의 \(metrics.low)개" : nil,
            metrics.blocked > 0 ? "차단 \(metrics.blocked)개" : nil,
            metrics.requiresLogin > 0 ? "로그인 필요 \(metrics.requiresLogin)개" : nil,
            metrics.failed > 0 ? "실패 \(metrics.failed)개" : nil,
            metrics.stale > 0 ? "지연 \(metrics.stale)개" : nil
        ].compactMap { $0 }

        return segments.joined(separator: " · ")
    }
}

extension UsageMonitorViewModel {
    private func taskContext(for session: WebAccountSession) -> SessionTaskContext {
        let localLogSnapshot = localLogSnapshots[session.platform]
        let signals = session.snapshot?.taskSignals ?? PlatformTaskSignals()
        let lastMeaningfulActivityAt = [
            session.snapshot?.activity.lastNetworkAt,
            session.snapshot?.activity.lastDOMMutationAt
        ]
        .compactMap { $0 }
        .max()

        return SessionTaskContext(
            conversationTitle: signals.confidence >= 0.25 ? signals.meaningfulConversationTitle : nil,
            latestUserPromptPreview: signals.normalizedLatestUserPromptPreview,
            latestAssistantStateText: signals.normalizedLatestAssistantPreview
                ?? (signals.confidence >= 0.2 ? signals.normalizedBusyIndicatorText : nil)
                ?? localLogSnapshot?.summary,
            isStreamingResponse: signals.confidence >= 0.3 && signals.isStreaming,
            isUserWaitingForReply: signals.confidence >= 0.28 && signals.isWaitingForAssistant,
            lastMeaningfulActivityAt: lastMeaningfulActivityAt,
            sourceConfidence: signals.confidence
        )
    }

    private func taskState(
        for session: WebAccountSession,
        availability: SessionAvailability,
        activity: SessionActivityState,
        context: SessionTaskContext
    ) -> SessionTaskState {
        if session.refreshState == .failed {
            return .error
        }

        if session.refreshState == .requiresLogin {
            return .needsLogin
        }

        if availability == .blocked {
            return .blocked
        }

        if activity == .stale {
            return .stale
        }

        if availability == .low {
            return .quotaLow
        }

        if let localState = localLogTaskState(for: session.platform),
           shouldApplyLocalLogState(localState, context: context) {
            return localState
        }

        let hasRecentTaskActivity = isRecent(context.lastMeaningfulActivityAt, within: 90)

        if context.isStreamingResponse && hasRecentTaskActivity {
            return .responding
        }

        if context.isUserWaitingForReply && hasRecentTaskActivity {
            return .waiting
        }

        if isActivelyWorking(session, context: context) {
            return .working
        }

        switch activity {
        case .idle, .unknown, .waiting, .active, .loading, .stale:
            return .idle
        }
    }

    private func isRecent(_ timestamp: Date?, within threshold: TimeInterval, now: Date = Date()) -> Bool {
        guard let timestamp else {
            return false
        }

        return now.timeIntervalSince(timestamp) <= threshold
    }

    private func isActivelyWorking(
        _ session: WebAccountSession,
        context: SessionTaskContext,
        now: Date = Date()
    ) -> Bool {
        guard let snapshot = session.snapshot else {
            return false
        }

        guard context.sourceConfidence >= 0.45 else {
            return false
        }

        let hasRecentActivity =
            isRecent(snapshot.activity.lastNetworkAt, within: 20, now: now)
            || isRecent(snapshot.activity.lastDOMMutationAt, within: 20, now: now)

        guard hasRecentActivity else {
            return false
        }

        return snapshot.taskSignals.normalizedBusyIndicatorText != nil
            || snapshot.taskSignals.normalizedLatestAssistantPreview != nil
    }

    private func localLogTaskState(for platform: AIPlatform, now: Date = Date()) -> SessionTaskState? {
        guard let snapshot = localLogSnapshots[platform] else {
            return nil
        }

        guard now.timeIntervalSince(snapshot.lastObservedAt) <= 120 else {
            return nil
        }

        switch snapshot.state {
        case .waiting:
            return .waiting
        case .working:
            return .working
        case .idle:
            return .idle
        }
    }

    private func shouldApplyLocalLogState(_ state: SessionTaskState, context: SessionTaskContext) -> Bool {
        switch state {
        case .working, .waiting:
            return context.sourceConfidence < 0.55 && !isRecent(context.lastMeaningfulActivityAt, within: 25)
        case .idle:
            return context.sourceConfidence < 0.35
        case .responding, .needsLogin, .quotaLow, .blocked, .stale, .error:
            return false
        }
    }

    private func refreshLocalLogSnapshotsIfNeeded(force: Bool = false, now: Date = Date()) async {
        let shouldRefresh = force || localLogSnapshots.isEmpty || {
            guard let lastLocalLogRefreshAt else {
                return true
            }
            return now.timeIntervalSince(lastLocalLogRefreshAt) >= 2
        }()

        guard shouldRefresh else {
            return
        }

        let snapshots = await localLogMonitor.captureSnapshots(now: now)
        guard snapshots != localLogSnapshots else {
            lastLocalLogRefreshAt = now
            return
        }

        objectWillChange.send()
        localLogSnapshots = snapshots
        lastLocalLogRefreshAt = now
    }

}
