import AppKit
import Foundation
import SwiftUI

struct PixelOfficeSourceColorAdjustment: Codable, Hashable {
    let h: Int
    let s: Int
    let b: Int
    let c: Int
    let colorize: Bool?

    var cacheKey: String {
        "\(h)-\(s)-\(b)-\(c)-\(colorize == true ? 1 : 0)"
    }
}

struct PixelOfficeSourcePlacedFurniture: Codable {
    let uid: String
    let type: String
    let col: Int
    let row: Int
}

struct PixelOfficeSourceLayout: Codable {
    let version: Int
    let cols: Int
    let rows: Int
    let layoutRevision: Int
    let tiles: [Int]
    let tileColors: [PixelOfficeSourceColorAdjustment?]
    let furniture: [PixelOfficeSourcePlacedFurniture]
}

private struct PixelOfficeFurnitureManifestNode: Codable {
    let type: String?
    let id: String?
    let name: String?
    let category: String?
    let canPlaceOnWalls: Bool?
    let canPlaceOnSurfaces: Bool?
    let backgroundTiles: Int?
    let width: Int?
    let height: Int?
    let footprintW: Int?
    let footprintH: Int?
    let groupType: String?
    let rotationScheme: String?
    let members: [PixelOfficeFurnitureManifestNode]?
    let file: String?
    let orientation: String?
    let state: String?
    let mirrorSide: Bool?
    let frame: Int?
}

private struct PixelOfficeFurnitureMetadata {
    let type: String
    let subpath: String
    let width: Int
    let height: Int
    let footprintW: Int
    let footprintH: Int
    let category: String
    let backgroundTiles: Int
    let orientation: String?
    let canPlaceOnSurfaces: Bool
    let mirrored: Bool

    var isDesk: Bool {
        category == "desks"
    }
}

struct PixelOfficeSourceSeat: Hashable {
    let uid: String
    let tile: PixelOfficeTilePoint
    let facing: PixelCharacterFacing
    let zone: PixelOfficeZone
}

struct PixelOfficeFloorTileRender: Identifiable {
    let id: String
    let image: NSImage
    let rect: CGRect
}

struct PixelOfficeSolidTileRender: Identifiable {
    let id: String
    let color: NSColor
    let rect: CGRect
}

struct PixelOfficeRenderableFurniture: Identifiable {
    let id: String
    let placement: PixelFurniturePlacement
    let zIndex: Double
}

struct PixelOfficeVisibleBounds {
    let minCol: Int
    let maxCol: Int
    let minRow: Int
    let maxRow: Int

    var columns: Int {
        max(maxCol - minCol + 1, 1)
    }

    var rows: Int {
        max(maxRow - minRow + 1, 1)
    }
}

@MainActor
final class PixelOfficeSourceLayoutStore {
    static let shared = PixelOfficeSourceLayoutStore()

    private(set) var layout: PixelOfficeSourceLayout?
    private(set) var visibleBounds = PixelOfficeVisibleBounds(minCol: 0, maxCol: 20, minRow: 0, maxRow: 21)
    private(set) var deskSeats: [PixelOfficeSourceSeat] = []
    private(set) var loungeSeats: [PixelOfficeSourceSeat] = []

    private var metadataByType: [String: PixelOfficeFurnitureMetadata] = [:]
    private var backdropImageCache: [String: NSImage] = [:]

    private init() {
        load()
    }

    func floorTiles(in metrics: PixelOfficeSceneMetrics) -> [PixelOfficeFloorTileRender] {
        guard let layout else {
            return []
        }

        var renders: [PixelOfficeFloorTileRender] = []
        renders.reserveCapacity(layout.cols * layout.rows)

        for row in 0..<layout.rows {
            for col in 0..<layout.cols {
                let index = row * layout.cols + col
                guard index < layout.tiles.count else {
                    continue
                }

                let tile = layout.tiles[index]
                guard tile != 255, tile != 0,
                      let image = PixelOfficeAssetStore.shared.floorTileImage(
                        pattern: tile,
                        adjustment: layout.tileColors[safe: index] ?? nil
                      ) else {
                    continue
                }

                let rect = metrics.rect(col: col, row: row, width: 1, height: 1)
                renders.append(
                    PixelOfficeFloorTileRender(
                        id: "floor-\(col)-\(row)",
                        image: image,
                        rect: rect
                    )
                )
            }
        }

        return renders
    }

    func wallBaseTiles(in metrics: PixelOfficeSceneMetrics) -> [PixelOfficeSolidTileRender] {
        guard let layout else {
            return []
        }

        var renders: [PixelOfficeSolidTileRender] = []
        renders.reserveCapacity(layout.cols * layout.rows)

        for row in 0..<layout.rows {
            for col in 0..<layout.cols {
                let index = row * layout.cols + col
                guard index < layout.tiles.count,
                      layout.tiles[index] == 0 else {
                    continue
                }

                let rect = metrics.rect(col: col, row: row, width: 1, height: 1)
                let color = PixelOfficeAssetStore.shared.wallBaseColor(
                    adjustment: layout.tileColors[safe: index] ?? nil
                )
                renders.append(
                    PixelOfficeSolidTileRender(
                        id: "wall-fill-\(col)-\(row)",
                        color: color,
                        rect: rect
                    )
                )
            }
        }

        return renders
    }

    func renderables(in metrics: PixelOfficeSceneMetrics) -> [PixelOfficeRenderableFurniture] {
        guard let layout else {
            return []
        }

        var renderables: [PixelOfficeRenderableFurniture] = []
        renderables.append(contentsOf: wallRenderables(in: metrics, layout: layout))
        renderables.append(contentsOf: furnitureRenderables(in: metrics, layout: layout))
        return renderables.sorted { lhs, rhs in
            if lhs.zIndex != rhs.zIndex {
                return lhs.zIndex < rhs.zIndex
            }

            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func backdropImage(in metrics: PixelOfficeSceneMetrics) -> NSImage? {
        let cacheKey = [
            Int(metrics.tileSize.rounded()),
            metrics.minCol,
            metrics.minRow,
            metrics.visibleColumns,
            metrics.visibleRows
        ]
        .map(String.init)
        .joined(separator: ":")

        if let cached = backdropImageCache[cacheKey] {
            return cached
        }

        let image = NSImage(size: metrics.sceneSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current else {
            return nil
        }
        context.imageInterpolation = .none

        let baseRect = CGRect(origin: .zero, size: metrics.sceneSize)
        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1).setFill()
        baseRect.fill()

        for tile in wallBaseTiles(in: metrics) {
            tile.color.setFill()
            translated(tile.rect, in: metrics).fill()
        }

        for tile in floorTiles(in: metrics) {
            tile.image.draw(
                in: translated(tile.rect, in: metrics),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        for item in renderables(in: metrics) {
            draw(placement: item.placement, in: metrics)
        }

        backdropImageCache[cacheKey] = image
        return image
    }

    func alertTiles() -> [PixelOfficeTilePoint] {
        [
            PixelOfficeTilePoint(col: 10, row: 14),
            PixelOfficeTilePoint(col: 11, row: 14),
            PixelOfficeTilePoint(col: 11, row: 12)
        ]
    }

    private func load() {
        loadLayout()
        loadMetadata()
        rebuildVisibleBounds()
        buildSeats()
    }

    private func loadLayout() {
        guard let url = PixelOfficeAssetStore.shared.resourceURL(for: "default-layout-1.json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PixelOfficeSourceLayout.self, from: data) else {
            layout = nil
            return
        }

        layout = decoded
        backdropImageCache.removeAll()
    }

    private func loadMetadata() {
        metadataByType = [:]
        guard let fileURL = PixelOfficeAssetStore.shared.resourceURL(for: "furniture-manifests.json"),
              let data = try? Data(contentsOf: fileURL),
              let nodes = try? JSONDecoder().decode([PixelOfficeFurnitureManifestNode].self, from: data) else {
            return
        }

        for node in nodes {
            collectMetadata(from: node, inherited: nil)
        }
        backdropImageCache.removeAll()
    }

    private func collectMetadata(
        from node: PixelOfficeFurnitureManifestNode,
        inherited: PixelOfficeFurnitureMetadata?
    ) {
        let inheritedCategory = node.category ?? inherited?.category ?? "misc"
        let inheritedBackgroundTiles = node.backgroundTiles ?? inherited?.backgroundTiles ?? 0
        let inheritedOrientation = node.orientation ?? inherited?.orientation
        let inheritedCanPlaceOnSurfaces = node.canPlaceOnSurfaces ?? inherited?.canPlaceOnSurfaces ?? false

        if node.type == "asset",
           let id = node.id,
           let width = node.width,
           let height = node.height,
           let footprintW = node.footprintW,
           let footprintH = node.footprintH {
            let fileName = node.file ?? "\(id).png"
            let metadata = PixelOfficeFurnitureMetadata(
                type: id,
                subpath: "furniture/\(fileName)",
                width: width,
                height: height,
                footprintW: footprintW,
                footprintH: footprintH,
                category: inheritedCategory,
                backgroundTiles: inheritedBackgroundTiles,
                orientation: inheritedOrientation,
                canPlaceOnSurfaces: inheritedCanPlaceOnSurfaces,
                mirrored: false
            )
            metadataByType[id] = metadata

            if node.mirrorSide == true, inheritedOrientation == "side" {
                metadataByType["\(id):left"] = PixelOfficeFurnitureMetadata(
                    type: "\(id):left",
                    subpath: metadata.subpath,
                    width: metadata.width,
                    height: metadata.height,
                    footprintW: metadata.footprintW,
                    footprintH: metadata.footprintH,
                    category: metadata.category,
                    backgroundTiles: metadata.backgroundTiles,
                    orientation: "left",
                    canPlaceOnSurfaces: metadata.canPlaceOnSurfaces,
                    mirrored: true
                )
            }
            return
        }

        guard let members = node.members else {
            return
        }

        let inheritedMetadata = PixelOfficeFurnitureMetadata(
            type: inherited?.type ?? node.id ?? "",
            subpath: inherited?.subpath ?? "",
            width: inherited?.width ?? 0,
            height: inherited?.height ?? 0,
            footprintW: inherited?.footprintW ?? 0,
            footprintH: inherited?.footprintH ?? 0,
            category: inheritedCategory,
            backgroundTiles: inheritedBackgroundTiles,
            orientation: inheritedOrientation,
            canPlaceOnSurfaces: inheritedCanPlaceOnSurfaces,
            mirrored: inherited?.mirrored ?? false
        )

        for member in members {
            collectMetadata(from: member, inherited: inheritedMetadata)
        }
    }

    private func rebuildVisibleBounds() {
        guard let layout else {
            visibleBounds = PixelOfficeVisibleBounds(minCol: 0, maxCol: 20, minRow: 0, maxRow: 21)
            return
        }
        visibleBounds = resolveVisibleBounds(for: layout)
    }

    private func resolveVisibleBounds(for layout: PixelOfficeSourceLayout) -> PixelOfficeVisibleBounds {
        var minCol = layout.cols - 1
        var maxCol = 0
        var minRow = layout.rows - 1
        var maxRow = 0
        var found = false

        for row in 0..<layout.rows {
            for col in 0..<layout.cols {
                let tile = layout.tiles[(row * layout.cols) + col]
                guard tile != 255 else {
                    continue
                }

                found = true
                minCol = min(minCol, col)
                maxCol = max(maxCol, col)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }

        for furniture in layout.furniture {
            guard let metadata = metadataByType[furniture.type] else {
                continue
            }

            found = true
            minCol = min(minCol, furniture.col)
            minRow = min(minRow, furniture.row)
            maxCol = max(maxCol, furniture.col + max(metadata.width / 16, 1) - 1)
            maxRow = max(maxRow, furniture.row + max(metadata.height / 16, 1) - 1)
        }

        guard found else {
            return PixelOfficeVisibleBounds(minCol: 0, maxCol: max(layout.cols - 1, 0), minRow: 0, maxRow: max(layout.rows - 1, 0))
        }

        return PixelOfficeVisibleBounds(
            minCol: minCol,
            maxCol: maxCol,
            minRow: minRow,
            maxRow: maxRow
        )
    }

    private func translated(_ rect: CGRect, in metrics: PixelOfficeSceneMetrics) -> CGRect {
        let localX = rect.origin.x - metrics.origin.x
        let localY = rect.origin.y - metrics.origin.y

        return CGRect(
            x: localX,
            y: metrics.sceneSize.height - localY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func draw(placement: PixelFurniturePlacement, in metrics: PixelOfficeSceneMetrics) {
        guard let image = placement.resolvedImage ?? PixelOfficeAssetStore.shared.image(placement.subpath) else {
            return
        }

        let rect = CGRect(
            x: placement.position.x - metrics.origin.x - placement.size.width / 2,
            y: metrics.sceneSize.height - (placement.position.y - metrics.origin.y) - placement.size.height / 2,
            width: placement.size.width,
            height: placement.size.height
        )

        if placement.mirrored, let cgContext = NSGraphicsContext.current?.cgContext {
            cgContext.saveGState()
            cgContext.translateBy(x: rect.midX, y: rect.midY)
            cgContext.scaleBy(x: -1, y: 1)
            cgContext.translateBy(x: -rect.midX, y: -rect.midY)
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: placement.opacity
            )
            cgContext.restoreGState()
            return
        }

        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: placement.opacity
        )
    }

    private func buildSeats() {
        deskSeats = []
        loungeSeats = []

        guard let layout else {
            return
        }

        let deskTiles = deskTileSet(from: layout)
        var deskPool: [PixelOfficeSourceSeat] = []
        var loungePool: [PixelOfficeSourceSeat] = []

        for furniture in layout.furniture {
            guard let metadata = metadataByType[furniture.type],
                  metadata.category == "chairs" else {
                continue
            }

            var seatIndex = 0
            for deltaRow in metadata.backgroundTiles..<metadata.footprintH {
                for deltaCol in 0..<metadata.footprintW {
                    let tile = PixelOfficeTilePoint(
                        col: furniture.col + deltaCol,
                        row: furniture.row + deltaRow
                    )
                    let seatUID = seatIndex == 0 ? furniture.uid : "\(furniture.uid):\(seatIndex)"
                    let facing = resolveFacing(
                        orientation: metadata.orientation,
                        tile: tile,
                        deskTiles: deskTiles
                    )
                    let seat = PixelOfficeSourceSeat(
                        uid: seatUID,
                        tile: tile,
                        facing: facing,
                        zone: tile.col >= 12 ? .lounge : .desk
                    )
                    if seat.zone == .desk {
                        deskPool.append(seat)
                    } else {
                        loungePool.append(seat)
                    }
                    seatIndex += 1
                }
            }
        }

        deskSeats = deskPool.sorted(by: deskSeatSort)
        loungeSeats = loungePool.sorted(by: loungeSeatSort)
    }

    private func deskTileSet(from layout: PixelOfficeSourceLayout) -> Set<String> {
        var result: Set<String> = []
        for furniture in layout.furniture {
            guard let metadata = metadataByType[furniture.type],
                  metadata.isDesk else {
                continue
            }

            for deltaRow in 0..<metadata.footprintH {
                for deltaCol in 0..<metadata.footprintW {
                    result.insert("\(furniture.col + deltaCol),\(furniture.row + deltaRow)")
                }
            }
        }
        return result
    }

    private func resolveFacing(
        orientation: String?,
        tile: PixelOfficeTilePoint,
        deskTiles: Set<String>
    ) -> PixelCharacterFacing {
        switch orientation {
        case "front":
            return .down
        case "back":
            return .up
        case "left":
            return .left
        case "right", "side":
            return .right
        default:
            let adjacency: [(Int, Int, PixelCharacterFacing)] = [
                (0, -1, .up),
                (0, 1, .down),
                (-1, 0, .left),
                (1, 0, .right)
            ]
            for (deltaCol, deltaRow, facing) in adjacency {
                if deskTiles.contains("\(tile.col + deltaCol),\(tile.row + deltaRow)") {
                    return facing
                }
            }
            return .down
        }
    }

    private func deskSeatSort(lhs: PixelOfficeSourceSeat, rhs: PixelOfficeSourceSeat) -> Bool {
        let leftPriority = deskSeatPriority(lhs)
        let rightPriority = deskSeatPriority(rhs)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if lhs.tile.row != rhs.tile.row {
            return lhs.tile.row < rhs.tile.row
        }
        return lhs.tile.col < rhs.tile.col
    }

    private func deskSeatPriority(_ seat: PixelOfficeSourceSeat) -> Int {
        switch seat.facing {
        case .up:
            0
        case .right, .left:
            1
        case .down:
            2
        }
    }

    private func loungeSeatSort(lhs: PixelOfficeSourceSeat, rhs: PixelOfficeSourceSeat) -> Bool {
        if lhs.tile.row != rhs.tile.row {
            return lhs.tile.row < rhs.tile.row
        }
        return lhs.tile.col < rhs.tile.col
    }

    private func wallRenderables(
        in metrics: PixelOfficeSceneMetrics,
        layout: PixelOfficeSourceLayout
    ) -> [PixelOfficeRenderableFurniture] {
        var renderables: [PixelOfficeRenderableFurniture] = []

        for row in 0..<layout.rows {
            for col in 0..<layout.cols {
                let index = row * layout.cols + col
                guard layout.tiles[safe: index] == 0,
                      let image = PixelOfficeAssetStore.shared.wallTileImage(
                        mask: wallMask(col: col, row: row, layout: layout),
                        adjustment: layout.tileColors[safe: index] ?? nil
                      ) else {
                    continue
                }

                let spriteSize = metrics.spriteSize(pixelWidth: 16, pixelHeight: 32)
                let position = metrics.bottomAlignedSpritePosition(
                    col: col,
                    row: row,
                    pixelWidth: 16,
                    pixelHeight: 32
                )

                renderables.append(
                    PixelOfficeRenderableFurniture(
                        id: "wall-\(col)-\(row)",
                        placement: PixelFurniturePlacement(
                            id: "wall-\(col)-\(row)",
                            subpath: "generated:wall",
                            position: position,
                            size: spriteSize,
                            resolvedImage: image
                        ),
                        zIndex: Double(metrics.yOffset(forRow: row + 1))
                    )
                )
            }
        }

        return renderables
    }

    private func furnitureRenderables(
        in metrics: PixelOfficeSceneMetrics,
        layout: PixelOfficeSourceLayout
    ) -> [PixelOfficeRenderableFurniture] {
        var deskZByTile: [String: CGFloat] = [:]
        for furniture in layout.furniture {
            guard let metadata = metadataByType[furniture.type],
                  metadata.isDesk else {
                continue
            }

            let spriteHeight = metrics.spriteSize(
                pixelWidth: CGFloat(metadata.width),
                pixelHeight: CGFloat(metadata.height)
            ).height
            let deskZY = metrics.yOffset(forRow: furniture.row) + spriteHeight
            for deltaRow in 0..<metadata.footprintH {
                for deltaCol in 0..<metadata.footprintW {
                    let key = "\(furniture.col + deltaCol),\(furniture.row + deltaRow)"
                    deskZByTile[key] = max(deskZByTile[key] ?? 0, deskZY)
                }
            }
        }

        var renderables: [PixelOfficeRenderableFurniture] = []

        for furniture in layout.furniture {
            guard let metadata = metadataByType[furniture.type] else {
                continue
            }

            let size = metrics.spriteSize(
                pixelWidth: CGFloat(metadata.width),
                pixelHeight: CGFloat(metadata.height)
            )
            let position = metrics.spritePosition(
                col: furniture.col,
                row: furniture.row,
                pixelWidth: CGFloat(metadata.width),
                pixelHeight: CGFloat(metadata.height)
            )

            var zY = metrics.yOffset(forRow: furniture.row) + size.height
            if metadata.category == "chairs" {
                if metadata.orientation == "back" {
                    zY = metrics.yOffset(forRow: furniture.row + metadata.footprintH) + 1
                } else {
                    zY = metrics.yOffset(forRow: furniture.row + 1)
                }
            }

            if metadata.canPlaceOnSurfaces {
                for deltaRow in 0..<metadata.footprintH {
                    for deltaCol in 0..<metadata.footprintW {
                        let key = "\(furniture.col + deltaCol),\(furniture.row + deltaRow)"
                        if let deskZ = deskZByTile[key], deskZ + 0.5 > zY {
                            zY = deskZ + 0.5
                        }
                    }
                }
            }

            renderables.append(
                PixelOfficeRenderableFurniture(
                    id: furniture.uid,
                    placement: PixelFurniturePlacement(
                        id: furniture.uid,
                        subpath: metadata.subpath,
                        position: position,
                        size: size,
                        mirrored: metadata.mirrored
                    ),
                    zIndex: Double(zY)
                )
            )
        }

        return renderables
    }

    private func wallMask(col: Int, row: Int, layout: PixelOfficeSourceLayout) -> Int {
        var mask = 0
        if row > 0, tile(col: col, row: row - 1, layout: layout) == 0 {
            mask |= 1
        }
        if col < layout.cols - 1, tile(col: col + 1, row: row, layout: layout) == 0 {
            mask |= 2
        }
        if row < layout.rows - 1, tile(col: col, row: row + 1, layout: layout) == 0 {
            mask |= 4
        }
        if col > 0, tile(col: col - 1, row: row, layout: layout) == 0 {
            mask |= 8
        }
        return mask
    }

    private func tile(col: Int, row: Int, layout: PixelOfficeSourceLayout) -> Int {
        guard col >= 0, row >= 0, col < layout.cols, row < layout.rows else {
            return 255
        }
        return layout.tiles[(row * layout.cols) + col]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
