import CoreGraphics
import Foundation

/// What a `koipond://` link asks the running pond to do. Scripts, Shortcuts and AI agents drive
/// the pond through these, e.g. `open -g "koipond://feed?x=0.5&y=0.5"`.
enum PondCommand: Equatable {
    case scene(PondScene)
    case night(Bool?)               // nil toggles
    case interactive(Bool)
    case feed(CGPoint)              // 0...1, y pointing down
    case caption(title: String, detail: String, seconds: TimeInterval)
    case addFish(KoiSpec)
    case releaseFish
    case snapshot(path: String)

    /// Nil for anything malformed; `error` says why, so a caller can print it.
    static func parse(_ url: URL) -> (command: PondCommand?, error: String?) {
        guard url.scheme?.lowercased() == "koipond", let host = url.host?.lowercased() else {
            return (nil, "不是 koipond:// 链接")
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }
        func number(_ key: String) -> Double? { query[key].flatMap(Double.init) }
        func flag(_ key: String) -> Bool? {
            switch query[key]?.lowercased() {
            case "1", "true", "on", "yes": true
            case "0", "false", "off", "no": false
            default: nil
            }
        }

        switch host {
        case "scene":
            let key = (parts.first ?? query["name"] ?? "").lowercased()
            guard let scene = PondScene.allCases.first(where: { $0.key == key || $0.rawValue == key }) else {
                return (nil, "没有这个场景：\(key)。可选 \(PondScene.allCases.map(\.key).joined(separator: " / "))")
            }
            return (.scene(scene), nil)
        case "night":
            return (.night(flag("on")), nil)
        case "day":
            return (.night(false), nil)
        case "mode":
            guard let on = flag("interactive") else { return (nil, "mode 需要 interactive=1 或 0") }
            return (.interactive(on), nil)
        case "feed":
            let x = min(max(number("x") ?? 0.5, 0), 1), y = min(max(number("y") ?? 0.5, 0), 1)
            return (.feed(CGPoint(x: x, y: y)), nil)
        case "caption":
            let title = query["title"] ?? ""
            let detail = query["text"] ?? ""
            guard !(title.isEmpty && detail.isEmpty) else { return (nil, "caption 需要 title 或 text") }
            return (.caption(title: String(title.prefix(40)), detail: String(detail.prefix(120)),
                             seconds: min(max(number("seconds") ?? 4, 1), 30)), nil)
        case "fish":
            if parts.first == "release" { return (.releaseFish, nil) }
            return parseFish(query)
        case "snapshot":
            guard let path = query["path"], path.hasPrefix("/"), path.lowercased().hasSuffix(".png") else {
                return (nil, "snapshot 需要 path=/绝对路径.png")
            }
            return (.snapshot(path: path), nil)
        default:
            return (nil, "不认识的指令：\(host)")
        }
    }

    private static func parseFish(_ query: [String: String]) -> (command: PondCommand?, error: String?) {
        let patterns: [String: KoiPattern] = ["kohaku": .kohaku, "tancho": .tancho, "showa": .showa, "ogon": .ogon, "custom": .custom]
        var strokes: [InkStroke] = []
        if let raw = query["strokes"], !raw.isEmpty {
            guard let data = raw.data(using: .utf8), let decoded = try? JSONDecoder().decode([StrokeInput].self, from: data) else {
                return (nil, "strokes 不是合法 JSON，格式见 skills/koipond-fish-designer/SKILL.md")
            }
            for input in decoded.prefix(64) {
                let points = input.points.prefix(400).compactMap { p -> CGPoint? in
                    p.count == 2 ? CGPoint(x: min(max(p[0], 0), 1), y: min(max(p[1], 0), 1)) : nil
                }
                guard points.count >= 2 else { continue }
                strokes.append(InkStroke(points: points, color: input.color.flatMap(RGBA.init(hex:)) ?? Palette.vermilion,
                                         width: CGFloat(min(max(input.width ?? 0.09, 0.02), 0.3))))
            }
        }
        let pattern = query["pattern"].flatMap { patterns[$0.lowercased()] } ?? (strokes.isEmpty ? .kohaku : .custom)
        guard let body = RGBA(hex: query["body"] ?? "#F5E8C7") else { return (nil, "body 颜色要写成 #RRGGBB") }
        guard let mark = RGBA(hex: query["mark"] ?? "#D4452A") else { return (nil, "mark 颜色要写成 #RRGGBB") }
        let scale = CGFloat(min(max(Double(query["scale"] ?? "") ?? 1, 0.6), 1.6))
        let speed = CGFloat(min(max(Double(query["speed"] ?? "") ?? 0.95, 0.4), 1.6))
        return (.addFish(KoiSpec(body: body, mark: mark, scale: scale, speed: speed, pattern: pattern, strokes: strokes)), nil)
    }

    private struct StrokeInput: Decodable {
        var points: [[Double]]
        var color: String?
        var width: Double?
    }
}

extension RGBA {
    /// `#RRGGBB`, `RRGGBB` or `#RGB`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }
}
