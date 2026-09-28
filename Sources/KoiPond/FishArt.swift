import CoreGraphics
import Foundation

/// Bakes each koi into small bitmaps once, so the pond only moves textures around every frame
/// instead of re-drawing paths. Units are points of a fish at scale 1, head pointing to +x, y up.
enum FishArt {
    static let bodyBox = CGRect(x: -34, y: -15.5, width: 66, height: 31)
    static let bodyCanvas = CGRect(x: -40, y: -27, width: 80, height: 54)
    /// The tail sprite hinges here and is drawn under the body, so wagging never opens a gap.
    static let tailHinge = CGPoint(x: -30, y: 0)
    static let tailCanvas = CGRect(x: -62, y: -20, width: 34, height: 40)
    static let pixelsPerUnit: CGFloat = 3

    static let bodyPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 32, y: 0))
        p.addCurve(to: CGPoint(x: 4, y: 15.5), control1: CGPoint(x: 32, y: 9), control2: CGPoint(x: 20, y: 15.5))
        p.addCurve(to: CGPoint(x: -34, y: 3.5), control1: CGPoint(x: -14, y: 15.5), control2: CGPoint(x: -28, y: 9))
        p.addLine(to: CGPoint(x: -34, y: -3.5))
        p.addCurve(to: CGPoint(x: 4, y: -15.5), control1: CGPoint(x: -28, y: -9), control2: CGPoint(x: -14, y: -15.5))
        p.addCurve(to: CGPoint(x: 32, y: 0), control1: CGPoint(x: 20, y: -15.5), control2: CGPoint(x: 32, y: -9))
        p.closeSubpath()
        return p
    }()

    static let tailPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -28, y: 3))
        p.addCurve(to: CGPoint(x: -59, y: 16), control1: CGPoint(x: -40, y: 5), control2: CGPoint(x: -50, y: 14))
        p.addQuadCurve(to: CGPoint(x: -51, y: 0), control: CGPoint(x: -59, y: 6))
        p.addQuadCurve(to: CGPoint(x: -59, y: -16), control: CGPoint(x: -59, y: -6))
        p.addCurve(to: CGPoint(x: -28, y: -3), control1: CGPoint(x: -50, y: -14), control2: CGPoint(x: -40, y: -5))
        p.closeSubpath()
        return p
    }()

    static func render(_ canvas: CGRect, ppu: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        let w = Int((canvas.width * ppu).rounded(.up)), h = Int((canvas.height * ppu).rounded(.up))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: ppu, y: ppu)
        ctx.translateBy(x: -canvas.minX, y: -canvas.minY)
        draw(ctx)
        return ctx.makeImage()
    }

    static func bodyImage(_ spec: KoiSpec) -> CGImage? {
        render(bodyCanvas, ppu: pixelsPerUnit) { ctx in drawBody(spec, in: ctx) }
    }

    static func tailImage(_ spec: KoiSpec) -> CGImage? {
        render(tailCanvas, ppu: pixelsPerUnit) { ctx in
            ctx.addPath(tailPath)
            ctx.setFillColor(spec.body.alpha(0.82).cgColor)
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(tailPath); ctx.clip()
            // Fin rays and a darker trailing edge make the tail read as translucent fin.
            ctx.setStrokeColor(spec.mark.alpha(0.16).cgColor)
            ctx.setLineWidth(0.7)
            for i in -4...4 {
                ctx.move(to: CGPoint(x: -29, y: 0))
                ctx.addLine(to: CGPoint(x: -60, y: CGFloat(i) * 4.4))
            }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(tailPath)
            ctx.setStrokeColor(spec.mark.alpha(0.18).cgColor)
            ctx.setLineWidth(0.6)
            ctx.strokePath()
        }
    }

    /// A soft dark blob that sits a few points below each fish to give the water depth.
    static let shadowImage: CGImage? = render(CGRect(x: -48, y: -24, width: 96, height: 48), ppu: 1) { ctx in
        let colors = [CGColor(gray: 0, alpha: 0.55), CGColor(gray: 0, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return }
        ctx.scaleBy(x: 1, y: 0.42)
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 46, options: [])
    }

    static func drawBody(_ spec: KoiSpec, in ctx: CGContext) {
        // Pectoral fins sit under the body and sweep back.
        for side: CGFloat in [-1, 1] {
            ctx.saveGState()
            ctx.translateBy(x: 9, y: side * 13)
            ctx.rotate(by: side * -0.55)
            let fin = CGRect(x: -12, y: -4.5 + side * 4.5, width: 16, height: 9)
            ctx.setFillColor(spec.body.alpha(0.62).cgColor)
            ctx.fillEllipse(in: fin)
            ctx.setStrokeColor(spec.mark.alpha(0.14).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: fin)
            ctx.restoreGState()
        }

        ctx.addPath(bodyPath)
        ctx.setFillColor(spec.body.cgColor)
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(bodyPath); ctx.clip()
        drawPattern(spec, in: ctx)

        // Faint scale texture.
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.055))
        ctx.setLineWidth(0.45)
        var row = 0
        for y in stride(from: -14.0, through: 14.0, by: 3.6) {
            let offset = row % 2 == 0 ? 0 : 1.8
            for x in stride(from: -28.0 + offset, through: 16.0, by: 3.6) {
                ctx.move(to: CGPoint(x: x, y: y - 2.2))
                ctx.addArc(center: CGPoint(x: x, y: y), radius: 2.2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            }
            row += 1
        }
        ctx.strokePath()

        // Top-down light: bright along the spine, darker at the flanks.
        let shade = [CGColor(gray: 0, alpha: 0.2), CGColor(gray: 1, alpha: spec.pattern == .ogon ? 0.34 : 0.18), CGColor(gray: 0, alpha: 0.2)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: shade, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: -15.5), end: CGPoint(x: 0, y: 15.5), options: [])
        }
        // Dorsal fin as a soft line down the back.
        ctx.setStrokeColor(spec.mark.alpha(0.22).cgColor)
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: -20, y: 0)); ctx.addLine(to: CGPoint(x: 8, y: 0))
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(bodyPath)
        ctx.setStrokeColor(CGColor(srgbRed: 0.24, green: 0.35, blue: 0.32, alpha: 0.3))
        ctx.setLineWidth(0.8)
        ctx.strokePath()

        for side: CGFloat in [-1, 1] {
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.14, blue: 0.14, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 21.5, y: side * 7.2 - 1.9, width: 3.8, height: 3.8))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
            ctx.fillEllipse(in: CGRect(x: 23.2, y: side * 7.2 + 0.2, width: 1.1, height: 1.1))
        }
    }

    private static func drawPattern(_ spec: KoiSpec, in ctx: CGContext) {
        func spot(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: RGBA) {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
        }
        switch spec.pattern {
        case .kohaku:
            spot(-16, 5, 9, 6.5, spec.mark.alpha(0.94))
            spot(1, -3, 11, 8, spec.mark.alpha(0.94))
            spot(19, 3, 7.5, 6, spec.mark.alpha(0.94))
        case .tancho:
            spot(19, 0, 6.5, 6.5, spec.mark)
        case .showa:
            spot(-12, -4, 9, 7, Palette.vermilion.alpha(0.9))
            spot(12, 4, 8, 6, Palette.vermilion.alpha(0.9))
            let black = spec.mark.alpha(0.88)
            spot(-22, 5, 4.5, 3.5, black); spot(-2, 9, 5, 3.5, black)
            spot(4, -8, 4, 3, black); spot(21, -5, 3.5, 3, black)
        case .ogon:
            spot(-8, 0, 20, 7, spec.mark.alpha(0.28))
        case .custom:
            let box = bodyBox
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for stroke in spec.strokes where !stroke.points.isEmpty {
                ctx.setStrokeColor(stroke.color.cgColor)
                ctx.setLineWidth(max(0.8, stroke.width * box.height))
                let mapped = stroke.points.map { CGPoint(x: box.minX + $0.x * box.width, y: box.maxY - $0.y * box.height) }
                if mapped.count == 1 {
                    let r = max(0.4, stroke.width * box.height / 2)
                    ctx.setFillColor(stroke.color.cgColor)
                    ctx.fillEllipse(in: CGRect(x: mapped[0].x - r, y: mapped[0].y - r, width: r * 2, height: r * 2))
                } else {
                    ctx.addLines(between: mapped)
                    ctx.strokePath()
                }
            }
        }
    }
}
