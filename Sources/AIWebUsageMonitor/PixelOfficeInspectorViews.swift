import AppKit
import SwiftUI

struct PixelOfficeHUD: View {
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

struct PixelOfficeInspector: View {
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

struct PixelOfficeContextSection: View {
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

struct PixelOfficeQuotaSection: View {
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

struct PixelOfficeInfoRow: View {
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

struct PixelOfficeInspectorBadge: View {
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

struct PixelOfficeEmptyInspector: View {
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

struct PixelOfficeFilteredInspector: View {
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

struct PixelOfficeRosterChip: View {
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
