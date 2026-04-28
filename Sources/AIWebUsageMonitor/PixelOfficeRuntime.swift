import AppKit
import SwiftUI

struct PixelOfficeAmbience {
    enum Phase: String {
        case dawn
        case day
        case dusk
        case night
    }

    let phase: Phase
    let skyTop: Color
    let skyBottom: Color
    let overlay: Color
    let accent: Color
    let moodTitle: String
    let moodSubtitle: String

    static func make(now: Date, agents: [PixelOfficeAgent]) -> PixelOfficeAmbience {
        let hour = Calendar.current.component(.hour, from: now)
        let alertCount = agents.filter(\.isAlerting).count
        let activeCount = agents.filter { $0.taskState == .working || $0.taskState == .responding }.count

        let phase: Phase
        switch hour {
        case 6..<10:
            phase = .dawn
        case 10..<17:
            phase = .day
        case 17..<21:
            phase = .dusk
        default:
            phase = .night
        }

        let moodTitle: String
        if alertCount > 0 {
            moodTitle = "긴급 대응 시간"
        } else if activeCount > 0 {
            moodTitle = "집중 작업 시간"
        } else {
            moodTitle = "여유 운영 시간"
        }

        let phaseLabel: String = switch phase {
        case .dawn: "새벽"
        case .day: "낮"
        case .dusk: "노을"
        case .night: "밤"
        }
        let moodSubtitle = "\(phaseLabel) 분위기 · 경고 \(alertCount) · 활성 \(activeCount)"

        switch phase {
        case .dawn:
            return PixelOfficeAmbience(
                phase: phase,
                skyTop: Color(red: 0.28, green: 0.25, blue: 0.42),
                skyBottom: Color(red: 0.52, green: 0.34, blue: 0.42),
                overlay: Color(red: 0.99, green: 0.76, blue: 0.52).opacity(0.10),
                accent: Color(red: 0.95, green: 0.66, blue: 0.44),
                moodTitle: moodTitle,
                moodSubtitle: moodSubtitle
            )
        case .day:
            return PixelOfficeAmbience(
                phase: phase,
                skyTop: Color(red: 0.20, green: 0.33, blue: 0.52),
                skyBottom: Color(red: 0.20, green: 0.53, blue: 0.62),
                overlay: Color(red: 0.70, green: 0.92, blue: 0.99).opacity(0.08),
                accent: Color(red: 0.40, green: 0.79, blue: 0.98),
                moodTitle: moodTitle,
                moodSubtitle: moodSubtitle
            )
        case .dusk:
            return PixelOfficeAmbience(
                phase: phase,
                skyTop: Color(red: 0.33, green: 0.21, blue: 0.39),
                skyBottom: Color(red: 0.70, green: 0.36, blue: 0.31),
                overlay: Color(red: 0.98, green: 0.61, blue: 0.36).opacity(0.12),
                accent: Color(red: 0.98, green: 0.71, blue: 0.33),
                moodTitle: moodTitle,
                moodSubtitle: moodSubtitle
            )
        case .night:
            return PixelOfficeAmbience(
                phase: phase,
                skyTop: Color(red: 0.05, green: 0.08, blue: 0.17),
                skyBottom: Color(red: 0.03, green: 0.05, blue: 0.10),
                overlay: Color(red: 0.24, green: 0.31, blue: 0.62).opacity(0.16),
                accent: Color(red: 0.62, green: 0.73, blue: 0.99),
                moodTitle: moodTitle,
                moodSubtitle: moodSubtitle
            )
        }
    }
}

enum PixelOfficeRenderProfile: String, CaseIterable, Identifiable {
    case balanced
    case cinematic
    case focused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "균형"
        case .cinematic:
            return "시네마"
        case .focused:
            return "집중"
        }
    }

    var frameInterval: Double {
        switch self {
        case .cinematic:
            return 1.0 / 12.0
        case .balanced:
            return 1.0 / 8.0
        case .focused:
            return 1.0 / 5.0
        }
    }

    var detailText: String {
        switch self {
        case .cinematic:
            return "조명/이펙트를 최대로 보여줍니다."
        case .balanced:
            return "시각 효과와 가독성의 균형 설정입니다."
        case .focused:
            return "정보 확인에 집중한 저연출 모드입니다."
        }
    }
}

struct PixelOfficeBriefingItem: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let tint: Color
}

struct PixelOfficeMotionFingerprint: Equatable {
    let id: UUID
    let zone: PixelOfficeZone
    let taskState: SessionTaskState
    let position: CGPoint
}

@MainActor
final class PixelOfficeMotionCoordinator: ObservableObject {
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
           nextAgent.taskState == .working || nextAgent.taskState == .blocked || nextAgent.taskState == .quotaLow {
            return true
        }

        return distance(from: currentPoint, to: nextAgent.position) > 0.02
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
