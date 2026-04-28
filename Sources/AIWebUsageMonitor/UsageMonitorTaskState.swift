import Foundation

extension UsageMonitorViewModel {
    func taskContext(for session: WebAccountSession) -> SessionTaskContext {
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
                ?? (signals.confidence >= 0.12 ? signals.normalizedBusyIndicatorText : nil)
                ?? localLogSnapshot?.summary,
            isStreamingResponse: signals.confidence >= 0.2 && signals.isStreaming,
            isUserWaitingForReply: signals.confidence >= 0.18 && signals.isWaitingForAssistant,
            lastMeaningfulActivityAt: lastMeaningfulActivityAt,
            sourceConfidence: signals.confidence
        )
    }

    func taskState(
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
        case .active:
            return hasRecentTaskActivity ? .working : .idle
        case .waiting, .loading:
            return hasRecentTaskActivity ? .waiting : .idle
        case .idle, .unknown, .stale:
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
            return context.sourceConfidence < 0.2
                && !isRecent(context.lastMeaningfulActivityAt, within: 45)
                && !context.isStreamingResponse
                && !context.isUserWaitingForReply
        case .responding, .needsLogin, .quotaLow, .blocked, .stale, .error:
            return false
        }
    }

    func refreshLocalLogSnapshotsIfNeeded(force: Bool = false, now: Date = Date()) async {
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

    func startLocalLogStreaming() {
        localLogStreamTask?.cancel()
        localLogStreamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.localLogMonitor.snapshotStream()
            for await snapshots in stream {
                guard !Task.isCancelled else {
                    break
                }
                await MainActor.run {
                    self.objectWillChange.send()
                    self.localLogSnapshots = snapshots
                    self.lastLocalLogRefreshAt = Date()
                }
            }
        }
    }

}
