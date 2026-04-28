import AppKit
import SwiftUI

struct PixelOfficeAgentView: View {
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

                if isSelected {
                    PixelOfficeAgentTag(agent: agent, isSelected: isSelected)
                        .offset(y: -34)
                } else if isHovered {
                    PixelOfficeAgentMiniTag(agent: agent)
                        .offset(y: -30)
                }

                if isSelected {
                    Circle()
                        .stroke(agent.tint.opacity(0.75), lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                        .blur(radius: 0.8)
                        .offset(y: -3)
                }

                if statusDotColor != .clear {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                        .offset(x: 17, y: -20)
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
        .scaleEffect(isSelected ? 1.03 : (isHovered ? 1.01 : 1.0))
        .help("\(agent.displayName) • \(agent.stateLabel)")
        .onHover { hovering in
            onHover(hovering ? agent.id : nil)
        }
    }

    private var statusDotColor: Color {
        switch agent.taskState {
        case .working, .responding:
            return Color(red: 0.22, green: 0.82, blue: 0.50)
        case .waiting:
            return Color(red: 0.35, green: 0.78, blue: 0.98)
        case .quotaLow, .stale:
            return Color(red: 0.98, green: 0.76, blue: 0.30)
        case .needsLogin, .blocked, .error:
            return Color(red: 0.98, green: 0.45, blue: 0.42)
        case .idle:
            return .clear
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

struct PixelOfficeAgentTag: View {
    let agent: PixelOfficeAgent
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(agent.badge)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(agent.tint.opacity(0.94))
                    )

                Text(agent.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(roleTitle)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(agent.tint.opacity(0.95))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Text(agent.stateLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(agent.tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 134, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(isSelected ? 0.68 : 0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(agent.tint.opacity(isSelected ? 0.48 : 0.22), lineWidth: 1)
                )
        )
    }

    private var roleTitle: String {
        switch agent.platform {
        case .codex:
            return "OPS"
        case .claude:
            return "R&D"
        case .cursor:
            return "BUILD"
        }
    }
}

struct PixelOfficeAgentMiniTag: View {
    let agent: PixelOfficeAgent

    var body: some View {
        HStack(spacing: 5) {
            Text(agent.badge)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
            Text(agent.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: 102, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.48))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

struct PixelOfficeFocusPanel: View {
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

struct PixelOfficeSceneEmptyOverlay: View {
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

struct PixelOfficeBubble: View {
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
