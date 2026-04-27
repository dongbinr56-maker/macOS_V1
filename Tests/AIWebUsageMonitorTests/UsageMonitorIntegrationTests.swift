import XCTest
@testable import AIWebUsageMonitor

@MainActor
final class UsageMonitorIntegrationTests: XCTestCase {
    func testSessionTaskStateFallsBackToIdleWhenOldConversationHasNoRecentActivity() throws {
        let suiteName = "AIWebUsageMonitorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date()
        let session = WebAccountSession(
            id: UUID(),
            platform: .codex,
            displayName: "Codex Idle",
            dataStoreID: UUID(),
            refreshState: .ready,
            lastCheckedAt: now,
            snapshot: UsageSnapshot(
                headline: "사용 가능",
                sourceURL: URL(string: "https://chatgpt.com/codex/settings/usage"),
                debugExcerpt: "quota loaded",
                quota: QuotaSnapshot(
                    entries: [
                        UsageQuotaEntry(
                            label: "5시간 사용 한도",
                            valueText: "100% 남음",
                            progress: 1
                        )
                    ]
                ),
                activity: ActivitySnapshot(
                    lastNetworkAt: now.addingTimeInterval(-5 * 60),
                    lastDOMMutationAt: now.addingTimeInterval(-5 * 60),
                    recentRequestCount: 3,
                    inFlightRequestCount: 0,
                    pageBusyState: "ready"
                ),
                taskSignals: PlatformTaskSignals(
                    conversationTitle: "Usage dashboard",
                    latestUserPromptPreview: "Fix the auth flow",
                    latestAssistantPreview: nil,
                    isStreaming: false,
                    isWaitingForAssistant: true,
                    confidence: 0.55
                ),
                updatedAt: now
            )
        )

        let store = AccountStore(defaults: defaults, inMemoryOnly: true)
        store.saveAccounts([session])

        let viewModel = makeViewModel(store: store)
        let loadedSession = try XCTUnwrap(viewModel.sessions.first)

        XCTAssertEqual(viewModel.activityState(for: loadedSession), .idle)
        XCTAssertEqual(viewModel.sessionTaskState(for: loadedSession), .idle)
    }

    func testSessionTaskStateBecomesWorkingOnlyForRecentExplicitWorkSignals() throws {
        let suiteName = "AIWebUsageMonitorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date()
        let session = WebAccountSession(
            id: UUID(),
            platform: .codex,
            displayName: "Codex Working",
            dataStoreID: UUID(),
            refreshState: .ready,
            lastCheckedAt: now,
            snapshot: UsageSnapshot(
                headline: "사용 가능",
                sourceURL: URL(string: "https://chatgpt.com/codex/settings/usage"),
                debugExcerpt: "quota loaded",
                quota: QuotaSnapshot(
                    entries: [
                        UsageQuotaEntry(
                            label: "5시간 사용 한도",
                            valueText: "100% 남음",
                            progress: 1
                        )
                    ]
                ),
                activity: ActivitySnapshot(
                    lastNetworkAt: now.addingTimeInterval(-5),
                    lastDOMMutationAt: now.addingTimeInterval(-3),
                    recentRequestCount: 1,
                    inFlightRequestCount: 0,
                    pageBusyState: "ready"
                ),
                taskSignals: PlatformTaskSignals(
                    conversationTitle: "Implement office scene",
                    latestUserPromptPreview: "Rebuild the layout",
                    latestAssistantPreview: "Inspecting files",
                    isStreaming: false,
                    isWaitingForAssistant: false,
                    busyIndicatorText: "Searching project",
                    confidence: 0.7
                ),
                updatedAt: now
            )
        )

        let store = AccountStore(defaults: defaults, inMemoryOnly: true)
        store.saveAccounts([session])

        let viewModel = makeViewModel(store: store)
        let loadedSession = try XCTUnwrap(viewModel.sessions.first)

        XCTAssertEqual(viewModel.sessionTaskState(for: loadedSession), .working)
    }

    func testLocalLogSnapshotMarksClaudeSessionAsWaitingWhenWebConfidenceIsLow() throws {
        let suiteName = "AIWebUsageMonitorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date()
        let session = WebAccountSession(
            id: UUID(),
            platform: .claude,
            displayName: "Claude Log Waiting",
            dataStoreID: UUID(),
            refreshState: .ready,
            lastCheckedAt: now,
            snapshot: UsageSnapshot(
                headline: "사용 가능",
                sourceURL: URL(string: "https://claude.ai/settings/usage"),
                debugExcerpt: "quota loaded",
                quota: QuotaSnapshot(
                    entries: [
                        UsageQuotaEntry(
                            label: "Weekly usage limit",
                            valueText: "80% remaining",
                            progress: 0.8
                        )
                    ]
                ),
                activity: ActivitySnapshot(
                    lastNetworkAt: now.addingTimeInterval(-150),
                    lastDOMMutationAt: now.addingTimeInterval(-150),
                    recentRequestCount: 0,
                    inFlightRequestCount: 0,
                    pageBusyState: "ready"
                ),
                taskSignals: PlatformTaskSignals(
                    latestUserPromptPreview: "old prompt",
                    isStreaming: false,
                    isWaitingForAssistant: false,
                    confidence: 0.2
                ),
                updatedAt: now
            )
        )

        let store = AccountStore(defaults: defaults, inMemoryOnly: true)
        store.saveAccounts([session])

        let viewModel = makeViewModel(store: store)
        viewModel.applyLocalLogSnapshot(
            LocalLogSnapshot(
                state: .waiting,
                lastObservedAt: now,
                summary: "Claude 로컬 로그에서 요청 수신 신호가 감지되었습니다."
            ),
            for: .claude
        )

        let loadedSession = try XCTUnwrap(viewModel.sessions.first)
        XCTAssertEqual(viewModel.sessionTaskState(for: loadedSession), .waiting)
    }

    func testLocalLogSnapshotDoesNotOverrideStrongWebSignals() throws {
        let suiteName = "AIWebUsageMonitorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date()
        let session = WebAccountSession(
            id: UUID(),
            platform: .claude,
            displayName: "Claude Strong Signals",
            dataStoreID: UUID(),
            refreshState: .ready,
            lastCheckedAt: now,
            snapshot: UsageSnapshot(
                headline: "사용 가능",
                sourceURL: URL(string: "https://claude.ai/settings/usage"),
                debugExcerpt: "quota loaded",
                quota: QuotaSnapshot(
                    entries: [
                        UsageQuotaEntry(
                            label: "Weekly usage limit",
                            valueText: "78% remaining",
                            progress: 0.78
                        )
                    ]
                ),
                activity: ActivitySnapshot(
                    lastNetworkAt: now,
                    lastDOMMutationAt: now,
                    recentRequestCount: 1,
                    inFlightRequestCount: 1,
                    pageBusyState: "loading"
                ),
                taskSignals: PlatformTaskSignals(
                    latestUserPromptPreview: "Build monitor",
                    latestAssistantPreview: "Responding now",
                    isStreaming: true,
                    isWaitingForAssistant: false,
                    confidence: 0.92
                ),
                updatedAt: now
            )
        )

        let store = AccountStore(defaults: defaults, inMemoryOnly: true)
        store.saveAccounts([session])

        let viewModel = makeViewModel(store: store)
        viewModel.applyLocalLogSnapshot(
            LocalLogSnapshot(
                state: .idle,
                lastObservedAt: now,
                summary: "Claude 로컬 로그에서 최근 작업 신호가 없습니다."
            ),
            for: .claude
        )

        let loadedSession = try XCTUnwrap(viewModel.sessions.first)
        XCTAssertEqual(viewModel.sessionTaskState(for: loadedSession), .responding)
    }

    func testAccountStoreRoundTripsTaskSignalsAndCleansAlertStatesForRemovedSession() throws {
        let suiteName = "AIWebUsageMonitorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AccountStore(defaults: defaults, inMemoryOnly: true)
        let sessionID = UUID()
        let account = WebAccountSession(
            id: sessionID,
            platform: .codex,
            displayName: "Codex Ops",
            profileName: "ops@example.com",
            dataStoreID: UUID(),
            refreshState: .ready,
            lastCheckedAt: Date(),
            snapshot: UsageSnapshot(
                headline: "사용 가능",
                sourceURL: URL(string: "https://chatgpt.com/codex/settings/usage"),
                debugExcerpt: "quota loaded",
                quota: QuotaSnapshot(
                    entries: [
                        UsageQuotaEntry(
                            label: "5시간 사용 한도",
                            valueText: "42% 남음",
                            resetText: "40분 후 재설정",
                            progress: 0.42
                        )
                    ]
                ),
                activity: ActivitySnapshot(
                    lastNetworkAt: Date(),
                    lastDOMMutationAt: Date(),
                    recentRequestCount: 2,
                    inFlightRequestCount: 1,
                    pageBusyState: "loading"
                ),
                taskSignals: PlatformTaskSignals(
                    conversationTitle: "Fix login redirect race",
                    latestUserPromptPreview: "로그인 레이스 컨디션 수정",
                    latestAssistantPreview: "응답 생성 중",
                    isStreaming: true,
                    isWaitingForAssistant: true,
                    hasBlockingError: false,
                    requiresLogin: false,
                    busyIndicatorText: "생성 중",
                    confidence: 0.84
                ),
                updatedAt: Date()
            )
        )

        store.saveAccounts([account])
        store.saveAlertState(
            key: "alert::\(sessionID.uuidString)::quota-5시간 사용 한도",
            level: "lowQuota"
        )

        let loaded = try XCTUnwrap(store.loadAccounts().first)
        let loadedSignals = try XCTUnwrap(loaded.snapshot?.taskSignals)

        XCTAssertEqual(loadedSignals.conversationTitle, "Fix login redirect race")
        XCTAssertEqual(loadedSignals.latestUserPromptPreview, "로그인 레이스 컨디션 수정")
        XCTAssertEqual(loadedSignals.latestAssistantPreview, "응답 생성 중")
        XCTAssertTrue(loadedSignals.isStreaming)
        XCTAssertTrue(loadedSignals.isWaitingForAssistant)
        XCTAssertEqual(loadedSignals.busyIndicatorText, "생성 중")
        XCTAssertEqual(loadedSignals.confidence, 0.84, accuracy: 0.001)
        XCTAssertEqual(store.loadAlertStates().count, 1)

        store.saveAccounts([])

        XCTAssertTrue(store.loadAccounts().isEmpty)
        XCTAssertTrue(store.loadAlertStates().isEmpty)
    }

    func testAccountStoreRestoresAccountsFromBackupWhenStoreIsEphemeral() throws {
        let suiteName = "AIWebUsageMonitorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let originalStore = AccountStore(defaults: defaults, inMemoryOnly: true)
        let account = WebAccountSession(
            id: UUID(),
            platform: .cursor,
            displayName: "Cursor Persisted",
            profileName: "cursor@example.com",
            dataStoreID: UUID(),
            refreshState: .ready,
            lastCheckedAt: Date()
        )

        originalStore.saveAccounts([account])

        let reloadedStore = AccountStore(defaults: defaults, inMemoryOnly: true)
        let restored = try XCTUnwrap(reloadedStore.loadAccounts().first)

        XCTAssertEqual(restored.id, account.id)
        XCTAssertEqual(restored.displayName, "Cursor Persisted")
        XCTAssertEqual(restored.profileName, "cursor@example.com")
        XCTAssertEqual(reloadedStore.loadAccounts().count, 1)
    }

    func testLoggedOutPayloadClearsSnapshotAndMarksSessionAsLoginRequired() throws {
        let suiteName = "AIWebUsageMonitorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let account = WebAccountSession(
            id: UUID(),
            platform: .claude,
            displayName: "Claude Session",
            refreshState: .ready,
            lastCheckedAt: Date(),
            snapshot: UsageSnapshot(
                headline: "기존 스냅샷",
                sourceURL: URL(string: "https://claude.ai/settings/usage"),
                debugExcerpt: "old snapshot",
                quota: QuotaSnapshot(
                    entries: [
                        UsageQuotaEntry(
                            label: "Weekly usage limit",
                            valueText: "61% remaining",
                            resetText: "resets in 2 days",
                            progress: 0.61
                        )
                    ]
                ),
                activity: ActivitySnapshot(lastNetworkAt: Date(), recentRequestCount: 1),
                taskSignals: PlatformTaskSignals(
                    conversationTitle: "Old conversation",
                    latestUserPromptPreview: "Old prompt",
                    latestAssistantPreview: "Old reply",
                    isStreaming: false,
                    isWaitingForAssistant: false,
                    confidence: 0.7
                ),
                updatedAt: Date()
            )
        )

        let store = AccountStore(defaults: defaults, inMemoryOnly: true)
        store.saveAccounts([account])

        let viewModel = UsageMonitorViewModel(
            sessionManager: WebSessionManager(),
            accountStore: store,
            alertManager: UsageAlertManager(accountStore: store),
            launchAtLoginManager: LaunchAtLoginManager(),
            refreshInterval: 60,
            lowQuotaThreshold: 0.20,
            idleThreshold: 10 * 60,
            staleThreshold: 15 * 60,
            refreshConcurrencyLimit: 2
        )

        viewModel.applyRefreshPayload(
            PlatformScrapePayload(
                isLoggedIn: false,
                pageTitle: "Claude",
                pageURL: URL(string: "https://claude.ai"),
                profileName: "claude-user@example.com",
                headline: "",
                debugExcerpt: "",
                quotaEntries: [],
                activity: ActivitySnapshot(),
                taskSignals: PlatformTaskSignals(requiresLogin: true, confidence: 0.5)
            ),
            for: account.id,
            platform: .claude,
            isReliableSnapshot: { _ in true }
        )

        let updated = try XCTUnwrap(viewModel.sessions.first)
        XCTAssertEqual(updated.refreshState, .requiresLogin)
        XCTAssertEqual(updated.profileName, "claude-user@example.com")
        XCTAssertNil(updated.snapshot)
        XCTAssertEqual(updated.lastErrorDescription, "로그인 상태를 확인하지 못했습니다. 로그인 창을 다시 열어 주세요.")
    }

    private func makeViewModel(store: AccountStore) -> UsageMonitorViewModel {
        UsageMonitorViewModel(
            sessionManager: WebSessionManager(),
            accountStore: store,
            alertManager: UsageAlertManager(accountStore: store),
            launchAtLoginManager: LaunchAtLoginManager(),
            refreshInterval: 60,
            lowQuotaThreshold: 0.20,
            idleThreshold: 10 * 60,
            staleThreshold: 15 * 60,
            refreshConcurrencyLimit: 2
        )
    }
}
