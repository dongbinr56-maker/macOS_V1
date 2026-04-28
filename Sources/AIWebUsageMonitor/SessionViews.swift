import SwiftUI

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
                    primaryTitle: viewModel.primaryActionTitle(for: account),
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

            if let reason = viewModel.sessionRiskReason(for: account) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.24))
            }

            if showsTaskContext {
                SessionTaskContextCard(
                    context: taskContext,
                    accent: presentationColor
                )
            }

            if let snapshot = account.snapshot, !snapshot.quota.entries.isEmpty {
                QuotaGridView(
                    entries: snapshot.quota.entries,
                    historyProvider: { label in
                        viewModel.quotaHistory(for: account, quotaLabel: label)
                    }
                )
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
        formatter.locale = Locale(identifier: "ko_KR")
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
            .font(.caption.weight(.semibold))

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
            .font(.caption.weight(.semibold))
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
    let historyProvider: (String) -> [QuotaHistoryPoint]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(entries) { entry in
                QuotaMetricCardView(
                    entry: entry,
                    history: historyProvider(entry.label)
                )
            }
        }
    }
}

struct QuotaMetricCardView: View {
    let entry: UsageQuotaEntry
    let history: [QuotaHistoryPoint]

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

            QuotaTrendSparkline(points: history, tint: trendTint)
                .frame(height: 20)

            if let resetDescription {
                Text(resetDescription)
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

    private var trendTint: Color {
        if let latest = history.last?.progress {
            return progressTint(latest)
        }
        if let current = entry.progress ?? extractQuotaPercent(from: entry.valueText) {
            return progressTint(current)
        }
        return .secondary
    }

    private var resetDescription: String? {
        let trimmedReset = entry.resetText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasReset = (trimmedReset?.isEmpty == false)

        if isFiveHourQuota {
            if let trimmedReset, hasReset {
                return "5시간 초기화: \(trimmedReset)"
            }
            return "5시간 초기화 시각 수집 중"
        }

        guard let trimmedReset, hasReset else {
            return nil
        }
        return "초기화: \(trimmedReset)"
    }

    private var isFiveHourQuota: Bool {
        let normalized = entry.label
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        return normalized.contains("5시간") || normalized.contains("5-hour")
    }
}

private struct QuotaTrendSparkline: View {
    let points: [QuotaHistoryPoint]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else {
                return
            }

            let sortedPoints = points.sorted(by: { $0.timestamp < $1.timestamp })
            let maxIndex = Double(max(sortedPoints.count - 1, 1))
            var path = Path()

            for (index, point) in sortedPoints.enumerated() {
                let x = size.width * CGFloat(Double(index) / maxIndex)
                let y = size.height * CGFloat(1 - min(max(point.progress, 0), 1))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(
                path,
                with: .color(tint.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }
}
