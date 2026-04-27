import AppKit
import SwiftUI

private enum MonitorDisplayMode: String, CaseIterable, Identifiable {
    case overview
    case office

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .office:
            return "Office"
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
        get { MonitorDisplayMode(rawValue: displayModeRaw) ?? .office }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Web Ops Monitor")
                        .font(.headline.weight(.semibold))
                    Text(viewModel.overviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("화면 모드", selection: Binding(
                    get: { displayMode },
                    set: { displayMode = $0 }
                )) {
                    ForEach(MonitorDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 148)

                if let lastFullRefreshAt = viewModel.lastFullRefreshAt {
                    Text("갱신 \(relativeTimestamp(from: lastFullRefreshAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            searchBar
            HeaderStatusPill(summary: viewModel.overallStatusSummary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(sectionBackground(cornerRadius: 22))
    }

    private func relativeTimestamp(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
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

struct PlatformOverviewSection: View {
    let platform: AIPlatform
    let sessions: [WebAccountSession]
    @ObservedObject var viewModel: UsageMonitorViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    PlatformBadge(platform: platform)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(platform.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(sessions.isEmpty ? "연결된 세션 없음" : "\(sessions.count)개 세션 연결됨")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("설정") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if sessions.isEmpty {
                Text("\(platform.displayName) 세션을 추가하면 이 섹션에 상태 카드가 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedSessions) { session in
                    SessionCardView(
                        account: session,
                        viewModel: viewModel,
                        showsDebugDisclosure: false
                    )
                }
            }
        }
        .padding(14)
        .background(sectionBackground)
    }

    private var sortedSessions: [WebAccountSession] {
        sessions.sorted { lhs, rhs in
            let leftPriority = priority(for: lhs)
            let rightPriority = priority(for: rhs)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }

            let leftChecked = lhs.lastCheckedAt ?? .distantPast
            let rightChecked = rhs.lastCheckedAt ?? .distantPast
            if leftChecked != rightChecked {
                return leftChecked > rightChecked
            }

            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func priority(for account: WebAccountSession) -> Int {
        if account.refreshState == .requiresLogin {
            return 0
        }

        if account.refreshState == .failed || viewModel.availability(for: account) == .blocked {
            return 0
        }

        if viewModel.availability(for: account) == .low {
            return 1
        }

        switch viewModel.activityState(for: account) {
        case .active, .waiting:
            return 2
        case .idle:
            return 3
        case .stale:
            return 4
        case .unknown, .loading:
            break
        }

        return 6
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct SessionCardView: View {
    let account: WebAccountSession
    @ObservedObject var viewModel: UsageMonitorViewModel
    var showsDebugDisclosure: Bool

    @State private var isShowingDebug = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                PlatformBadge(platform: account.platform, compact: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(refreshStateText)
                        .font(.caption)
                        .foregroundStyle(refreshStateColor)
                }

                Spacer()

                if let lastCheckedAt = account.lastCheckedAt {
                    Text(relativeTimestamp(from: lastCheckedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                SessionStateBadge(
                    text: presentationToken.title,
                    color: presentationColor
                )
                if let sourceURL = account.snapshot?.sourceURL {
                    SessionStateBadge(
                        text: sourceURL.host() ?? sourceURL.absoluteString,
                        color: .secondary
                    )
                }
            }

            HStack(spacing: 8) {
                SessionPrimaryActionMenu(
                    primaryTitle: primaryButtonTitle,
                    onPrimaryAction: primaryAction,
                    onRefresh: {
                        Task {
                            await viewModel.refresh(accountID: account.id)
                        }
                    },
                    onOpenSource: account.snapshot?.sourceURL.map { sourceURL in
                        { NSWorkspace.shared.open(sourceURL) }
                    },
                    onOpenLogin: (account.refreshState == .requiresLogin || account.refreshState == .failed)
                        ? { viewModel.reopenLoginWindow(for: account.id) }
                        : nil,
                    copyItems: copyMenuItems
                )
            }

            if showsTaskContext {
                SessionTaskContextCard(
                    context: taskContext,
                    accent: presentationColor
                )
            }

            if let snapshot = account.snapshot, !snapshot.quota.entries.isEmpty {
                QuotaGridView(entries: snapshot.quota.entries)
            } else if let snapshot = account.snapshot, !snapshot.headline.isEmpty {
                SessionIssueCardView(
                    title: "사용량 수집 결과",
                    message: account.lastErrorDescription ?? snapshot.headline,
                    sourceURL: snapshot.sourceURL
                )
            } else if let error = account.lastErrorDescription, !error.isEmpty {
                SessionIssueCardView(
                    title: "세션 확인 필요",
                    message: error,
                    sourceURL: nil
                )
            }

            if let snapshot = account.snapshot, showsDebugDisclosure, !snapshot.debugExcerpt.isEmpty {
                DisclosureGroup("최신 debug excerpt", isExpanded: $isShowingDebug) {
                    ScrollView {
                        Text(snapshot.debugExcerpt)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if let error = account.lastErrorDescription, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.055), lineWidth: 1)
                )
        )
    }

    private var refreshStateText: String {
        switch account.refreshState {
        case .idle:
            return "대기 중"
        case .loading:
            return "갱신 중"
        case .ready:
            return "정상 수집"
        case .requiresLogin:
            return "로그인 필요"
        case .failed:
            return "수집 실패"
        }
    }

    private var refreshStateColor: Color {
        switch account.refreshState {
        case .idle:
            return .secondary
        case .loading:
            return .blue
        case .ready:
            return .green
        case .requiresLogin:
            return .orange
        case .failed:
            return .red
        }
    }

    private var presentationToken: PresentationStateToken {
        viewModel.presentationState(for: account).token
    }

    private var presentationColor: Color {
        switch presentationToken.state {
        case .working:
            return Color(red: 0.20, green: 0.73, blue: 0.49)
        case .waiting:
            return Color(red: 0.27, green: 0.62, blue: 0.96)
        case .idle:
            return .secondary
        case .atRisk:
            return Color(red: 0.96, green: 0.67, blue: 0.29)
        case .blocked:
            return Color(red: 0.92, green: 0.36, blue: 0.38)
        }
    }

    private var primaryButtonTitle: String {
        if account.refreshState == .requiresLogin || account.refreshState == .failed {
            return "로그인"
        }
        return "열기"
    }

    private func primaryAction() {
        if account.refreshState == .requiresLogin || account.refreshState == .failed {
            viewModel.reopenLoginWindow(for: account.id)
            return
        }
        NSWorkspace.shared.open(account.snapshot?.sourceURL ?? account.platform.dashboardURL)
    }

    private func relativeTimestamp(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var taskContext: SessionTaskContext {
        viewModel.sessionTaskContext(for: account)
    }

    private var showsTaskContext: Bool {
        let title = normalized(taskContext.conversationTitle)
        let prompt = normalized(taskContext.latestUserPromptPreview)
        let status = normalized(taskContext.latestAssistantStateText)

        return title != nil || prompt != nil || status != nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var copyMenuItems: [SessionPrimaryActionMenu.CopyMenuItem] {
        var items: [SessionPrimaryActionMenu.CopyMenuItem] = []
        if let title = normalized(taskContext.conversationTitle) {
            items.append(.init(title: "화면 제목 복사", value: title))
        }
        if let prompt = normalized(taskContext.latestUserPromptPreview) {
            items.append(.init(title: "프롬프트 복사", value: prompt))
        }
        if let status = normalized(taskContext.latestAssistantStateText) {
            items.append(.init(title: "응답 상태 복사", value: status))
        }
        if let sourceURL = account.snapshot?.sourceURL {
            items.append(.init(title: "원본 URL 복사", value: sourceURL.absoluteString))
        }
        return items
    }
}

private struct SessionPrimaryActionMenu: View {
    struct CopyMenuItem: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    let primaryTitle: String
    let onPrimaryAction: () -> Void
    let onRefresh: () -> Void
    let onOpenSource: (() -> Void)?
    let onOpenLogin: (() -> Void)?
    let copyItems: [CopyMenuItem]

    var body: some View {
        HStack(spacing: 8) {
            Button(primaryTitle) {
                onPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Menu("복사") {
                ForEach(copyItems) { item in
                    Button(item.title) {
                        copyTextToPasteboard(item.value)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)

            Menu("더보기") {
                Button("새로고침") {
                    onRefresh()
                }
                if let onOpenSource {
                    Button("원본 열기") {
                        onOpenSource()
                    }
                }
                if let onOpenLogin {
                    Button("로그인 창 열기") {
                        onOpenLogin()
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
        }
    }
}

private struct SessionTaskContextCard: View {
    let context: SessionTaskContext
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = normalized(context.conversationTitle) {
                SessionContextLine(title: "현재 화면", value: title, tint: accent)
            }

            if let prompt = normalized(context.latestUserPromptPreview) {
                SessionContextLine(
                    title: "프롬프트",
                    value: prompt,
                    tint: Color(red: 0.36, green: 0.72, blue: 0.98)
                )
            }

            if let status = normalized(context.latestAssistantStateText) {
                SessionContextLine(
                    title: "응답 상태",
                    value: status,
                    tint: Color(red: 0.42, green: 0.85, blue: 0.65)
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SessionContextLine: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }
}

struct SessionStateBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(color.opacity(0.12)))
    }
}

struct SessionIssueCardView: View {
    let title: String
    let message: String
    let sourceURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let sourceURL {
                Text(sourceURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

struct QuotaGridView: View {
    let entries: [UsageQuotaEntry]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(entries) { entry in
                QuotaMetricCardView(entry: entry)
            }
        }
    }
}

struct QuotaMetricCardView: View {
    let entry: UsageQuotaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(displayQuotaValueText(entry.valueText, progress: entry.progress))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            if let progress = entry.progress ?? extractQuotaPercent(from: entry.valueText) {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(progressTint(progress))
            }

            if let resetText = entry.resetText, !resetText.isEmpty {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
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

struct SettingsSheetView: View {
    @ObservedObject var viewModel: UsageMonitorViewModel
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("환경설정")
                            .font(.title3.weight(.semibold))
                        Text("세션 관리, 알림, 자동 실행과 debug 확인을 여기서 관리합니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("닫기") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }

                SettingsActionsView(viewModel: viewModel)

                ForEach(AIPlatform.allCases) { platform in
                    SettingsPlatformSectionView(
                        platform: platform,
                        sessions: viewModel.sessions(for: platform),
                        viewModel: viewModel
                    )
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsActionsView: View {
    @ObservedObject var viewModel: UsageMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("앱 동작")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                SettingsActionButton(
                    title: viewModel.isRefreshingAll ? "갱신 중" : "전체 새로고침",
                    subtitle: "모든 세션 다시 읽기",
                    systemImage: "arrow.clockwise",
                    isProminent: true
                ) {
                    Task {
                        await viewModel.refreshAll()
                    }
                }
                .disabled(viewModel.isRefreshingAll)

                SettingsActionButton(
                    title: "테스트 알림",
                    subtitle: "알림 채널 확인",
                    systemImage: "bell.badge"
                ) {
                    viewModel.sendTestNotification()
                }

                SettingsActionButton(
                    title: "종료",
                    subtitle: "앱 프로세스 종료",
                    systemImage: "power"
                ) {
                    NSApp.terminate(nil)
                }
            }
            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("로그인 시 자동 실행")
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.launchAtLoginManager.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { viewModel.launchAtLoginManager.isEnabled },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                Button("알림 권한 요청") {
                    viewModel.requestNotificationAuthorization()
                }
                .buttonStyle(.bordered)

                Button("시스템 알림 설정") {
                    viewModel.openSystemNotificationSettings()
                }
                .buttonStyle(.bordered)
            }

            if let error = viewModel.launchAtLoginManager.lastErrorDescription, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct SettingsActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isProminent ? Color.white : Color.primary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isProminent ? Color.white : Color.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isProminent ? Color.white.opacity(0.74) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isProminent ? Color.accentColor.opacity(0.88) : Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke((isProminent ? Color.accentColor : Color.white).opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsPlatformSectionView: View {
    let platform: AIPlatform
    let sessions: [WebAccountSession]
    @ObservedObject var viewModel: UsageMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(platform.displayName) 세션")
                        .font(.headline)
                    Text(sessions.isEmpty ? "연결된 세션이 없습니다." : "독립 세션 \(sessions.count)개 연결됨")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("세션 추가") {
                    viewModel.addAccount(for: platform)
                }
                .buttonStyle(.bordered)
            }

            if sessions.isEmpty {
                Text("새 세션을 추가하면 로그인 창이 열리고, 이후 usage 페이지를 백그라운드에서 다시 읽습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { account in
                    SettingsAccountCardView(account: account, viewModel: viewModel)
                }
            }
        }
        .padding(18)
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

struct SettingsAccountCardView: View {
    let account: WebAccountSession
    @ObservedObject var viewModel: UsageMonitorViewModel

    @State private var draftName: String
    @State private var showingDeleteAlert = false

    init(account: WebAccountSession, viewModel: UsageMonitorViewModel) {
        self.account = account
        self.viewModel = viewModel
        _draftName = State(initialValue: account.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        PlatformBadge(platform: account.platform, compact: true)
                        TextField("계정 이름", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline.weight(.semibold))
                            .onSubmit(saveDisplayName)
                    }

                    Text(account.profileName ?? "프로필 미확인")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.refresh(accountID: account.id)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("로그인") {
                    viewModel.reopenLoginWindow(for: account.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if draftName != account.displayName {
                Button("이름 저장", action: saveDisplayName)
                    .buttonStyle(.bordered)
            }

            SessionCardView(
                account: account,
                viewModel: viewModel,
                showsDebugDisclosure: true
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .onChange(of: account.displayName) { _, newValue in
            draftName = newValue
        }
        .alert("계정을 삭제할까요?", isPresented: $showingDeleteAlert) {
            Button("삭제", role: .destructive) {
                viewModel.removeAccount(accountID: account.id)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장된 세션과 로컬 데이터스토어를 함께 정리합니다.")
        }
    }

    private func saveDisplayName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = account.displayName
            return
        }

        draftName = trimmed
        viewModel.renameAccount(accountID: account.id, displayName: trimmed)
    }
}

struct PlatformBadge: View {
    let platform: AIPlatform
    var compact = false

    var body: some View {
        Text(platform.shortDisplayName)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(Capsule(style: .continuous).fill(badgeColor))
    }

    private var badgeColor: Color {
        switch platform {
        case .codex:
            return Color(red: 0.25, green: 0.35, blue: 0.60)
        case .claude:
            return Color(red: 0.63, green: 0.41, blue: 0.18)
        case .cursor:
            return Color(red: 0.16, green: 0.55, blue: 0.42)
        }
    }
}

private func copyTextToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}
