import SwiftUI
import CoreGraphics

enum PondScene: String, CaseIterable, Identifiable, Codable {
    case pond = "月下鱼塘"
    case dance = "牵手共舞"
    case touch = "腹肌挑战"

    var id: String { rawValue }

    /// Short English key used by the debug environment variable `KOI_SCENE`.
    var key: String {
        switch self {
        case .pond: "pond"
        case .dance: "dance"
        case .touch: "touch"
        }
    }
}

struct RGBA: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    func alpha(_ value: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: value) }
}

enum Palette {
    static let cream = RGBA(r: 0.98, g: 0.91, b: 0.73)
    static let silver = RGBA(r: 0.95, g: 0.92, b: 0.83)
    static let gold = RGBA(r: 0.94, g: 0.68, b: 0.28)
    static let pearl = RGBA(r: 0.91, g: 0.91, b: 0.82)
    static let vermilion = RGBA(r: 0.83, g: 0.27, b: 0.16)
    static let ink = RGBA(r: 0.18, g: 0.24, b: 0.23)
    static let rust = RGBA(r: 0.79, g: 0.37, b: 0.16)

    static let editorBodies: [RGBA] = [RGBA(r: 0.96, g: 0.91, b: 0.78), RGBA(r: 0.96, g: 0.58, b: 0.30), RGBA(r: 0.91, g: 0.91, b: 0.83), RGBA(r: 0.23, g: 0.40, b: 0.39)]
    static let editorInks: [RGBA] = [vermilion, ink, gold, RGBA(r: 0.96, g: 0.92, b: 0.79)]
}

struct InkStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Points normalised to the fish body's bounding box (0...1, y pointing down), so the
    /// drawing lands on the swimming fish exactly where it was painted in the editor.
    var points: [CGPoint]
    var color: RGBA
    /// Line width relative to the body's height.
    var width: CGFloat
}

enum KoiPattern: Int, Codable {
    case kohaku, tancho, showa, ogon, custom
}

struct KoiSpec: Codable, Identifiable, Equatable {
    var id = UUID()
    var body: RGBA
    var mark: RGBA
    var scale: CGFloat
    var speed: CGFloat
    var pattern: KoiPattern
    var strokes: [InkStroke] = []

    static func defaultSchool() -> [KoiSpec] {
        let looks: [(RGBA, RGBA, KoiPattern)] = [
            (Palette.cream, Palette.vermilion, .kohaku),
            (Palette.silver, Palette.ink, .showa),
            (Palette.gold, Palette.rust, .ogon),
            (Palette.pearl, Palette.vermilion, .tancho)
        ]
        return (0..<16).map { i in
            let look = looks[i % looks.count]
            return KoiSpec(body: look.0, mark: look.1,
                           scale: 0.9 + CGFloat(i % 6) * 0.07,
                           speed: 0.8 + CGFloat(i % 7) * 0.07,
                           pattern: look.2)
        }
    }
}
