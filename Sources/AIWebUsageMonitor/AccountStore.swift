import Foundation
import SwiftData

@Model
final class StoredSession {
    @Attribute(.unique) var id: String
    var platformRawValue: String
    var displayName: String
    var profileName: String?
    var usesAutoDisplayName: Bool
    var dataStoreID: String
    var createdAt: Date
    var refreshStateRawValue: String
    var lastCheckedAt: Date?
    var lastErrorDescription: String?

    init(
        id: String,
        platformRawValue: String,
        displayName: String,
        profileName: String?,
        usesAutoDisplayName: Bool,
        dataStoreID: String,
        createdAt: Date,
        refreshStateRawValue: String,
        lastCheckedAt: Date?,
        lastErrorDescription: String?
    ) {
        self.id = id
        self.platformRawValue = platformRawValue
        self.displayName = displayName
        self.profileName = profileName
        self.usesAutoDisplayName = usesAutoDisplayName
        self.dataStoreID = dataStoreID
        self.createdAt = createdAt
        self.refreshStateRawValue = refreshStateRawValue
        self.lastCheckedAt = lastCheckedAt
        self.lastErrorDescription = lastErrorDescription
    }
}

@Model
final class StoredSnapshot {
    @Attribute(.unique) var sessionID: String
    var headline: String
    var sourceURLString: String?
    var debugExcerpt: String
    var updatedAt: Date
    var lastNetworkAt: Date?
    var lastDOMMutationAt: Date?
    var recentRequestCount: Int
    var inFlightRequestCount: Int
    var pageBusyState: String?
    var conversationTitle: String?
    var latestUserPromptPreview: String?
    var latestAssistantPreview: String?
    var isStreaming: Bool
    var isWaitingForAssistant: Bool
    var hasBlockingError: Bool
    var requiresLogin: Bool
    var busyIndicatorText: String?
    var taskConfidence: Double

    init(
        sessionID: String,
        headline: String,
        sourceURLString: String?,
        debugExcerpt: String,
        updatedAt: Date,
        lastNetworkAt: Date?,
        lastDOMMutationAt: Date?,
        recentRequestCount: Int,
        inFlightRequestCount: Int,
        pageBusyState: String?,
        conversationTitle: String? = nil,
        latestUserPromptPreview: String? = nil,
        latestAssistantPreview: String? = nil,
        isStreaming: Bool = false,
        isWaitingForAssistant: Bool = false,
        hasBlockingError: Bool = false,
        requiresLogin: Bool = false,
        busyIndicatorText: String? = nil,
        taskConfidence: Double = 0
    ) {
        self.sessionID = sessionID
        self.headline = headline
        self.sourceURLString = sourceURLString
        self.debugExcerpt = debugExcerpt
        self.updatedAt = updatedAt
        self.lastNetworkAt = lastNetworkAt
        self.lastDOMMutationAt = lastDOMMutationAt
        self.recentRequestCount = recentRequestCount
        self.inFlightRequestCount = inFlightRequestCount
        self.pageBusyState = pageBusyState
        self.conversationTitle = conversationTitle
        self.latestUserPromptPreview = latestUserPromptPreview
        self.latestAssistantPreview = latestAssistantPreview
        self.isStreaming = isStreaming
        self.isWaitingForAssistant = isWaitingForAssistant
        self.hasBlockingError = hasBlockingError
        self.requiresLogin = requiresLogin
        self.busyIndicatorText = busyIndicatorText
        self.taskConfidence = taskConfidence
    }
}

@Model
final class StoredQuotaMetric {
    var sessionID: String
    var sortOrder: Int
    var label: String
    var valueText: String
    var resetText: String?
    var progress: Double?

    init(
        sessionID: String,
        sortOrder: Int,
        label: String,
        valueText: String,
        resetText: String?,
        progress: Double?
    ) {
        self.sessionID = sessionID
        self.sortOrder = sortOrder
        self.label = label
        self.valueText = valueText
        self.resetText = resetText
        self.progress = progress
    }
}

@Model
final class StoredAlertState {
    @Attribute(.unique) var key: String
    var level: String
    var updatedAt: Date

    init(key: String, level: String, updatedAt: Date) {
        self.key = key
        self.level = level
        self.updatedAt = updatedAt
    }
}

@MainActor
final class AccountStore {
    private let defaults: UserDefaults
    private let inMemoryOnly: Bool
    private let legacyAccountsKey = "ai-web-usage-monitor.accounts"
    private let migrationFlagKey = "ai-web-usage-monitor.storage-migrated-v2"
    private let container: ModelContainer
    private let context: ModelContext

    init(defaults: UserDefaults = .standard, inMemoryOnly: Bool = false) {
        self.defaults = defaults
        self.inMemoryOnly = inMemoryOnly

        let schema = Schema([
            StoredSession.self,
            StoredSnapshot.self,
            StoredQuotaMetric.self,
            StoredAlertState.self
        ])

        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemoryOnly)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
        } catch {
            guard !inMemoryOnly else {
                fatalError("SwiftData 초기화 실패: \(error.localizedDescription)")
            }
            do {
                let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: [fallbackConfiguration])
                self.container = container
            } catch {
                fatalError("SwiftData 초기화 실패: \(error.localizedDescription)")
            }
        }

        self.context = ModelContext(container)

        do {
            try migrateLegacyAccountsIfNeeded()
        } catch {
            assertionFailure("기존 계정 마이그레이션 실패: \(error.localizedDescription)")
        }
    }

    func loadAccounts() -> [WebAccountSession] {
        let sessions = (try? context.fetch(FetchDescriptor<StoredSession>())) ?? []
        let snapshots = (try? context.fetch(FetchDescriptor<StoredSnapshot>())) ?? []
        let quotaMetrics = (try? context.fetch(FetchDescriptor<StoredQuotaMetric>())) ?? []

        let snapshotsBySessionID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sessionID, $0) })
        let metricsBySessionID = Dictionary(grouping: quotaMetrics, by: \.sessionID)

        return sessions
            .compactMap { storedSession in
                guard let id = UUID(uuidString: storedSession.id),
                      let platform = AIPlatform(rawValue: storedSession.platformRawValue),
                      let dataStoreID = UUID(uuidString: storedSession.dataStoreID)
                else {
                    return nil
                }

                let snapshot = snapshotsBySessionID[storedSession.id].map { storedSnapshot in
                    UsageSnapshot(
                        headline: storedSnapshot.headline,
                        sourceURL: storedSnapshot.sourceURLString.flatMap(URL.init(string:)),
                        debugExcerpt: storedSnapshot.debugExcerpt,
                        quota: QuotaSnapshot(
                            entries: (metricsBySessionID[storedSession.id] ?? [])
                                .sorted { $0.sortOrder < $1.sortOrder }
                                .map {
                                    UsageQuotaEntry(
                                        label: $0.label,
                                        valueText: $0.valueText,
                                        resetText: $0.resetText,
                                        progress: $0.progress
                                    )
                                }
                        ),
                        activity: ActivitySnapshot(
                            lastNetworkAt: storedSnapshot.lastNetworkAt,
                            lastDOMMutationAt: storedSnapshot.lastDOMMutationAt,
                            recentRequestCount: storedSnapshot.recentRequestCount,
                            inFlightRequestCount: storedSnapshot.inFlightRequestCount,
                            pageBusyState: storedSnapshot.pageBusyState
                        ),
                        taskSignals: PlatformTaskSignals(
                            conversationTitle: storedSnapshot.conversationTitle,
                            latestUserPromptPreview: storedSnapshot.latestUserPromptPreview,
                            latestAssistantPreview: storedSnapshot.latestAssistantPreview,
                            isStreaming: storedSnapshot.isStreaming,
                            isWaitingForAssistant: storedSnapshot.isWaitingForAssistant,
                            hasBlockingError: storedSnapshot.hasBlockingError,
                            requiresLogin: storedSnapshot.requiresLogin,
                            busyIndicatorText: storedSnapshot.busyIndicatorText,
                            confidence: storedSnapshot.taskConfidence
                        ),
                        updatedAt: storedSnapshot.updatedAt
                    )
                }

                return WebAccountSession(
                    id: id,
                    platform: platform,
                    displayName: storedSession.displayName,
                    profileName: storedSession.profileName,
                    usesAutoDisplayName: storedSession.usesAutoDisplayName,
                    dataStoreID: dataStoreID,
                    createdAt: storedSession.createdAt,
                    refreshState: AccountRefreshState(rawValue: storedSession.refreshStateRawValue) ?? .idle,
                    lastCheckedAt: storedSession.lastCheckedAt,
                    snapshot: snapshot,
                    lastErrorDescription: storedSession.lastErrorDescription
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func saveAccounts(_ accounts: [WebAccountSession]) {
        let existingSessions = (try? context.fetch(FetchDescriptor<StoredSession>())) ?? []
        let existingSnapshots = (try? context.fetch(FetchDescriptor<StoredSnapshot>())) ?? []
        let existingQuotaMetrics = (try? context.fetch(FetchDescriptor<StoredQuotaMetric>())) ?? []
        let existingAlertStates = (try? context.fetch(FetchDescriptor<StoredAlertState>())) ?? []

        let sessionsByID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })
        let snapshotsByID = Dictionary(uniqueKeysWithValues: existingSnapshots.map { ($0.sessionID, $0) })
        let metricsBySessionID = Dictionary(grouping: existingQuotaMetrics, by: \.sessionID)
        let incomingIDs = Set(accounts.map { $0.id.uuidString })

        for storedSession in existingSessions where !incomingIDs.contains(storedSession.id) {
            context.delete(storedSession)
        }

        for storedSnapshot in existingSnapshots where !incomingIDs.contains(storedSnapshot.sessionID) {
            context.delete(storedSnapshot)
        }

        for storedMetric in existingQuotaMetrics where !incomingIDs.contains(storedMetric.sessionID) {
            context.delete(storedMetric)
        }

        for storedAlertState in existingAlertStates {
            guard let sessionID = sessionID(forAlertKey: storedAlertState.key) else {
                continue
            }

            if !incomingIDs.contains(sessionID) {
                context.delete(storedAlertState)
            }
        }

        for account in accounts {
            let sessionID = account.id.uuidString
            let storedSession = sessionsByID[sessionID] ?? {
                let newValue = StoredSession(
                    id: sessionID,
                    platformRawValue: account.platform.rawValue,
                    displayName: account.displayName,
                    profileName: account.profileName,
                    usesAutoDisplayName: account.usesAutoDisplayName,
                    dataStoreID: account.dataStoreID.uuidString,
                    createdAt: account.createdAt,
                    refreshStateRawValue: account.refreshState.rawValue,
                    lastCheckedAt: account.lastCheckedAt,
                    lastErrorDescription: account.lastErrorDescription
                )
                context.insert(newValue)
                return newValue
            }()

            storedSession.platformRawValue = account.platform.rawValue
            storedSession.displayName = account.displayName
            storedSession.profileName = account.profileName
            storedSession.usesAutoDisplayName = account.usesAutoDisplayName
            storedSession.dataStoreID = account.dataStoreID.uuidString
            storedSession.createdAt = account.createdAt
            storedSession.refreshStateRawValue = account.refreshState.rawValue
            storedSession.lastCheckedAt = account.lastCheckedAt
            storedSession.lastErrorDescription = account.lastErrorDescription

            for metric in metricsBySessionID[sessionID] ?? [] {
                context.delete(metric)
            }

            if let snapshot = account.snapshot {
                let storedSnapshot = snapshotsByID[sessionID] ?? {
                    let newValue = StoredSnapshot(
                        sessionID: sessionID,
                        headline: snapshot.headline,
                        sourceURLString: snapshot.sourceURL?.absoluteString,
                        debugExcerpt: snapshot.debugExcerpt,
                        updatedAt: snapshot.updatedAt,
                        lastNetworkAt: snapshot.activity.lastNetworkAt,
                        lastDOMMutationAt: snapshot.activity.lastDOMMutationAt,
                        recentRequestCount: snapshot.activity.recentRequestCount,
                        inFlightRequestCount: snapshot.activity.inFlightRequestCount,
                        pageBusyState: snapshot.activity.pageBusyState,
                        conversationTitle: snapshot.taskSignals.conversationTitle,
                        latestUserPromptPreview: snapshot.taskSignals.latestUserPromptPreview,
                        latestAssistantPreview: snapshot.taskSignals.latestAssistantPreview,
                        isStreaming: snapshot.taskSignals.isStreaming,
                        isWaitingForAssistant: snapshot.taskSignals.isWaitingForAssistant,
                        hasBlockingError: snapshot.taskSignals.hasBlockingError,
                        requiresLogin: snapshot.taskSignals.requiresLogin,
                        busyIndicatorText: snapshot.taskSignals.busyIndicatorText,
                        taskConfidence: snapshot.taskSignals.confidence
                    )
                    context.insert(newValue)
                    return newValue
                }()

                storedSnapshot.headline = snapshot.headline
                storedSnapshot.sourceURLString = snapshot.sourceURL?.absoluteString
                storedSnapshot.debugExcerpt = UsageSnapshot.trimDebugExcerpt(snapshot.debugExcerpt)
                storedSnapshot.updatedAt = snapshot.updatedAt
                storedSnapshot.lastNetworkAt = snapshot.activity.lastNetworkAt
                storedSnapshot.lastDOMMutationAt = snapshot.activity.lastDOMMutationAt
                storedSnapshot.recentRequestCount = snapshot.activity.recentRequestCount
                storedSnapshot.inFlightRequestCount = snapshot.activity.inFlightRequestCount
                storedSnapshot.pageBusyState = snapshot.activity.pageBusyState
                storedSnapshot.conversationTitle = snapshot.taskSignals.conversationTitle
                storedSnapshot.latestUserPromptPreview = snapshot.taskSignals.latestUserPromptPreview
                storedSnapshot.latestAssistantPreview = snapshot.taskSignals.latestAssistantPreview
                storedSnapshot.isStreaming = snapshot.taskSignals.isStreaming
                storedSnapshot.isWaitingForAssistant = snapshot.taskSignals.isWaitingForAssistant
                storedSnapshot.hasBlockingError = snapshot.taskSignals.hasBlockingError
                storedSnapshot.requiresLogin = snapshot.taskSignals.requiresLogin
                storedSnapshot.busyIndicatorText = snapshot.taskSignals.busyIndicatorText
                storedSnapshot.taskConfidence = snapshot.taskSignals.confidence

                for (index, entry) in snapshot.quota.entries.enumerated() {
                    context.insert(
                        StoredQuotaMetric(
                            sessionID: sessionID,
                            sortOrder: index,
                            label: entry.label,
                            valueText: entry.valueText,
                            resetText: entry.resetText,
                            progress: entry.progress
                        )
                    )
                }
            } else if let storedSnapshot = snapshotsByID[sessionID] {
                context.delete(storedSnapshot)
            }
        }

        saveContext()
    }

    func loadAlertStates() -> [String: String] {
        let states = (try? context.fetch(FetchDescriptor<StoredAlertState>())) ?? []
        return Dictionary(uniqueKeysWithValues: states.map { ($0.key, $0.level) })
    }

    func saveAlertState(key: String, level: String) {
        let descriptor = FetchDescriptor<StoredAlertState>()
        let states = (try? context.fetch(descriptor)) ?? []
        if let existing = states.first(where: { $0.key == key }) {
            existing.level = level
            existing.updatedAt = Date()
        } else {
            context.insert(StoredAlertState(key: key, level: level, updatedAt: Date()))
        }
        saveContext()
    }

    func removeAlertState(key: String) {
        let descriptor = FetchDescriptor<StoredAlertState>()
        let states = (try? context.fetch(descriptor)) ?? []
        guard let existing = states.first(where: { $0.key == key }) else {
            return
        }

        context.delete(existing)
        saveContext()
    }

    private func migrateLegacyAccountsIfNeeded() throws {
        guard !defaults.bool(forKey: migrationFlagKey) else {
            return
        }

        let existingSessionCount = ((try? context.fetch(FetchDescriptor<StoredSession>())) ?? []).count
        guard existingSessionCount == 0 else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        guard let data = defaults.data(forKey: legacyAccountsKey) else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        let decoder = JSONDecoder()
        let accounts = (try? decoder.decode([WebAccountSession].self, from: data)) ?? []
        saveAccounts(accounts)
        defaults.removeObject(forKey: legacyAccountsKey)
        defaults.set(true, forKey: migrationFlagKey)
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            assertionFailure("SwiftData 저장 실패: \(error.localizedDescription)")
        }
    }

    private func sessionID(forAlertKey key: String) -> String? {
        let components = key.split(separator: "::")
        guard components.count >= 3 else {
            return nil
        }

        let sessionID = String(components[1])
        return UUID(uuidString: sessionID) != nil ? sessionID : nil
    }
}
