import AppKit
import SwiftUI

struct PixelOfficeSceneCard: View {
    let agents: [PixelOfficeAgent]
    let totalAgentCount: Int
    let hasSessions: Bool
    let selectedAgentID: UUID?
    let focusedAgent: PixelOfficeAgent?
    let renderProfile: PixelOfficeRenderProfile
    let onSelect: (UUID) -> Void
    let onHover: (UUID?) -> Void
    let onResetFilters: () -> Void
    let onOpenSettings: () -> Void
    @StateObject private var motionCoordinator = PixelOfficeMotionCoordinator()
    @State private var ambienceNow = Date()

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
                    Text("픽셀 오피스")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .kerning(1.4)
                    Text(sceneSubtitle(ambience: ambience))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
                    Text("\(agents.count)/\(totalAgentCount) 세션")
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

            TimelineView(.animation(minimumInterval: renderProfile.frameInterval, paused: false)) { context in
                ZStack(alignment: .topLeading) {
                    PixelOfficeScene(
                        agents: agents,
                        motionCoordinator: motionCoordinator,
                        selectedAgentID: selectedAgentID,
                        focusedAgent: focusedAgent,
                        ambience: ambience,
                        renderProfile: renderProfile,
                        timestamp: context.date.timeIntervalSinceReferenceDate,
                        onSelect: onSelect,
                        onHover: onHover
                    )
                    PixelOfficeSceneHUD(
                        ambience: ambience,
                        qualityScore: qualityScore,
                        selectedAgent: selectedAgent
                    )
                    .padding(10)
                }
                .onChange(of: context.date) { _, value in
                    ambienceNow = value
                }
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

    private var ambience: PixelOfficeAmbience {
        PixelOfficeAmbience.make(now: ambienceNow, agents: agents)
    }

    private var selectedAgent: PixelOfficeAgent? {
        if let selectedAgentID {
            return agents.first(where: { $0.id == selectedAgentID })
        }
        return agents.first
    }

    private var qualityScore: Int {
        guard !agents.isEmpty else { return 100 }
        let alerts = agents.filter(\.isAlerting).count
        let stale = agents.filter { $0.taskState == .stale }.count
        let penalty = alerts * 20 + stale * 8
        return max(0, min(100, 100 - penalty))
    }

    private func sceneSubtitle(ambience: PixelOfficeAmbience) -> String {
        guard hasSessions else {
            return "Codex나 Claude 세션을 추가하면 픽셀 오피스에 캐릭터가 배치됩니다."
        }

        guard !agents.isEmpty else {
            return "현재 필터에 맞는 세션이 없어 빈 오피스를 표시합니다."
        }

        let blocked = agents.filter(\.isAlerting).count
        if blocked > 0 {
            return "\(ambience.moodSubtitle) · \(blocked)개 세션이 경고 상태입니다."
        }

        let working = agents.filter { $0.zone == .desk }.count
        return "\(ambience.moodSubtitle) · \(working)개 세션이 워크스테이션에서 작업 중입니다."
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

struct PixelOfficeSceneHUD: View {
    let ambience: PixelOfficeAmbience
    let qualityScore: Int
    let selectedAgent: PixelOfficeAgent?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ambience.moodTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(selectedAgent?.displayName ?? ambience.moodSubtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text("퀄리티 \(qualityScore)")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(qualityScore >= 80 ? Color.green : (qualityScore >= 50 ? Color.yellow : Color.red))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

struct PixelOfficeCommandDeck: View {
    let totalAgentCount: Int
    let visibleAgentCount: Int
    let visibilityFilter: PixelOfficeAgentVisibilityFilter
    let platformFilter: PixelOfficePlatformFilter
    let selectedAgent: PixelOfficeAgent?
    let alertAgents: [PixelOfficeAgent]
    let activeAgents: [PixelOfficeAgent]
    let renderProfile: PixelOfficeRenderProfile
    let briefingItems: [PixelOfficeBriefingItem]
    let isRefreshing: Bool
    let onSelectVisibility: (PixelOfficeAgentVisibilityFilter) -> Void
    let onSelectPlatform: (PixelOfficePlatformFilter) -> Void
    let onSelectRenderProfile: (PixelOfficeRenderProfile) -> Void
    let onSelectAgent: (UUID) -> Void
    let onRefreshAll: () -> Void
    let onResetFilters: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("오피스 컨트롤")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .kerning(1.2)
                    Text("노출 \(visibleAgentCount) · 전체 \(totalAgentCount)")
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

            PixelOfficeFilterRow(
                title: "연출",
                items: PixelOfficeRenderProfile.allCases,
                selectedID: renderProfile.id,
                label: \.title,
                onSelect: onSelectRenderProfile
            )

            Text(renderProfile.detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !alertAgents.isEmpty || !activeAgents.isEmpty {
                PixelOfficeMissionBoard(
                    selectedAgentID: selectedAgent?.id,
                    alertAgents: alertAgents,
                    activeAgents: activeAgents,
                    onSelectAgent: onSelectAgent
                )
            }

            PixelOfficeBriefingPanel(items: briefingItems)
            PixelOfficeStatusLegend()

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

struct PixelOfficeMissionBoard: View {
    let selectedAgentID: UUID?
    let alertAgents: [PixelOfficeAgent]
    let activeAgents: [PixelOfficeAgent]
    let onSelectAgent: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !alertAgents.isEmpty {
                PixelOfficeMissionLane(
                    title: "긴급 요청",
                    agents: alertAgents,
                    selectedAgentID: selectedAgentID,
                    onSelectAgent: onSelectAgent
                )
            }

            if !activeAgents.isEmpty {
                PixelOfficeMissionLane(
                    title: "진행 중 퀘스트",
                    agents: activeAgents,
                    selectedAgentID: selectedAgentID,
                    onSelectAgent: onSelectAgent
                )
            }
        }
    }
}

struct PixelOfficeMissionLane: View {
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

struct PixelOfficeBriefingPanel: View {
    let items: [PixelOfficeBriefingItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("상황 브리핑")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(items.prefix(3)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(item.tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

struct PixelOfficeStatusLegend: View {
    private let entries: [(String, Color)] = [
        ("작업/응답", Color(red: 0.22, green: 0.82, blue: 0.50)),
        ("대기", Color(red: 0.35, green: 0.78, blue: 0.98)),
        ("주의", Color(red: 0.98, green: 0.76, blue: 0.30)),
        ("오류/차단", Color(red: 0.98, green: 0.45, blue: 0.42))
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(entries, id: \.0) { entry in
                HStack(spacing: 5) {
                    Circle()
                        .fill(entry.1)
                        .frame(width: 7, height: 7)
                    Text(entry.0)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

struct PixelOfficeFilterRow<Item: Identifiable>: View where Item.ID == String {
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
