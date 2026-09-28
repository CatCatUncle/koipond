import AppKit
import SpriteKit

/// Shared plumbing for every scene: a pre-rendered backdrop, pointer and tap routing,
/// frame-time bookkeeping and a few cheap effects (ripples, floating text, sparkles).
class StageScene: SKScene {
    weak var state: PondState?
    private(set) var pointer: CGPoint?
    private(set) var pointerMovedAt: TimeInterval = -100
    private(set) var now: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var built = false
    private var builtSize: CGSize = .zero

    let backdrop = SKSpriteNode()
    let content = SKNode()
    /// Polled once per frame, so the fish notice the cursor even when the window isn't taking clicks.
    var pointerSource: (() -> CGPoint?)?

    init(state: PondState, size: CGSize) {
        self.state = state
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        anchorPoint = .zero
        backdrop.anchorPoint = .zero
        backdrop.zPosition = -100
        // The backdrop is opaque and drawn first, so it can overwrite instead of blending.
        backdrop.blendMode = .replace
        addChild(backdrop)
        addChild(content)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        if !built { built = true; build(); rebuildForSize() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard built, size.width > 1, size.height > 1, size != builtSize else { return }
        rebuildForSize()
    }

    private func rebuildForSize() {
        builtSize = size
        backdrop.texture = renderBackdrop()
        backdrop.size = size
        layout()
    }

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate != 0 { FrameMeter.shared.record(currentTime - lastUpdate) }
        // Clamp so a scene resumed after being hidden doesn't teleport everything.
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(1.0 / 20, max(0, currentTime - lastUpdate))
        lastUpdate = currentTime
        now += dt
        if let pointerSource {
            let p = pointerSource()
            if p != pointer { pointerMoved(to: p) }
        }
        step(dt: dt)
    }

    var pointerIsMoving: Bool { now - pointerMovedAt < 0.6 }

    // MARK: Subclass hooks

    func build() {}
    func layout() {}
    func step(dt: TimeInterval) {}
    func drawBackdrop(in ctx: CGContext, size: CGSize) {}
    func tap(at point: CGPoint) {}
    func drag(to point: CGPoint) {}
    /// Called when appearance-related state changes (day/night).
    func refresh() {}

    func pointerMoved(to point: CGPoint?) {
        if let point, let old = pointer, hypot(point.x - old.x, point.y - old.y) > 0.5 { pointerMovedAt = now }
        if pointer == nil, point != nil { pointerMovedAt = now }
        pointer = point
    }

    // MARK: Helpers

    /// Smooth gradients look identical at half resolution and cost a quarter of the memory.
    func renderBackdrop(scale: CGFloat = 0.5) -> SKTexture? {
        guard size.width > 1, size.height > 1 else { return nil }
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        drawBackdrop(in: ctx, size: size)
        guard let image = ctx.makeImage() else { return nil }
        return SKTexture(cgImage: image)
    }

    func ripple(at point: CGPoint, radius: CGFloat = 60, color: NSColor = .white, alpha: CGFloat = 0.45,
                duration: TimeInterval = 1.3, rings: Int = 2, z: CGFloat = 50) {
        for i in 0..<rings {
            let ring = SKSpriteNode(texture: Textures.ring)
            ring.size = CGSize(width: radius * 2, height: radius * 2)
            ring.position = point
            ring.color = color
            ring.colorBlendFactor = 1
            ring.alpha = 0
            ring.zPosition = z
            ring.setScale(0.12)
            content.addChild(ring)
            let grow = SKAction.scale(to: 1, duration: duration)
            grow.timingMode = .easeOut
            ring.run(.sequence([
                .wait(forDuration: Double(i) * 0.16),
                .fadeAlpha(to: alpha * (1 - CGFloat(i) * 0.25), duration: 0.03),
                .group([grow, .fadeOut(withDuration: duration)]),
                .removeFromParent()
            ]))
        }
    }

    func floatText(_ text: String, at point: CGPoint, color: NSColor = .white, size fontSize: CGFloat = 17) {
        let label = SKLabelNode(text: text)
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = fontSize
        label.fontColor = color
        label.position = point
        label.zPosition = 80
        label.alpha = 0
        content.addChild(label)
        let rise = SKAction.moveBy(x: 0, y: 46, duration: 1.1)
        rise.timingMode = .easeOut
        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), rise, .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.5)])]),
            .removeFromParent()
        ]))
    }

    func sparkle(at point: CGPoint, color: NSColor, count: Int = 14, spread: CGFloat = 90, z: CGFloat = 60) {
        for _ in 0..<count {
            let dot = SKSpriteNode(texture: Textures.glow)
            let s = CGFloat.random(in: 6...14)
            dot.size = CGSize(width: s, height: s)
            dot.color = color
            dot.colorBlendFactor = 1
            dot.blendMode = .add
            dot.position = point
            dot.zPosition = z
            content.addChild(dot)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let distance = CGFloat.random(in: spread * 0.35...spread)
            let fly = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.8)
            fly.timingMode = .easeOut
            dot.run(.sequence([.group([fly, .fadeOut(withDuration: 0.85), .scale(to: 0.3, duration: 0.85)]), .removeFromParent()]))
        }
    }

    func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

/// Tiny shared textures. Sprites sharing a texture are batched into one draw call.
enum Textures {
    static let ring: SKTexture = make(size: 128) { ctx, s in
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: 2, y: 2, width: s - 4, height: s - 4))
    }

    static let glow: SKTexture = make(size: 64) { ctx, s in
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.3, 1])!
        let c = CGPoint(x: s / 2, y: s / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
    }

    static let disc: SKTexture = make(size: 32) { ctx, s in
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: s - 2, height: s - 2))
    }

    static func make(size: CGFloat, draw: (CGContext, CGFloat) -> Void) -> SKTexture {
        let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, size)
        return SKTexture(cgImage: ctx.makeImage()!)
    }

    static func image(width: CGFloat, height: CGFloat, scale: CGFloat = 2, draw: (CGContext) -> Void) -> SKTexture {
        let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        return SKTexture(cgImage: ctx.makeImage()!)
    }
}

extension CGContext {
    func fillLinear(_ rect: CGRect, colors: [NSColor], from start: CGPoint, to end: CGPoint) {
        let cg = colors.map(\.cgColor) as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cg, locations: nil) else { return }
        saveGState()
        clip(to: rect)
        drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    func fillRadial(center: CGPoint, radius: CGFloat, colors: [NSColor], startRadius: CGFloat = 0) {
        let cg = colors.map(\.cgColor) as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cg, locations: nil) else { return }
        drawRadialGradient(gradient, startCenter: center, startRadius: startRadius, endCenter: center, endRadius: radius, options: [.drawsBeforeStartLocation])
    }
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Plays sprite-sheet frames with a very short crossfade, so pose changes read as motion rather than jump cuts.
final class FramePlayer {
    let node = SKNode()
    private let base = SKSpriteNode()
    private let top = SKSpriteNode()
    private(set) var textures: [SKTexture]
    private(set) var current = 0
    private var height: CGFloat = 400

    init(textures: [SKTexture]) {
        self.textures = textures
        // Anchored at the feet, so idle breathing and pose changes keep the character grounded.
        base.anchorPoint = CGPoint(x: 0.5, y: 0)
        top.anchorPoint = CGPoint(x: 0.5, y: 0)
        top.alpha = 0
        top.zPosition = 1
        node.addChild(base)
        node.addChild(top)
        show(0, fade: 0)
    }

    func setTextures(_ textures: [SKTexture], keep index: Int? = nil) {
        self.textures = textures
        show(index ?? current, fade: 0.25)
    }

    func setHeight(_ h: CGFloat) {
        height = h
        resize(base); resize(top)
    }

    private func resize(_ sprite: SKSpriteNode) {
        guard let t = sprite.texture else { return }
        let s = t.size()
        sprite.size = CGSize(width: height * s.width / max(1, s.height), height: height)
    }

    func show(_ index: Int, fade: TimeInterval = 0.08) {
        guard !textures.isEmpty else { return }
        let i = min(max(index, 0), textures.count - 1)
        current = i
        let texture = textures[i]
        if top.hasActions() { top.removeAllActions(); base.texture = top.texture; resize(base) }
        if fade <= 0 {
            base.texture = texture; resize(base); top.alpha = 0
            return
        }
        top.texture = texture
        resize(top)
        top.alpha = 0
        top.run(.sequence([.fadeIn(withDuration: fade), .run { [weak self] in
            guard let self else { return }
            self.base.texture = texture
            self.resize(self.base)
            self.top.alpha = 0
        }]))
    }

    /// Plays `(frame, hold)` pairs, then settles on `rest`. A new call interrupts the old one.
    func play(_ sequence: [(Int, TimeInterval)], rest: Int) {
        node.removeAction(forKey: "play")
        var actions: [SKAction] = []
        for (frame, hold) in sequence {
            actions.append(.run { [weak self] in self?.show(frame) })
            actions.append(.wait(forDuration: hold))
        }
        actions.append(.run { [weak self] in self?.show(rest, fade: 0.14) })
        node.run(.sequence(actions), withKey: "play")
    }

    var isPlaying: Bool { node.action(forKey: "play") != nil }
}
