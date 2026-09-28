import AppKit
import SpriteKit

/// The koi pond. Fish steer with a small flocking model: they wander, keep off the edges and
/// each other, scatter from a moving cursor, drift up to a cursor that stays still, and race
/// for food and eat it.
final class PondStage: StageScene {
    private final class Fish {
        let spec: KoiSpec
        let node = SKNode()
        let body: SKSpriteNode
        let tail: SKSpriteNode
        let shadow: SKSpriteNode
        let scale: CGFloat
        let cruise: CGFloat
        let phase: CGFloat
        var pos: CGPoint
        var heading: CGFloat
        var speed: CGFloat
        var tailPhase: CGFloat = 0
        var startle: CGFloat = 0
        var fleeFrom: CGPoint = .zero

        init(spec: KoiSpec, pos: CGPoint, heading: CGFloat) {
            self.spec = spec
            self.pos = pos
            self.heading = heading
            scale = spec.scale * (spec.pattern == .custom ? 1.0 : 0.85)
            cruise = 38 * spec.speed
            speed = cruise
            phase = CGFloat.random(in: 0...(2 * .pi))
            let canvas = FishArt.bodyCanvas
            let art = PondStage.art(for: spec)
            body = SKSpriteNode(texture: art.body, size: canvas.size)
            body.anchorPoint = CGPoint(x: -canvas.minX / canvas.width, y: -canvas.minY / canvas.height)
            let tailCanvas = FishArt.tailCanvas
            tail = SKSpriteNode(texture: art.tail, size: tailCanvas.size)
            tail.anchorPoint = CGPoint(x: (FishArt.tailHinge.x - tailCanvas.minX) / tailCanvas.width, y: 0.5)
            tail.position = FishArt.tailHinge
            tail.zPosition = -0.5
            shadow = SKSpriteNode(texture: PondStage.shadowTexture, size: CGSize(width: 96, height: 48))
            node.addChild(tail)
            node.addChild(body)
            node.setScale(scale)
            shadow.setScale(scale)
        }

        var head: CGPoint { CGPoint(x: pos.x + cos(heading) * 26 * scale, y: pos.y + sin(heading) * 26 * scale) }
    }

    private final class Pellet {
        let node: SKSpriteNode
        let born: TimeInterval
        init(node: SKSpriteNode, born: TimeInterval) { self.node = node; self.born = born }
    }

    private struct Lily {
        let node: SKSpriteNode
        let radius: CGFloat
    }

    static let shadowTexture: SKTexture? = FishArt.shadowImage.map { SKTexture(cgImage: $0) }

    /// The default school only has a handful of looks, so fish share textures instead of each
    /// redrawing its own every time the pond scene is built.
    private struct ArtKey: Hashable { var body: RGBA; var mark: RGBA; var pattern: KoiPattern; var custom: UUID? }
    private static var artCache: [ArtKey: (body: SKTexture?, tail: SKTexture?)] = [:]

    private static func art(for spec: KoiSpec) -> (body: SKTexture?, tail: SKTexture?) {
        let key = ArtKey(body: spec.body, mark: spec.mark, pattern: spec.pattern, custom: spec.pattern == .custom ? spec.id : nil)
        if let cached = artCache[key] { return cached }
        let art = (body: FishArt.bodyImage(spec).map { SKTexture(cgImage: $0) }, tail: FishArt.tailImage(spec).map { SKTexture(cgImage: $0) })
        artCache[key] = art
        return art
    }

    private var fish: [Fish] = []
    private var pellets: [Pellet] = []
    private let fishLayer = SKNode()
    private let shadowLayer = SKNode()
    private var decor = SKNode()
    private var lilies: [Lily] = []
    private var shafts: [SKSpriteNode] = []
    private var glints: [SKSpriteNode] = []
    private var air: [SKNode] = []
    private var vignette = SKSpriteNode()
    private var renderedNight: Bool?
    private var nextAmbient: TimeInterval = 2
    private var lastDragRipple: TimeInterval = 0

    private var night: Bool { state?.night ?? false }

    override func build() {
        shadowLayer.zPosition = 10
        fishLayer.zPosition = 20
        content.addChild(shadowLayer)
        content.addChild(fishLayer)
        let specs = KoiSpec.defaultSchool() + (state?.customFish ?? [])
        for spec in specs { addFish(spec, at: nil) }
    }

    override func layout() {
        rebuildDecor(fade: false)
        for f in fish {
            f.pos.x = min(max(f.pos.x, 40), size.width - 40)
            f.pos.y = min(max(f.pos.y, 40), size.height - 40)
        }
    }

    override func refresh() {
        guard renderedNight != night else { return }
        let old = SKSpriteNode(texture: backdrop.texture, size: size)
        old.anchorPoint = .zero
        old.zPosition = -99
        addChild(old)
        backdrop.texture = renderBackdrop()
        old.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
        rebuildDecor(fade: true)
    }

    // MARK: Fish

    @discardableResult
    private func addFish(_ spec: KoiSpec, at point: CGPoint?) -> Fish {
        let w = max(size.width, 400), h = max(size.height, 300)
        let start = point ?? CGPoint(x: CGFloat.random(in: w * 0.12...w * 0.88), y: CGFloat.random(in: h * 0.15...h * 0.85))
        let f = Fish(spec: spec, pos: start, heading: CGFloat.random(in: -.pi ... .pi))
        f.node.position = start
        fishLayer.addChild(f.node)
        shadowLayer.addChild(f.shadow)
        fish.append(f)
        return f
    }

    /// A freshly drawn fish splashes in at the centre of the pond.
    func introduce(_ spec: KoiSpec) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        let f = addFish(spec, at: center)
        f.speed = f.cruise * 2.5
        // The pond keeps the same number of drawn fish as the saved list; the oldest swims off.
        let drawn = fish.filter { $0.spec.pattern == .custom }
        for old in drawn.prefix(max(0, drawn.count - PondState.maxCustomFish)) {
            old.node.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
            old.shadow.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
            fish.removeAll { $0 === old }
        }
        let final = f.scale
        f.node.setScale(0.01)
        let pop = SKAction.scale(to: final, duration: 0.45)
        pop.timingMode = .easeOut
        f.node.run(pop)
        ripple(at: center, radius: 110, alpha: 0.6, duration: 1.6, rings: 3)
        sparkle(at: center, color: rgb(1, 0.86, 0.55), count: 18, spread: 120)
        floatText("新锦鲤入池", at: CGPoint(x: center.x, y: center.y + 40), color: rgb(1, 0.95, 0.82))
    }

    func releaseCustomFish() {
        for f in fish where f.spec.pattern == .custom {
            ripple(at: f.pos, radius: 40, alpha: 0.4, duration: 0.9, rings: 1)
            f.node.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
            f.shadow.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
        }
        fish.removeAll { $0.spec.pattern == .custom }
    }

    // MARK: Input

    override func tap(at point: CGPoint) {
        if let lily = lilies.first(where: { hypot($0.node.position.x - point.x, ($0.node.position.y - point.y) * 1.4) < $0.radius }) {
            lily.node.run(.sequence([.scale(to: 0.9, duration: 0.08), .scale(to: 1.05, duration: 0.16), .scale(to: 1, duration: 0.2)]))
            ripple(at: lily.node.position, radius: lily.radius * 1.8, alpha: 0.35, duration: 1.2, rings: 2)
            return
        }
        let hit = fish.contains { hypot($0.pos.x - point.x, $0.pos.y - point.y) < 30 * $0.scale }
        if hit {
            // Poking a fish startles it and its neighbours instead of dropping food.
            for f in fish {
                let d = hypot(f.pos.x - point.x, f.pos.y - point.y)
                if d < 200 { f.startle = max(f.startle, 1 - d / 240); f.fleeFrom = point }
            }
            ripple(at: point, radius: 90, alpha: 0.55, duration: 1.1, rings: 3)
            return
        }
        feed(at: point)
    }

    override func drag(to point: CGPoint) {
        guard now - lastDragRipple > 0.07 else { return }
        lastDragRipple = now
        ripple(at: point, radius: 28, alpha: 0.28, duration: 0.9, rings: 1)
    }

    private func feed(at point: CGPoint) {
        ripple(at: point, radius: 70, alpha: 0.5, duration: 1.5, rings: 3)
        for _ in 0..<4 {
            let pellet = SKSpriteNode(texture: Textures.glow, size: CGSize(width: 13, height: 13))
            pellet.color = rgb(0.98, 0.78, 0.36)
            pellet.colorBlendFactor = 1
            pellet.position = point
            pellet.zPosition = 30
            content.addChild(pellet)
            let angle = CGFloat.random(in: 0..<(2 * .pi)), distance = CGFloat.random(in: 6...26)
            let scatter = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.35)
            scatter.timingMode = .easeOut
            pellet.run(scatter)
            pellets.append(Pellet(node: pellet, born: now))
        }
        if pellets.count > 28 {
            for old in pellets.prefix(pellets.count - 28) { old.node.removeFromParent() }
            pellets.removeFirst(pellets.count - 28)
        }
    }

    private func eat(_ pellet: Pellet, by f: Fish) {
        pellets.removeAll { $0 === pellet }
        pellet.node.run(.sequence([.group([.scale(to: 0.1, duration: 0.12), .fadeOut(withDuration: 0.12)]), .removeFromParent()]))
        ripple(at: pellet.node.position, radius: 18, alpha: 0.35, duration: 0.6, rings: 1)
        f.tailPhase += 1.4
    }

    // MARK: Simulation

    override func step(dt: TimeInterval) {
        let dt = CGFloat(dt)
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }

        // Stale food fades and dissolves.
        pellets.removeAll { pellet in
            let age = now - pellet.born
            if age > 16 { pellet.node.removeFromParent(); return true }
            if age > 14 { pellet.node.alpha = CGFloat((16 - age) / 2) }
            return false
        }

        let pointer = self.pointer
        let moving = pointerIsMoving
        let stillFor = now - pointerMovedAt
        let margin: CGFloat = 110

        for f in fish {
            var sx = cos(f.heading), sy = sin(f.heading)
            // Wander: slow, fish-specific curves.
            let t = CGFloat(now)
            let wander = sin(t * 0.21 + f.phase) * 0.8 + sin(t * 0.57 + f.phase * 1.7) * 0.35
            sx += cos(f.heading + wander) * 0.8
            sy += sin(f.heading + wander) * 0.8
            var target = f.cruise
            var urgency: CGFloat = 0

            // Soft walls.
            if f.pos.x < margin { sx += (margin - f.pos.x) / margin * 2.5 }
            if f.pos.x > w - margin { sx -= (f.pos.x - (w - margin)) / margin * 2.5 }
            if f.pos.y < margin { sy += (margin - f.pos.y) / margin * 2.5 }
            if f.pos.y > h - margin { sy -= (f.pos.y - (h - margin)) / margin * 2.5 }

            // Food.
            var nearest: Pellet?
            var nearestDistance: CGFloat = 560
            let head = f.head
            for pellet in pellets {
                let d = hypot(pellet.node.position.x - head.x, pellet.node.position.y - head.y)
                if d < nearestDistance { nearestDistance = d; nearest = pellet }
            }
            if let pellet = nearest {
                if nearestDistance < 9 + 6 * f.scale {
                    eat(pellet, by: f)
                } else {
                    let dx = pellet.node.position.x - head.x, dy = pellet.node.position.y - head.y
                    sx += dx / nearestDistance * 3
                    sy += dy / nearestDistance * 3
                    target = f.cruise * (nearestDistance < 60 ? 1.3 : 2.2)
                    urgency = max(urgency, 0.6)
                }
            }

            // Cursor: a moving cursor scares fish off, a resting one draws them in.
            if let p = pointer {
                let dx = f.pos.x - p.x, dy = f.pos.y - p.y
                let d = max(1, hypot(dx, dy))
                if moving && d < 160 {
                    let k = 1 - d / 160
                    sx += dx / d * k * 5
                    sy += dy / d * k * 5
                    target = max(target, f.cruise * (1 + 3 * k))
                    urgency = max(urgency, k)
                } else if !moving && stillFor > 2.5 && d < 420 && nearest == nil {
                    let pull: CGFloat = d > 70 ? -(1 - d / 420) * 1.6 : (70 - d) / 70 * 1.2
                    sx += dx / d * pull
                    sy += dy / d * pull
                    target = f.cruise * (d > 90 ? 0.9 : 0.45)
                }
            }

            if f.startle > 0 {
                let dx = f.pos.x - f.fleeFrom.x, dy = f.pos.y - f.fleeFrom.y
                let d = max(1, hypot(dx, dy))
                sx += dx / d * 7 * f.startle
                sy += dy / d * 7 * f.startle
                target = max(target, f.cruise * (1 + 4 * f.startle))
                urgency = max(urgency, f.startle)
                f.startle = max(0, f.startle - dt * 0.9)
            }

            // Personal space.
            for other in fish where other !== f {
                let dx = f.pos.x - other.pos.x, dy = f.pos.y - other.pos.y
                let reach = 34 * (f.scale + other.scale)
                if abs(dx) < reach && abs(dy) < reach {
                    let d = max(1, hypot(dx, dy))
                    if d < reach { sx += dx / d * (1 - d / reach) * 1.4; sy += dy / d * (1 - d / reach) * 1.4 }
                }
            }

            let desired = atan2(sy, sx)
            var diff = desired - f.heading
            while diff > .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            let maxTurn = (1.5 + 5 * urgency) * dt
            f.heading += min(max(diff, -maxTurn), maxTurn)
            let rate: CGFloat = target > f.speed ? 3.5 : 1.1
            f.speed += (target - f.speed) * min(1, dt * rate)
            f.pos.x = min(max(f.pos.x + cos(f.heading) * f.speed * dt, -50), w + 50)
            f.pos.y = min(max(f.pos.y + sin(f.heading) * f.speed * dt, -50), h + 50)

            f.tailPhase += dt * (5 + f.speed * 0.1)
            let swing = 0.26 + min(0.3, max(0, f.speed / f.cruise - 1) * 0.12)
            f.tail.zRotation = sin(f.tailPhase) * swing
            f.node.position = f.pos
            f.node.zRotation = f.heading + sin(f.tailPhase + 1.3) * swing * 0.14
            f.shadow.position = CGPoint(x: f.pos.x + 6 * f.scale, y: f.pos.y - 10 * f.scale)
            f.shadow.zRotation = f.heading
        }

        // Now and then a fish nudges the surface.
        if now > nextAmbient, let f = fish.randomElement() {
            nextAmbient = now + Double.random(in: 2.5...5.5)
            ripple(at: f.head, radius: 24, alpha: 0.22, duration: 1.1, rings: 1, z: 25)
        }

        animateDecor()
    }

    // MARK: Scenery

    override func drawBackdrop(in ctx: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let colors = night
            ? [rgb(0.06, 0.24, 0.22), rgb(0.055, 0.20, 0.19), rgb(0.08, 0.29, 0.27)]
            : [rgb(0.53, 0.78, 0.66), rgb(0.37, 0.70, 0.61), rgb(0.27, 0.59, 0.55)]
        ctx.fillLinear(rect, colors: colors, from: CGPoint(x: 0, y: size.height), to: CGPoint(x: size.width, y: 0))

        // Deeper water patches and a scatter of pebbles on the bottom.
        var rng = SeededRandom(seed: 7)
        for _ in 0..<5 {
            let c = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
            ctx.fillRadial(center: c, radius: 180 + rng.next() * 220, colors: [rgb(0, 0.1, 0.1, night ? 0.16 : 0.1), rgb(0, 0.1, 0.1, 0)])
        }
        for _ in 0..<90 {
            let c = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
            let r = 2 + rng.next() * 7
            ctx.setFillColor(CGColor(gray: rng.next() > 0.5 ? 1 : 0, alpha: night ? 0.03 : 0.045))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
        }

        if night {
            // The Mid-Autumn full moon reflected in the pond.
            let moon = Self.moonCenter(in: size)
            ctx.fillRadial(center: moon, radius: 150, colors: [rgb(0.98, 0.89, 0.62, 0.22), rgb(0.98, 0.89, 0.62, 0)])
            ctx.setFillColor(rgb(0.99, 0.93, 0.74, 0.93).cgColor)
            ctx.fillEllipse(in: CGRect(x: moon.x - 27, y: moon.y - 27, width: 54, height: 54))
            ctx.setFillColor(rgb(0.93, 0.84, 0.6, 0.35).cgColor)
            ctx.fillEllipse(in: CGRect(x: moon.x - 12, y: moon.y + 2, width: 14, height: 10))
            ctx.fillEllipse(in: CGRect(x: moon.x + 5, y: moon.y - 13, width: 9, height: 7))
        }
    }

    static func moonCenter(in size: CGSize) -> CGPoint { CGPoint(x: size.width * 0.79 + 33, y: size.height * 0.89 - 33) }

    private func rebuildDecor(fade: Bool) {
        renderedNight = night
        let old = decor
        decor = SKNode()
        content.addChild(decor)
        if fade {
            decor.alpha = 0
            decor.run(.fadeIn(withDuration: 0.6))
            old.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
        } else {
            old.removeFromParent()
        }
        let w = size.width, h = size.height

        // Light shafts.
        shafts = (0..<6).map { i in
            let shaft = SKSpriteNode(texture: Self.shaftTexture, size: CGSize(width: 150 + CGFloat(i % 3) * 50, height: h * 1.35))
            shaft.alpha = night ? 0.3 : 0.9
            shaft.blendMode = .add
            shaft.zPosition = 1
            shaft.zRotation = -0.3
            shaft.position = CGPoint(x: (CGFloat(i) + 0.3) / 5.6 * w, y: h / 2)
            shaft.userData = ["x": (CGFloat(i) + 0.3) / 5.6 * w]
            decor.addChild(shaft)
            return shaft
        }

        // Drifting glints on the surface.
        glints = (0..<18).map { i in
            let r = CGFloat(3 + i % 8)
            let glint = SKSpriteNode(texture: Textures.glow, size: CGSize(width: r * 3.2, height: r * 1.0))
            glint.alpha = night ? 0.07 : 0.14
            glint.zPosition = 2
            decor.addChild(glint)
            return glint
        }

        // Lily pads float on top of the fish.
        let count = max(4, Int(w / 330))
        lilies = (0..<count).map { i in
            let r = CGFloat(28 + i % 4 * 7)
            let x = CGFloat((i * 227 + 60) % 997) / 997 * w + r
            let y = h - CGFloat((i * 359 + 40) % 997) / 997 * h - r * 0.71
            let pad = SKSpriteNode(texture: lilyTexture(radius: r, flower: i % 3 == 0))
            var p = CGPoint(x: min(max(x, r), w - r), y: min(max(y, r), h - r))
            // Keep the moon's reflection clear, day and night, so pads don't jump when it turns.
            let moon = Self.moonCenter(in: size)
            let dx = p.x - moon.x, dy = p.y - moon.y, d = max(1, hypot(dx, dy)), keep = 120 + r
            if d < keep { p = CGPoint(x: p.x + dx / d * (keep - d), y: p.y + dy / d * (keep - d)) }
            pad.position = CGPoint(x: min(max(p.x, r), w - r), y: min(max(p.y, r), h - r))
            pad.zPosition = 40
            let sway = SKAction.sequence([.rotate(byAngle: 0.05, duration: 3.5 + Double(i) * 0.4), .rotate(byAngle: -0.05, duration: 3.5 + Double(i) * 0.4)])
            sway.timingMode = .easeInEaseOut
            pad.run(.repeatForever(sway))
            decor.addChild(pad)
            return Lily(node: pad, radius: r)
        }

        // Fireflies at night; by day, osmanthus blossoms drifting on the water.
        air = (0..<(night ? 8 : 14)).map { i in
            let node = SKNode()
            node.zPosition = 60
            if night {
                let halo = SKSpriteNode(texture: Textures.glow, size: CGSize(width: 26, height: 26))
                halo.color = rgb(0.71, 0.91, 0.53); halo.colorBlendFactor = 1; halo.alpha = 0.35; halo.blendMode = .add
                let core = SKSpriteNode(texture: Textures.glow, size: CGSize(width: 7, height: 7))
                core.color = rgb(0.85, 0.98, 0.66); core.colorBlendFactor = 1
                node.addChild(halo); node.addChild(core)
            } else {
                let s = CGFloat(12 + i % 4 * 2)
                let blossom = SKSpriteNode(texture: Self.blossomTexture, size: CGSize(width: s, height: s))
                blossom.alpha = 0.92
                node.addChild(blossom)
                node.zPosition = 45
            }
            decor.addChild(node)
            return node
        }

        vignette = SKSpriteNode(texture: vignetteTexture(), size: size)
        vignette.anchorPoint = .zero
        vignette.zPosition = 90
        decor.addChild(vignette)
        animateDecor()
    }

    private func animateDecor() {
        let t = now, w = size.width, h = size.height
        for (i, shaft) in shafts.enumerated() {
            let base = shaft.userData?["x"] as? CGFloat ?? 0
            shaft.position.x = base + CGFloat(sin(t * 0.07 + Double(i))) * 28
        }
        for (i, glint) in glints.enumerated() {
            let x = CGFloat((i * 173 + 41) % 997) / 997 * w
            let y = h - CGFloat((i * 313 + 89) % 991) / 991 * h
            glint.position = CGPoint(x: x + CGFloat(sin(t * 0.12 + Double(i))) * 11, y: y - CGFloat(cos(t * 0.09 + Double(i))) * 7)
        }
        for (i, node) in air.enumerated() {
            let seed = Double(i) * 2.21
            let speed = night ? 1.0 : 0.25
            let x = CGFloat((i * 139 + 35) % 991) / 991 * w + CGFloat(sin(t * 0.45 * speed + seed) * 34)
            let y = h - CGFloat((i * 247 + 130) % 993) / 993 * h - CGFloat(cos(t * 0.31 * speed + seed) * 25)
            node.position = CGPoint(x: x, y: y)
            if night {
                node.alpha = CGFloat(0.4 + (sin(t * 2.3 + seed) + 1) * 0.3)
            } else {
                node.zRotation = CGFloat(t * 0.15 + seed)
            }
        }
    }

    private static let shaftTexture = Textures.image(width: 64, height: 64, scale: 1) { ctx in
        // Soft on both sides and fading out towards the ends.
        ctx.fillLinear(CGRect(x: 0, y: 0, width: 64, height: 64),
                       colors: [NSColor(white: 1, alpha: 0), NSColor(white: 1, alpha: 0.06), NSColor(white: 1, alpha: 0)],
                       from: CGPoint(x: 0, y: 32), to: CGPoint(x: 64, y: 32))
        ctx.setBlendMode(.destinationIn)
        ctx.fillLinear(CGRect(x: 0, y: 0, width: 64, height: 64),
                       colors: [NSColor(white: 1, alpha: 0.2), NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 0.35)],
                       from: CGPoint(x: 32, y: 0), to: CGPoint(x: 32, y: 64))
    }

    /// A four-petal osmanthus flower.
    private static let blossomTexture = Textures.image(width: 16, height: 16, scale: 3) { ctx in
        ctx.setShadow(offset: CGSize(width: 0.6, height: -0.8), blur: 1.2, color: CGColor(gray: 0, alpha: 0.25))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for k in 0..<4 {
            ctx.saveGState()
            ctx.translateBy(x: 8, y: 8)
            ctx.rotate(by: CGFloat(k) * .pi / 2 + 0.3)
            ctx.setFillColor(rgb(0.99, 0.78, 0.32).cgColor)
            ctx.fillEllipse(in: CGRect(x: -2.4, y: 0.4, width: 4.8, height: 6.2))
            ctx.restoreGState()
        }
        ctx.setFillColor(rgb(0.93, 0.56, 0.16).cgColor)
        ctx.fillEllipse(in: CGRect(x: 6.6, y: 6.6, width: 2.8, height: 2.8))
        ctx.endTransparencyLayer()
    }

    private func lilyTexture(radius r: CGFloat, flower: Bool) -> SKTexture {
        let w = r * 2 + 20, h = r * 1.42 + 20
        let n = night
        return Textures.image(width: w, height: h) { ctx in
            let pad = CGRect(x: 10, y: 10, width: r * 2, height: r * 1.42)
            // Soft shadow on the water under the pad.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 3, height: -4), blur: 8, color: CGColor(gray: 0, alpha: 0.28))
            let green = n ? rgb(0.1, 0.32, 0.24) : rgb(0.12, 0.37, 0.27)
            ctx.setFillColor(green.cgColor)
            ctx.fillEllipse(in: pad)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: pad); ctx.clip()
            ctx.fillRadial(center: CGPoint(x: pad.midX - r * 0.2, y: pad.midY + r * 0.15), radius: r * 1.4,
                           colors: [green.blended(withFraction: 0.25, of: .white) ?? green, green])
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.12)); ctx.setLineWidth(0.8)
            for k in 0..<7 {
                let a = CGFloat(k) / 7 * 2 * .pi + 0.4
                ctx.move(to: CGPoint(x: pad.midX, y: pad.midY))
                ctx.addLine(to: CGPoint(x: pad.midX + cos(a) * r, y: pad.midY + sin(a) * r * 0.71))
            }
            ctx.strokePath()
            ctx.restoreGState()
            // The notch that makes it a lily pad.
            ctx.setBlendMode(.clear)
            ctx.move(to: CGPoint(x: pad.midX, y: pad.midY))
            ctx.addLine(to: CGPoint(x: pad.midX + r * 1.1, y: pad.midY + r * 0.13))
            ctx.addLine(to: CGPoint(x: pad.midX + r * 1.1, y: pad.midY - r * 0.02))
            ctx.closePath(); ctx.fillPath()
            ctx.setBlendMode(.normal)
            if flower {
                let c = CGPoint(x: pad.midX - r * 0.3, y: pad.midY + r * 0.05)
                for petal in 0..<8 {
                    let a = CGFloat(petal) * .pi / 4
                    ctx.saveGState()
                    ctx.translateBy(x: c.x + cos(a) * 6, y: c.y + sin(a) * 6)
                    ctx.rotate(by: a + .pi / 2)
                    ctx.setFillColor(rgb(0.98, 0.82, 0.62, n ? 0.85 : 0.97).cgColor)
                    ctx.fillEllipse(in: CGRect(x: -3.5, y: -6, width: 7, height: 12))
                    ctx.restoreGState()
                }
                ctx.setFillColor(rgb(0.94, 0.72, 0.28).cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
            }
        }
    }

    private func vignetteTexture() -> SKTexture {
        let w = size.width, h = size.height, n = night
        return Textures.image(width: w, height: h, scale: 0.25) { ctx in
            ctx.fillRadial(center: CGPoint(x: w / 2, y: h / 2), radius: hypot(w, h) * 0.65,
                           colors: [rgb(0, 0, 0, 0), rgb(0, 0, 0, n ? 0.2 : 0.13)], startRadius: min(w, h) * 0.24)
        }
    }
}

/// Deterministic scenery so the pond looks the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 1_000_000) / 1_000_000
    }
}
