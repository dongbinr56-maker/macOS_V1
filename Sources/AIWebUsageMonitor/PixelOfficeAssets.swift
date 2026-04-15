import AppKit
import SwiftUI

@MainActor
final class PixelOfficeAssetStore {
    static let shared = PixelOfficeAssetStore()

    private let resourceRoot: URL?
    private var imageCache: [String: NSImage] = [:]
    private var frameCache: [String: NSImage] = [:]
    private var processedImageCache: [String: NSImage] = [:]

    private init() {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        resourceRoot = bundle.resourceURL?.appendingPathComponent("PixelOfficeAssets", isDirectory: true)
    }

    func image(_ subpath: String) -> NSImage? {
        if let cached = imageCache[subpath] {
            return cached
        }

        guard let url = resourceRoot?.appendingPathComponent(subpath),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        imageCache[subpath] = image
        return image
    }

    func resourceURL(for subpath: String) -> URL? {
        resourceRoot?.appendingPathComponent(subpath)
    }

    func floorTileImage(pattern: Int, adjustment: PixelOfficeSourceColorAdjustment?) -> NSImage? {
        guard pattern >= 1, pattern <= 9 else {
            return nil
        }

        let resolvedPattern = pattern == 9 ? 8 : pattern
        guard let image = image("floors/floor_\(resolvedPattern).png") else {
            return nil
        }

        guard let adjustment else {
            return image
        }

        let cacheKey = "floor-\(resolvedPattern)-\(adjustment.cacheKey)"
        return processedImage(cacheKey: cacheKey, image: image, adjustment: adjustment)
    }

    func wallTileImage(mask: Int, adjustment: PixelOfficeSourceColorAdjustment?) -> NSImage? {
        let clampedMask = max(0, min(mask, 15))
        let cacheKey = "wall-\(clampedMask)-\(adjustment?.cacheKey ?? "plain")"
        if let cached = processedImageCache[cacheKey] {
            return cached
        }

        guard let sheet = image("walls/wall_0.png"),
              let cgImage = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let tileWidth = 16
        let tileHeight = 32
        let columns = max(cgImage.width / tileWidth, 1)
        let sourceX = (clampedMask % columns) * tileWidth
        let rowIndex = clampedMask / columns
        let topOriginY = rowIndex * tileHeight
        let cropRect = CGRect(
            x: sourceX,
            y: cgImage.height - topOriginY - tileHeight,
            width: tileWidth,
            height: tileHeight
        )

        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }

        let baseImage = NSImage(cgImage: cropped, size: NSSize(width: tileWidth, height: tileHeight))
        let resolved = adjustment.map { processedImage(cacheKey: cacheKey, image: baseImage, adjustment: $0) } ?? baseImage
        if let resolved {
            processedImageCache[cacheKey] = resolved
        }
        return resolved
    }

    func wallBaseColor(adjustment: PixelOfficeSourceColorAdjustment?) -> NSColor {
        guard let adjustment else {
            return NSColor(calibratedWhite: 0.5, alpha: 1)
        }

        let transformed = Self.colorized(
            red: 0.5,
            green: 0.5,
            blue: 0.5,
            adjustment: adjustment
        )
        return NSColor(
            calibratedRed: transformed.red,
            green: transformed.green,
            blue: transformed.blue,
            alpha: 1
        )
    }

    func characterFrame(sheetIndex: Int, facing: PixelCharacterFacing, frame: Int) -> NSImage? {
        let safeSheet = ((sheetIndex % 6) + 6) % 6
        let resolvedFacing = facing.spriteSheetFacing
        let cacheKey = "\(safeSheet)-\(resolvedFacing)-\(frame)"
        if let cached = frameCache[cacheKey] {
            return cached
        }

        guard let sheet = image("characters/char_\(safeSheet).png"),
              let cgImage = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let rowIndex: Int = switch resolvedFacing {
        case .down:
            0
        case .up:
            1
        case .right, .left:
            2
        }

        let frameWidth = 16
        let frameHeight = 32
        let topOriginY = rowIndex * frameHeight
        let cropRect = CGRect(
            x: max(0, min(frame, 6)) * frameWidth,
            y: cgImage.height - topOriginY - frameHeight,
            width: frameWidth,
            height: frameHeight
        )

        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }

        let image = NSImage(cgImage: cropped, size: NSSize(width: frameWidth, height: frameHeight))
        frameCache[cacheKey] = image
        return image
    }

    private func processedImage(
        cacheKey: String,
        image: NSImage,
        adjustment: PixelOfficeSourceColorAdjustment
    ) -> NSImage? {
        if let cached = processedImageCache[cacheKey] {
            return cached
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bitmap = bitmapRep(for: cgImage) else {
            return image
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y) else {
                    continue
                }

                let alpha = color.alphaComponent
                if alpha <= 0.001 {
                    continue
                }

                let transformed = Self.colorized(
                    red: color.redComponent,
                    green: color.greenComponent,
                    blue: color.blueComponent,
                    adjustment: adjustment
                )
                bitmap.setColor(
                    NSColor(
                        calibratedRed: transformed.red,
                        green: transformed.green,
                        blue: transformed.blue,
                        alpha: alpha
                    ),
                    atX: x,
                    y: y
                )
            }
        }

        let processed = NSImage(size: NSSize(width: width, height: height))
        processed.addRepresentation(bitmap)
        processedImageCache[cacheKey] = processed
        return processed
    }

    private func bitmapRep(for image: CGImage) -> NSBitmapImageRep? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage() else {
            return nil
        }

        return NSBitmapImageRep(cgImage: rendered)
    }

    private static func colorized(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        adjustment: PixelOfficeSourceColorAdjustment
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        let contrastFactor = (100 + CGFloat(adjustment.c)) / 100
        var lightness = 0.5 + (luminance - 0.5) * contrastFactor
        lightness += CGFloat(adjustment.b) / 200
        lightness = min(max(lightness, 0), 1)

        return hslToRGB(
            hue: CGFloat(adjustment.h) / 360,
            saturation: CGFloat(adjustment.s) / 100,
            lightness: lightness
        )
    }

    private static func hslToRGB(
        hue: CGFloat,
        saturation: CGFloat,
        lightness: CGFloat
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard saturation > 0 else {
            return (lightness, lightness, lightness)
        }

        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        func hueToRGB(_ t: CGFloat) -> CGFloat {
            var value = t
            if value < 0 { value += 1 }
            if value > 1 { value -= 1 }
            if value < 1.0 / 6.0 { return p + (q - p) * 6 * value }
            if value < 0.5 { return q }
            if value < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - value) * 6 }
            return p
        }

        return (
            hueToRGB(hue + 1.0 / 3.0),
            hueToRGB(hue),
            hueToRGB(hue - 1.0 / 3.0)
        )
    }
}

struct PixelOfficeCharacterSprite: View {
    let sheetIndex: Int
    let facing: PixelCharacterFacing
    let state: PixelCharacterAnimationState
    let timestamp: TimeInterval
    let tint: Color
    let highlight: Bool

    var body: some View {
        ZStack {
            if highlight {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 44, height: 72)
            }

            if let image = PixelOfficeAssetStore.shared.characterFrame(
                sheetIndex: sheetIndex,
                facing: facing,
                frame: currentFrame
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(x: facing.isMirrored ? -1 : 1, y: 1)
                    .shadow(color: Color.black.opacity(0.18), radius: 5, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.65))
                    .frame(width: 28, height: 52)
            }
        }
    }

    private var currentFrame: Int {
        switch state {
        case .idle:
            return 1
        case .walking:
            switch Int((timestamp / 0.15).rounded(.down)).quotientAndRemainder(dividingBy: 4).remainder {
            case 0:
                return 0
            case 1:
                return 1
            case 2:
                return 2
            default:
                return 1
            }
        case .typing:
            return Int((timestamp * 3.0).rounded(.down)).quotientAndRemainder(dividingBy: 2).remainder == 0 ? 3 : 4
        case .reading:
            return Int((timestamp * 2.6).rounded(.down)).quotientAndRemainder(dividingBy: 2).remainder == 0 ? 5 : 6
        }
    }
}

struct PixelOfficeImage: View {
    let subpath: String
    let size: CGSize

    var body: some View {
        Group {
            if let image = PixelOfficeAssetStore.shared.image(subpath) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct PixelOfficeTiledImage: View {
    let subpath: String
    let size: CGSize

    var body: some View {
        PixelOfficeImage(subpath: subpath, size: size)
            .overlay(
                Rectangle()
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
    }
}
