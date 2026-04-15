import XCTest
@testable import AIWebUsageMonitor

@MainActor
final class PixelOfficeSceneBuilderTests: XCTestCase {
    func testAgentsAreSortedBySeverityAndMappedToZones() {
        let blocked = descriptor(
            name: "Claude Blocked",
            platform: .claude,
            availability: .blocked,
            taskState: .blocked
        )
        let working = descriptor(
            name: "Codex Working",
            platform: .codex,
            availability: .available,
            activity: .active,
            context: SessionTaskContext(latestAssistantStateText: "Implementing", isStreamingResponse: true, isUserWaitingForReply: false, lastMeaningfulActivityAt: Date(), sourceConfidence: 0.8),
            taskState: .responding
        )
        let idle = descriptor(
            name: "Codex Idle",
            platform: .codex,
            availability: .available,
            activity: .idle,
            taskState: .idle
        )

        let agents = PixelOfficeSceneBuilder.makeAgents(from: [idle, working, blocked])

        XCTAssertEqual(agents.map(\.displayName), ["Claude Blocked", "Codex Working", "Codex Idle"])
        XCTAssertEqual(agents.map(\.zone), [.lounge, .desk, .lounge])
        XCTAssertEqual(agents.map(\.facing), [.right, .up, .left])
        XCTAssertEqual(agents.map(\.isAlerting), [true, false, false])
        XCTAssertEqual(agents[0].stateLabel, "사용 불가")
        XCTAssertEqual(agents[1].stateLabel, "응답 생성 중")
    }

    func testSummaryCountsDeskLoungeAndAlertAgents() {
        let agents = PixelOfficeSceneBuilder.makeAgents(
            from: [
                descriptor(name: "A", platform: .codex, availability: .available, taskState: .working),
                descriptor(name: "B", platform: .claude, availability: .available, taskState: .waiting),
                descriptor(name: "C", platform: .claude, availability: .low, taskState: .quotaLow)
            ]
        )

        let summary = PixelOfficeSceneBuilder.summary(for: agents)

        XCTAssertEqual(summary.title, "경고 상태 감지")
        XCTAssertEqual(summary.subtitle, "2 desks · 0 lounge · 1 alerts")
        XCTAssertEqual(summary.counters, "2|0|1")
    }

    func testDetailLineFallsBackToAvailabilityAndActivity() {
        let lowQuota = descriptor(
            name: "Low",
            platform: .codex,
            availability: .low,
            activity: .idle,
            taskState: .quotaLow
        )
        let active = descriptor(
            name: "Active",
            platform: .codex,
            availability: .available,
            activity: .active,
            taskState: .working
        )

        let agents = PixelOfficeSceneBuilder.makeAgents(from: [lowQuota, active])

        XCTAssertEqual(agents.first(where: { $0.displayName == "Low" })?.detailLine, "남은 한도가 낮아 주의가 필요합니다.")
        XCTAssertEqual(agents.first(where: { $0.displayName == "Active" })?.detailLine, "최근 작업 흔적이 감지되었습니다.")
    }

    func testAgentFilterMatchesVisibilityAndPlatform() {
        let agents = PixelOfficeSceneBuilder.makeAgents(
            from: [
                descriptor(name: "Codex Working", platform: .codex, availability: .available, activity: .active, taskState: .working),
                descriptor(name: "Claude Alert", platform: .claude, availability: .blocked, activity: .waiting, taskState: .blocked),
                descriptor(name: "Cursor Idle", platform: .cursor, availability: .available, activity: .idle, taskState: .idle)
            ]
        )

        let alerts = PixelOfficeAgentFilter(visibility: .alerts, platform: .all).apply(to: agents)
        let codexWorking = PixelOfficeAgentFilter(visibility: .working, platform: .codex).apply(to: agents)
        let idleCursor = PixelOfficeAgentFilter(visibility: .idle, platform: .cursor).apply(to: agents)

        XCTAssertEqual(alerts.map(\.displayName), ["Claude Alert"])
        XCTAssertEqual(codexWorking.map(\.displayName), ["Codex Working"])
        XCTAssertEqual(idleCursor.map(\.displayName), ["Cursor Idle"])
    }

    func testAlertQueuePrioritizesBlockingStatesFirst() {
        let agents = PixelOfficeSceneBuilder.makeAgents(
            from: [
                descriptor(name: "Quota Low", platform: .codex, availability: .low, taskState: .quotaLow),
                descriptor(name: "Needs Login", platform: .claude, availability: .available, taskState: .needsLogin),
                descriptor(name: "Blocked", platform: .cursor, availability: .blocked, taskState: .blocked),
                descriptor(name: "Stale", platform: .codex, availability: .available, taskState: .stale)
            ]
        )

        let queue = PixelOfficeSceneBuilder.alertQueue(from: agents)

        XCTAssertEqual(queue.map(\.displayName), ["Needs Login", "Blocked", "Quota Low", "Stale"])
    }

    func testActiveQueueKeepsRespondingWorkingWaitingOrder() {
        let agents = PixelOfficeSceneBuilder.makeAgents(
            from: [
                descriptor(name: "Waiting", platform: .codex, availability: .available, taskState: .waiting),
                descriptor(name: "Working", platform: .claude, availability: .available, taskState: .working),
                descriptor(name: "Responding", platform: .cursor, availability: .available, taskState: .responding),
                descriptor(name: "Idle", platform: .codex, availability: .available, taskState: .idle)
            ]
        )

        let queue = PixelOfficeSceneBuilder.activeQueue(from: agents)

        XCTAssertEqual(queue.map(\.displayName), ["Responding", "Working", "Waiting"])
    }

    func testWaitingAgentsUseDeskZone() {
        let agents = PixelOfficeSceneBuilder.makeAgents(
            from: [
                descriptor(name: "Waiting", platform: .codex, availability: .available, taskState: .waiting),
                descriptor(name: "Idle", platform: .claude, availability: .available, taskState: .idle)
            ]
        )

        XCTAssertEqual(agents.first(where: { $0.displayName == "Waiting" })?.zone, .desk)
        XCTAssertEqual(agents.first(where: { $0.displayName == "Idle" })?.zone, .lounge)
    }

    func testUnavailableAgentsUseLoungeSeatsButRemainAlerting() throws {
        let agents = PixelOfficeSceneBuilder.makeAgents(
            from: [
                descriptor(name: "Blocked", platform: .codex, availability: .blocked, taskState: .blocked),
                descriptor(name: "Needs Login", platform: .claude, availability: .available, taskState: .needsLogin),
                descriptor(name: "Error", platform: .cursor, availability: .available, taskState: .error)
            ]
        )

        XCTAssertEqual(agents.map(\.zone), [.lounge, .lounge, .lounge])
        XCTAssertTrue(agents.allSatisfy(\.isAlerting))
        XCTAssertTrue(agents.allSatisfy(\.isUnavailableForWork))
        XCTAssertEqual(PixelOfficeSceneBuilder.alertQueue(from: agents).map(\.displayName), ["Blocked", "Needs Login", "Error"])

        let pose = PixelOfficeSceneBuilder.currentNormalizedPose(
            for: agents[0],
            timestamp: 0
        )
        XCTAssertTrue(pose.isSeated)
        switch pose.animationState {
        case .idle:
            break
        case .walking, .typing, .reading:
            XCTFail("Unavailable agents should stay idle on the lounge seats.")
        }
    }

    func testTransitionWaypointsStayOnWalkableFloorTiles() throws {
        let loungeAgent = try XCTUnwrap(
            PixelOfficeSceneBuilder
                .makeAgents(from: [descriptor(name: "Idle", platform: .codex, availability: .available, taskState: .idle)])
                .first
        )
        let deskAgent = try XCTUnwrap(
            PixelOfficeSceneBuilder
                .makeAgents(from: [descriptor(name: "Working", platform: .claude, availability: .available, taskState: .working)])
                .first
        )

        let plan = try XCTUnwrap(
            PixelOfficeSceneBuilder.transitionPlan(
                from: loungeAgent.position,
                previousAgent: loungeAgent,
                to: deskAgent,
                startTime: 0
            )
        )

        let interiorWaypoints = Array(plan.path.dropFirst().dropLast())
        XCTAssertFalse(interiorWaypoints.isEmpty)
        let safeWaypoints: [CGPoint] = [
            normalizedPoint(col: 15, row: 16),
            normalizedPoint(col: 14, row: 14),
            normalizedPoint(col: 10, row: 17),
            normalizedPoint(col: 8, row: 14),
            normalizedPoint(col: 8, row: 11),
            normalizedPoint(col: 9, row: 14),
            normalizedPoint(col: 9, row: 11),
            normalizedPoint(col: 16, row: 11),
            normalizedPoint(col: 15, row: 11)
        ]
        XCTAssertTrue(
            interiorWaypoints.allSatisfy { point in
                safeWaypoints.contains { candidate in
                    abs(candidate.x - point.x) <= 0.0001 && abs(candidate.y - point.y) <= 0.0001
                }
            },
            interiorWaypoints.map { point in
                let allowed = safeWaypoints.contains { candidate in
                    abs(candidate.x - point.x) <= 0.0001 && abs(candidate.y - point.y) <= 0.0001
                }
                return "(\(String(format: "%.6f", point.x)), \(String(format: "%.6f", point.y))) allowed=\(allowed)"
            }.joined(separator: ", ")
        )
    }

    private func descriptor(
        name: String,
        platform: AIPlatform,
        availability: SessionAvailability,
        activity: SessionActivityState = .waiting,
        context: SessionTaskContext? = nil,
        taskState: SessionTaskState
    ) -> PixelOfficeSessionDescriptor {
        PixelOfficeSessionDescriptor(
            session: WebAccountSession(platform: platform, displayName: name),
            availability: availability,
            activity: activity,
            context: context ?? emptyContext(),
            taskState: taskState
        )
    }

    private func emptyContext() -> SessionTaskContext {
        SessionTaskContext(
            conversationTitle: nil,
            latestUserPromptPreview: nil,
            latestAssistantStateText: nil,
            isStreamingResponse: false,
            isUserWaitingForReply: false,
            lastMeaningfulActivityAt: nil,
            sourceConfidence: 0
        )
    }

    private func normalizedPoint(col: Int, row: Int) -> CGPoint {
        PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: col, row: row))
    }
}
