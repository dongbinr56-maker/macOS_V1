import AppKit
import SwiftUI

private struct PixelOfficeMotionFingerprint: Equatable {
    let id: UUID
    let zone: PixelOfficeZone
    let taskState: SessionTaskState
    let position: CGPoint
}

@MainActor
private final class PixelOfficeMotionCoordinator: ObservableObject {
    private struct TrackedAgent {
        var agent: PixelOfficeAgent
        var transition: PixelOfficeTransitionPlan?
    }

    private var trackedAgents: [UUID: TrackedAgent] = [:]
    private let unitSceneRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    func sync(with agents: [PixelOfficeAgent], at timestamp: TimeInterval) {
        var updated: [UUID: TrackedAgent] = [:]

        for agent in agents {
            guard let existing = trackedAgents[agent.id] else {
                updated[agent.id] = TrackedAgent(agent: agent, transition: nil)
                continue
            }

            let currentPose = pose(for: existing, timestamp: timestamp, in: unitSceneRect)
            let transition = transition(
                from: existing,
                to: agent,
                currentPoint: currentPose.point,
                timestamp: timestamp
            )

            updated[agent.id] = TrackedAgent(
                agent: agent,
                transition: transition
            )
        }

        trackedAgents = updated
    }

    func pose(
        for agent: PixelOfficeAgent,
        timestamp: TimeInterval,
        metrics: PixelOfficeSceneMetrics
    ) -> PixelOfficeAnimatedPose {
        let tracked = trackedAgents[agent.id] ?? TrackedAgent(agent: agent, transition: nil)
        return pose(for: tracked, timestamp: timestamp, in: metrics.sceneRect)
    }

    private func pose(
        for tracked: TrackedAgent,
        timestamp: TimeInterval,
        in sceneRect: CGRect
    ) -> PixelOfficeAnimatedPose {
        if let transition = tracked.transition,
           let pose = PixelOfficeSceneBuilder.transitionPose(
               for: transition,
               targetAgent: tracked.agent,
               timestamp: timestamp,
               in: sceneRect
           ) {
            return pose
        }

        return PixelOfficeSceneBuilder.scenePose(
            for: tracked.agent,
            timestamp: timestamp,
            in: sceneRect
        )
    }

    private func transition(
        from existing: TrackedAgent,
        to nextAgent: PixelOfficeAgent,
        currentPoint: CGPoint,
        timestamp: TimeInterval
    ) -> PixelOfficeTransitionPlan? {
        guard needsTransition(from: existing.agent, to: nextAgent, currentPoint: currentPoint) else {
            return existing.transition.flatMap { transition in
                transition.endTime > timestamp ? transition : nil
            }
        }

        return PixelOfficeSceneBuilder.transitionPlan(
            from: currentPoint,
            previousAgent: existing.agent,
            to: nextAgent,
            startTime: timestamp
        )
    }

    private func needsTransition(
        from currentAgent: PixelOfficeAgent,
        to nextAgent: PixelOfficeAgent,
        currentPoint: CGPoint
    ) -> Bool {
        if currentAgent.zone != nextAgent.zone {
            return true
        }

        if currentAgent.taskState != nextAgent.taskState,
           currentAgent.taskState == .idle || nextAgent.taskState == .idle || nextAgent.taskState == .waiting {
            return true
        }

        return distance(from: currentPoint, to: nextAgent.position) > 0.008
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

struct PixelOfficeView: View {
    let sessions: [WebAccountSession]
    @ObservedObject var viewModel: UsageMonitorViewModel
    let onOpenSettings: () -> Void

    @State private var selectedAgentID: UUID?
    @State private var hoveredAgentID: UUID?
    @AppStorage("pixelOfficeVisibilityFilter") private var visibilityFilterRaw = PixelOfficeAgentVisibilityFilter.all.rawValue
    @AppStorage("pixelOfficePlatformFilter") private var platformFilterRaw = PixelOfficePlatformFilter.all.rawValue

    private var allOfficeAgents: [PixelOfficeAgent] {
        let descriptors = sessions.map { session in
            PixelOfficeSessionDescriptor(
                session: session,
                availability: viewModel.availability(for: session),
                activity: viewModel.activityState(for: session),
                context: viewModel.sessionTaskContext(for: session),
                taskState: viewModel.sessionTaskState(for: session)
            )
        }
        return PixelOfficeSceneBuilder.makeAgents(from: descriptors)
    }

    private var visibilityFilter: PixelOfficeAgentVisibilityFilter {
        get { PixelOfficeAgentVisibilityFilter(rawValue: visibilityFilterRaw) ?? .all }
        nonmutating set { visibilityFilterRaw = newValue.rawValue }
    }

    private var platformFilter: PixelOfficePlatformFilter {
        get { PixelOfficePlatformFilter(rawValue: platformFilterRaw) ?? .all }
        nonmutating set { platformFilterRaw = newValue.rawValue }
    }

    private var officeFilter: PixelOfficeAgentFilter {
        PixelOfficeAgentFilter(
            visibility: visibilityFilter,
            platform: platformFilter
        )
    }

    private var officeAgents: [PixelOfficeAgent] {
        officeFilter.apply(to: allOfficeAgents)
    }

    private var alertAgents: [PixelOfficeAgent] {
        PixelOfficeSceneBuilder.alertQueue(from: officeAgents)
    }

    private var activeAgents: [PixelOfficeAgent] {
        PixelOfficeSceneBuilder.activeQueue(from: officeAgents)
    }

    private var hasFilteredResults: Bool {
        !allOfficeAgents.isEmpty && officeAgents.isEmpty
    }

    private var selectedAgent: PixelOfficeAgent? {
        if let selectedAgentID,
           let agent = officeAgents.first(where: { $0.id == selectedAgentID }) {
            return agent
        }

        return officeAgents.first
    }

    private var focusedAgent: PixelOfficeAgent? {
        if let hoveredAgentID,
           let agent = officeAgents.first(where: { $0.id == hoveredAgentID }) {
            return agent
        }

        return selectedAgent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelOfficeCommandDeck(
                totalAgentCount: allOfficeAgents.count,
                visibleAgentCount: officeAgents.count,
                visibilityFilter: visibilityFilter,
                platformFilter: platformFilter,
                selectedAgent: selectedAgent,
                alertAgents: alertAgents,
                activeAgents: activeAgents,
                isRefreshing: viewModel.isRefreshingAll,
                onSelectVisibility: { visibilityFilter = $0 },
                onSelectPlatform: { platformFilter = $0 },
                onSelectAgent: { selectedAgentID = $0 },
                onRefreshAll: {
                    Task {
                        await viewModel.refreshAll()
                    }
                },
                onResetFilters: resetFilters,
                onOpenSettings: onOpenSettings
            )

            PixelOfficeSceneCard(
                agents: officeAgents,
                totalAgentCount: allOfficeAgents.count,
                hasSessions: !allOfficeAgents.isEmpty,
                selectedAgentID: selectedAgentID,
                focusedAgent: focusedAgent,
                onSelect: { selectedAgentID = $0 },
                onHover: { hoveredAgentID = $0 },
                onResetFilters: resetFilters,
                onOpenSettings: onOpenSettings
            )

            if let selectedAgent {
                PixelOfficeInspector(
                    agent: selectedAgent,
                    onRefresh: {
                        Task {
                            await viewModel.refresh(accountID: selectedAgent.id)
                        }
                    },
                    onLogin: {
                        viewModel.reopenLoginWindow(for: selectedAgent.id)
                    },
                    onOpenSource: selectedAgent.sourceURL.map { sourceURL in
                        {
                            NSWorkspace.shared.open(sourceURL)
                        }
                    },
                    onOpenDashboard: {
                        NSWorkspace.shared.open(selectedAgent.sourceURL ?? selectedAgent.dashboardURL)
                    }
                )
            } else if hasFilteredResults {
                PixelOfficeFilteredInspector(
                    hiddenCount: allOfficeAgents.count,
                    onResetFilters: resetFilters
                )
            } else {
                PixelOfficeEmptyInspector(onOpenSettings: onOpenSettings)
            }

            if !officeAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(officeAgents) { agent in
                            PixelOfficeRosterChip(
                                agent: agent,
                                isSelected: agent.id == selectedAgent?.id
                            ) {
                                selectedAgentID = agent.id
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .onAppear {
            if selectedAgentID == nil {
                selectedAgentID = officeAgents.first?.id
            }
        }
        .onChange(of: officeAgents.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedAgentID }) {
                selectedAgentID = ids.first
            }

            if !ids.contains(where: { $0 == hoveredAgentID }) {
                hoveredAgentID = nil
            }
        }
    }

    private func resetFilters() {
        visibilityFilter = .all
        platformFilter = .all
    }
}

private struct PixelOfficeSceneCard: View {
    let agents: [PixelOfficeAgent]
    let totalAgentCount: Int
    let hasSessions: Bool
    let selectedAgentID: UUID?
    let focusedAgent: PixelOfficeAgent?
    let onSelect: (UUID) -> Void
    let onHover: (UUID?) -> Void
    let onResetFilters: () -> Void
    let onOpenSettings: () -> Void
    @StateObject private var motionCoordinator = PixelOfficeMotionCoordinator()

    private var motionFingerprint: [PixelOfficeMotionFingerprint] {
        agents.map {
            PixelOfficeMotionFingerprint(
                id: $0.id,
                zone: $0.zone,
                taskState: $0.taskState,
                position: $0.position
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PIXEL OFFICE")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .kerning(1.4)
                    Text(sceneSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !hasSessions {
                    Button("세션 추가") {
                        onOpenSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if agents.isEmpty {
                    Button("필터 초기화") {
                        onResetFilters()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text("\(agents.count)/\(totalAgentCount) AGENTS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
            }

            TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: false)) { context in
                PixelOfficeScene(
                    agents: agents,
                    motionCoordinator: motionCoordinator,
                    selectedAgentID: selectedAgentID,
                    focusedAgent: focusedAgent,
                    timestamp: context.date.timeIntervalSinceReferenceDate,
                    onSelect: onSelect,
                    onHover: onHover
                )
            }
            .frame(height: 392)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            if !hasSessions {
                PixelOfficeSceneEmptyOverlay(
                    title: "세션이 아직 없습니다.",
                    message: "설정에서 Codex, Claude, Cursor 세션을 연결하면 오피스 안에 바로 배치됩니다.",
                    buttonTitle: "세션 추가",
                    action: onOpenSettings
                )
            } else if agents.isEmpty {
                PixelOfficeSceneEmptyOverlay(
                    title: "현재 필터와 일치하는 세션이 없습니다.",
                    message: "필터를 초기화하거나 다른 플랫폼을 선택해서 다시 확인하세요.",
                    buttonTitle: "필터 초기화",
                    action: onResetFilters
                )
            }
        }
        .padding(14)
        .background(cardBackground)
        .onAppear {
            motionCoordinator.sync(
                with: agents,
                at: Date.timeIntervalSinceReferenceDate
            )
        }
        .onChange(of: motionFingerprint) { _, _ in
            motionCoordinator.sync(
                with: agents,
                at: Date.timeIntervalSinceReferenceDate
            )
        }
    }

    private var sceneSubtitle: String {
        guard hasSessions else {
            return "Codex나 Claude 세션을 추가하면 픽셀 오피스에 캐릭터가 배치됩니다."
        }

        guard !agents.isEmpty else {
            return "현재 필터에 맞는 세션이 없어 빈 오피스를 표시합니다."
        }

        let blocked = agents.filter(\.isAlerting).count
        if blocked > 0 {
            return "\(blocked)개의 세션이 경고 상태로 표시되고 있습니다."
        }

        let working = agents.filter { $0.zone == .desk }.count
        return "\(working)개의 세션이 워크스테이션에서 작업 중입니다."
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.16),
                        Color(red: 0.05, green: 0.08, blue: 0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct PixelOfficeCommandDeck: View {
    let totalAgentCount: Int
    let visibleAgentCount: Int
    let visibilityFilter: PixelOfficeAgentVisibilityFilter
    let platformFilter: PixelOfficePlatformFilter
    let selectedAgent: PixelOfficeAgent?
    let alertAgents: [PixelOfficeAgent]
    let activeAgents: [PixelOfficeAgent]
    let isRefreshing: Bool
    let onSelectVisibility: (PixelOfficeAgentVisibilityFilter) -> Void
    let onSelectPlatform: (PixelOfficePlatformFilter) -> Void
    let onSelectAgent: (UUID) -> Void
    let onRefreshAll: () -> Void
    let onResetFilters: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OFFICE CONTROL")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .kerning(1.2)
                    Text("\(visibleAgentCount) visible · \(totalAgentCount) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onRefreshAll()
                } label: {
                    Label(isRefreshing ? "갱신 중" : "전체 새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)

                Button("설정") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            PixelOfficeFilterRow(
                title: "상태",
                items: PixelOfficeAgentVisibilityFilter.allCases,
                selectedID: visibilityFilter.id,
                label: \.title,
                onSelect: onSelectVisibility
            )

            PixelOfficeFilterRow(
                title: "플랫폼",
                items: PixelOfficePlatformFilter.allCases,
                selectedID: platformFilter.id,
                label: \.title,
                onSelect: onSelectPlatform
            )

            if !alertAgents.isEmpty || !activeAgents.isEmpty {
                PixelOfficeMissionBoard(
                    selectedAgentID: selectedAgent?.id,
                    alertAgents: alertAgents,
                    activeAgents: activeAgents,
                    onSelectAgent: onSelectAgent
                )
            }

            if visibilityFilter != .all || platformFilter != .all {
                Button("필터 초기화") {
                    onResetFilters()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct PixelOfficeMissionBoard: View {
    let selectedAgentID: UUID?
    let alertAgents: [PixelOfficeAgent]
    let activeAgents: [PixelOfficeAgent]
    let onSelectAgent: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !alertAgents.isEmpty {
                PixelOfficeMissionLane(
                    title: "즉시 조치",
                    agents: alertAgents,
                    selectedAgentID: selectedAgentID,
                    onSelectAgent: onSelectAgent
                )
            }

            if !activeAgents.isEmpty {
                PixelOfficeMissionLane(
                    title: "활성 작업",
                    agents: activeAgents,
                    selectedAgentID: selectedAgentID,
                    onSelectAgent: onSelectAgent
                )
            }
        }
    }
}

private struct PixelOfficeMissionLane: View {
    let title: String
    let agents: [PixelOfficeAgent]
    let selectedAgentID: UUID?
    let onSelectAgent: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(agents) { agent in
                        Button {
                            onSelectAgent(agent.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(agent.tint)
                                        .frame(width: 8, height: 8)
                                    Text(agent.badge)
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Text(agent.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(agent.conversationTitle ?? agent.latestUserPromptPreview ?? agent.stateLabel)
                                    .font(.caption2)
                                    .foregroundStyle(agent.tint)
                                    .lineLimit(2)
                            }
                            .padding(10)
                            .frame(width: 154, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(agent.id == selectedAgentID ? agent.tint.opacity(0.16) : Color(nsColor: .windowBackgroundColor).opacity(0.86))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(agent.id == selectedAgentID ? agent.tint.opacity(0.50) : Color.white.opacity(0.05), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

private struct PixelOfficeFilterRow<Item: Identifiable>: View where Item.ID == String {
    let title: String
    let items: [Item]
    let selectedID: String
    let label: KeyPath<Item, String>
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        let isSelected = item.id == selectedID
                        Button(item[keyPath: label]) {
                            onSelect(item)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.92) : Color.white.opacity(0.05))
                        )
                    }
                }
            }
        }
    }
}

private struct PixelOfficeScene: View {
    let agents: [PixelOfficeAgent]
    let motionCoordinator: PixelOfficeMotionCoordinator
    let selectedAgentID: UUID?
    let focusedAgent: PixelOfficeAgent?
    let timestamp: TimeInterval
    let onSelect: (UUID) -> Void
    let onHover: (UUID?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let metrics = PixelOfficeSceneLayout.metrics(in: proxy.size)
            let renderedAgents = agents
                .map { agent in
                    (
                        agent,
                        motionCoordinator.pose(
                            for: agent,
                            timestamp: timestamp,
                            metrics: metrics
                        )
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.1.point.y != rhs.1.point.y {
                        return lhs.1.point.y < rhs.1.point.y
                    }

                    return lhs.0.displayName.localizedStandardCompare(rhs.0.displayName) == .orderedAscending
                }

            ZStack {
                PixelOfficeBackdrop(metrics: metrics)

                ForEach(renderedAgents, id: \.0.id) { rendered in
                    PixelOfficeAgentView(
                        agent: rendered.0,
                        pose: rendered.1,
                        isSelected: rendered.0.id == selectedAgentID,
                        isHovered: rendered.0.id == focusedAgent?.id && rendered.0.id != selectedAgentID,
                        timestamp: timestamp,
                        onHover: onHover
                    ) {
                        onSelect(rendered.0.id)
                    }
                    .position(rendered.1.point)
                    .zIndex(Double(rendered.1.point.y - metrics.origin.y + metrics.tileSize / 2 + 0.5))
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.15),
                    Color(red: 0.03, green: 0.05, blue: 0.09)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct PixelOfficeBackdrop: View {
    let metrics: PixelOfficeSceneMetrics

    var body: some View {
        let backdrop = PixelOfficeSourceLayoutStore.shared.backdropImage(in: metrics)

        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.11)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.03, green: 0.04, blue: 0.08))
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)

            if let backdrop {
                Image(nsImage: backdrop)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                    .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)
        }
    }
}

private struct PixelOfficeTiledArea: View {
    let subpath: String
    let rect: CGRect
    let tileSize: CGFloat

    var body: some View {
        let columns = max(Int(ceil(rect.width / tileSize)), 1)
        let rows = max(Int(ceil(rect.height / tileSize)), 1)

        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { _ in
                        PixelOfficeTiledImage(
                            subpath: subpath,
                            size: CGSize(width: tileSize, height: tileSize)
                        )
                    }
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .position(x: rect.midX, y: rect.midY)
    }
}

private struct PixelOfficeFurnitureView: View {
    let item: PixelFurniturePlacement
    let timestamp: TimeInterval

    var body: some View {
        ZStack(alignment: .center) {
            if item.glow {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.glowColor.opacity(0.22))
                    .frame(width: item.size.width + 18, height: item.size.height + 18)
                    .blur(radius: 6)
            }

            furnitureBody
                .opacity(item.opacity)
                .brightness(item.brightness)
                .scaleEffect(x: item.mirrored ? -1 : 1, y: 1)
                .overlay(alignment: .center) {
                    if item.monitorFrames.count > 1 {
                        PixelOfficeImage(
                            subpath: item.monitorFrames[currentMonitorFrameIndex],
                            size: item.size
                        )
                    }
                }
        }
        .position(item.position)
    }

    @ViewBuilder
    private var furnitureBody: some View {
        if let resolvedImage = item.resolvedImage {
            Image(nsImage: resolvedImage)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
        } else if item.subpath.hasPrefix("custom:") {
            PixelOfficeCustomFurnitureView(kind: item.subpath, size: item.size)
        } else {
            PixelOfficeImage(subpath: item.subpath, size: item.size)
        }
    }

    private var currentMonitorFrameIndex: Int {
        guard !item.monitorFrames.isEmpty else {
            return 0
        }

        return Int((timestamp * 2.2).rounded(.down)).quotientAndRemainder(dividingBy: item.monitorFrames.count).remainder
    }
}

private struct PixelOfficeCustomFurnitureView: View {
    let kind: String
    let size: CGSize

    var body: some View {
        PixelOfficePixelArt(
            rows: spriteRows,
            palette: palette,
            size: size
        )
    }

    private var spriteRows: [String] {
        switch kind {
        case "custom:vending-machine":
            return [
                "................",
                ".AAAAAAAAAAAAAA.",
                ".ABBBBBBBBBBBBA.",
                ".ABCCCCDDCCCCBA.",
                ".ABCEEEEFEEEECBA",
                ".ABCEEEEFEEEECBA",
                ".ABCGGGGGGGGECBA",
                ".ABCGHHIHHHHECBA",
                ".ABCGHHIHHHHECBA",
                ".ABCGJJJJJJJECBA",
                ".ABCKKKKKKKKECBA",
                ".ABCKLLLMLKKECBA",
                ".ABCKLLLMLKKECBA",
                ".ABCKNNNNNNKECBA",
                ".ABCOOOPOOOKECBA",
                ".ABCOOOPOOOKECBA",
                ".ABCQQQQQQQKECBA",
                ".ABCRRRRRRRKECBA",
                ".ABCSSSSSSSKECBA",
                ".ABCTTTTTTTKECBA",
                ".ABCUUUUUUUKECBA",
                ".ABCVVVVVVVKECBA",
                ".ABWWWWWWWWKECBA",
                ".ABXXXXXXXXXECBA",
                ".ABYYYYYYYYYECBA",
                ".ABZZZZZZZZZECBA",
                ".AB000000000ECBA",
                ".AB111111111ECBA",
                ".AB222223333ECBA",
                ".AB444445555ECBA",
                ".AB666666666EBA.",
                ".AAAAAAAAAAAAAA."
            ]
        case "custom:water-cooler":
            return [
                "........",
                "..AAAA..",
                ".ABBBBA.",
                ".ABCCBA.",
                "..ADDA..",
                "..ADDA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA.."
            ]
        case "custom:counter":
            return [
                "................",
                "................",
                "AAAAAAAAAAAAAAAA",
                "ABBBBBBBBBBBBBBA",
                "ACCCCCCCCCCCCCCA",
                "ADDDDEEEEEDDDDDA",
                "ADDDDFFFFFDDDDDA",
                "ADDDDEEEEEDDDDDA",
                "ADDDDDDDDDDDDDDA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AJJJJHHIIHHJJJJA",
                "AKKKKKKKKKKKKKKA"
            ]
        case "custom:fridge":
            return [
                "..AAAA..",
                ".ABBBBA.",
                ".ACCCCA.",
                ".ACDDCA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".ACEECA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".ACDDCA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".AFFFFA.",
                ".AGGGGA.",
                ".AHHHHA."
            ]
        default:
            return ["....", ".AA.", ".AA.", "...."]
        }
    }

    private var palette: [Character: Color] {
        switch kind {
        case "custom:vending-machine":
            return [
                ".": .clear,
                "A": Color(red: 0.16, green: 0.20, blue: 0.31),
                "B": Color(red: 0.74, green: 0.84, blue: 0.93),
                "C": Color(red: 0.29, green: 0.36, blue: 0.53),
                "D": Color(red: 0.63, green: 0.10, blue: 0.15),
                "E": Color(red: 0.92, green: 0.95, blue: 0.98),
                "F": Color(red: 0.18, green: 0.69, blue: 0.57),
                "G": Color(red: 0.51, green: 0.58, blue: 0.70),
                "H": Color(red: 0.15, green: 0.21, blue: 0.29),
                "I": Color(red: 0.80, green: 0.88, blue: 0.95),
                "J": Color(red: 0.79, green: 0.69, blue: 0.34),
                "K": Color(red: 0.28, green: 0.33, blue: 0.46),
                "L": Color(red: 0.98, green: 0.61, blue: 0.24),
                "M": Color(red: 0.92, green: 0.28, blue: 0.30),
                "N": Color(red: 0.25, green: 0.58, blue: 0.92),
                "O": Color(red: 0.22, green: 0.25, blue: 0.34),
                "P": Color(red: 0.97, green: 0.93, blue: 0.67),
                "Q": Color(red: 0.75, green: 0.76, blue: 0.79),
                "R": Color(red: 0.61, green: 0.66, blue: 0.73),
                "S": Color(red: 0.33, green: 0.37, blue: 0.45),
                "T": Color(red: 0.49, green: 0.52, blue: 0.58),
                "U": Color(red: 0.22, green: 0.25, blue: 0.31),
                "V": Color(red: 0.87, green: 0.89, blue: 0.92),
                "W": Color(red: 0.98, green: 0.74, blue: 0.28),
                "X": Color(red: 0.85, green: 0.18, blue: 0.21),
                "Y": Color(red: 0.18, green: 0.77, blue: 0.64),
                "Z": Color(red: 0.24, green: 0.68, blue: 0.89),
                "0": Color(red: 0.29, green: 0.31, blue: 0.39),
                "1": Color(red: 0.40, green: 0.42, blue: 0.48),
                "2": Color(red: 0.25, green: 0.27, blue: 0.32),
                "3": Color(red: 0.13, green: 0.14, blue: 0.18),
                "4": Color(red: 0.57, green: 0.63, blue: 0.73),
                "5": Color(red: 0.31, green: 0.35, blue: 0.43),
                "6": Color(red: 0.12, green: 0.14, blue: 0.20)
            ]
        case "custom:water-cooler":
            return [
                ".": .clear,
                "A": Color(red: 0.23, green: 0.27, blue: 0.34),
                "B": Color(red: 0.86, green: 0.94, blue: 0.99),
                "C": Color(red: 0.62, green: 0.77, blue: 0.95),
                "D": Color(red: 0.89, green: 0.91, blue: 0.96),
                "E": Color(red: 0.74, green: 0.78, blue: 0.84)
            ]
        case "custom:counter":
            return [
                ".": .clear,
                "A": Color(red: 0.20, green: 0.19, blue: 0.24),
                "B": Color(red: 0.93, green: 0.92, blue: 0.88),
                "C": Color(red: 0.87, green: 0.83, blue: 0.76),
                "D": Color(red: 0.72, green: 0.54, blue: 0.31),
                "E": Color(red: 0.66, green: 0.47, blue: 0.25),
                "F": Color(red: 0.57, green: 0.38, blue: 0.18),
                "G": Color(red: 0.70, green: 0.72, blue: 0.76),
                "H": Color(red: 0.40, green: 0.43, blue: 0.50),
                "I": Color(red: 0.24, green: 0.26, blue: 0.31),
                "J": Color(red: 0.59, green: 0.61, blue: 0.65),
                "K": Color(red: 0.27, green: 0.29, blue: 0.35)
            ]
        case "custom:fridge":
            return [
                ".": .clear,
                "A": Color(red: 0.18, green: 0.20, blue: 0.25),
                "B": Color(red: 0.91, green: 0.93, blue: 0.96),
                "C": Color(red: 0.82, green: 0.85, blue: 0.89),
                "D": Color(red: 0.62, green: 0.66, blue: 0.72),
                "E": Color(red: 0.73, green: 0.76, blue: 0.81),
                "F": Color(red: 0.69, green: 0.72, blue: 0.76),
                "G": Color(red: 0.57, green: 0.61, blue: 0.67),
                "H": Color(red: 0.36, green: 0.39, blue: 0.46)
            ]
        default:
            return [".": .clear, "A": Color.white]
        }
    }
}

private struct PixelOfficePixelArt: View {
    let rows: [String]
    let palette: [Character: Color]
    let size: CGSize

    var body: some View {
        GeometryReader { proxy in
            let rowCount = max(rows.count, 1)
            let columnCount = max(rows.map(\.count).max() ?? 1, 1)
            let pixelWidth = proxy.size.width / CGFloat(columnCount)
            let pixelHeight = proxy.size.height / CGFloat(rowCount)

            Canvas { context, _ in
                for (rowIndex, row) in rows.enumerated() {
                    for (columnIndex, character) in row.enumerated() {
                        guard character != ".", let color = palette[character] else {
                            continue
                        }

                        let rect = CGRect(
                            x: CGFloat(columnIndex) * pixelWidth,
                            y: CGFloat(rowIndex) * pixelHeight,
                            width: ceil(pixelWidth),
                            height: ceil(pixelHeight)
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .drawingGroup(opaque: false)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct PixelOfficeAgentView: View {
    let agent: PixelOfficeAgent
    let pose: PixelOfficeAnimatedPose
    let isSelected: Bool
    let isHovered: Bool
    let timestamp: TimeInterval
    let onHover: (UUID?) -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isSelected || pose.isSeated {
                    Ellipse()
                        .fill(agent.tint.opacity(isSelected ? 0.26 : 0.12))
                        .frame(width: pose.isSeated ? 30 : 26, height: 10)
                        .offset(y: 18)
                }

                if isSelected || isHovered {
                    PixelOfficeAgentTag(agent: agent, isSelected: isSelected)
                        .offset(y: -36)
                }

                if let bubbleText = bubbleText {
                    PixelOfficeBubble(text: bubbleText, color: bubbleColor)
                        .offset(x: bubbleXOffset, y: -52)
                }

                PixelOfficeCharacterSprite(
                    sheetIndex: agent.spriteIndex,
                    facing: pose.facing,
                    state: pose.animationState,
                    timestamp: timestamp,
                    tint: agent.tint,
                    highlight: isSelected
                )
                .frame(width: 44, height: 72)
                .offset(y: pose.isSeated ? 6 : verticalBob)
            }
            .frame(width: 88, height: 108)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : (isHovered ? 1.02 : 1.0))
        .help("\(agent.displayName) • \(agent.stateLabel)")
        .onHover { hovering in
            onHover(hovering ? agent.id : nil)
        }
    }

    private var bubbleText: String? {
        switch agent.taskState {
        case .responding:
            return "READ"
        case .waiting:
            return "WAIT"
        case .quotaLow:
            return "LOW"
        case .needsLogin:
            return "LOGIN"
        case .blocked:
            return "STOP"
        case .error:
            return "ERR"
        case .stale:
            return "LAG"
        case .working, .idle:
            return nil
        }
    }

    private var bubbleColor: Color {
        switch agent.taskState {
        case .responding:
            return Color(red: 0.42, green: 0.85, blue: 0.65)
        case .waiting:
            return Color(red: 0.35, green: 0.78, blue: 0.98)
        case .quotaLow, .stale:
            return Color(red: 0.98, green: 0.76, blue: 0.30)
        case .needsLogin, .blocked, .error:
            return Color(red: 0.98, green: 0.45, blue: 0.42)
        case .working, .idle:
            return agent.tint
        }
    }

    private var bubbleXOffset: CGFloat {
        switch pose.facing {
        case .left:
            return -18
        case .right:
            return 18
        case .down, .up:
            return agent.isAlerting ? 18 : 0
        }
    }

    private var verticalBob: CGFloat {
        guard !pose.isSeated else {
            return 0
        }

        let amplitude: Double = switch pose.animationState {
        case .walking:
            0
        case .typing, .reading:
            0.4
        case .idle:
            0.9
        }

        return CGFloat(sin(timestamp * 3.2 + agent.animationOffset) * amplitude)
    }
}

private struct PixelOfficeAgentTag: View {
    let agent: PixelOfficeAgent
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(agent.badge)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(agent.tint.opacity(0.94))
                    )

                Text(agent.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Text(agent.stateLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(agent.tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(isSelected ? 0.68 : 0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(agent.tint.opacity(isSelected ? 0.48 : 0.22), lineWidth: 1)
                )
        )
    }
}

private struct PixelOfficeFocusPanel: View {
    let agent: PixelOfficeAgent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(agent.badge)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(agent.tint.opacity(0.95)))

                Text(agent.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Text(agent.stateLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(agent.tint)

            Text(agent.conversationTitle ?? agent.latestUserPromptPreview ?? agent.detailLine)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.74))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 184, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct PixelOfficeSceneEmptyOverlay: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)

            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(20)
    }
}

private struct PixelOfficeBubble: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
    }
}

private struct PixelOfficeHUD: View {
    let summary: PixelOfficeSummary
    let selectedAgent: PixelOfficeAgent?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text(selectedAgent?.detailLine ?? summary.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.76))
                    .lineLimit(2)
            }

            Spacer()

            Text(summary.counters)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.44))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(12)
    }
}

private struct PixelOfficeInspector: View {
    let agent: PixelOfficeAgent
    let onRefresh: () -> Void
    let onLogin: () -> Void
    let onOpenSource: (() -> Void)?
    let onOpenDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PixelOfficeCharacterSprite(
                    sheetIndex: agent.spriteIndex,
                    facing: agent.facing,
                    state: .idle,
                    timestamp: 0,
                    tint: agent.tint,
                    highlight: true
                )
                .frame(width: 42, height: 70)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(agent.displayName)
                            .font(.headline.weight(.semibold))
                        Text(agent.badge)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(agent.tint)
                            )
                    }

                    Text(agent.stateLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(agent.tint)

                    Text(agent.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 8) {
                PixelOfficeInspectorBadge(
                    label: agent.platform.displayName,
                    tint: agent.tint.opacity(0.18),
                    foreground: agent.tint
                )

                if let profileName = agent.profileName, !profileName.isEmpty {
                    PixelOfficeInspectorBadge(
                        label: profileName,
                        tint: Color.white.opacity(0.05),
                        foreground: .secondary
                    )
                }

                if let lastCheckedAt = agent.lastCheckedAt {
                    PixelOfficeInspectorBadge(
                        label: relativeTimestamp(from: lastCheckedAt),
                        tint: Color.white.opacity(0.05),
                        foreground: .secondary
                    )
                }
            }

            if let resetText = agent.resetText {
                Text("한도 리셋: \(resetText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if agent.conversationTitle != nil || agent.latestUserPromptPreview != nil || agent.latestAssistantPreview != nil {
                PixelOfficeContextSection(agent: agent)
            }

            if !agent.quotaEntries.isEmpty {
                PixelOfficeQuotaSection(entries: agent.quotaEntries, accent: agent.tint)
            }

            HStack(spacing: 8) {
                Button("대시보드") {
                    onOpenDashboard()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let onOpenSource {
                    Button("원본") {
                        onOpenSource()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("새로고침") {
                    onRefresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if agent.taskState == .needsLogin || agent.taskState == .error {
                    Button("로그인") {
                        onLogin()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Menu("복사") {
                    if let conversationTitle = normalized(agent.conversationTitle) {
                        Button("화면 제목 복사") {
                            copyTextToPasteboard(conversationTitle)
                        }
                    }

                    if let latestUserPromptPreview = normalized(agent.latestUserPromptPreview) {
                        Button("프롬프트 복사") {
                            copyTextToPasteboard(latestUserPromptPreview)
                        }
                    }

                    if let latestAssistantPreview = normalized(agent.latestAssistantPreview) {
                        Button("응답 상태 복사") {
                            copyTextToPasteboard(latestAssistantPreview)
                        }
                    }

                    if let sourceURL = agent.sourceURL {
                        Button("원본 URL 복사") {
                            copyTextToPasteboard(sourceURL.absoluteString)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func relativeTimestamp(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PixelOfficeContextSection: View {
    let agent: PixelOfficeAgent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let conversationTitle = agent.conversationTitle, !conversationTitle.isEmpty {
                PixelOfficeInfoRow(
                    title: "현재 화면",
                    value: conversationTitle,
                    accent: agent.tint
                )
            }

            if let latestUserPromptPreview = agent.latestUserPromptPreview, !latestUserPromptPreview.isEmpty {
                PixelOfficeInfoRow(
                    title: "프롬프트",
                    value: latestUserPromptPreview,
                    accent: Color(red: 0.36, green: 0.72, blue: 0.98)
                )
            }

            if let latestAssistantPreview = agent.latestAssistantPreview, !latestAssistantPreview.isEmpty {
                PixelOfficeInfoRow(
                    title: "응답 상태",
                    value: latestAssistantPreview,
                    accent: Color(red: 0.42, green: 0.85, blue: 0.65)
                )
            }
        }
    }
}

private struct PixelOfficeQuotaSection: View {
    let entries: [UsageQuotaEntry]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("핵심 사용량")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.valueText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    if let progress = entry.progress {
                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(progressTint(progress))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(accent.opacity(0.10), lineWidth: 1)
                        )
                )
            }
        }
    }

    private func progressTint(_ progress: Double) -> Color {
        if progress <= 0.2 {
            return Color(red: 1.0, green: 0.44, blue: 0.46)
        }

        if progress <= 0.4 {
            return Color(red: 1.0, green: 0.70, blue: 0.30)
        }

        return Color(red: 0.16, green: 0.82, blue: 0.40)
    }
}

private struct PixelOfficeInfoRow: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct PixelOfficeInspectorBadge: View {
    let label: String
    let tint: Color
    let foreground: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(tint))
    }
}

private struct PixelOfficeEmptyInspector: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("세션이 아직 없습니다.")
                .font(.headline)
            Text("설정에서 Codex 또는 Claude 세션을 추가하면 각 세션이 픽셀 캐릭터로 오피스에 배치됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("설정 열기", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct PixelOfficeFilteredInspector: View {
    let hiddenCount: Int
    let onResetFilters: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("필터 때문에 세션이 숨겨져 있습니다.")
                .font(.headline)
            Text("현재 등록된 \(hiddenCount)개 세션은 존재하지만, 상태 또는 플랫폼 필터 때문에 화면에서 제외되었습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("필터 초기화", action: onResetFilters)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct PixelOfficeRosterChip: View {
    let agent: PixelOfficeAgent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(agent.tint)
                        .frame(width: 8, height: 8)
                    Text(agent.badge)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(agent.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(agent.stateLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(agent.tint)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(width: 132, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? agent.tint.opacity(0.16) : Color(nsColor: .controlBackgroundColor).opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? agent.tint.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("\(agent.displayName) • \(agent.stateLabel)")
    }
}

private func copyTextToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}
