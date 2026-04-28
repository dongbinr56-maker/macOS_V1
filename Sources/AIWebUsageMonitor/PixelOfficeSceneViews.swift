import AppKit
import SwiftUI

struct PixelOfficeScene: View {
    let agents: [PixelOfficeAgent]
    let motionCoordinator: PixelOfficeMotionCoordinator
    let selectedAgentID: UUID?
    let focusedAgent: PixelOfficeAgent?
    let ambience: PixelOfficeAmbience
    let renderProfile: PixelOfficeRenderProfile
    let timestamp: TimeInterval
    let onSelect: (UUID) -> Void
    let onHover: (UUID?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let metrics = PixelOfficeSceneLayout.metrics(in: proxy.size)
            let renderedAgents = agents
                .map { agent in
                    (
                        agent,
                        motionCoordinator.pose(
                            for: agent,
                            timestamp: timestamp,
                            metrics: metrics
                        )
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.1.point.y != rhs.1.point.y {
                        return lhs.1.point.y < rhs.1.point.y
                    }

                    return lhs.0.displayName.localizedStandardCompare(rhs.0.displayName) == .orderedAscending
                }

            let sceneLayers = ZStack {
                PixelOfficeBackdrop(
                    metrics: metrics,
                    ambience: ambience,
                    renderProfile: renderProfile,
                    timestamp: timestamp
                )

                PixelOfficeAlertLighting(
                    metrics: metrics,
                    agents: agents,
                    timestamp: timestamp
                )

                ForEach(renderedAgents, id: \.0.id) { rendered in
                    PixelOfficeAgentView(
                        agent: rendered.0,
                        pose: rendered.1,
                        isSelected: rendered.0.id == selectedAgentID,
                        isHovered: rendered.0.id == focusedAgent?.id && rendered.0.id != selectedAgentID,
                        timestamp: timestamp,
                        onHover: onHover
                    ) {
                        onSelect(rendered.0.id)
                    }
                    .position(rendered.1.point)
                    .zIndex(Double(rendered.1.point.y - metrics.origin.y + metrics.tileSize / 2 + 0.5))
                }
            }

            let camera = cameraTransform(metrics: metrics, renderedAgents: renderedAgents)
            sceneLayers
                .scaleEffect(camera.scale, anchor: .center)
                .offset(x: camera.offset.width, y: camera.offset.height)
                .animation(.easeInOut(duration: 0.35), value: camera.scale)
                .animation(.easeInOut(duration: 0.35), value: camera.offset)
        }
        .background(
            LinearGradient(
                colors: [
                    ambience.skyTop,
                    ambience.skyBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func cameraTransform(
        metrics: PixelOfficeSceneMetrics,
        renderedAgents: [(PixelOfficeAgent, PixelOfficeAnimatedPose)]
    ) -> (scale: CGFloat, offset: CGSize) {
        guard renderProfile != .focused,
              let selectedAgentID,
              let selected = renderedAgents.first(where: { $0.0.id == selectedAgentID }) else {
            return (1.0, .zero)
        }

        let target = selected.1.point
        let center = CGPoint(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)
        let dx = (center.x - target.x) * 0.34
        let dy = (center.y - target.y) * 0.26
        let clampedX = max(-18, min(18, dx))
        let clampedY = max(-14, min(14, dy))
        let scale: CGFloat = renderProfile == .cinematic ? 1.07 : 1.04
        return (scale, CGSize(width: clampedX, height: clampedY))
    }
}

struct PixelOfficeBackdrop: View {
    let metrics: PixelOfficeSceneMetrics
    let ambience: PixelOfficeAmbience
    let renderProfile: PixelOfficeRenderProfile
    let timestamp: TimeInterval

    var body: some View {
        let backdrop = PixelOfficeSourceLayoutStore.shared.backdropImage(in: metrics)

        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.11)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.03, green: 0.04, blue: 0.08))
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)

            if let backdrop {
                Image(nsImage: backdrop)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                    .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)

            Rectangle()
                .fill(ambience.overlay)
                .opacity(renderProfile == .focused ? 0.45 : 1)
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)

            if ambience.phase == .night, renderProfile != .focused {
                PixelOfficeNightFireflies(
                    metrics: metrics,
                    timestamp: timestamp,
                    accent: ambience.accent,
                    density: renderProfile == .cinematic ? 1.0 : 0.65
                )
            }

            if renderProfile == .cinematic {
                PixelOfficeCinematicDust(metrics: metrics, timestamp: timestamp, accent: ambience.accent)
            }
        }
    }
}

struct PixelOfficeNightFireflies: View {
    let metrics: PixelOfficeSceneMetrics
    let timestamp: TimeInterval
    let accent: Color
    let density: Double

    private let anchors: [CGPoint] = [
        CGPoint(x: 0.10, y: 0.18),
        CGPoint(x: 0.24, y: 0.14),
        CGPoint(x: 0.39, y: 0.20),
        CGPoint(x: 0.61, y: 0.17),
        CGPoint(x: 0.75, y: 0.14),
        CGPoint(x: 0.88, y: 0.21)
    ]

    var body: some View {
        let limit = max(2, Int(Double(anchors.count) * density))
        ZStack {
            ForEach(Array(anchors.prefix(limit).enumerated()), id: \.offset) { index, anchor in
                Circle()
                    .fill(accent.opacity(0.65))
                    .frame(width: 3, height: 3)
                    .blur(radius: 0.5)
                    .opacity(0.35 + (sin(timestamp * 1.7 + Double(index) * 1.1) + 1) * 0.24)
                    .position(
                        x: metrics.sceneRect.minX + metrics.sceneSize.width * anchor.x,
                        y: metrics.sceneRect.minY + metrics.sceneSize.height * anchor.y
                    )
            }
        }
    }
}

struct PixelOfficeCinematicDust: View {
    let metrics: PixelOfficeSceneMetrics
    let timestamp: TimeInterval
    let accent: Color

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let phase = timestamp * 0.18 + Double(index) * 0.23
                let x = metrics.sceneRect.minX + metrics.sceneSize.width * CGFloat((phase.truncatingRemainder(dividingBy: 1)))
                let yBase = 0.14 + Double(index % 4) * 0.12
                let y = metrics.sceneRect.minY + metrics.sceneSize.height * CGFloat(yBase + sin(timestamp * 0.7 + Double(index)) * 0.015)

                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 6, height: 6)
                    .blur(radius: 1.5)
                    .position(x: x, y: y)
            }
        }
        .blendMode(.screen)
    }
}

struct PixelOfficeAlertLighting: View {
    let metrics: PixelOfficeSceneMetrics
    let agents: [PixelOfficeAgent]
    let timestamp: TimeInterval

    private var alertIntensity: Double {
        guard agents.contains(where: \.isAlerting) else {
            return 0
        }
        return 0.08 + (sin(timestamp * 2.8) + 1) * 0.06
    }

    var body: some View {
        if alertIntensity > 0 {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(alertIntensity * 0.45),
                            Color.orange.opacity(alertIntensity),
                            Color.clear
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: metrics.sceneSize.width, height: metrics.sceneSize.height)
                .position(x: metrics.sceneRect.midX, y: metrics.sceneRect.midY)
                .blendMode(.screen)
        }
    }
}

struct PixelOfficeTiledArea: View {
    let subpath: String
    let rect: CGRect
    let tileSize: CGFloat

    var body: some View {
        let columns = max(Int(ceil(rect.width / tileSize)), 1)
        let rows = max(Int(ceil(rect.height / tileSize)), 1)

        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { _ in
                        PixelOfficeTiledImage(
                            subpath: subpath,
                            size: CGSize(width: tileSize, height: tileSize)
                        )
                    }
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .position(x: rect.midX, y: rect.midY)
    }
}

struct PixelOfficeFurnitureView: View {
    let item: PixelFurniturePlacement
    let timestamp: TimeInterval

    var body: some View {
        ZStack(alignment: .center) {
            if item.glow {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.glowColor.opacity(0.22))
                    .frame(width: item.size.width + 18, height: item.size.height + 18)
                    .blur(radius: 6)
            }

            furnitureBody
                .opacity(item.opacity)
                .brightness(item.brightness)
                .scaleEffect(x: item.mirrored ? -1 : 1, y: 1)
                .overlay(alignment: .center) {
                    if item.monitorFrames.count > 1 {
                        PixelOfficeImage(
                            subpath: item.monitorFrames[currentMonitorFrameIndex],
                            size: item.size
                        )
                    }
                }
        }
        .position(item.position)
    }

    @ViewBuilder
    private var furnitureBody: some View {
        if let resolvedImage = item.resolvedImage {
            Image(nsImage: resolvedImage)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
        } else if item.subpath.hasPrefix("custom:") {
            PixelOfficeCustomFurnitureView(kind: item.subpath, size: item.size)
        } else {
            PixelOfficeImage(subpath: item.subpath, size: item.size)
        }
    }

    private var currentMonitorFrameIndex: Int {
        guard !item.monitorFrames.isEmpty else {
            return 0
        }

        return Int((timestamp * 2.2).rounded(.down)).quotientAndRemainder(dividingBy: item.monitorFrames.count).remainder
    }
}

struct PixelOfficeCustomFurnitureView: View {
    let kind: String
    let size: CGSize

    var body: some View {
        PixelOfficePixelArt(
            rows: spriteRows,
            palette: palette,
            size: size
        )
    }

    private var spriteRows: [String] {
        switch kind {
        case "custom:vending-machine":
            return [
                "................",
                ".AAAAAAAAAAAAAA.",
                ".ABBBBBBBBBBBBA.",
                ".ABCCCCDDCCCCBA.",
                ".ABCEEEEFEEEECBA",
                ".ABCEEEEFEEEECBA",
                ".ABCGGGGGGGGECBA",
                ".ABCGHHIHHHHECBA",
                ".ABCGHHIHHHHECBA",
                ".ABCGJJJJJJJECBA",
                ".ABCKKKKKKKKECBA",
                ".ABCKLLLMLKKECBA",
                ".ABCKLLLMLKKECBA",
                ".ABCKNNNNNNKECBA",
                ".ABCOOOPOOOKECBA",
                ".ABCOOOPOOOKECBA",
                ".ABCQQQQQQQKECBA",
                ".ABCRRRRRRRKECBA",
                ".ABCSSSSSSSKECBA",
                ".ABCTTTTTTTKECBA",
                ".ABCUUUUUUUKECBA",
                ".ABCVVVVVVVKECBA",
                ".ABWWWWWWWWKECBA",
                ".ABXXXXXXXXXECBA",
                ".ABYYYYYYYYYECBA",
                ".ABZZZZZZZZZECBA",
                ".AB000000000ECBA",
                ".AB111111111ECBA",
                ".AB222223333ECBA",
                ".AB444445555ECBA",
                ".AB666666666EBA.",
                ".AAAAAAAAAAAAAA."
            ]
        case "custom:water-cooler":
            return [
                "........",
                "..AAAA..",
                ".ABBBBA.",
                ".ABCCBA.",
                "..ADDA..",
                "..ADDA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA..",
                "..AEEA.."
            ]
        case "custom:counter":
            return [
                "................",
                "................",
                "AAAAAAAAAAAAAAAA",
                "ABBBBBBBBBBBBBBA",
                "ACCCCCCCCCCCCCCA",
                "ADDDDEEEEEDDDDDA",
                "ADDDDFFFFFDDDDDA",
                "ADDDDEEEEEDDDDDA",
                "ADDDDDDDDDDDDDDA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AGGGGHHIIHHGGGGA",
                "AJJJJHHIIHHJJJJA",
                "AKKKKKKKKKKKKKKA"
            ]
        case "custom:fridge":
            return [
                "..AAAA..",
                ".ABBBBA.",
                ".ACCCCA.",
                ".ACDDCA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".ACEECA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".ACDDCA.",
                ".ACCCCA.",
                ".ACCCCA.",
                ".AFFFFA.",
                ".AGGGGA.",
                ".AHHHHA."
            ]
        default:
            return ["....", ".AA.", ".AA.", "...."]
        }
    }

    private var palette: [Character: Color] {
        switch kind {
        case "custom:vending-machine":
            return [
                ".": .clear,
                "A": Color(red: 0.16, green: 0.20, blue: 0.31),
                "B": Color(red: 0.74, green: 0.84, blue: 0.93),
                "C": Color(red: 0.29, green: 0.36, blue: 0.53),
                "D": Color(red: 0.63, green: 0.10, blue: 0.15),
                "E": Color(red: 0.92, green: 0.95, blue: 0.98),
                "F": Color(red: 0.18, green: 0.69, blue: 0.57),
                "G": Color(red: 0.51, green: 0.58, blue: 0.70),
                "H": Color(red: 0.15, green: 0.21, blue: 0.29),
                "I": Color(red: 0.80, green: 0.88, blue: 0.95),
                "J": Color(red: 0.79, green: 0.69, blue: 0.34),
                "K": Color(red: 0.28, green: 0.33, blue: 0.46),
                "L": Color(red: 0.98, green: 0.61, blue: 0.24),
                "M": Color(red: 0.92, green: 0.28, blue: 0.30),
                "N": Color(red: 0.25, green: 0.58, blue: 0.92),
                "O": Color(red: 0.22, green: 0.25, blue: 0.34),
                "P": Color(red: 0.97, green: 0.93, blue: 0.67),
                "Q": Color(red: 0.75, green: 0.76, blue: 0.79),
                "R": Color(red: 0.61, green: 0.66, blue: 0.73),
                "S": Color(red: 0.33, green: 0.37, blue: 0.45),
                "T": Color(red: 0.49, green: 0.52, blue: 0.58),
                "U": Color(red: 0.22, green: 0.25, blue: 0.31),
                "V": Color(red: 0.87, green: 0.89, blue: 0.92),
                "W": Color(red: 0.98, green: 0.74, blue: 0.28),
                "X": Color(red: 0.85, green: 0.18, blue: 0.21),
                "Y": Color(red: 0.18, green: 0.77, blue: 0.64),
                "Z": Color(red: 0.24, green: 0.68, blue: 0.89),
                "0": Color(red: 0.29, green: 0.31, blue: 0.39),
                "1": Color(red: 0.40, green: 0.42, blue: 0.48),
                "2": Color(red: 0.25, green: 0.27, blue: 0.32),
                "3": Color(red: 0.13, green: 0.14, blue: 0.18),
                "4": Color(red: 0.57, green: 0.63, blue: 0.73),
                "5": Color(red: 0.31, green: 0.35, blue: 0.43),
                "6": Color(red: 0.12, green: 0.14, blue: 0.20)
            ]
        case "custom:water-cooler":
            return [
                ".": .clear,
                "A": Color(red: 0.23, green: 0.27, blue: 0.34),
                "B": Color(red: 0.86, green: 0.94, blue: 0.99),
                "C": Color(red: 0.62, green: 0.77, blue: 0.95),
                "D": Color(red: 0.89, green: 0.91, blue: 0.96),
                "E": Color(red: 0.74, green: 0.78, blue: 0.84)
            ]
        case "custom:counter":
            return [
                ".": .clear,
                "A": Color(red: 0.20, green: 0.19, blue: 0.24),
                "B": Color(red: 0.93, green: 0.92, blue: 0.88),
                "C": Color(red: 0.87, green: 0.83, blue: 0.76),
                "D": Color(red: 0.72, green: 0.54, blue: 0.31),
                "E": Color(red: 0.66, green: 0.47, blue: 0.25),
                "F": Color(red: 0.57, green: 0.38, blue: 0.18),
                "G": Color(red: 0.70, green: 0.72, blue: 0.76),
                "H": Color(red: 0.40, green: 0.43, blue: 0.50),
                "I": Color(red: 0.24, green: 0.26, blue: 0.31),
                "J": Color(red: 0.59, green: 0.61, blue: 0.65),
                "K": Color(red: 0.27, green: 0.29, blue: 0.35)
            ]
        case "custom:fridge":
            return [
                ".": .clear,
                "A": Color(red: 0.18, green: 0.20, blue: 0.25),
                "B": Color(red: 0.91, green: 0.93, blue: 0.96),
                "C": Color(red: 0.82, green: 0.85, blue: 0.89),
                "D": Color(red: 0.62, green: 0.66, blue: 0.72),
                "E": Color(red: 0.73, green: 0.76, blue: 0.81),
                "F": Color(red: 0.69, green: 0.72, blue: 0.76),
                "G": Color(red: 0.57, green: 0.61, blue: 0.67),
                "H": Color(red: 0.36, green: 0.39, blue: 0.46)
            ]
        default:
            return [".": .clear, "A": Color.white]
        }
    }
}

struct PixelOfficePixelArt: View {
    let rows: [String]
    let palette: [Character: Color]
    let size: CGSize

    var body: some View {
        GeometryReader { proxy in
            let rowCount = max(rows.count, 1)
            let columnCount = max(rows.map(\.count).max() ?? 1, 1)
            let pixelWidth = proxy.size.width / CGFloat(columnCount)
            let pixelHeight = proxy.size.height / CGFloat(rowCount)

            Canvas { context, _ in
                for (rowIndex, row) in rows.enumerated() {
                    for (columnIndex, character) in row.enumerated() {
                        guard character != ".", let color = palette[character] else {
                            continue
                        }

                        let rect = CGRect(
                            x: CGFloat(columnIndex) * pixelWidth,
                            y: CGFloat(rowIndex) * pixelHeight,
                            width: ceil(pixelWidth),
                            height: ceil(pixelHeight)
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .drawingGroup(opaque: false)
        }
        .frame(width: size.width, height: size.height)
    }
}
