import SwiftUI

struct PixelOfficeSessionDescriptor {
    let session: WebAccountSession
    let availability: SessionAvailability
    let activity: SessionActivityState
    let context: SessionTaskContext
    let taskState: SessionTaskState
}

struct PixelOfficeTilePoint: Hashable {
    let col: Int
    let row: Int
}

struct PixelOfficeAgent: Identifiable {
    let id: UUID
    let displayName: String
    let badge: String
    let platform: AIPlatform
    let zone: PixelOfficeZone
    let taskState: SessionTaskState
    let position: CGPoint
    let seatTile: PixelOfficeTilePoint
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
        switch taskState {
        case .needsLogin, .quotaLow, .blocked, .stale, .error:
            return true
        case .working, .responding, .waiting, .idle:
            return false
        }
    }

    var isUnavailableForWork: Bool {
        switch taskState {
        case .needsLogin, .blocked, .error:
            return true
        case .working, .responding, .waiting, .idle, .quotaLow, .stale:
            return false
        }
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
            agent.isAlerting
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
    case walking
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
    var resolvedImage: NSImage? = nil
    var mirrored: Bool = false
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

struct PixelOfficeSceneMetrics {
    let tileSize: CGFloat
    let origin: CGPoint
    let minCol: Int
    let minRow: Int
    let visibleColumns: Int
    let visibleRows: Int

    var sceneSize: CGSize {
        CGSize(
            width: CGFloat(visibleColumns) * tileSize,
            height: CGFloat(visibleRows) * tileSize
        )
    }

    var sceneRect: CGRect {
        CGRect(origin: origin, size: sceneSize)
    }

    func center(of tile: PixelOfficeTilePoint) -> CGPoint {
        CGPoint(
            x: origin.x + (CGFloat(tile.col - minCol) + 0.5) * tileSize,
            y: origin.y + (CGFloat(tile.row - minRow) + 0.5) * tileSize
        )
    }

    func rect(col: Int, row: Int, width: Int, height: Int) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(col - minCol) * tileSize,
            y: origin.y + CGFloat(row - minRow) * tileSize,
            width: CGFloat(width) * tileSize,
            height: CGFloat(height) * tileSize
        )
    }

    func spriteSize(pixelWidth: CGFloat, pixelHeight: CGFloat) -> CGSize {
        CGSize(
            width: (pixelWidth / 16.0) * tileSize,
            height: (pixelHeight / 16.0) * tileSize
        )
    }

    func spritePosition(col: Int, row: Int, pixelWidth: CGFloat, pixelHeight: CGFloat) -> CGPoint {
        let size = spriteSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        return CGPoint(
            x: origin.x + CGFloat(col - minCol) * tileSize + size.width / 2,
            y: origin.y + CGFloat(row - minRow) * tileSize + size.height / 2
        )
    }

    func bottomAlignedSpritePosition(col: Int, row: Int, pixelWidth: CGFloat, pixelHeight: CGFloat) -> CGPoint {
        let size = spriteSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        return CGPoint(
            x: origin.x + CGFloat(col - minCol) * tileSize + size.width / 2,
            y: origin.y + CGFloat(row - minRow + 1) * tileSize - size.height / 2
        )
    }

    func yOffset(forRow row: Int) -> CGFloat {
        CGFloat(row - minRow) * tileSize
    }
}

@MainActor
enum PixelOfficeSceneLayout {
    static let columns = 21
    static let rows = 22

    static func normalizedPosition(for tile: PixelOfficeTilePoint) -> CGPoint {
        CGPoint(
            x: (CGFloat(tile.col) + 0.5) / CGFloat(columns),
            y: (CGFloat(tile.row) + 0.5) / CGFloat(rows)
        )
    }

    static func metrics(in size: CGSize) -> PixelOfficeSceneMetrics {
        let bounds = PixelOfficeSourceLayoutStore.shared.visibleBounds
        let tileSize = max(
            CGFloat(12),
            floor(min(size.width / CGFloat(bounds.columns), size.height / CGFloat(bounds.rows)))
        )
        let sceneSize = CGSize(width: CGFloat(bounds.columns) * tileSize, height: CGFloat(bounds.rows) * tileSize)
        let origin = CGPoint(
            x: round((size.width - sceneSize.width) / 2),
            y: round((size.height - sceneSize.height) / 2)
        )
        return PixelOfficeSceneMetrics(
            tileSize: tileSize,
            origin: origin,
            minCol: bounds.minCol,
            minRow: bounds.minRow,
            visibleColumns: bounds.columns,
            visibleRows: bounds.rows
        )
    }

    static func furniture(in metrics: PixelOfficeSceneMetrics) -> PixelOfficeFurnitureLayers {
        let backLayer: [PixelFurniturePlacement] = [
            placement("office-shelf-left", "furniture/BOOKSHELF.png", col: 1, row: 1, pixelWidth: 32, pixelHeight: 16, metrics: metrics),
            placement("office-shelf-right", "furniture/BOOKSHELF.png", col: 7, row: 1, pixelWidth: 32, pixelHeight: 16, metrics: metrics),
            placement("office-floor-plant-left", "furniture/PLANT.png", col: 1, row: 17, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("office-floor-plant-right", "furniture/PLANT_2.png", col: 9, row: 17, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("utility-vending", "custom:vending-machine", col: 12, row: 0, pixelWidth: 32, pixelHeight: 48, metrics: metrics),
            placement("utility-water", "custom:water-cooler", col: 15, row: 1, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("utility-bin", "furniture/BIN.png", col: 16, row: 2, pixelWidth: 16, pixelHeight: 16, metrics: metrics),
            placement("utility-counter", "custom:counter", col: 17, row: 1, pixelWidth: 48, pixelHeight: 32, metrics: metrics),
            placement("utility-fridge", "custom:fridge", col: 20, row: 0, pixelWidth: 16, pixelHeight: 48, metrics: metrics),
            placement("utility-clock", "furniture/CLOCK.png", col: 18, row: 0, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("lounge-shelf-left", "furniture/BOOKSHELF.png", col: 12, row: 10, pixelWidth: 32, pixelHeight: 16, metrics: metrics),
            placement("lounge-shelf-right", "furniture/BOOKSHELF.png", col: 18, row: 10, pixelWidth: 32, pixelHeight: 16, metrics: metrics),
            placement("lounge-painting", "furniture/LARGE_PAINTING.png", col: 15, row: 9, pixelWidth: 32, pixelHeight: 32, metrics: metrics),
            placement("lounge-plant-left", "furniture/PLANT_2.png", col: 14, row: 10, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("lounge-plant-right", "furniture/PLANT_2.png", col: 17, row: 10, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("lounge-floor-plant-left", "furniture/PLANT.png", col: 12, row: 19, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("lounge-floor-plant-right", "furniture/PLANT_2.png", col: 19, row: 18, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("lounge-sofa-left", "furniture/SOFA_SIDE.png", col: 13, row: 14, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("lounge-sofa-right", "furniture/SOFA_SIDE.png", col: 17, row: 14, pixelWidth: 16, pixelHeight: 32, metrics: metrics, mirrored: true)
        ]

        let middleLayer: [PixelFurniturePlacement] = []

        let frontLayer: [PixelFurniturePlacement] = [
            deskPlacement("office-desk-top-left", col: 2, row: 6, metrics: metrics),
            deskPlacement("office-desk-top-right", col: 7, row: 6, metrics: metrics),
            deskPlacement("office-desk-bottom-left", col: 2, row: 13, metrics: metrics),
            deskPlacement("office-desk-bottom-right", col: 7, row: 13, metrics: metrics),
            placement("office-monitor-top-left", "furniture/PC_FRONT_OFF.png", col: 3, row: 6, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("office-monitor-top-right", "furniture/PC_FRONT_OFF.png", col: 8, row: 6, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement(
                "office-monitor-bottom-left",
                "furniture/PC_FRONT_ON_1.png",
                col: 3,
                row: 13,
                pixelWidth: 16,
                pixelHeight: 32,
                metrics: metrics,
                glow: true,
                glowColor: Color(red: 0.36, green: 0.84, blue: 0.75),
                monitorFrames: [
                    "furniture/PC_FRONT_ON_1.png",
                    "furniture/PC_FRONT_ON_2.png",
                    "furniture/PC_FRONT_ON_3.png"
                ]
            ),
            placement(
                "office-monitor-bottom-right",
                "furniture/PC_FRONT_ON_1.png",
                col: 8,
                row: 13,
                pixelWidth: 16,
                pixelHeight: 32,
                metrics: metrics,
                glow: true,
                glowColor: Color(red: 0.36, green: 0.84, blue: 0.75),
                monitorFrames: [
                    "furniture/PC_FRONT_ON_1.png",
                    "furniture/PC_FRONT_ON_2.png",
                    "furniture/PC_FRONT_ON_3.png"
                ]
            ),
            placement("office-chair-top-left", "furniture/WOODEN_CHAIR_BACK.png", col: 4, row: 9, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("office-chair-top-right", "furniture/WOODEN_CHAIR_BACK.png", col: 8, row: 9, pixelWidth: 16, pixelHeight: 32, metrics: metrics),
            placement("office-coffee-left", "furniture/COFFEE.png", col: 4, row: 7, pixelWidth: 16, pixelHeight: 16, metrics: metrics),
            placement("office-coffee-right", "furniture/COFFEE.png", col: 9, row: 7, pixelWidth: 16, pixelHeight: 16, metrics: metrics),
            placement("office-coffee-bottom-left", "furniture/COFFEE.png", col: 4, row: 14, pixelWidth: 16, pixelHeight: 16, metrics: metrics),
            placement("office-coffee-bottom-right", "furniture/COFFEE.png", col: 9, row: 14, pixelWidth: 16, pixelHeight: 16, metrics: metrics),
            placement("lounge-table", "furniture/COFFEE_TABLE.png", col: 14, row: 14, pixelWidth: 32, pixelHeight: 32, metrics: metrics),
            placement("lounge-coffee", "furniture/COFFEE.png", col: 15, row: 15, pixelWidth: 16, pixelHeight: 16, metrics: metrics)
        ]

        return PixelOfficeFurnitureLayers(
            backLayer: backLayer,
            middleLayer: middleLayer,
            frontLayer: frontLayer
        )
    }

    static func animatedPose(
        for agent: PixelOfficeAgent,
        timestamp: TimeInterval,
        metrics: PixelOfficeSceneMetrics
    ) -> PixelOfficeAnimatedPose {
        switch agent.taskState {
        case .working:
            return PixelOfficeAnimatedPose(
                point: metrics.center(of: agent.seatTile),
                facing: agent.facing,
                animationState: .typing,
                isSeated: true
            )
        case .responding:
            return PixelOfficeAnimatedPose(
                point: metrics.center(of: agent.seatTile),
                facing: agent.facing,
                animationState: .reading,
                isSeated: true
            )
        case .idle:
            return routePose(
                route: idleRoute(for: agent),
                timestamp: timestamp,
                metrics: metrics,
                fallbackFacing: agent.facing,
                stationaryState: .idle
            )
        case .stale:
            return PixelOfficeAnimatedPose(
                point: metrics.center(of: agent.seatTile),
                facing: agent.facing,
                animationState: .idle,
                isSeated: true
            )
        case .waiting:
            return PixelOfficeAnimatedPose(
                point: metrics.center(of: agent.seatTile),
                facing: .down,
                animationState: .idle,
                isSeated: true
            )
        case .needsLogin, .quotaLow, .blocked, .error:
            return PixelOfficeAnimatedPose(
                point: metrics.center(of: agent.seatTile),
                facing: agent.facing,
                animationState: .idle,
                isSeated: true
            )
        }
    }

    private struct RouteStop {
        let tile: PixelOfficeTilePoint
        let dwell: Double
        let seated: Bool
        let facing: PixelCharacterFacing?
    }

    private static func routePose(
        route: [RouteStop],
        timestamp: TimeInterval,
        metrics: PixelOfficeSceneMetrics,
        fallbackFacing: PixelCharacterFacing,
        stationaryState: PixelCharacterAnimationState
    ) -> PixelOfficeAnimatedPose {
        guard route.count > 1 else {
            let point = metrics.center(of: route.first?.tile ?? PixelOfficeTilePoint(col: 10, row: 11))
            return PixelOfficeAnimatedPose(
                point: point,
                facing: route.first?.facing ?? fallbackFacing,
                animationState: stationaryState,
                isSeated: route.first?.seated ?? false
            )
        }

        var cycleDuration = 0.0
        for index in route.indices {
            cycleDuration += route[index].dwell
            let nextIndex = (index + 1) % route.count
            cycleDuration += travelDuration(from: route[index].tile, to: route[nextIndex].tile)
        }

        let time = positiveRemainder(timestamp * 0.95 + routeSeed(route) * 1.4, cycleDuration)
        var cursor = time

        for index in route.indices {
            let current = route[index]
            let next = route[(index + 1) % route.count]

            if cursor <= current.dwell {
                return PixelOfficeAnimatedPose(
                    point: metrics.center(of: current.tile),
                    facing: current.facing ?? facing(from: current.tile, to: next.tile, fallback: fallbackFacing),
                    animationState: stationaryState,
                    isSeated: current.seated
                )
            }

            cursor -= current.dwell
            let segmentDuration = travelDuration(from: current.tile, to: next.tile)
            if cursor <= segmentDuration {
                let from = metrics.center(of: current.tile)
                let to = metrics.center(of: next.tile)
                let progress = max(0, min(1, cursor / max(segmentDuration, 0.001)))
                let point = CGPoint(
                    x: from.x + (to.x - from.x) * progress,
                    y: from.y + (to.y - from.y) * progress
                )
                return PixelOfficeAnimatedPose(
                    point: point,
                    facing: facing(from: current.tile, to: next.tile, fallback: fallbackFacing),
                    animationState: .walking,
                    isSeated: false
                )
            }

            cursor -= segmentDuration
        }

        let last = route.last!
        return PixelOfficeAnimatedPose(
            point: metrics.center(of: last.tile),
            facing: last.facing ?? fallbackFacing,
            animationState: stationaryState,
            isSeated: last.seated
        )
    }

    private static func idleRoute(for agent: PixelOfficeAgent) -> [RouteStop] {
        if agent.seatTile.col >= 13 {
            let aisle = PixelOfficeTilePoint(col: 11, row: 15)
            let bookshelf = PixelOfficeTilePoint(col: 15 + (agent.spriteIndex % 2), row: 12)
            return [
                RouteStop(tile: agent.seatTile, dwell: 5.0, seated: true, facing: agent.facing),
                RouteStop(tile: aisle, dwell: 0.6, seated: false, facing: .left),
                RouteStop(tile: bookshelf, dwell: 0.9, seated: false, facing: .up),
                RouteStop(tile: agent.seatTile, dwell: 3.4, seated: true, facing: agent.facing)
            ]
        }

        let officePass = PixelOfficeTilePoint(col: 9, row: 14)
        let officeTop = PixelOfficeTilePoint(col: 6 + (agent.spriteIndex % 2), row: 11)
        return [
            RouteStop(tile: agent.seatTile, dwell: 1.2, seated: false, facing: .down),
            RouteStop(tile: officePass, dwell: 0.8, seated: false, facing: .right),
            RouteStop(tile: officeTop, dwell: 0.9, seated: false, facing: .up),
            RouteStop(tile: agent.seatTile, dwell: 0.8, seated: false, facing: .down)
        ]
    }

    private static func waitingRoute(for agent: PixelOfficeAgent) -> [RouteStop] {
        let corridorA = PixelOfficeTilePoint(col: 9, row: 13)
        let corridorB = PixelOfficeTilePoint(col: 11, row: 13)
        let corridorC = PixelOfficeTilePoint(col: 10, row: 9)
        return [
            RouteStop(tile: agent.seatTile, dwell: 0.8, seated: false, facing: .down),
            RouteStop(tile: corridorA, dwell: 0.6, seated: false, facing: .up),
            RouteStop(tile: corridorC, dwell: 0.7, seated: false, facing: .up),
            RouteStop(tile: corridorB, dwell: 0.6, seated: false, facing: .right)
        ]
    }

    private static func alertRoute(for agent: PixelOfficeAgent) -> [RouteStop] {
        let utilityCenter = PixelOfficeTilePoint(col: 16, row: 4)
        let utilityLeft = PixelOfficeTilePoint(col: 14, row: 4)
        let doorway = PixelOfficeTilePoint(col: 12, row: 14)
        if agent.seatTile.row <= 6 {
            return [
                RouteStop(tile: agent.seatTile, dwell: 1.8, seated: false, facing: agent.facing),
                RouteStop(tile: utilityCenter, dwell: 0.8, seated: false, facing: .down),
                RouteStop(tile: utilityLeft, dwell: 0.8, seated: false, facing: .left),
                RouteStop(tile: agent.seatTile, dwell: 1.0, seated: false, facing: agent.facing)
            ]
        }

        return [
            RouteStop(tile: doorway, dwell: 1.0, seated: false, facing: .right),
            RouteStop(tile: utilityCenter, dwell: 1.0, seated: false, facing: .down),
            RouteStop(tile: utilityLeft, dwell: 0.7, seated: false, facing: .left),
            RouteStop(tile: doorway, dwell: 0.7, seated: false, facing: .right)
        ]
    }

    private static func routeSeed(_ route: [RouteStop]) -> Double {
        route.reduce(0) { partialResult, stop in
            partialResult + Double(stop.tile.col * 31 + stop.tile.row * 17)
        }
    }

    private static func travelDuration(from start: PixelOfficeTilePoint, to end: PixelOfficeTilePoint) -> Double {
        let distance = abs(start.col - end.col) + abs(start.row - end.row)
        return max(Double(distance) / 3.0, 0.2)
    }

    private static func facing(
        from start: PixelOfficeTilePoint,
        to end: PixelOfficeTilePoint,
        fallback: PixelCharacterFacing
    ) -> PixelCharacterFacing {
        let horizontal = end.col - start.col
        let vertical = end.row - start.row
        if abs(horizontal) > abs(vertical) {
            return horizontal >= 0 ? .right : .left
        }
        if vertical != 0 {
            return vertical >= 0 ? .down : .up
        }
        return fallback
    }

    private static func positiveRemainder(_ lhs: Double, _ rhs: Double) -> Double {
        let value = lhs.truncatingRemainder(dividingBy: rhs)
        return value >= 0 ? value : value + rhs
    }

    private static func placement(
        _ id: String,
        _ subpath: String,
        col: Int,
        row: Int,
        pixelWidth: CGFloat,
        pixelHeight: CGFloat,
        metrics: PixelOfficeSceneMetrics,
        mirrored: Bool = false,
        glow: Bool = false,
        glowColor: Color = .white,
        monitorFrames: [String] = []
    ) -> PixelFurniturePlacement {
        PixelFurniturePlacement(
            id: id,
            subpath: subpath,
            position: metrics.spritePosition(col: col, row: row, pixelWidth: pixelWidth, pixelHeight: pixelHeight),
            size: metrics.spriteSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight),
            mirrored: mirrored,
            opacity: 1,
            brightness: 0,
            glow: glow,
            glowColor: glowColor,
            monitorFrames: monitorFrames
        )
    }

    private static func deskPlacement(
        _ id: String,
        col: Int,
        row: Int,
        metrics: PixelOfficeSceneMetrics
    ) -> PixelFurniturePlacement {
        placement(
            id,
            "furniture/DESK_FRONT.png",
            col: col,
            row: row,
            pixelWidth: 48,
            pixelHeight: 32,
            metrics: metrics
        )
    }
}

struct PixelOfficeAnimatedPose {
    let point: CGPoint
    let facing: PixelCharacterFacing
    let animationState: PixelCharacterAnimationState
    let isSeated: Bool
}

struct PixelOfficeTransitionPlan {
    let path: [CGPoint]
    let segmentDurations: [Double]
    let startTime: TimeInterval

    var endTime: TimeInterval {
        startTime + segmentDurations.reduce(0, +)
    }
}

@MainActor
enum PixelOfficeSceneBuilder {
    private struct PixelOfficeAnchor {
        let tile: PixelOfficeTilePoint
        let facing: PixelCharacterFacing
        let scenePoint: CGPoint
    }

    private static let unitSceneRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    private static var deskAisleLower: CGPoint { tileWaypoint(col: 8, row: 14) }
    private static var deskAisleUpper: CGPoint { tileWaypoint(col: 8, row: 11) }
    private static var rightDoorway: CGPoint { tileWaypoint(col: 10, row: 17) }
    private static var loungeCenter: CGPoint { tileWaypoint(col: 15, row: 16) }
    private static var loungeBookcase: CGPoint { tileWaypoint(col: 14, row: 14) }
    private static var utilityCenter: CGPoint { tileWaypoint(col: 16, row: 11) }
    private static var utilityLeft: CGPoint { tileWaypoint(col: 15, row: 11) }

    private static var deskSlots: [PixelOfficeAnchor] {
        let seats = PixelOfficeSourceLayoutStore.shared.deskSeats
        if !seats.isEmpty {
            return seats.map {
                PixelOfficeAnchor(
                    tile: $0.tile,
                    facing: $0.facing,
                    scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: $0.tile)
                )
            }
        }

        return [
            .init(tile: PixelOfficeTilePoint(col: 4, row: 16), facing: .up, scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: 4, row: 16))),
            .init(tile: PixelOfficeTilePoint(col: 8, row: 16), facing: .up, scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: 8, row: 16))),
            .init(tile: PixelOfficeTilePoint(col: 4, row: 9), facing: .up, scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: 4, row: 9))),
            .init(tile: PixelOfficeTilePoint(col: 8, row: 9), facing: .up, scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: 8, row: 9)))
        ]
    }

    private static var loungeSlots: [PixelOfficeAnchor] {
        let seats = PixelOfficeSourceLayoutStore.shared.loungeSeats
        if !seats.isEmpty {
            return seats.map {
                PixelOfficeAnchor(
                    tile: $0.tile,
                    facing: $0.facing,
                    scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: $0.tile)
                )
            }
        }

        return [
            .init(tile: PixelOfficeTilePoint(col: 13, row: 15), facing: .right, scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: 13, row: 15))),
            .init(tile: PixelOfficeTilePoint(col: 17, row: 15), facing: .left, scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: 17, row: 15)))
        ]
    }

    private static var alertSlots: [PixelOfficeAnchor] {
        let tiles = PixelOfficeSourceLayoutStore.shared.alertTiles()
        if !tiles.isEmpty {
            return tiles.map {
                PixelOfficeAnchor(
                    tile: $0,
                    facing: .right,
                    scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: $0)
                )
            }
        }

        return [
            .init(tile: PixelOfficeTilePoint(col: 12, row: 13), facing: .right, scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: PixelOfficeTilePoint(col: 12, row: 13)))
        ]
    }

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
                position: assignedAnchor.scenePoint,
                seatTile: assignedAnchor.tile,
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

    private struct SceneRouteStop {
        let point: CGPoint
        let dwell: Double
        let seated: Bool
        let facing: PixelCharacterFacing?
    }

    private struct ScenePoseState {
        let point: CGPoint
        let facing: PixelCharacterFacing
        let animationState: PixelCharacterAnimationState
        let isSeated: Bool
    }

    static func scenePose(
        for agent: PixelOfficeAgent,
        timestamp: TimeInterval,
        in sceneRect: CGRect
    ) -> PixelOfficeAnimatedPose {
        let state = scenePoseState(for: agent, timestamp: timestamp)
        return PixelOfficeAnimatedPose(
            point: scenePoint(state.point, in: sceneRect),
            facing: state.facing,
            animationState: state.animationState,
            isSeated: state.isSeated
        )
    }

    static func currentNormalizedPose(
        for agent: PixelOfficeAgent,
        timestamp: TimeInterval
    ) -> PixelOfficeAnimatedPose {
        scenePose(
            for: agent,
            timestamp: timestamp,
            in: unitSceneRect
        )
    }

    static func transitionPlan(
        from startPoint: CGPoint,
        previousAgent: PixelOfficeAgent,
        to nextAgent: PixelOfficeAgent,
        startTime: TimeInterval
    ) -> PixelOfficeTransitionPlan? {
        let path = compactPath(
            [
                startPoint
            ] + exitWaypoints(for: previousAgent.zone, from: startPoint)
                + entryWaypoints(for: nextAgent.zone, destination: nextAgent.position)
                + [nextAgent.position]
        )

        guard path.count > 1 else {
            return nil
        }

        let segmentDurations = zip(path, path.dropFirst()).map { start, end in
            transitionTravelDuration(from: start, to: end)
        }

        guard segmentDurations.contains(where: { $0 > 0 }) else {
            return nil
        }

        return PixelOfficeTransitionPlan(
            path: path,
            segmentDurations: segmentDurations,
            startTime: startTime
        )
    }

    static func transitionPose(
        for plan: PixelOfficeTransitionPlan,
        targetAgent: PixelOfficeAgent,
        timestamp: TimeInterval,
        in sceneRect: CGRect
    ) -> PixelOfficeAnimatedPose? {
        guard timestamp < plan.endTime else {
            return nil
        }

        var cursor = max(0, timestamp - plan.startTime)
        for index in plan.segmentDurations.indices {
            let duration = max(plan.segmentDurations[index], 0.001)
            let start = plan.path[index]
            let end = plan.path[index + 1]
            if cursor <= duration {
                let progress = max(0, min(1, cursor / duration))
                let point = CGPoint(
                    x: start.x + (end.x - start.x) * progress,
                    y: start.y + (end.y - start.y) * progress
                )
                return PixelOfficeAnimatedPose(
                    point: scenePoint(point, in: sceneRect),
                    facing: facing(from: start, to: end, fallback: targetAgent.facing),
                    animationState: .walking,
                    isSeated: false
                )
            }

            cursor -= duration
        }

        return nil
    }

    private static func scenePoseState(
        for agent: PixelOfficeAgent,
        timestamp: TimeInterval
    ) -> ScenePoseState {
        switch agent.taskState {
        case .working:
            return ScenePoseState(
                point: agent.position,
                facing: agent.facing,
                animationState: .typing,
                isSeated: true
            )
        case .responding:
            return ScenePoseState(
                point: agent.position,
                facing: agent.facing,
                animationState: .reading,
                isSeated: true
            )
        case .idle:
            return routePoseState(
                route: idleRoute(for: agent),
                timestamp: timestamp,
                fallbackFacing: agent.facing,
                stationaryState: .idle
            )
        case .stale:
            return ScenePoseState(
                point: agent.position,
                facing: agent.facing,
                animationState: .idle,
                isSeated: true
            )
        case .needsLogin, .blocked, .error:
            return ScenePoseState(
                point: agent.position,
                facing: agent.facing,
                animationState: .idle,
                isSeated: true
            )
        case .waiting:
            return ScenePoseState(
                point: agent.position,
                facing: .down,
                animationState: .idle,
                isSeated: true
            )
        case .quotaLow:
            return ScenePoseState(
                point: agent.position,
                facing: agent.facing,
                animationState: .idle,
                isSeated: true
            )
        }
    }

    private static func routePoseState(
        route: [SceneRouteStop],
        timestamp: TimeInterval,
        fallbackFacing: PixelCharacterFacing,
        stationaryState: PixelCharacterAnimationState
    ) -> ScenePoseState {
        guard route.count > 1 else {
            return ScenePoseState(
                point: route.first?.point ?? CGPoint(x: 0.5, y: 0.5),
                facing: route.first?.facing ?? fallbackFacing,
                animationState: stationaryState,
                isSeated: route.first?.seated ?? false
            )
        }

        var cycleDuration = 0.0
        for index in route.indices {
            cycleDuration += route[index].dwell
            let nextIndex = (index + 1) % route.count
            cycleDuration += normalizedTravelDuration(from: route[index].point, to: route[nextIndex].point)
        }

        let time = positiveRemainder(timestamp * 0.95 + routeSeed(route) * 1.4, cycleDuration)
        var cursor = time

        for index in route.indices {
            let current = route[index]
            let next = route[(index + 1) % route.count]

            if cursor <= current.dwell {
                return ScenePoseState(
                    point: current.point,
                    facing: current.facing ?? facing(from: current.point, to: next.point, fallback: fallbackFacing),
                    animationState: stationaryState,
                    isSeated: current.seated
                )
            }

            cursor -= current.dwell
            let segmentDuration = normalizedTravelDuration(from: current.point, to: next.point)
            if cursor <= segmentDuration {
                let progress = max(0, min(1, cursor / max(segmentDuration, 0.001)))
                let point = CGPoint(
                    x: current.point.x + (next.point.x - current.point.x) * progress,
                    y: current.point.y + (next.point.y - current.point.y) * progress
                )
                return ScenePoseState(
                    point: point,
                    facing: facing(from: current.point, to: next.point, fallback: fallbackFacing),
                    animationState: .walking,
                    isSeated: false
                )
            }

            cursor -= segmentDuration
        }

        let last = route.last!
        return ScenePoseState(
            point: last.point,
            facing: last.facing ?? fallbackFacing,
            animationState: stationaryState,
            isSeated: last.seated
        )
    }

    private static func idleRoute(for agent: PixelOfficeAgent) -> [SceneRouteStop] {
        if agent.zone == .lounge {
            return [
                SceneRouteStop(point: agent.position, dwell: 4.8, seated: true, facing: agent.facing),
                SceneRouteStop(point: loungeCenter, dwell: 0.7, seated: false, facing: .up),
                SceneRouteStop(point: loungeBookcase, dwell: 0.9, seated: false, facing: .up),
                SceneRouteStop(point: agent.position, dwell: 3.4, seated: true, facing: agent.facing)
            ]
        }

        let aisle = tileWaypoint(col: 8 + (agent.spriteIndex % 2), row: 14)
        let topDesk = tileWaypoint(col: 8 + (agent.spriteIndex % 2), row: 11)
        return [
            SceneRouteStop(point: agent.position, dwell: 0.8, seated: false, facing: .down),
            SceneRouteStop(point: aisle, dwell: 0.8, seated: false, facing: .right),
            SceneRouteStop(point: topDesk, dwell: 0.9, seated: false, facing: .up),
            SceneRouteStop(point: agent.position, dwell: 0.8, seated: false, facing: .down)
        ]
    }

    private static func waitingRoute(for agent: PixelOfficeAgent) -> [SceneRouteStop] {
        let rightCenter = tileWaypoint(col: 9, row: 14)
        return [
            SceneRouteStop(point: agent.position, dwell: 0.5, seated: false, facing: .down),
            SceneRouteStop(point: deskAisleLower, dwell: 0.5, seated: false, facing: .up),
            SceneRouteStop(point: deskAisleUpper, dwell: 0.7, seated: false, facing: .up),
            SceneRouteStop(point: rightCenter, dwell: 0.6, seated: false, facing: .right)
        ]
    }

    private static func alertRoute(for agent: PixelOfficeAgent) -> [SceneRouteStop] {
        return [
            SceneRouteStop(point: agent.position, dwell: 1.0, seated: false, facing: agent.facing),
            SceneRouteStop(point: utilityCenter, dwell: 1.0, seated: false, facing: .down),
            SceneRouteStop(point: utilityLeft, dwell: 0.7, seated: false, facing: .left),
            SceneRouteStop(point: rightDoorway, dwell: 0.7, seated: false, facing: .right)
        ]
    }

    private static func routeSeed(_ route: [SceneRouteStop]) -> Double {
        route.reduce(0) { partialResult, stop in
            partialResult + Double(Int(stop.point.x * 1000) * 31 + Int(stop.point.y * 1000) * 17)
        }
    }

    private static func normalizedTravelDuration(from start: CGPoint, to end: CGPoint) -> Double {
        let distance = hypot(end.x - start.x, end.y - start.y)
        return max(Double(distance / 0.14), 0.2)
    }

    private static func transitionTravelDuration(from start: CGPoint, to end: CGPoint) -> Double {
        let distance = hypot(end.x - start.x, end.y - start.y)
        return max(Double(distance / 0.18), 0.18)
    }

    private static func facing(
        from start: CGPoint,
        to end: CGPoint,
        fallback: PixelCharacterFacing
    ) -> PixelCharacterFacing {
        let horizontal = end.x - start.x
        let vertical = end.y - start.y
        if abs(horizontal) > abs(vertical) {
            return horizontal >= 0 ? .right : .left
        }
        if vertical != 0 {
            return vertical >= 0 ? .down : .up
        }
        return fallback
    }

    private static func scenePoint(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * normalized.x,
            y: rect.minY + rect.height * normalized.y
        )
    }

    private static func positiveRemainder(_ lhs: Double, _ rhs: Double) -> Double {
        let value = lhs.truncatingRemainder(dividingBy: rhs)
        return value >= 0 ? value : value + rhs
    }

    private static func exitWaypoints(for zone: PixelOfficeZone, from point: CGPoint) -> [CGPoint] {
        switch zone {
        case .desk:
            return [point.y >= 0.60 ? deskAisleLower : deskAisleUpper]
        case .lounge:
            return [loungeCenter, rightDoorway]
        case .alert:
            return [utilityCenter, rightDoorway]
        }
    }

    private static func entryWaypoints(for zone: PixelOfficeZone, destination: CGPoint) -> [CGPoint] {
        switch zone {
        case .desk:
            return [destination.y >= 0.60 ? deskAisleLower : deskAisleUpper]
        case .lounge:
            return [rightDoorway, loungeCenter]
        case .alert:
            return [rightDoorway, utilityCenter]
        }
    }

    private static func compactPath(_ points: [CGPoint]) -> [CGPoint] {
        var compacted: [CGPoint] = []
        for point in points {
            if let last = compacted.last, isApproximatelyEqual(last, point) {
                continue
            }
            compacted.append(point)
        }
        return compacted
    }

    private static func tileWaypoint(col: Int, row: Int) -> CGPoint {
        PixelOfficeSceneLayout.normalizedPosition(
            for: PixelOfficeTilePoint(col: col, row: row)
        )
    }

    private static func isApproximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
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
            let normalized = PixelOfficeSceneLayout.normalizedPosition(for: anchor.tile)
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
            let fallbackTile = PixelOfficeTilePoint(col: 10, row: 11)
            return PixelOfficeAnchor(
                tile: fallbackTile,
                facing: .down,
                scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: fallbackTile)
            )
        }

        if index < anchors.count {
            return anchors[index]
        }

        let fallbackColumn = index % 3
        let fallbackRow = index / 3

        switch fallbackZone {
        case .desk:
            let tile = PixelOfficeTilePoint(
                col: 4 + fallbackColumn * 4,
                row: 16 + fallbackRow * 3
            )
            return PixelOfficeAnchor(
                tile: tile,
                facing: .up,
                scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: tile)
            )
        case .lounge:
            let tile = PixelOfficeTilePoint(
                col: 13 + fallbackColumn * 2,
                row: 15 + fallbackRow * 2
            )
            return PixelOfficeAnchor(
                tile: tile,
                facing: fallbackColumn == 0 ? .right : .left,
                scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: tile)
            )
        case .alert:
            let tile = PixelOfficeTilePoint(
                col: 12 + fallbackColumn * 2,
                row: 4 + fallbackRow * 2
            )
            return PixelOfficeAnchor(
                tile: tile,
                facing: .down,
                scenePoint: PixelOfficeSceneLayout.normalizedPosition(for: tile)
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
        let lounging = agents.filter { $0.zone == .lounge && !$0.isAlerting }.count

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
            from: agents.filter(\.isAlerting),
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
        case .working, .responding, .waiting:
            return .desk
        case .idle, .needsLogin, .blocked, .error:
            return .lounge
        case .quotaLow, .stale:
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
