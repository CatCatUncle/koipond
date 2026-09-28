import CoreGraphics
import Foundation
import ImageIO
import SpriteKit

enum SpriteSheet: String, CaseIterable {
    case dancer = "Dancer"
    case absModel = "AbsModel"

    var grid: (columns: Int, rows: Int) { (4, 1) }
}

/// Decodes and green-screen keys the character sheets once, off the main thread, and hands out
/// GPU textures. Scenes that need a sheet before the background preload reaches it wait for it.
final class SpriteLibrary: @unchecked Sendable {
    static let shared = SpriteLibrary()

    private let lock = NSLock()
    private var cache: [SpriteSheet: [SKTexture]] = [:]
    /// One lock per sheet, so a scene waiting for its sheet never also waits for someone else's.
    private let sheetLocks = Dictionary(uniqueKeysWithValues: SpriteSheet.allCases.map { ($0, NSLock()) })

    private static let bundle: Bundle? = {
        let name = "KoiPond_KoiPond.bundle"
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name),
                          Bundle.main.bundleURL.appendingPathComponent(name),
                          Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name)]
        return candidates.compactMap { $0 }.lazy.compactMap { Bundle(url: $0) }.first
    }()

    /// Keys every sheet in the background, starting with the one the opening scene needs.
    func preloadAll(first scene: PondScene) {
        let firstSheet: SpriteSheet? = switch scene {
        case .pond: nil
        case .dance: .dancer
        case .touch: .absModel
        }
        let order = (firstSheet.map { [$0] } ?? []) + SpriteSheet.allCases.filter { $0 != firstSheet }
        DispatchQueue.global(qos: .userInitiated).async {
            for sheet in order { _ = self.textures(sheet) }
        }
    }

    func textures(_ sheet: SpriteSheet) -> [SKTexture] {
        let sheetLock = sheetLocks[sheet]!
        sheetLock.lock()
        defer { sheetLock.unlock() }
        lock.lock()
        let cached = cache[sheet]
        lock.unlock()
        if let cached { return cached }
        let textures = Self.load(sheet).map { image -> SKTexture in
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .linear
            return texture
        }
        lock.lock()
        cache[sheet] = textures
        lock.unlock()
        return textures
    }

    private static func load(_ sheet: SpriteSheet) -> [CGImage] {
        guard let url = bundle?.url(forResource: sheet.rawValue, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let keyed = removeGreen(image) else {
            NSLog("KoiPond: missing sprite sheet \(sheet.rawValue)")
            return []
        }
        let (columns, rows) = sheet.grid
        let cellWidth = keyed.width / columns, cellHeight = keyed.height / rows
        return (0..<(columns * rows)).compactMap { index in
            keyed.cropping(to: CGRect(x: (index % columns) * cellWidth, y: (index / columns) * cellHeight, width: cellWidth, height: cellHeight))
        }
    }

    /// Keys the whole sheet in one pass, and pulls leftover green spill out of hair and edges.
    private static func removeGreen(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let px = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            let other = max(r, b)
            let excess = g - other
            guard excess > 10 else { continue }
            if g > 85 && excess > 20 {
                let alpha = max(0, min(1, 1 - Float(excess - 20) / 75))
                let despilled = min(g, other + 8)
                px[i] = UInt8(Float(r) * alpha)
                px[i + 1] = UInt8(Float(despilled) * alpha)
                px[i + 2] = UInt8(Float(b) * alpha)
                px[i + 3] = UInt8(Float(px[i + 3]) * alpha)
            } else {
                px[i + 1] = UInt8(other + 10)
            }
        }
        return ctx.makeImage()
    }
}
