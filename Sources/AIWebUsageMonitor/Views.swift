import AppKit
import SwiftUI

private enum MonitorDisplayMode: String, CaseIterable, Identifiable {
    case overview
    case office

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "개요"
        case .office:
            return "오피스"
        }
    }
}

struct MenuBarPopoverView: View {
    static let popoverSize = CGSize(width: 560, height: 680)

    @ObservedObject var viewModel: UsageMonitorViewModel
    @State private var showingSettings = false
    @State private var searchText = ""
    @AppStorage("menuBarDisplayMode") private var displayModeRaw = MonitorDisplayMode.overview.rawValue

    private var displayMode: MonitorDisplayMode {
        get { MonitorDisplayMode(rawValue: displayModeRaw) ?? .overview }
        nonmutating set { displayModeRaw = newValue.rawValue }
    }

    private var searchFilter: SessionSearchFilter {
        SessionSearchFilter(query: searchText)
    }

    private var visibleSessions: [WebAccountSession] {
        searchFilter.apply(to: viewModel.sessions)
    }

    private var visiblePlatforms: [AIPlatform] {
        AIPlatform.allCases.filter { platform in
            !sessions(for: platform, within: visibleSessions).isEmpty || !searchFilter.isActive
        }
    }

    var body: some View {
        Group {
            if showingSettings {
                SettingsSheetView(
                    viewModel: viewModel,
                    isPresented: $showingSettings
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header

                        if displayMode == .office {
                            PixelOfficeView(
                                sessions: visibleSessions,
                                viewModel: viewModel,
                                onOpenSettings: { showingSettings = true }
                            )
                        } else if viewModel.sessions.isEmpty {
                            EmptyUsageStateView {
                                showingSettings = true
                            }
                        } else if visibleSessions.isEmpty {
                            EmptySearchStateView(
                                query: searchText,
                                onClearSearch: { searchText = "" }
                            )
                        } else {
                            ForEach(visiblePlatforms) { platform in
                                PlatformOverviewSection(
                                    platform: platform,
                                    sessions: sessions(for: platform, within: visibleSessions),
                                    viewModel: viewModel,
                                    onOpenSettings: { showingSettings = true }
                                )
                            }
                        }
                    }
                    .padding(14)
                }
                .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var header: some View {
        let actionItems = viewModel.immediateActionItems()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Web Ops Monitor")
                        .font(.headline.weight(.semibold))
                    Text(viewModel.overviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(alignment: .center, spacing: 8) {
                    Picker("화면 모드", selection: Binding(
                        get: { displayMode },
                        set: { displayMode = $0 }
                    )) {
                        ForEach(MonitorDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 148)

                    if let lastFullRefreshAt = viewModel.lastFullRefreshAt {
                        Text("갱신 \(relativeTimestamp(from: lastFullRefreshAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }

            searchBar
            HeaderStatusPill(summary: viewModel.overallStatusSummary)
            if !actionItems.isEmpty {
                ImmediateActionSection(
                    items: actionItems,
                    onAction: { item in
                        if let session = viewModel.sessions.first(where: { $0.id == item.accountID }) {
                            if item.action == .login {
                                viewModel.reopenLoginWindow(for: session.id)
                            } else if item.action == .refresh {
                                Task { await viewModel.refresh(accountID: session.id) }
                            } else {
                                NSWorkspace.shared.open(session.snapshot?.sourceURL ?? session.platform.dashboardURL)
                            }
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(sectionBackground(cornerRadius: 22))
    }

    private func relativeTimestamp(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("세션, 프로필, 화면 제목, 프롬프트 검색", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
                .lineLimit(1)

            if searchFilter.isActive {
                Text("\(visibleSessions.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                refreshVisibleSessions()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(visibleSessions.isEmpty || viewModel.isRefreshingAll)
            .help(searchFilter.isActive ? "검색 결과 세션 새로고침" : "전체 세션 새로고침")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func sessions(for platform: AIPlatform, within sessions: [WebAccountSession]) -> [WebAccountSession] {
        sessions
            .filter { $0.platform == platform }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func refreshVisibleSessions() {
        let targetIDs = visibleSessions.map(\.id)

        Task {
            guard !targetIDs.isEmpty else {
                return
            }

            await viewModel.refresh(accountIDs: targetIDs)
        }
    }

    private func sectionBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct HeaderStatusPill: View {
    let summary: PlatformHealthSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: summary.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tintColor)

            Text(summary.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(backgroundColor))
        .overlay(
            Capsule(style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private var tintColor: Color {
        switch summary.health {
        case .available:
            return Color(red: 0.19, green: 0.74, blue: 0.40)
        case .low:
            return Color(red: 1.0, green: 0.72, blue: 0.32)
        case .blocked, .failed:
            return Color(red: 1.0, green: 0.47, blue: 0.48)
        case .checking:
            return Color(red: 0.37, green: 0.64, blue: 1.0)
        case .requiresLogin:
            return Color(red: 0.98, green: 0.62, blue: 0.26)
        case .idle:
            return Color(red: 0.58, green: 0.67, blue: 0.92)
        case .stale:
            return Color(red: 0.86, green: 0.63, blue: 0.26)
        case .empty:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch summary.health {
        case .available:
            return Color(red: 0.14, green: 0.24, blue: 0.18).opacity(0.82)
        case .low:
            return Color(red: 0.29, green: 0.21, blue: 0.11).opacity(0.82)
        case .blocked, .failed:
            return Color(red: 0.31, green: 0.12, blue: 0.14).opacity(0.82)
        case .checking:
            return Color(red: 0.13, green: 0.18, blue: 0.28).opacity(0.82)
        case .requiresLogin:
            return Color(red: 0.29, green: 0.18, blue: 0.10).opacity(0.82)
        case .idle:
            return Color(red: 0.14, green: 0.18, blue: 0.28).opacity(0.82)
        case .stale:
            return Color(red: 0.30, green: 0.22, blue: 0.12).opacity(0.82)
        case .empty:
            return Color.white.opacity(0.05)
        }
    }

    private var borderColor: Color {
        tintColor.opacity(0.18)
    }
}

private struct ImmediateActionSection: View {
    let items: [ImmediateActionItem]
    let onAction: (ImmediateActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("즉시 조치")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.30))

            ForEach(items) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.caption.weight(.semibold))
                        Text(item.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(item.actionTitle) {
                        onAction(item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.22, green: 0.17, blue: 0.10).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.98, green: 0.72, blue: 0.30).opacity(0.24), lineWidth: 1)
                )
        )
    }
}

struct EmptyUsageStateView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("연결된 세션이 없습니다.")
                .font(.headline)
            Text("설정에서 Codex, Claude, Cursor 세션을 추가하면 사용 가능 상태와 활동성을 바로 표시합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("설정 열기", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(sectionCardBackground)
    }

    private var sectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct EmptySearchStateView: View {
    let query: String
    let onClearSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("검색 결과가 없습니다.")
                .font(.headline)
            Text("`\(query)`와 일치하는 세션, 프로필, 화면 제목, 프롬프트를 찾지 못했습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("검색 초기화", action: onClearSearch)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
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
