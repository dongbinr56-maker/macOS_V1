import AppKit
import SwiftUI

struct PixelOfficeView: View {
    let sessions: [WebAccountSession]
    @ObservedObject var viewModel: UsageMonitorViewModel
    let onOpenSettings: () -> Void

    @State private var selectedAgentID: UUID?
    @State private var hoveredAgentID: UUID?
    @AppStorage("pixelOfficeVisibilityFilter") private var visibilityFilterRaw = PixelOfficeAgentVisibilityFilter.all.rawValue
    @AppStorage("pixelOfficePlatformFilter") private var platformFilterRaw = PixelOfficePlatformFilter.all.rawValue
    @AppStorage("pixelOfficeRenderProfile") private var renderProfileRaw = PixelOfficeRenderProfile.balanced.rawValue

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

    private var renderProfile: PixelOfficeRenderProfile {
        get { PixelOfficeRenderProfile(rawValue: renderProfileRaw) ?? .balanced }
        nonmutating set { renderProfileRaw = newValue.rawValue }
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

    private var briefingItems: [PixelOfficeBriefingItem] {
        var items: [PixelOfficeBriefingItem] = []

        for agent in alertAgents.prefix(2) {
            items.append(
                PixelOfficeBriefingItem(
                    id: agent.id,
                    title: "\(agent.displayName) 즉시 확인 필요",
                    detail: agent.detailLine,
                    tint: agent.tint
                )
            )
        }

        if items.count < 3 {
            for agent in activeAgents.prefix(3 - items.count) {
                items.append(
                    PixelOfficeBriefingItem(
                        id: agent.id,
                        title: "\(agent.displayName) 작업 진행 중",
                        detail: agent.conversationTitle ?? agent.latestAssistantPreview ?? agent.stateLabel,
                        tint: agent.tint
                    )
                )
            }
        }

        if items.isEmpty {
            items.append(
                PixelOfficeBriefingItem(
                    id: UUID(),
                    title: "특이 상황 없음",
                    detail: "현재 오피스는 안정적으로 운영 중입니다.",
                    tint: Color(red: 0.44, green: 0.77, blue: 0.56)
                )
            )
        }

        return items
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
                renderProfile: renderProfile,
                briefingItems: briefingItems,
                isRefreshing: viewModel.isRefreshingAll,
                onSelectVisibility: { visibilityFilter = $0 },
                onSelectPlatform: { platformFilter = $0 },
                onSelectRenderProfile: { renderProfile = $0 },
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
                renderProfile: renderProfile,
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

