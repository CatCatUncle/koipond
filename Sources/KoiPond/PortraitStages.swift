import AppKit
import SpriteKit

/// A scene built around one character sprite sheet: backdrop, a grounded character that
/// breathes while idle, and a tap that plays a short move.
class PortraitStage: StageScene {
    let player: FramePlayer
    let floorShadow = SKSpriteNode(texture: Textures.glow)
    private(set) var characterHeight: CGFloat = 400
    private(set) var feet: CGPoint = .zero

    init(state: PondState, size: CGSize, sheet: SpriteSheet) {
        player = FramePlayer(textures: SpriteLibrary.shared.textures(sheet))
        super.init(state: state, size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Centre and height of the character, in scene coordinates (y up).
    func characterFrame() -> (center: CGPoint, height: CGFloat) { (CGPoint(x: size.width / 2, y: size.height * 0.44), size.height * 0.74) }

    override func build() {
        floorShadow.color = .black
        floorShadow.colorBlendFactor = 1
        floorShadow.alpha = 0.32
        floorShadow.zPosition = 5
        content.addChild(floorShadow)
        player.node.zPosition = 10
        content.addChild(player.node)
        let inhale = SKAction.scaleY(to: 1.01, duration: 1.7)
        inhale.timingMode = .easeInEaseOut
        let exhale = SKAction.scaleY(to: 1, duration: 1.7)
        exhale.timingMode = .easeInEaseOut
        player.node.run(.repeatForever(.sequence([inhale, exhale])), withKey: "breathe")
    }

    override func layout() {
        let frame = characterFrame()
        characterHeight = frame.height
        feet = CGPoint(x: frame.center.x, y: frame.center.y - frame.height / 2)
        player.setHeight(frame.height)
        player.node.position = feet
        floorShadow.size = CGSize(width: frame.height * 0.5, height: frame.height * 0.07)
        floorShadow.position = CGPoint(x: feet.x, y: feet.y + frame.height * 0.035)
    }

    var characterCenter: CGPoint { CGPoint(x: feet.x, y: feet.y + characterHeight / 2) }
}

final class DanceStage: PortraitStage {
    private var orbit: [SKSpriteNode] = []
    /// The dotted line from the dancer's hand to the cursor. Loose dot sprites instead of a dashed
    /// SKShapeNode, which would re-tessellate on every mouse move.
    private var ribbon: [SKSpriteNode] = []
    private let hand = SKSpriteNode(texture: DanceStage.handTexture)

    init(state: PondState, size: CGSize) { super.init(state: state, size: size, sheet: .dancer) }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func characterFrame() -> (center: CGPoint, height: CGFloat) {
        (CGPoint(x: size.width * 0.51, y: size.height * 0.44), min(size.height * 0.75, 720))
    }

    override func build() {
        super.build()
        orbit = (0..<18).map { _ in
            let dot = SKSpriteNode(texture: Textures.glow, size: CGSize(width: 9, height: 9))
            dot.color = rgb(1, 0.84, 0.59); dot.colorBlendFactor = 1; dot.blendMode = .add
            dot.zPosition = 20
            content.addChild(dot)
            return dot
        }
        hand.zPosition = 90
        hand.isHidden = true
        content.addChild(hand)
    }

    override func drawBackdrop(in ctx: CGContext, size: CGSize) {
        ctx.fillLinear(CGRect(origin: .zero, size: size), colors: [rgb(0.17, 0.31, 0.34), rgb(0.35, 0.46, 0.41), rgb(0.12, 0.25, 0.29)],
                       from: CGPoint(x: 0, y: size.height), to: CGPoint(x: size.width, y: 0))
        let c = CGPoint(x: size.width * 0.51, y: size.height * 0.44)
        ctx.fillRadial(center: c, radius: 380, colors: [rgb(0.96, 0.75, 0.47, 0.26), rgb(0.96, 0.75, 0.47, 0)], startRadius: 15)
    }

    override func pointerMoved(to point: CGPoint?) {
        super.pointerMoved(to: point)
        guard let point else { layRibbon(dots: []); hand.isHidden = true; return }
        hand.isHidden = false
        hand.position = CGPoint(x: point.x + 2, y: point.y + 17)
        let c = characterCenter
        let start = CGPoint(x: c.x + 35, y: c.y + characterHeight * 0.2)
        let c1 = CGPoint(x: start.x + 105, y: start.y + 70), c2 = CGPoint(x: point.x - 70, y: point.y + 90)
        layRibbon(dots: Self.evenlySpaced(start, c1, c2, point, spacing: 12, limit: 240))
    }

    private func layRibbon(dots: [CGPoint]) {
        while ribbon.count < dots.count {
            let dot = SKSpriteNode(texture: Textures.disc, size: CGSize(width: 2.6, height: 2.6))
            dot.color = rgb(0.97, 0.81, 0.55)
            dot.colorBlendFactor = 1
            dot.alpha = 0.5
            dot.zPosition = 30
            content.addChild(dot)
            ribbon.append(dot)
        }
        for (i, dot) in ribbon.enumerated() {
            dot.isHidden = i >= dots.count
            if i < dots.count { dot.position = dots[i] }
        }
    }

    /// Points every `spacing` along a cubic Bézier, measured by arc length.
    private static func evenlySpaced(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, spacing: CGFloat, limit: Int) -> [CGPoint] {
        func at(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }
        var out = [p0]
        var prev = p0, travelled: CGFloat = 0, next = spacing
        for i in 1...64 {
            let p = at(CGFloat(i) / 64)
            let segment = hypot(p.x - prev.x, p.y - prev.y)
            while segment > 0, next <= travelled + segment, out.count < limit {
                let f = (next - travelled) / segment
                out.append(CGPoint(x: prev.x + (p.x - prev.x) * f, y: prev.y + (p.y - prev.y) * f))
                next += spacing
            }
            travelled += segment
            prev = p
        }
        return out
    }

    override func tap(at point: CGPoint) {
        player.play([(1, 0.3), (2, 0.3), (3, 0.32)], rest: 0)
        haptic()
        sparkle(at: characterCenter, color: rgb(1, 0.82, 0.55), count: 16, spread: characterHeight * 0.35)
        let count = state?.bump(.dance) ?? 0
        floatText("共舞 \(count) 圈", at: CGPoint(x: characterCenter.x, y: feet.y + characterHeight + 8), color: rgb(1, 0.9, 0.7))
    }

    override func step(dt: TimeInterval) {
        let c = characterCenter
        let t = now
        for (i, dot) in orbit.enumerated() {
            let a = Double(i) * 2.4 + t * 0.18
            let r = CGFloat(160 + (i % 5) * 31)
            dot.position = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r * 1.2)
            dot.alpha = CGFloat(0.48 + 0.32 * sin(t + a))
        }
    }

    private static let handTexture: SKTexture = {
        let config = NSImage.SymbolConfiguration(pointSize: 27, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [rgb(1, 0.86, 0.59), rgb(0.35, 0.24, 0.18)]))
        let image = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let size = image?.size ?? CGSize(width: 30, height: 30)
        return Textures.image(width: size.width + 8, height: size.height + 8) { ctx in
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: CGColor(gray: 0, alpha: 0.25))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            image?.draw(in: CGRect(x: 4, y: 4, width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
        }
    }()
}

final class TouchStage: PortraitStage {
    private let badge = SKShapeNode(rectOf: CGSize(width: 100, height: 37), cornerRadius: 18)
    private let badgeLabel = SKLabelNode()

    init(state: PondState, size: CGSize) { super.init(state: state, size: size, sheet: .absModel) }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func characterFrame() -> (center: CGPoint, height: CGFloat) {
        // The photo is cropped at the hips, so it bleeds off the bottom edge instead of floating.
        let height = min(size.height * 0.86, 900)
        return (CGPoint(x: size.width * 0.51, y: height / 2 - 6), height)
    }

    override func build() {
        super.build()
        floorShadow.isHidden = true
        badge.fillColor = NSColor(white: 1, alpha: 0.8)
        badge.strokeColor = .clear
        badge.zPosition = 40
        badgeLabel.fontName = "PingFangSC-Semibold"
        badgeLabel.fontSize = 12
        badgeLabel.fontColor = rgb(0.25, 0.34, 0.28)
        badgeLabel.verticalAlignmentMode = .center
        badge.addChild(badgeLabel)
        content.addChild(badge)
        updateBadge()
    }

    override func layout() {
        super.layout()
        let c = characterCenter
        badge.position = CGPoint(x: c.x + 244, y: c.y + min(characterHeight * 0.32, 262))
    }

    private func updateBadge() {
        let count = state?.counts[.touch] ?? 0
        badgeLabel.text = count == 0 ? "点一下试试" : "互动 × \(count)"
    }

    override func drawBackdrop(in ctx: CGContext, size: CGSize) {
        ctx.fillLinear(CGRect(origin: .zero, size: size), colors: [rgb(0.88, 0.81, 0.67), rgb(0.72, 0.83, 0.75), rgb(0.39, 0.62, 0.56)],
                       from: CGPoint(x: 0, y: size.height), to: CGPoint(x: size.width, y: 0))
        let c = CGPoint(x: size.width * 0.51, y: size.height * 0.47)
        ctx.fillRadial(center: c, radius: 360, colors: [NSColor(white: 1, alpha: 0.55), NSColor(white: 1, alpha: 0.02)], startRadius: 24)
    }

    override func tap(at point: CGPoint) {
        player.play([(1, 0.2), (2, 0.24), (3, 0.26), (2, 0.22)], rest: 0)
        haptic()
        ripple(at: point, radius: 110, color: rgb(1, 0.9, 0.58), alpha: 0.6, duration: 1.4, rings: 3, z: 50)
        _ = state?.bump(.touch)
        updateBadge()
        badge.removeAction(forKey: "pop")
        badge.setScale(1)
        badge.run(.sequence([.scale(to: 1.15, duration: 0.08), .scale(to: 1, duration: 0.18)]), withKey: "pop")
    }
}
