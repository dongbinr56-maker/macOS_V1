import AppKit
import SwiftUI

@MainActor
final class PixelOfficeAssetStore {
    static let shared = PixelOfficeAssetStore()

    private let resourceRoot: URL?
    private var imageCache: [String: NSImage] = [:]
    private var frameCache: [String: NSImage] = [:]

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
