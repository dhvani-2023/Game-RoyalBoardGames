import SwiftUI
import UIKit

/// Maps table centimetres to points. [vertical] stands the table on end (portrait), head at the bottom.
/// All Pool drawing happens in points so the reference's numbers carry over 1:1.
struct PoolTableMap {
    let t: PoolTableGeometry
    let vertical: Bool
    /// The whole table including rails.
    let rect: CGRect
    let s: CGFloat
    let centre: CGPoint
    let surface: CGRect

    /// Rail and cushion each side, in cm.
    static let RAIL = 14.0

    init(_ size: CGSize, _ vertical: Bool, _ t: PoolTableGeometry, pad: CGFloat = 0) {
        self.t = t
        self.vertical = vertical
        let L = t.length + 2 * PoolTableMap.RAIL
        let W = t.width + 2 * PoolTableMap.RAIL
        let ratio = CGFloat(vertical ? W / L : L / W)
        var w = size.width - 2 * pad
        var h = w / ratio
        if h > size.height - 2 * pad { h = size.height - 2 * pad; w = h * ratio }
        rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        s = (vertical ? rect.height : rect.width) / CGFloat(t.length + 2 * PoolTableMap.RAIL)
        centre = CGPoint(x: rect.midX, y: rect.midY)
        let sw = CGFloat(t.length) * s
        let sh = CGFloat(t.width) * s
        surface = vertical ? CGRect(x: centre.x - sh / 2, y: centre.y - sw / 2, width: sh, height: sw)
            : CGRect(x: centre.x - sw / 2, y: centre.y - sh / 2, width: sw, height: sh)
    }

    func pt(_ v: Vec2) -> CGPoint { pt(v.x, v.y) }
    func pt(_ x: Double, _ y: Double) -> CGPoint { let d = vec(x, y); return CGPoint(x: centre.x + d.x * s, y: centre.y + d.y * s) }
    func pt(_ frame: [Float], _ i: Int) -> CGPoint { pt(Double(frame[2 * i]), Double(frame[2 * i + 1])) }

    /// A table direction as a screen direction (unscaled).
    func vec(_ x: Double, _ y: Double) -> CGPoint { vertical ? CGPoint(x: y, y: -x) : CGPoint(x: x, y: y) }
    func vec(_ v: Vec2) -> CGPoint { vec(v.x, v.y) }

    func cm(_ p: CGPoint) -> Vec2 {
        let dx = Double((p.x - centre.x) / s)
        let dy = Double((p.y - centre.y) / s)
        return vertical ? Vec2(-dy, dx) : Vec2(dx, dy)
    }

    /// Screen drag → table direction.
    func tableVec(_ d: CGPoint) -> Vec2 { vertical ? Vec2(-Double(d.y), Double(d.x)) : Vec2(Double(d.x), Double(d.y)) }

    func len(_ cm: Double) -> CGFloat { CGFloat(cm) * s }
}

private func deg(_ radians: Double) -> Double { radians * 180 / Double.pi }

private extension PoolRGBA {
    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
}

// MARK: - Number glyphs

/// Ball numbers (Nunito Black, ink 0x141414), rendered once per number and pixel size.
@MainActor
final class PoolGlyphs {
    static let shared = PoolGlyphs()
    static let REF: CGFloat = 40

    struct Glyph {
        let image: CGImage
        /// The text's line box in points.
        let size: CGSize
        let scale: CGFloat
    }

    private var cache: [Int: Glyph] = [:]

    /// [n]'s number at font size [size] points.
    func glyph(_ n: Int, _ size: CGFloat, _ scale: CGFloat) -> Glyph? {
        guard (1...15).contains(n), size > 0.3 else { return nil }
        let px = max(2, Int((size * scale * 2).rounded()))
        let key = n * 1_000_000 + px * 10 + Int(scale)
        if let hit = cache[key] { return hit }
        let fontSize = CGFloat(px) / (scale * 2)
        let font = RoyalFonts.uiBody(fontSize, .Black)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: poolHex(0x141414).ui]
        let str = "\(n)" as NSString
        let raw = str.size(withAttributes: attrs)
        let box = CGSize(width: ceil(raw.width * scale) / scale, height: ceil(raw.height * scale) / scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: box, format: format).image { _ in
            str.draw(at: CGPoint(x: (box.width - raw.width) / 2, y: (box.height - raw.height) / 2), withAttributes: attrs)
        }
        guard let cg = image.cgImage else { return nil }
        let g = Glyph(image: cg, size: box, scale: scale)
        if cache.count > 600 { cache.removeAll() }
        cache[key] = g
        return g
    }
}

// MARK: - Ball sprites (shadow, shading and gloss: the same for every ball, scaled)

enum PoolBallSprites {
    private static let REF: CGFloat = 96

    /// The soft shadow, a circle of radius REF (the reference's blurred sprite).
    static let shadow: CGImage? = render(CGSize(width: REF * 2, height: REF * 2)) { cg in
        let c = CGPoint(x: REF, y: REF)
        PoolCG.fillRadial(cg, PoolArt.circle(c, REF),
                          [PoolRGBA.black.alpha(0.45), PoolRGBA.black.alpha(0.43), PoolRGBA.black.alpha(0.22), PoolRGBA.black.alpha(0.06), PoolRGBA.black.alpha(0.0)],
                          [0, 0.5, 0.73, 0.88, 1], c, REF)
    }

    /// Shading and the gloss highlight over a ball of radius REF, in its 2·REF box.
    static let shade: CGImage? = render(CGSize(width: REF * 2, height: REF * 2)) { cg in
        let r = REF
        let c = CGPoint(x: r, y: r)
        PoolCG.fillRadial(cg, PoolArt.circle(c, r), [PoolRGBA.white.alpha(0.0), PoolRGBA.black.alpha(0.0), PoolRGBA.black.alpha(0.42)],
                          nil, CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), r * 1.45)
        let oval = Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.68, width: r * 0.58, height: r * 0.4))
        PoolCG.fillRadial(cg, oval, [PoolRGBA.white.alpha(0.85), PoolRGBA.white.alpha(0.0)], nil, CGPoint(x: c.x - r * 0.33, y: c.y - r * 0.48), r * 0.36)
    }

    private static func render(_ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }.cgImage
    }
}

// MARK: - CoreGraphics helpers (static art)

enum PoolCG {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func gradient(_ colors: [PoolRGBA], _ locations: [CGFloat]?) -> CGGradient {
        let locs = locations ?? colors.indices.map { colors.count > 1 ? CGFloat($0) / CGFloat(colors.count - 1) : 0 }
        return CGGradient(colorsSpace: space, colors: colors.map { $0.cg } as CFArray, locations: locs)!
    }

    static func fill(_ cg: CGContext, _ p: Path, _ c: PoolRGBA, evenOdd: Bool = false) {
        cg.setFillColor(c.cg)
        cg.addPath(p.cgPath)
        cg.fillPath(using: evenOdd ? .evenOdd : .winding)
    }

    static func stroke(_ cg: CGContext, _ p: Path, _ c: PoolRGBA, _ width: CGFloat, cap: CGLineCap = .butt, join: CGLineJoin = .miter) {
        cg.saveGState()
        cg.setStrokeColor(c.cg)
        cg.setLineWidth(width)
        cg.setLineCap(cap)
        cg.setLineJoin(join)
        cg.addPath(p.cgPath)
        cg.strokePath()
        cg.restoreGState()
    }

    static func line(_ cg: CGContext, _ c: PoolRGBA, _ a: CGPoint, _ b: CGPoint, _ width: CGFloat) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        stroke(cg, p, c, width)
    }

    static func fillCircle(_ cg: CGContext, _ c: PoolRGBA, _ r: CGFloat, _ center: CGPoint) {
        guard r > 0 else { return }
        fill(cg, PoolArt.circle(center, r), c)
    }

    static func strokeCircle(_ cg: CGContext, _ c: PoolRGBA, _ r: CGFloat, _ center: CGPoint, _ width: CGFloat) {
        guard r > 0 else { return }
        stroke(cg, PoolArt.circle(center, r), c, width)
    }

    static func fillLinear(_ cg: CGContext, _ p: Path, _ colors: [PoolRGBA], _ start: CGPoint, _ end: CGPoint) {
        cg.saveGState()
        cg.addPath(p.cgPath)
        cg.clip()
        cg.drawLinearGradient(gradient(colors, nil), start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    static func strokeLinear(_ cg: CGContext, _ p: Path, _ colors: [PoolRGBA], _ start: CGPoint, _ end: CGPoint, _ width: CGFloat) {
        cg.saveGState()
        cg.addPath(p.cgPath)
        cg.setLineWidth(width)
        cg.replacePathWithStrokedPath()
        cg.clip()
        cg.drawLinearGradient(gradient(colors, nil), start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    static func fillRadial(_ cg: CGContext, _ p: Path, _ colors: [PoolRGBA], _ locations: [CGFloat]?, _ center: CGPoint, _ radius: CGFloat) {
        cg.saveGState()
        cg.addPath(p.cgPath)
        cg.clip()
        cg.drawRadialGradient(gradient(colors, locations), startCenter: center, startRadius: 0, endCenter: center, endRadius: max(0.0001, radius),
                              options: [.drawsAfterEndLocation])
        cg.restoreGState()
    }

    /// A soft glow (the reference's shadow filter): a few widening translucent strokes.
    static func glow(_ cg: CGContext, _ p: Path, _ color: PoolRGBA, _ radius: CGFloat, _ width: CGFloat = 0) {
        for k in stride(from: 3, through: 1, by: -1) {
            stroke(cg, p, color.alpha(color.a * 0.16), width + radius * CGFloat(k) * 0.7, cap: .round, join: .round)
        }
    }

    static func withClip(_ cg: CGContext, _ p: Path, evenOdd: Bool = false, _ body: () -> Void) {
        cg.saveGState()
        cg.addPath(p.cgPath)
        if evenOdd { cg.clip(using: .evenOdd) } else { cg.clip() }
        body()
        cg.restoreGState()
    }

    static func withAlpha(_ cg: CGContext, _ alpha: CGFloat, _ bounds: CGRect, _ body: () -> Void) {
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        body()
        cg.endTransparencyLayer()
        cg.restoreGState()
    }
}

enum PoolArt {
    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

    private static func roundRect(_ r: CGRect, _ radius: CGFloat) -> Path { Path(roundedRect: r, cornerRadius: radius, style: .circular) }

    private static func white(_ a: Double) -> PoolRGBA { PoolRGBA.white.alpha(a) }
    private static func black(_ a: Double) -> PoolRGBA { PoolRGBA.black.alpha(a) }

    /// A soft glow (the reference's shadow filter): a few widening translucent strokes.
    static func glow(_ ctx: GraphicsContext, _ path: Path, _ color: PoolRGBA, _ radius: CGFloat, _ width: CGFloat = 0) {
        for k in stride(from: 3, through: 1, by: -1) {
            ctx.stroke(path, with: .color(color.alpha(color.a * 0.16).color),
                       style: StrokeStyle(lineWidth: width + radius * CGFloat(k) * 0.7, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Table (CoreGraphics, rendered once into a plate)

    static func drawTable(_ cg: CGContext, _ m: PoolTableMap, _ th: PoolTableTheme) {
        let outer = roundRect(m.rect, m.len(6.0))
        PoolCG.fillLinear(cg, outer, th.rail, m.rect.origin, CGPoint(x: m.rect.maxX, y: m.rect.maxY))
        railPattern(cg, m, th)
        let cushion = m.surface.insetBy(dx: -m.len(3.2), dy: -m.len(3.2))
        PoolCG.fill(cg, Path(roundedRect: cushion, cornerRadius: m.len(1.0), style: .circular), th.cloth[1].lerp(.black, 0.25))
        let sf = m.surface
        PoolCG.fillRadial(cg, Path(sf), th.cloth, nil, m.centre, max(sf.width, sf.height) * 0.62)
        let clothPath = Path(sf)
        PoolCG.withClip(cg, clothPath) {
            let rng = PoolRandom(5)
            let nap = Int(sf.width * sf.height / 90)
            for _ in 0..<min(1400, nap) {
                let x = sf.minX + CGFloat(Float(rng.unit())) * sf.width
                let y = sf.minY + CGFloat(Float(rng.unit())) * sf.height
                PoolCG.fillCircle(cg, white(0.03 + rng.unit() * 0.03), 0.6, CGPoint(x: x, y: y))
            }
            emblem(cg, m, th)
            PoolCG.line(cg, white(0.22), m.pt(m.t.headString, -m.t.b), m.pt(m.t.headString, m.t.b), 1)
            PoolCG.fillCircle(cg, white(0.4), m.len(0.8), m.pt(m.t.footSpot))
            PoolCG.stroke(cg, clothPath, black(0.35), m.len(1.4))
        }
        PoolCG.stroke(cg, Path(sf.insetBy(dx: -0.5, dy: -0.5)), white(0.12), 1)
        // Sights on the rails.
        for k in [1, 2, 3, 5, 6, 7] {
            let x = -m.t.a + Double(k) * m.t.length / 8
            for sy in [-1.0, 1.0] { diamond(cg, m.pt(x, sy * (m.t.b + 9)), m.len(1.2), th) }
        }
        for k in [1, 2, 3] {
            let y = -m.t.b + Double(k) * m.t.width / 4
            for sx in [-1.0, 1.0] { diamond(cg, m.pt(sx * (m.t.a + 9), y), m.len(1.2), th) }
        }
        for pk in m.t.pockets {
            let p = m.pt(pk.c)
            let r = m.len(pk.r * (pk.corner ? 0.98 : 0.92))
            PoolCG.fillCircle(cg, th.neon ? poolHex(0xFF3DCB).alpha(0.9) : th.trim.lerp(.black, 0.15), r * 1.18, p)
            PoolCG.fillRadial(cg, circle(p, r), [poolHex(0x000000), poolHex(0x151515)], nil, p, r)
            PoolCG.strokeCircle(cg, white(0.08), r * 0.92, p, r * 0.1)
        }
    }

    private static func diamond(_ cg: CGContext, _ c: CGPoint, _ r: CGFloat, _ th: PoolTableTheme) {
        var d = Path()
        d.move(to: CGPoint(x: c.x, y: c.y - r)); d.addLine(to: CGPoint(x: c.x + r * 0.6, y: c.y))
        d.addLine(to: CGPoint(x: c.x, y: c.y + r)); d.addLine(to: CGPoint(x: c.x - r * 0.6, y: c.y)); d.closeSubpath()
        if th.neon { PoolCG.glow(cg, d, th.trim, 3) }
        PoolCG.fill(cg, d, th.neon ? th.trim : poolHex(0xF8F1DA))
    }

    private static func railPattern(_ cg: CGContext, _ m: PoolTableMap, _ th: PoolTableTheme) {
        var ring = Path(roundedRect: m.rect, cornerRadius: m.len(6.0), style: .circular)
        ring.addRect(m.surface.insetBy(dx: -m.len(3.2), dy: -m.len(3.2)))
        let r = m.rect
        PoolCG.withClip(cg, ring, evenOdd: true) {
            let rng = PoolRandom(3)
            let long = max(r.width, r.height)
            let across = min(r.width, r.height)
            // u runs along the table's length, v across it.
            func along(_ u: CGFloat, _ v: CGFloat) -> CGPoint { m.vertical ? CGPoint(x: r.minX + v, y: r.minY + u) : CGPoint(x: r.minX + u, y: r.minY + v) }
            switch th.style {
            case .Wood, .Bamboo, .Sandstone:
                for i in 0..<60 {
                    var p = Path()
                    let v = CGFloat(i) * across / 60 + CGFloat(Float(rng.unit() * 3))
                    var u: CGFloat = 0
                    p.move(to: along(0, v))
                    while u < long {
                        p.addLine(to: along(u, v + CGFloat(sin(Double(u) * 0.02 + Double(i))) * 1.5))
                        u += 6
                    }
                    PoolCG.stroke(cg, p, th.rail[1].alpha(0.25), 0.8)
                }
                if th.style == .Bamboo {
                    var k: CGFloat = 20
                    while k < long {
                        PoolCG.line(cg, th.rail[1].alpha(0.45), along(k, 0), along(k, across), 2)
                        k += 46
                    }
                }
                if th.style == .Sandstone {
                    for i in 0..<14 {
                        let u = CGFloat(i) * long / 14 + 18
                        PoolCG.fillCircle(cg, th.trim.alpha(0.6), m.len(1.2), along(u, m.len(4.0)))
                        PoolCG.fillCircle(cg, th.trim.alpha(0.6), m.len(1.2), along(u, across - m.len(4.0)))
                    }
                }
            case .Studded:
                for i in 0..<40 {
                    let u = CGFloat(i) * long / 40
                    PoolCG.fillCircle(cg, white(0.35), 1.3, along(u, m.len(4.0)))
                    PoolCG.fillCircle(cg, white(0.35), 1.3, along(u, across - m.len(4.0)))
                }
            case .Ornate, .Baroque:
                let ink = th.style == .Ornate ? th.trim : poolHex(0x8A5A10)
                for i in 0..<18 {
                    for v in [m.len(4.5), across - m.len(4.5)] {
                        let c = along(CGFloat(i) * long / 18 + 10, v)
                        let rad = m.len(2.4)
                        let arc = RoyalDraw.arcPath(0, 280, false, CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad))
                        PoolCG.stroke(cg, arc, ink.alpha(0.75), 1.4)
                    }
                }
            case .Neon:
                let inner = r.insetBy(dx: m.len(2.0), dy: m.len(2.0))
                PoolCG.stroke(cg, Path(roundedRect: inner, cornerRadius: m.len(5.0), style: .circular), th.trim.alpha(0.9), 2)
            case .Frost:
                for i in 0..<24 {
                    let u = CGFloat(i) * long / 24
                    PoolCG.line(cg, th.trim.alpha(0.3), along(u, 0), along(u + 12, m.len(9.0)), 3)
                }
            }
        }
        let hi = roundRect(r.insetBy(dx: 1.5, dy: 1.5), m.len(6.0))
        if th.neon { PoolCG.glow(cg, hi, th.trim, 6, 2) }
        PoolCG.strokeLinear(cg, hi, [white(0.5), white(0.05)], r.origin, CGPoint(x: r.minX, y: r.maxY), 2)
    }

    private static func emblem(_ cg: CGContext, _ m: PoolTableMap, _ th: PoolTableTheme) {
        let c = m.centre
        let R = m.len(14.0)
        let opacity: CGFloat = th.neon ? 0.4 : 0.16
        let bounds = CGRect(x: c.x - R * 1.5, y: c.y - R * 1.5, width: R * 3, height: R * 3)
        let ink = PoolRGBA.white
        func ray(_ a: Double, _ from: CGFloat, _ to: CGFloat) -> (CGPoint, CGPoint) {
            (CGPoint(x: c.x + R * from * CGFloat(cos(a)), y: c.y + R * from * CGFloat(sin(a))),
             CGPoint(x: c.x + R * to * CGFloat(cos(a)), y: c.y + R * to * CGFloat(sin(a))))
        }
        PoolCG.withAlpha(cg, opacity, bounds) {
            switch th.emblem {
            case .Crest:
                PoolCG.strokeCircle(cg, ink, R, c, 2)
                PoolCG.strokeCircle(cg, ink, R * 0.7, c, 1)
                let font = RoyalFonts.uiBody(R * 0.9, .Black)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let str = "8" as NSString
                let size = str.size(withAttributes: attrs)
                UIGraphicsPushContext(cg)
                str.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2), withAttributes: attrs)
                UIGraphicsPopContext()
            case .Wave:
                for i in 0..<3 {
                    let y = c.y + CGFloat(i - 1) * R * 0.4
                    var w = Path()
                    w.move(to: CGPoint(x: c.x - R, y: y))
                    w.addCurve(to: CGPoint(x: c.x + R, y: y), control1: CGPoint(x: c.x - R * 0.3, y: y - R * 0.4), control2: CGPoint(x: c.x + R * 0.3, y: y + R * 0.4))
                    PoolCG.stroke(cg, w, ink, 2.5)
                }
            case .Flame:
                var f = Path()
                f.move(to: CGPoint(x: c.x, y: c.y - R))
                f.addQuadCurve(to: CGPoint(x: c.x + R * 0.6, y: c.y + R * 0.6), control: CGPoint(x: c.x + R * 0.9, y: c.y - R * 0.1))
                f.addQuadCurve(to: CGPoint(x: c.x - R * 0.6, y: c.y + R * 0.6), control: CGPoint(x: c.x, y: c.y + R * 1.1))
                f.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R), control: CGPoint(x: c.x - R * 0.9, y: c.y - R * 0.1))
                PoolCG.fill(cg, f, ink)
            case .Circuit:
                for i in 0..<6 {
                    let (_, end) = ray(Double(i) * Double.pi / 3, 0, 1)
                    PoolCG.line(cg, poolHex(0x3EF4FF), c, end, 2)
                    PoolCG.fillCircle(cg, poolHex(0xFF3DCB), 3, end)
                }
                PoolCG.strokeCircle(cg, poolHex(0x3EF4FF), R * 0.4, c, 2)
            case .Crown:
                let pts: [(CGFloat, CGFloat)] = [(-1, 0.5), (-1.1, -0.5), (-0.5, 0), (0, -0.8), (0.5, 0), (1.1, -0.5), (1, 0.5)]
                var p = Path()
                for (i, q) in pts.enumerated() {
                    let pt = CGPoint(x: c.x + q.0 * R * 0.8, y: c.y + q.1 * R * 0.8)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                PoolCG.fill(cg, p, ink)
            case .Snowflake:
                for i in 0..<6 {
                    let (_, end) = ray(Double(i) * Double.pi / 3, 0, 1)
                    PoolCG.line(cg, poolHex(0x2F6FB0), c, end, 3)
                }
            case .Sun:
                PoolCG.fillCircle(cg, ink, R * 0.5, c)
                for i in 0..<12 {
                    let (a, b) = ray(Double(i) * Double.pi / 6, 0.65, 1)
                    PoolCG.line(cg, ink, a, b, 3)
                }
            case .Lotus:
                for i in 0..<8 {
                    let a = Double(i) * Double.pi / 4 - Double.pi / 2
                    var p = Path()
                    p.move(to: c)
                    p.addQuadCurve(to: CGPoint(x: c.x + R * CGFloat(cos(a)), y: c.y + R * CGFloat(sin(a))),
                                   control: CGPoint(x: c.x + R * 0.6 * CGFloat(cos(a + 0.5)), y: c.y + R * 0.6 * CGFloat(sin(a + 0.5))))
                    p.addQuadCurve(to: c, control: CGPoint(x: c.x + R * 0.6 * CGFloat(cos(a - 0.5)), y: c.y + R * 0.6 * CGFloat(sin(a - 0.5))))
                    PoolCG.fill(cg, p, ink)
                }
            }
        }
    }

    // MARK: Balls (live, per frame)

    /// The soft shadow under a ball (the reference's blurred sprite).
    static func ballShadow(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        guard let img = PoolBallSprites.shadow else { return }
        let sc = CGPoint(x: c.x + r * 0.22, y: c.y + r * 0.34)
        let rr = r * 1.3
        ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: sc.x - rr, y: sc.y - rr, width: 2 * rr, height: 2 * rr))
    }

    /// Unit circle, 36 samples, for the stripe caps.
    private static let capCos: [Double] = (0..<36).map { cos(Double($0) / 36 * 2 * Double.pi) }
    private static let capSin: [Double] = (0..<36).map { sin(Double($0) / 36 * 2 * Double.pi) }

    /// A ball from above: colour, stripe band and number disc placed by its orientation, then shading and gloss.
    /// [numberSize] is the number's font size in points; [glyphs] false draws no number.
    @MainActor
    static func drawBall(
        _ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ n: Int, _ q: Quat, _ vertical: Bool,
        _ glyphs: Bool, _ numberSize: CGFloat, alpha: Double = 1, shadow: Bool = false, scale: CGFloat
    ) {
        if alpha <= 0.001 || r <= 0 { return }
        if alpha < 0.999 {
            var layer = ctx
            layer.opacity = alpha
            layer.drawLayer { l in drawBallBody(l, c, r, n, q, vertical, glyphs, numberSize, shadow, scale) }
        } else {
            drawBallBody(ctx, c, r, n, q, vertical, glyphs, numberSize, shadow, scale)
        }
    }

    @MainActor
    private static func drawBallBody(
        _ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ n: Int, _ q: Quat, _ vertical: Bool,
        _ glyphs: Bool, _ numberSize: CGFloat, _ shadow: Bool, _ scale: CGFloat
    ) {
        if shadow { ballShadow(ctx, c, r) }
        func vec(_ x: Double, _ y: Double) -> CGPoint { vertical ? CGPoint(x: y, y: -x) : CGPoint(x: x, y: y) }
        func screen(_ v: Vec3) -> CGPoint { let d = vec(v.x, v.y); return CGPoint(x: c.x + d.x * r, y: c.y + d.y * r) }
        let ballPath = circle(c, r)
        if n == 0 {
            ctx.fill(ballPath, with: .color(poolHex(0xF8F6EE).color))
            // The red dot shows the cue ball's roll and spin.
            let a = PoolQuat.rotate(q, Vec3(0.0, 0.0, -1.0))
            if a.z < -0.1 {
                let p = screen(a * 0.95)
                ctx.fill(circle(p, r * 0.16 * CGFloat(min(1.0, -a.z + 0.3))), with: .color(poolHex(0xE0242B).color))
            }
        } else {
            let colour = PoolBallColour.colour(n)
            let stripe = n > 8
            ctx.fill(ballPath, with: .color(colour.color))
            var inner = ctx
            inner.clip(to: ballPath)
            if stripe {
                // White caps either side of the band.
                let axis = PoolQuat.rotate(q, Vec3(1.0, 0.0, 0.0))
                for sign in [1.0, -1.0] {
                    if let cap = capPath(axis * sign, 0.52, c, r, screen) { inner.fill(cap, with: .color(poolHex(0xF8F6EE).color)) }
                }
            }
            let a0 = PoolQuat.rotate(q, Vec3(0.0, 0.0, -1.0))
            let a = a0.z < 0 ? a0 : -a0
            let facing = -a.z
            if facing > 0.12 {
                let centre = screen(a)
                let dir = vec(a.x, a.y)
                let phi = deg(atan2(Double(dir.y), Double(dir.x)))
                let discAlpha = min(1.0, (facing - 0.12) / 0.2)
                var disc = inner
                disc.translateBy(x: centre.x, y: centre.y)
                disc.rotate(by: .degrees(phi))
                disc.scaleBy(x: CGFloat(facing), y: 1)
                disc.rotate(by: .degrees(-phi))
                disc.fill(circle(.zero, r * 0.36), with: .color(poolHex(0xF8F6EE).alpha(discAlpha).color))
                if glyphs, let g = PoolGlyphs.shared.glyph(n, numberSize, scale) {
                    let up0 = PoolQuat.rotate(q, Vec3(0.0, -1.0, 0.0))
                    let up = vec(up0.x, up0.y)
                    var text = disc
                    text.rotate(by: .degrees(deg(atan2(Double(up.x), Double(-up.y)))))
                    text.opacity = discAlpha
                    text.draw(Image(decorative: g.image, scale: g.scale),
                              in: CGRect(x: -g.size.width / 2, y: -g.size.height / 2, width: g.size.width, height: g.size.height))
                }
            }
        }
        if let shade = PoolBallSprites.shade {
            ctx.draw(Image(decorative: shade, scale: 1), in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// The visible part of the spherical cap beyond [w] along [axis], as a screen path.
    private static func capPath(_ axis: Vec3, _ w: Double, _ c: CGPoint, _ r: CGFloat, _ screen: (Vec3) -> CGPoint) -> Path? {
        // Two directions across the cap's circle.
        let helper = abs(axis.z) < 0.9 ? Vec3(0.0, 0.0, 1.0) : Vec3(1.0, 0.0, 0.0)
        let e1 = axis.cross(helper).normalized
        let e2 = axis.cross(e1)
        let k = (1 - w * w).squareRoot()
        let count = 36
        return withUnsafeTemporaryAllocation(of: Vec3.self, capacity: count) { pts -> Path? in
            var visible = 0
            for i in 0..<count {
                let p = axis * w + (e1 * capCos[i] + e2 * capSin[i]) * k
                pts.initializeElement(at: i, to: p)
                if p.z < 0 { visible += 1 }
            }
            if visible == 0 { return nil }
            var path = Path()
            if visible == count {
                for i in 0..<count { let s = screen(pts[i]); if i == 0 { path.move(to: s) } else { path.addLine(to: s) } }
                path.closeSubpath()
                return path
            }
            // Start at the first visible point after a hidden one and walk the visible run.
            var start = -1
            for i in 0..<count where pts[i].z < 0 && !(pts[(i + count - 1) % count].z < 0) { start = i; break }
            if start < 0 { return nil }
            var i = start
            var first = CGPoint.zero
            var last = CGPoint.zero
            var n = 0
            while pts[i].z < 0 {
                let s = screen(pts[i])
                if n == 0 { first = s; path.move(to: s) } else { path.addLine(to: s) }
                last = s
                n += 1
                i = (i + 1) % count
                if i == start { break }
            }
            if n == 0 { return nil }
            // Close along the rim on the cap's side.
            let a0 = atan2(Double(last.y - c.y), Double(last.x - c.x))
            let a1 = atan2(Double(first.y - c.y), Double(first.x - c.x))
            let side = screen(axis)
            let sideAngle = atan2(Double(side.y - c.y), Double(side.x - c.x))
            func within(_ x: Double, _ from: Double, _ sweep: Double) -> Bool {
                let d = ieeeRemainder(x - from, 2 * Double.pi)
                let dd = d < 0 ? d + 2 * Double.pi : d
                return sweep >= 0 ? dd <= sweep : (2 * Double.pi - dd) <= -sweep
            }
            var sweep = ieeeRemainder(a1 - a0, 2 * Double.pi)
            if sweep < 0 { sweep += 2 * Double.pi }
            if !within(sideAngle, a0, sweep) { sweep -= 2 * Double.pi }
            let steps = 16
            for s in 1...steps {
                let a = a0 + sweep * Double(s) / Double(steps)
                path.addLine(to: CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
            }
            path.closeSubpath()
            return path
        }
    }

    // MARK: Cue (CoreGraphics, rendered once per design and size)

    /// A cue lying along +x from its tip at the origin, in parts: tip, ferrule, shaft, joint, forearm, butt.
    static func drawCue(_ cg: CGContext, _ length: CGFloat, _ width: CGFloat, _ st: PoolCueStyle) {
        let L = length
        let W = width
        func piece(_ x0: CGFloat, _ x1: CGFloat, _ w0: CGFloat, _ w1: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x0, y: -w0 / 2)); p.addLine(to: CGPoint(x: x1, y: -w1 / 2))
            p.addLine(to: CGPoint(x: x1, y: w1 / 2)); p.addLine(to: CGPoint(x: x0, y: w0 / 2)); p.closeSubpath()
            return p
        }
        // The shadow, offset and blurred.
        let sh = piece(0, L, W * 0.6, W * 1.2).offsetBy(dx: W * 0.6, dy: W * 1.2)
        PoolCG.fill(cg, sh, black(0.45 * 0.5))
        PoolCG.stroke(cg, sh, black(0.45 * 0.28), W * 0.6, join: .round)
        PoolCG.stroke(cg, sh, black(0.45 * 0.14), W * 1.2, join: .round)
        let shaftEnd = L * 0.5
        let foreEnd = L * 0.78
        func grad(_ p: Path, _ c: [PoolRGBA]) {
            PoolCG.fillLinear(cg, p, [c[0], c[1], c[0].lerp(.black, 0.35)], CGPoint(x: 0, y: -W), CGPoint(x: 0, y: W))
        }
        PoolCG.fill(cg, piece(0, W * 0.5, W * 0.62, W * 0.62), poolHex(0x3A7BD5))
        PoolCG.fill(cg, piece(W * 0.5, W * 1.6, W * 0.64, W * 0.66), poolHex(0xF7F5EE))
        grad(piece(W * 1.6, shaftEnd, W * 0.66, W * 0.85), st.shaft)
        PoolCG.fill(cg, piece(shaftEnd, shaftEnd + W * 0.5, W * 0.86, W * 0.88), st.accent)
        grad(piece(shaftEnd + W * 0.5, foreEnd, W * 0.88, W * 1.04), st.forearm)
        grad(piece(foreEnd, L - W * 0.8, W * 1.04, W * 1.18), st.butt)
        PoolCG.fill(cg, piece(L - W * 0.8, L, W * 1.18, W * 1.2), st.butt[1].lerp(.black, 0.4))
        let a = st.accent
        PoolCG.withClip(cg, piece(shaftEnd + W * 0.5, L - W * 0.8, W * 0.88, W * 1.18)) {
            switch st.inlay {
            case .Plain:
                break
            case .Rings:
                for k in 0..<4 {
                    let kk = CGFloat(k)
                    PoolCG.fill(cg, piece(foreEnd - W * 3 + kk * W * 1.2, foreEnd - W * 2.7 + kk * W * 1.2, W * 2, W * 2), a)
                }
            case .Points:
                for k in 0..<3 {
                    let x = shaftEnd + W * 2 + CGFloat(k) * W * 6
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: -W)); p.addLine(to: CGPoint(x: x + W * 5, y: 0)); p.addLine(to: CGPoint(x: x, y: W)); p.closeSubpath()
                    PoolCG.fill(cg, p, a.alpha(0.85))
                }
            case .Neon:
                var p = Path()
                p.move(to: CGPoint(x: shaftEnd, y: 0)); p.addLine(to: CGPoint(x: L, y: 0))
                PoolCG.glow(cg, p, a, 4, W * 0.18)
                PoolCG.stroke(cg, p, a, W * 0.18)
            case .Gems:
                for k in 0..<5 { PoolCG.fillCircle(cg, a, W * 0.28, CGPoint(x: foreEnd + CGFloat(k) * W * 2.2 + W, y: 0)) }
                PoolCG.fill(cg, piece(shaftEnd + W * 0.5, foreEnd, W * 0.3, W * 0.3), poolHex(0xFFF0B8).alpha(0.8))
            case .Crystal:
                for k in 0..<8 {
                    let x = shaftEnd + CGFloat(k) * W * 3
                    PoolCG.line(cg, white(0.7), CGPoint(x: x, y: -W), CGPoint(x: x + W * 1.5, y: W), 1.2)
                }
            case .Tiger:
                for k in 0..<14 {
                    let x = shaftEnd + CGFloat(k) * W * 1.6
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: -W)); p.addQuadCurve(to: CGPoint(x: x + W * 0.6, y: W), control: CGPoint(x: x + W * 1.2, y: 0))
                    PoolCG.stroke(cg, p, a.alpha(0.55), W * 0.25)
                }
            case .Stars:
                let rng = PoolRandom(2)
                for _ in 0..<26 {
                    let x = shaftEnd + CGFloat(Float(rng.unit())) * (L - shaftEnd)
                    let y = CGFloat(Float(rng.unit() - 0.5)) * W
                    PoolCG.fillCircle(cg, a, 0.8, CGPoint(x: x, y: y))
                }
            }
        }
        PoolCG.stroke(cg, piece(0, L, W * 0.62, W * 1.2), black(0.25), 0.6)
    }
}

/// Cue sprites, rendered once per design, size and screen scale, then drawn rotated each frame.
@MainActor
enum PoolCueSprites {
    private struct Key: Hashable {
        let id: Int
        let l: Int
        let w: Int
        let scale: Int
    }

    private static var cache: [Key: CGImage] = [:]
    private static var order: [Key] = []

    static func sprite(_ st: PoolCueStyle, _ length: CGFloat, _ width: CGFloat, _ scale: CGFloat) -> CGImage? {
        guard length > 1, width > 0.2 else { return nil }
        let key = Key(id: st.id, l: Int((length * 2).rounded()), w: Int((width * 8).rounded()), scale: Int(scale * 10))
        if let hit = cache[key] { return hit }
        let L = CGFloat(key.l) / 2
        let W = CGFloat(key.w) / 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: L + W * 8, height: W * 8), format: format).image { r in
            let cg = r.cgContext
            cg.translateBy(x: W * 4, y: W * 4)
            PoolArt.drawCue(cg, L, W, st)
        }
        guard let cgImage = image.cgImage else { return nil }
        cache[key] = cgImage
        order.append(key)
        if order.count > 24 { cache[order.removeFirst()] = nil }
        return cgImage
    }

    /// A cue lying along [dir] behind the [tip] point (the Kotlin `drawCue`).
    static func drawCue(_ ctx: GraphicsContext, _ tip: CGPoint, _ dir: CGPoint, _ length: CGFloat, _ width: CGFloat,
                        _ st: PoolCueStyle, alpha: Double = 1, scale: CGFloat) {
        if alpha <= 0.001 { return }
        guard let img = sprite(st, length, width, scale) else { return }
        let L = CGFloat(Int((length * 2).rounded())) / 2
        let W = CGFloat(Int((width * 8).rounded())) / 8
        var c = ctx
        c.translateBy(x: tip.x, y: tip.y)
        c.rotate(by: .radians(atan2(Double(-dir.y), Double(-dir.x))))
        if alpha < 0.999 { c.opacity = alpha }
        c.draw(Image(decorative: img, scale: scale), in: CGRect(x: -W * 4, y: -W * 4, width: L + W * 8, height: W * 8))
    }
}

/// Renders static table plates once per design, size, orientation and pixel size.
@MainActor
enum PoolPlateCache {
    private struct Key: Hashable {
        let theme: Int
        let size: PoolTableSize
        let vertical: Bool
        let w: Int
        let h: Int
        let scale: Int
    }

    private static var cache: [Key: CGImage] = [:]
    private static var order: [Key] = []

    static func get(_ theme: PoolTableTheme, _ size: PoolTableSize, _ vertical: Bool, _ w: CGFloat, _ h: CGFloat, _ scale: CGFloat) -> CGImage? {
        let key = Key(theme: theme.id, size: size, vertical: vertical, w: Int((w * scale).rounded()), h: Int((h * scale).rounded()), scale: Int(scale * 10))
        if let hit = cache[key] {
            if let i = order.firstIndex(of: key) { order.remove(at: i); order.append(key) }
            return hit
        }
        guard key.w > 0, key.h > 0 else { return nil }
        let pts = CGSize(width: CGFloat(key.w) / scale, height: CGFloat(key.h) / scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: pts, format: format).image { r in
            PoolArt.drawTable(r.cgContext, PoolTableMap(pts, vertical, PoolTableGeometry.of(size)), theme)
        }
        guard let cgImage = image.cgImage else { return nil }
        cache[key] = cgImage
        order.append(key)
        if order.count > 14 { cache[order.removeFirst()] = nil }
        return cgImage
    }
}

/// The static table: drawn once per design, size and orientation, never while balls move.
struct PoolTablePlate: View {
    let theme: PoolTableTheme
    let size: PoolTableSize
    let vertical: Bool
    @Environment(\.displayScale) private var scale

    init(_ theme: PoolTableTheme, _ size: PoolTableSize, _ vertical: Bool) {
        self.theme = theme
        self.size = size
        self.vertical = vertical
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if w > 0, h > 0, let img = PoolPlateCache.get(theme, size, vertical, w, h, scale) {
                Image(decorative: img, scale: scale)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: w, height: h)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small ball for panels and the return chute.
struct PoolMiniBall: View {
    let n: Int
    var size: CGFloat = 16
    var dim: Bool = false
    @Environment(\.displayScale) private var scale

    private static let q = PoolQuat.axisAngle(Vec3(1.0, 0.0, 0.0), 0.25)

    init(_ n: Int, _ size: CGFloat = 16, dim: Bool = false) {
        self.n = n
        self.size = size
        self.dim = dim
    }

    var body: some View {
        let n = n
        let size = size
        let scale = scale
        Canvas { ctx, s in
            PoolArt.drawBall(ctx, CGPoint(x: s.width / 2, y: s.height / 2), size * 0.45, n, PoolMiniBall.q, false, n != 0, size * 0.3, scale: scale)
        }
        .frame(width: size, height: size)
        .opacity(dim ? 0.22 : 1)
        .accessibilityHidden(true)
    }
}
