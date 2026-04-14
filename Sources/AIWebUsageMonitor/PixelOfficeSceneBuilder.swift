import SwiftUI

struct PixelOfficeSessionDescriptor {
    let session: WebAccountSession
    let availability: SessionAvailability
    let activity: SessionActivityState
    let context: SessionTaskContext
    let taskState: SessionTaskState
}

struct PixelOfficeAgent: Identifiable {
    let id: UUID
    let displayName: String
    let badge: String
    let platform: AIPlatform
    let zone: PixelOfficeZone
    let taskState: SessionTaskState
    let position: CGPoint
    let facing: PixelCharacterFacing
    let tint: Color
    let spriteIndex: Int
    let animationOffset: Double
    let detailLine: String
    let resetText: String?
    let profileName: String?
    let sourceURL: URL?
    let dashboardURL: URL
    let lastCheckedAt: Date?
    let conversationTitle: String?
    let latestUserPromptPreview: String?
    let latestAssistantPreview: String?
    let quotaEntries: [UsageQuotaEntry]

    var isAlerting: Bool {
        zone == .alert
    }

    var stateLabel: String {
        switch taskState {
        case .working:
            return "집중 작업 중"
        case .responding:
            return "응답 생성 중"
        case .waiting:
            return "대기 중"
        case .idle:
            return "쉬는 중"
        case .needsLogin:
            return "로그인 필요"
        case .quotaLow:
            return "한도 주의"
        case .blocked:
            return "사용 불가"
        case .stale:
            return "세션 지연"
        case .error:
            return "세션 오류"
        }
    }
}

enum PixelOfficeAgentVisibilityFilter: String, CaseIterable, Identifiable {
    case all
    case working
    case alerts
    case idle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .working:
            return "Work"
        case .alerts:
            return "Alerts"
        case .idle:
            return "Idle"
        }
    }
}

enum PixelOfficePlatformFilter: String, CaseIterable, Identifiable {
    case all
    case codex
    case claude
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .codex:
            return AIPlatform.codex.displayName
        case .claude:
            return AIPlatform.claude.displayName
        case .cursor:
            return AIPlatform.cursor.displayName
        }
    }

    var platform: AIPlatform? {
        switch self {
        case .all:
            return nil
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .cursor:
            return .cursor
        }
    }
}

struct PixelOfficeAgentFilter {
    let visibility: PixelOfficeAgentVisibilityFilter
    let platform: PixelOfficePlatformFilter

    func apply(to agents: [PixelOfficeAgent]) -> [PixelOfficeAgent] {
        agents.filter(matches)
    }

    func matches(_ agent: PixelOfficeAgent) -> Bool {
        let visibilityMatch: Bool = switch visibility {
        case .all:
            true
        case .working:
            agent.taskState == .working || agent.taskState == .responding || agent.taskState == .waiting
        case .alerts:
            agent.zone == .alert
        case .idle:
            agent.taskState == .idle || agent.taskState == .stale
        }

        guard visibilityMatch else {
            return false
        }

        guard let selectedPlatform = platform.platform else {
            return true
        }

        return agent.platform == selectedPlatform
    }
}

enum PixelOfficeZone {
    case desk
    case lounge
    case alert
}

enum PixelCharacterAnimationState {
    case idle
    case typing
    case reading
}

enum PixelCharacterFacing {
    case down
    case up
    case right
    case left

    var spriteSheetFacing: PixelCharacterFacing {
        switch self {
        case .left:
            return .right
        case .down, .up, .right:
            return self
        }
    }

    var isMirrored: Bool {
        self == .left
    }
}

struct PixelOfficeSummary {
    let title: String
    let subtitle: String
    let counters: String
}

struct PixelFurniturePlacement: Identifiable {
    let id: String
    let subpath: String
    let position: CGPoint
    let size: CGSize
    var opacity: Double = 1
    var brightness: Double = 0
    var glow: Bool = false
    var glowColor: Color = .white
    var monitorFrames: [String] = []
}

struct PixelOfficeFurnitureLayers {
    let backLayer: [PixelFurniturePlacement]
    let middleLayer: [PixelFurniturePlacement]
    let frontLayer: [PixelFurniturePlacement]
}

enum PixelOfficeSceneBuilder {
    private struct PixelOfficeAnchor {
        let position: CGPoint
        let facing: PixelCharacterFacing
    }

    private static let deskSlots: [PixelOfficeAnchor] = [
        .init(position: CGPoint(x: 0.18, y: 0.42), facing: .up),
        .init(position: CGPoint(x: 0.32, y: 0.42), facing: .up),
        .init(position: CGPoint(x: 0.18, y: 0.66), facing: .up),
        .init(position: CGPoint(x: 0.32, y: 0.66), facing: .up)
    ]

    private static let loungeSlots: [PixelOfficeAnchor] = [
        .init(position: CGPoint(x: 0.72, y: 0.60), facing: .right),
        .init(position: CGPoint(x: 0.79, y: 0.67), facing: .down),
        .init(position: CGPoint(x: 0.88, y: 0.61), facing: .left),
        .init(position: CGPoint(x: 0.84, y: 0.83), facing: .left)
    ]

    private static let alertSlots: [PixelOfficeAnchor] = [
        .init(position: CGPoint(x: 0.58, y: 0.35), facing: .right),
        .init(position: CGPoint(x: 0.72, y: 0.20), facing: .down),
        .init(position: CGPoint(x: 0.86, y: 0.22), facing: .left)
    ]

    static func makeAgents(from descriptors: [PixelOfficeSessionDescriptor]) -> [PixelOfficeAgent] {
        let sorted = descriptors.sorted { lhs, rhs in
            let leftPriority = priority(for: lhs.taskState)
            let rightPriority = priority(for: rhs.taskState)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }

            if lhs.session.platform != rhs.session.platform {
                return platformPriority(lhs.session.platform) < platformPriority(rhs.session.platform)
            }

            return lhs.session.displayName.localizedStandardCompare(rhs.session.displayName) == .orderedAscending
        }

        var deskIndex = 0
        var loungeIndex = 0
        var alertIndex = 0

        return sorted.enumerated().map { index, descriptor in
            let session = descriptor.session
            let zone = zone(for: descriptor.taskState)

            let assignedAnchor: PixelOfficeAnchor
            switch zone {
            case .desk:
                assignedAnchor = anchor(for: deskSlots, index: deskIndex, fallbackZone: .desk)
                deskIndex += 1
            case .lounge:
                assignedAnchor = anchor(for: loungeSlots, index: loungeIndex, fallbackZone: .lounge)
                loungeIndex += 1
            case .alert:
                assignedAnchor = anchor(for: alertSlots, index: alertIndex, fallbackZone: .alert)
                alertIndex += 1
            }

            return PixelOfficeAgent(
                id: session.id,
                displayName: session.displayName,
                badge: session.platform.shortDisplayName,
                platform: session.platform,
                zone: zone,
                taskState: descriptor.taskState,
                position: assignedAnchor.position,
                facing: assignedAnchor.facing,
                tint: color(
                    for: session.platform,
                    taskState: descriptor.taskState,
                    availability: descriptor.availability
                ),
                spriteIndex: index % 6,
                animationOffset: Double(index) * 0.55,
                detailLine: detailLine(for: descriptor),
                resetText: session.snapshot?.primaryResetSummary(for: session.platform),
                profileName: session.profileName,
                sourceURL: session.snapshot?.sourceURL,
                dashboardURL: session.platform.dashboardURL,
                lastCheckedAt: session.lastCheckedAt,
                conversationTitle: descriptor.context.conversationTitle,
                latestUserPromptPreview: descriptor.context.latestUserPromptPreview,
                latestAssistantPreview: descriptor.context.latestAssistantStateText,
                quotaEntries: primaryQuotaEntries(for: session)
            )
        }
    }

    static func furniture(in size: CGSize) -> PixelOfficeFurnitureLayers {
        let backLayer: [PixelFurniturePlacement] = [
            .init(
                id: "hall-painting-left",
                subpath: "furniture/SMALL_PAINTING.png",
                position: point(0.16, 0.18, in: size),
                size: CGSize(width: 48, height: 18)
            ),
            .init(
                id: "hall-clock",
                subpath: "furniture/CLOCK.png",
                position: point(0.28, 0.17, in: size),
                size: CGSize(width: 24, height: 24)
            ),
            .init(
                id: "hall-plant-left",
                subpath: "furniture/HANGING_PLANT.png",
                position: point(0.09, 0.20, in: size),
                size: CGSize(width: 24, height: 28)
            ),
            .init(
                id: "hall-plant-center",
                subpath: "furniture/HANGING_PLANT.png",
                position: point(0.43, 0.20, in: size),
                size: CGSize(width: 24, height: 28)
            ),
            .init(
                id: "right-bookshelf-left",
                subpath: "furniture/DOUBLE_BOOKSHELF.png",
                position: point(0.67, 0.27, in: size),
                size: CGSize(width: 78, height: 30)
            ),
            .init(
                id: "right-painting",
                subpath: "furniture/LARGE_PAINTING.png",
                position: point(0.80, 0.23, in: size),
                size: CGSize(width: 88, height: 22)
            ),
            .init(
                id: "right-bookshelf-right",
                subpath: "furniture/DOUBLE_BOOKSHELF.png",
                position: point(0.92, 0.27, in: size),
                size: CGSize(width: 78, height: 30)
            ),
            .init(
                id: "right-painting-small",
                subpath: "furniture/SMALL_PAINTING_2.png",
                position: point(0.92, 0.18, in: size),
                size: CGSize(width: 46, height: 18)
            ),
            .init(
                id: "whiteboard",
                subpath: "furniture/WHITEBOARD.png",
                position: point(0.56, 0.42, in: size),
                size: CGSize(width: 46, height: 72)
            ),
            .init(
                id: "right-plant-top",
                subpath: "furniture/PLANT_2.png",
                position: point(0.62, 0.31, in: size),
                size: CGSize(width: 28, height: 36)
            ),
            .init(
                id: "right-plant-bottom",
                subpath: "furniture/PLANT.png",
                position: point(0.94, 0.84, in: size),
                size: CGSize(width: 34, height: 40)
            )
        ]

        var middleLayer: [PixelFurniturePlacement] = []
        var frontLayer: [PixelFurniturePlacement] = []

        for (index, anchor) in deskSlots.enumerated() {
            let normalized = anchor.position
            let deskPoint = point(normalized.x, normalized.y - 0.02, in: size)
            let monitorPoint = point(normalized.x, normalized.y - 0.07, in: size)
            let chairPoint = point(normalized.x, normalized.y + 0.05, in: size)

            middleLayer.append(
                PixelFurniturePlacement(
                    id: "desk-\(index)",
                    subpath: "furniture/DESK_FRONT.png",
                    position: deskPoint,
                    size: CGSize(width: 84, height: 28),
                    opacity: 1
                )
            )

            middleLayer.append(
                PixelFurniturePlacement(
                    id: "monitor-\(index)",
                    subpath: "furniture/PC_FRONT_ON_1.png",
                    position: monitorPoint,
                    size: CGSize(width: 26, height: 22),
                    opacity: 1,
                    brightness: 0,
                    glow: true,
                    glowColor: Color(red: 0.33, green: 0.90, blue: 0.76),
                    monitorFrames: [
                        "furniture/PC_FRONT_ON_1.png",
                        "furniture/PC_FRONT_ON_2.png",
                        "furniture/PC_FRONT_ON_3.png"
                    ]
                )
            )

            frontLayer.append(
                PixelFurniturePlacement(
                    id: "chair-\(index)",
                    subpath: "furniture/CUSHIONED_CHAIR_FRONT.png",
                    position: chairPoint,
                    size: CGSize(width: 20, height: 24),
                    opacity: 0.95
                )
            )
        }

        middleLayer.append(
            PixelFurniturePlacement(
                id: "lounge-sofa-left",
                subpath: "furniture/SOFA_SIDE.png",
                position: point(0.68, 0.67, in: size),
                size: CGSize(width: 22, height: 68)
            )
        )
        middleLayer.append(
            PixelFurniturePlacement(
                id: "lounge-sofa-front",
                subpath: "furniture/SOFA_FRONT.png",
                position: point(0.79, 0.57, in: size),
                size: CGSize(width: 92, height: 28)
            )
        )
        middleLayer.append(
            PixelFurniturePlacement(
                id: "lounge-sofa-back",
                subpath: "furniture/SOFA_BACK.png",
                position: point(0.79, 0.76, in: size),
                size: CGSize(width: 92, height: 28)
            )
        )
        middleLayer.append(
            PixelFurniturePlacement(
                id: "lounge-sofa-right",
                subpath: "furniture/SOFA_SIDE.png",
                position: point(0.90, 0.67, in: size),
                size: CGSize(width: 22, height: 68)
            )
        )
        middleLayer.append(
            PixelFurniturePlacement(
                id: "lounge-table",
                subpath: "furniture/COFFEE_TABLE.png",
                position: point(0.79, 0.67, in: size),
                size: CGSize(width: 42, height: 28)
            )
        )
        middleLayer.append(
            PixelFurniturePlacement(
                id: "side-table",
                subpath: "furniture/SMALL_TABLE_FRONT.png",
                position: point(0.90, 0.84, in: size),
                size: CGSize(width: 42, height: 24)
            )
        )
        middleLayer.append(
            PixelFurniturePlacement(
                id: "left-side-table",
                subpath: "furniture/SMALL_TABLE_SIDE.png",
                position: point(0.08, 0.76, in: size),
                size: CGSize(width: 20, height: 44)
            )
        )

        frontLayer.append(
            PixelFurniturePlacement(
                id: "left-bin",
                subpath: "furniture/BIN.png",
                position: point(0.07, 0.88, in: size),
                size: CGSize(width: 18, height: 24)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "left-coffee",
                subpath: "furniture/COFFEE.png",
                position: point(0.08, 0.72, in: size),
                size: CGSize(width: 10, height: 12)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "lounge-coffee",
                subpath: "furniture/COFFEE.png",
                position: point(0.79, 0.65, in: size),
                size: CGSize(width: 10, height: 12)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "side-coffee",
                subpath: "furniture/COFFEE.png",
                position: point(0.90, 0.81, in: size),
                size: CGSize(width: 10, height: 12)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "plant-left-floor",
                subpath: "furniture/PLANT.png",
                position: point(0.07, 0.84, in: size),
                size: CGSize(width: 30, height: 36)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "plant-right-floor",
                subpath: "furniture/PLANT_2.png",
                position: point(0.62, 0.81, in: size),
                size: CGSize(width: 30, height: 36)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "right-small-plant",
                subpath: "furniture/CACTUS.png",
                position: point(0.95, 0.36, in: size),
                size: CGSize(width: 18, height: 24)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "bench-bottom",
                subpath: "furniture/CUSHIONED_BENCH.png",
                position: point(0.28, 0.84, in: size),
                size: CGSize(width: 44, height: 20)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "bench-side",
                subpath: "furniture/WOODEN_CHAIR_SIDE.png",
                position: point(0.39, 0.84, in: size),
                size: CGSize(width: 20, height: 32)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "bench-back",
                subpath: "furniture/WOODEN_CHAIR_BACK.png",
                position: point(0.40, 0.32, in: size),
                size: CGSize(width: 22, height: 20)
            )
        )
        frontLayer.append(
            PixelFurniturePlacement(
                id: "small-painting-left",
                subpath: "furniture/SMALL_PAINTING_2.png",
                position: point(0.08, 0.38, in: size),
                size: CGSize(width: 38, height: 16)
            )
        )

        return PixelOfficeFurnitureLayers(
            backLayer: backLayer,
            middleLayer: middleLayer,
            frontLayer: frontLayer
        )
    }

    private static func anchor(
        for anchors: [PixelOfficeAnchor],
        index: Int,
        fallbackZone: PixelOfficeZone
    ) -> PixelOfficeAnchor {
        guard !anchors.isEmpty else {
            return PixelOfficeAnchor(position: CGPoint(x: 0.5, y: 0.5), facing: .down)
        }

        if index < anchors.count {
            return anchors[index]
        }

        let fallbackColumn = index % 3
        let fallbackRow = index / 3

        switch fallbackZone {
        case .desk:
            return PixelOfficeAnchor(
                position: CGPoint(
                    x: 0.18 + CGFloat(fallbackColumn) * 0.14,
                    y: 0.42 + CGFloat(fallbackRow) * 0.12
                ),
                facing: .up
            )
        case .lounge:
            return PixelOfficeAnchor(
                position: CGPoint(
                    x: 0.70 + CGFloat(fallbackColumn) * 0.08,
                    y: 0.58 + CGFloat(fallbackRow) * 0.10
                ),
                facing: fallbackColumn == 0 ? .right : .left
            )
        case .alert:
            return PixelOfficeAnchor(
                position: CGPoint(
                    x: 0.58 + CGFloat(fallbackColumn) * 0.10,
                    y: 0.20 + CGFloat(fallbackRow) * 0.10
                ),
                facing: .down
            )
        }
    }

    static func summary(for agents: [PixelOfficeAgent]) -> PixelOfficeSummary {
        guard !agents.isEmpty else {
            return PixelOfficeSummary(
                title: "오피스 준비 중",
                subtitle: "세션이 연결되면 Codex와 Claude가 오피스 안에 나타납니다.",
                counters: "0/0"
            )
        }

        let working = agents.filter { $0.zone == .desk }.count
        let alerting = agents.filter(\.isAlerting).count
        let lounging = agents.filter { $0.zone == .lounge }.count

        let title: String
        if alerting > 0 {
            title = "경고 상태 감지"
        } else if working > 0 {
            title = "집중 작업 시간"
        } else {
            title = "조용한 오피스"
        }

        return PixelOfficeSummary(
            title: title,
            subtitle: "\(working) desks · \(lounging) lounge · \(alerting) alerts",
            counters: "\(working)|\(lounging)|\(alerting)"
        )
    }

    static func alertQueue(from agents: [PixelOfficeAgent], limit: Int = 4) -> [PixelOfficeAgent] {
        prioritizedQueue(
            from: agents.filter { $0.zone == .alert },
            limit: limit
        )
    }

    static func activeQueue(from agents: [PixelOfficeAgent], limit: Int = 4) -> [PixelOfficeAgent] {
        prioritizedQueue(
            from: agents.filter {
                $0.taskState == .responding || $0.taskState == .working || $0.taskState == .waiting
            },
            limit: limit
        )
    }

    private static func zone(for taskState: SessionTaskState) -> PixelOfficeZone {
        switch taskState {
        case .working, .responding:
            return .desk
        case .waiting, .idle:
            return .lounge
        case .needsLogin, .quotaLow, .blocked, .stale, .error:
            return .alert
        }
    }

    private static func prioritizedQueue(from agents: [PixelOfficeAgent], limit: Int) -> [PixelOfficeAgent] {
        Array(
            agents
                .sorted { lhs, rhs in
                    let leftPriority = priority(for: lhs.taskState)
                    let rightPriority = priority(for: rhs.taskState)
                    if leftPriority != rightPriority {
                        return leftPriority < rightPriority
                    }

                    let leftPlatform = platformPriority(lhs.platform)
                    let rightPlatform = platformPriority(rhs.platform)
                    if leftPlatform != rightPlatform {
                        return leftPlatform < rightPlatform
                    }

                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
                .prefix(max(limit, 0))
        )
    }

    private static func priority(for state: SessionTaskState) -> Int {
        switch state {
        case .blocked, .error, .needsLogin:
            return 0
        case .quotaLow, .stale:
            return 1
        case .responding:
            return 2
        case .working:
            return 3
        case .waiting:
            return 4
        case .idle:
            return 5
        }
    }

    private static func platformPriority(_ platform: AIPlatform) -> Int {
        switch platform {
        case .codex:
            return 0
        case .claude:
            return 1
        case .cursor:
            return 2
        }
    }

    private static func primaryQuotaEntries(for session: WebAccountSession) -> [UsageQuotaEntry] {
        guard let snapshot = session.snapshot else {
            return []
        }

        let primary = snapshot.primaryQuotaEntries(for: session.platform)
        if !primary.isEmpty {
            return primary
        }

        return Array(snapshot.quota.entries.prefix(2))
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * x, y: size.height * y)
    }

    private static func color(
        for platform: AIPlatform,
        taskState: SessionTaskState,
        availability: SessionAvailability
    ) -> Color {
        if taskState == .blocked || taskState == .error || taskState == .needsLogin {
            return Color(red: 0.95, green: 0.37, blue: 0.39)
        }

        if taskState == .quotaLow || availability == .low {
            return Color(red: 0.96, green: 0.71, blue: 0.30)
        }

        switch platform {
        case .codex:
            return Color(red: 0.28, green: 0.86, blue: 0.74)
        case .claude:
            return Color(red: 0.98, green: 0.59, blue: 0.33)
        case .cursor:
            return Color(red: 0.42, green: 0.67, blue: 0.98)
        }
    }

    private static func detailLine(for descriptor: PixelOfficeSessionDescriptor) -> String {
        if let status = descriptor.context.statusLine, !status.isEmpty {
            return status
        }

        if let title = descriptor.context.displayTitle, !title.isEmpty {
            return title
        }

        switch descriptor.availability {
        case .blocked:
            return "한도 소진으로 현재 사용할 수 없습니다."
        case .low:
            return "남은 한도가 낮아 주의가 필요합니다."
        case .available:
            break
        case .unknown:
            return "사용량 정보를 다시 기다리는 중입니다."
        }

        switch descriptor.activity {
        case .active, .loading:
            return "최근 작업 흔적이 감지되었습니다."
        case .waiting:
            return "새 응답이나 활동을 기다리는 중입니다."
        case .idle:
            return "최근 활동 없이 조용한 상태입니다."
        case .stale:
            return "마지막 갱신 시각이 오래되었습니다."
        case .unknown:
            return "세션 상태를 확인하는 중입니다."
        }
    }
}
