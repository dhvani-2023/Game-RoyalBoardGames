import SwiftUI
import QuartzCore
import GameKit

/// Maps board centimetres to points inside a rectangle that includes the frame.
/// [u] is points per point (1): the reference's fixed hairline widths are in points.
struct CarromMetrics {
    let width: CGFloat
    let height: CGFloat
    let u: CGFloat

    init(_ width: CGFloat, _ height: CGFloat, _ u: CGFloat = 1) {
        self.width = width
        self.height = height
        self.u = u
    }

    var frame: CGFloat { width * 0.07 }
    var surface: CGRect { CGRect(x: frame, y: frame, width: width - 2 * frame, height: height - 2 * frame) }
    var s: CGFloat { (width - 2 * frame) / CGFloat(2 * CarromBoard.half) }
    private var midX: CGFloat { width / 2 }
    private var midY: CGFloat { height / 2 }

    func ptX(_ x: Double) -> CGFloat { midX + CGFloat(x) * s }
    func ptY(_ y: Double) -> CGFloat { midY + CGFloat(y) * s }
    func pt(_ v: CarromVec) -> CGPoint { CGPoint(x: ptX(v.x), y: ptY(v.y)) }
    func pt(_ x: Float, _ y: Float) -> CGPoint { CGPoint(x: midX + CGFloat(x) * s, y: midY + CGFloat(y) * s) }
    func cm(_ px: CGFloat, _ py: CGFloat) -> CarromVec { CarromVec(Double((px - midX) / s), Double((py - midY) / s)) }
    func len(_ cm: Double) -> CGFloat { CGFloat(cm) * s }
}

// MARK: - Paint helpers (the reference drew with GraphicsContext; these keep its calls in one place)

/// What a shape is filled or stroked with.
enum CarromPaint {
    case solid(CarromColor)
    case linearGradient(CGPoint, CGPoint, [CarromColor])
    /// Centre, colours spread from `start` to `end` radius.
    case radialGradient(CGPoint, [CarromColor], CGFloat, CGFloat)

    static func color(_ c: CarromColor) -> CarromPaint { .solid(c) }

    static func linear(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ colors: [CarromColor]) -> CarromPaint {
        .linearGradient(CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1), colors)
    }

    /// SwiftUI's radial gradient: colours spread from [startRadius] to [endRadius].
    static func radial(_ cx: CGFloat, _ cy: CGFloat, _ colors: [CarromColor], _ endRadius: CGFloat, _ startRadius: CGFloat = 0) -> CarromPaint {
        .radialGradient(CGPoint(x: cx, y: cy), colors, Swift.max(endRadius, 0.01), Swift.max(0, startRadius))
    }

    var shading: GraphicsContext.Shading {
        switch self {
        case .solid(let c):
            return .color(c.color)
        case .linearGradient(let a, let b, let cs):
            return .linearGradient(Gradient(colors: cs.map(\.color)), startPoint: a, endPoint: b)
        case .radialGradient(let c, let cs, let end, let start):
            return .radialGradient(Gradient(colors: cs.map(\.color)), center: c, startRadius: Swift.min(start, end), endRadius: end)
        }
    }
}

/// A drop shadow or glow applied to everything drawn with a paint (the reference's `.shadow` filter).
struct CarromShadow {
    let color: CarromColor
    let radius: CGFloat
    var dx: CGFloat = 0
    var dy: CGFloat = 0

    init(_ color: CarromColor, _ radius: CGFloat, _ dx: CGFloat = 0, _ dy: CGFloat = 0) {
        self.color = color
        self.radius = radius
        self.dx = dx
        self.dy = dy
    }
}

enum CarromDraw {
    /// Fills [path]; [blur] is the reference's `.blur(radius:)` on that one shape.
    static func fill(_ c: GraphicsContext, _ path: Path, _ paint: CarromPaint, shadow: CarromShadow? = nil, blur: CGFloat = 0, eoFill: Bool = false) {
        let style = FillStyle(eoFill: eoFill, antialiased: true)
        let shadowed = shadow.map { $0.radius > 0 } ?? false
        if !shadowed && blur <= 0.3 {
            c.fill(path, with: paint.shading, style: style)
            return
        }
        c.drawLayer { l in
            if shadowed, let s = shadow { l.addFilter(.shadow(color: s.color.color, radius: s.radius, x: s.dx, y: s.dy)) }
            if blur > 0.3 { l.addFilter(.blur(radius: blur)) }
            l.fill(path, with: paint.shading, style: style)
        }
    }

    static func fill(_ c: GraphicsContext, _ path: Path, _ color: CarromColor, shadow: CarromShadow? = nil, blur: CGFloat = 0) {
        fill(c, path, .solid(color), shadow: shadow, blur: blur)
    }

    static func stroke(_ c: GraphicsContext, _ path: Path, _ paint: CarromPaint, _ width: CGFloat, cap: CGLineCap = .butt,
                       join: CGLineJoin = .miter, dash: [CGFloat] = [], shadow: CarromShadow? = nil, blur: CGFloat = 0) {
        let style = StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: join, dash: dash, dashPhase: 0)
        let shadowed = shadow.map { $0.radius > 0 } ?? false
        if !shadowed && blur <= 0.3 {
            c.stroke(path, with: paint.shading, style: style)
            return
        }
        c.drawLayer { l in
            if shadowed, let s = shadow { l.addFilter(.shadow(color: s.color.color, radius: s.radius, x: s.dx, y: s.dy)) }
            if blur > 0.3 { l.addFilter(.blur(radius: blur)) }
            l.stroke(path, with: paint.shading, style: style)
        }
    }

    static func stroke(_ c: GraphicsContext, _ path: Path, _ color: CarromColor, _ width: CGFloat, cap: CGLineCap = .butt,
                       join: CGLineJoin = .miter, dash: [CGFloat] = [], shadow: CarromShadow? = nil, blur: CGFloat = 0) {
        stroke(c, path, .solid(color), width, cap: cap, join: join, dash: dash, shadow: shadow, blur: blur)
    }

    static func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
        return p
    }

    static func arcPath(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ start: Double, _ end: Double) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        return p
    }

    static func roundRect(_ r: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: r, cornerRadius: radius, style: .circular)
    }
}

/// Everything about the board and pieces that's drawn in code.
enum CarromArt {
    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        let rr = Swift.max(r, 0)
        return Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: 2 * rr, height: 2 * rr))
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path { circle(c.x, c.y, r) }

    static func star(_ cx: CGFloat, _ cy: CGFloat, _ points: Int, _ outer: CGFloat, _ inner: CGFloat, _ rotation: Double = -Double.pi / 2) -> Path {
        var p = Path()
        for i in 0..<(2 * points) {
            let r = i % 2 == 0 ? outer : inner
            let a = rotation + Double(i) * Double.pi / Double(points)
            let q = CGPoint(x: cx + r * CGFloat(Foundation.cos(a)), y: cy + r * CGFloat(Foundation.sin(a)))
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }

    static func petal(_ cx: CGFloat, _ cy: CGFloat, _ angle: Double, _ from: CGFloat, _ to: CGFloat, _ width: CGFloat) -> Path {
        var p = Path()
        let dx = CGFloat(Foundation.cos(angle))
        let dy = CGFloat(Foundation.sin(angle))
        let nx = -dy
        let ny = dx
        let a = CGPoint(x: cx + dx * from, y: cy + dy * from)
        let b = CGPoint(x: cx + dx * to, y: cy + dy * to)
        let mid = (from + to) / 2
        p.move(to: a)
        p.addQuadCurve(to: b, control: CGPoint(x: cx + dx * mid + nx * width, y: cy + dy * mid + ny * width))
        p.addQuadCurve(to: a, control: CGPoint(x: cx + dx * mid - nx * width, y: cy + dy * mid - ny * width))
        p.closeSubpath()
        return p
    }

    private static func grain(_ c: GraphicsContext, _ r: CGRect, _ color: CarromColor, _ seed: UInt64, _ count: Int, _ u: CGFloat) {
        var rng = CarromRandom(seed)
        for i in 0..<count {
            var p = Path()
            let y0 = r.minY + (CGFloat(i) + CGFloat(Float(rng.unit()))) * r.height / CGFloat(count)
            let amp = CGFloat(Float(0.6 + rng.unit() * 2.4)) * r.width / 320
            let freq = CGFloat(Float(0.008 + rng.unit() * 0.02)) * 320 / r.width
            let phase = CGFloat(Float(rng.unit() * 6))
            p.move(to: CGPoint(x: r.minX, y: y0))
            var x = r.minX
            let stepX = Swift.max(2 * u, r.width / 90)
            while x <= r.maxX + stepX {
                p.addLine(to: CGPoint(x: x, y: y0 + amp * CGFloat(Foundation.sin(Double(x * freq + phase)))))
                x += stepX
            }
            let alpha = Double(Float(0.4 + rng.unit() * 0.6))
            let width = CGFloat(Float(0.4 + rng.unit())) * Swift.max(0.6 * u, r.width / 300)
            CarromDraw.stroke(c, p, color.opacity(alpha), width)
        }
    }

    private static func rotated(_ p: Path, _ cx: CGFloat, _ cy: CGFloat, _ angle: Double) -> Path {
        let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: CGFloat(angle)).translatedBy(x: -cx, y: -cy)
        return p.applying(t)
    }

    // MARK: Board

    static func drawBoard(_ c: GraphicsContext, _ m: CarromMetrics, _ t: CarromBoardTheme) {
        let u = m.u
        let rect = CGRect(x: 0, y: 0, width: m.width, height: m.height)
        let fw = m.frame
        let outer = CarromDraw.roundRect(rect, fw * 0.9)
        CarromDraw.fill(c, outer, .linear(rect.minX, rect.minY, rect.maxX, rect.maxY, t.frame))
        var ring = outer
        ring.addRect(m.surface)
        do {
            var g = c
            g.clip(to: ring, style: FillStyle(eoFill: true))
            if t.neon {
                let inset = rect.insetBy(dx: fw * 0.5, dy: fw * 0.5)
                CarromDraw.stroke(g, CarromDraw.roundRect(inset, fw * 0.5), t.line.opacity(0.35), Swift.max(u, fw * 0.06))
            } else {
                grain(g, rect, t.frame[1], 3, 46, u)
            }
            let edge = rect.insetBy(dx: 1.5 * u, dy: 1.5 * u)
            CarromDraw.stroke(
                g, CarromDraw.roundRect(edge, fw * 0.85),
                .linear(rect.minX, rect.minY, rect.minX, rect.maxY, [CarromColor.white.opacity(0.55), CarromColor.white.opacity(0.05)]),
                Swift.max(u, fw * 0.1)
            )
        }

        // Corner caps, like brass corners on a club board.
        for k in 0..<4 {
            var b = Path()
            let inset = fw * 0.22
            let len = fw * 2.9
            b.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset + len))
            b.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            b.addLine(to: CGPoint(x: rect.minX + inset + len, y: rect.minY + inset))
            let path = rotated(b, rect.midX, rect.midY, Double(k) * Double.pi / 2)
            let glow = t.neon ? CarromShadow(t.cap.opacity(0.9), fw * 0.4) : nil
            CarromDraw.stroke(c, path, CarromColor.black.opacity(0.35), fw * 0.56, cap: .round, join: .round, shadow: glow)
            CarromDraw.stroke(
                c, path,
                .linear(rect.minX, rect.minY, rect.maxX, rect.maxY, [t.cap.mix(.white, 0.35), t.cap, t.cap.mix(.black, 0.25)]),
                fw * 0.44, cap: .round, join: .round, shadow: glow
            )
        }

        // The playing surface.
        let sr = m.surface
        let cx = sr.midX
        let cy = sr.midY
        CarromDraw.fill(c, Path(sr), .linear(sr.minX, sr.minY, sr.maxX, sr.maxY, t.surface))
        do {
            var g = c
            g.clip(to: Path(sr))
            if t.neon {
                var grid = Path()
                var x = sr.minX
                while x < sr.maxX { grid.move(to: CGPoint(x: x, y: sr.minY)); grid.addLine(to: CGPoint(x: x, y: sr.maxY)); x += m.len(4.0) }
                var y = sr.minY
                while y < sr.maxY { grid.move(to: CGPoint(x: sr.minX, y: y)); grid.addLine(to: CGPoint(x: sr.maxX, y: y)); y += m.len(4.0) }
                CarromDraw.stroke(g, grid, t.grain.opacity(0.6), 0.6 * u)
            } else {
                grain(g, sr, t.grain.opacity(0.3), 9, 84, u)
            }
            CarromDraw.fill(g, Path(sr), .radial(cx - m.len(8.0), cy - m.len(10.0), [CarromColor.white.opacity(t.neon ? 0.08 : 0.28), .transparent], sr.width * 0.62))
            CarromDraw.fill(g, Path(sr), .radial(cx, cy, [.transparent, CarromColor.black.opacity(t.neon ? 0.35 : 0.2)], sr.width * 0.78, sr.width * 0.3))
            markings(g, m, t)
            CarromDraw.stroke(g, Path(sr), CarromColor.black.opacity(0.4), fw * 0.3)
        }

        // Pockets.
        for p in CarromBoard.pockets {
            let pc = m.pt(p)
            let r = m.len(CarromBoard.pocketR)
            CarromDraw.fill(c, circle(pc, r * 1.17), t.neon ? t.line.opacity(0.85) : t.frame[1].mix(.black, 0.45))
            let ox: CGFloat = p.x < 0 ? -1 : 1
            let oy: CGFloat = p.y < 0 ? -1 : 1
            CarromDraw.fill(c, circle(pc, r), .radial(pc.x + ox * r * 0.35, pc.y + oy * r * 0.35, [CarromColor(0x000000), CarromColor(0x0B0B0B), CarromColor(0x262626)], r * 1.5))
            let back = Foundation.atan2(-p.y, -p.x)
            CarromDraw.stroke(c, CarromDraw.arcPath(pc.x, pc.y, r * 0.86, back - 0.9, back + 0.9), CarromColor.white.opacity(0.16), r * 0.12)
        }
    }

    private static func markings(_ c: GraphicsContext, _ m: CarromMetrics, _ t: CarromBoardTheme) {
        let u = m.u
        let glow = t.neon ? CarromShadow(t.line.opacity(0.95), m.len(0.7)) : nil
        let ink = t.line
        for k in 0..<4 {
            let rot = CarromBoard.rotation(k)
            func p(_ x: Double, _ y: Double) -> CGPoint { m.pt(CarromVec(x, y).rotated(rot)) }
            var thick = Path()
            thick.move(to: p(-CarromBoard.slideMax, CarromBoard.baseOuter))
            thick.addLine(to: p(CarromBoard.slideMax, CarromBoard.baseOuter))
            CarromDraw.stroke(c, thick, ink, Swift.max(u, m.len(0.55)), shadow: glow)
            var thin = Path()
            thin.move(to: p(-CarromBoard.slideMax, CarromBoard.baseInner))
            thin.addLine(to: p(CarromBoard.slideMax, CarromBoard.baseInner))
            CarromDraw.stroke(c, thin, ink, Swift.max(0.6 * u, m.len(0.2)), shadow: glow)
            for sx in [-1.0, 1.0] {
                let cc = p(sx * CarromBoard.slideMax, CarromBoard.baseY)
                let br = m.len(CarromBoard.baseCircleR)
                CarromDraw.fill(c, circle(cc, br), t.surface[0], shadow: glow)
                CarromDraw.stroke(c, circle(cc, br), ink, Swift.max(0.6 * u, m.len(0.2)), shadow: glow)
                CarromDraw.fill(c, circle(cc, m.len(1.27 * CarromBoard.pieceScale)), .radial(cc.x, cc.y, [t.circle.mix(.white, 0.25), t.circle], m.len(1.4)), shadow: glow)
            }
        }
        // Corner arrows: 45°, through the gap between base circles, stopping 5 cm short of the pocket.
        for pk in CarromBoard.pockets {
            let uv = pk.normalized
            let b = pk - uv * (CarromBoard.pocketR + 5)
            let a = b - uv * 25.7
            var line = Path()
            line.move(to: m.pt(a))
            line.addLine(to: m.pt(b))
            for side in [-1.0, 1.0] {
                line.move(to: m.pt(b))
                line.addLine(to: m.pt(b - uv.rotated(side * 0.45) * 1.6))
            }
            CarromDraw.stroke(c, line, ink, Swift.max(0.8 * u, m.len(0.22)), cap: .round, shadow: glow)
            let back = Foundation.atan2(-uv.y, -uv.x)
            let ac = m.pt(a + uv * 1.2)
            CarromDraw.stroke(c, CarromDraw.arcPath(ac.x, ac.y, m.len(3.175), back - 1.15, back + 1.15), ink, Swift.max(0.8 * u, m.len(0.2)), cap: .round, shadow: glow)
        }
        let cc = m.pt(CarromVec.ZERO)
        centreArt(c, cc.x, cc.y, m.len(CarromBoard.outerR), t, glow, u)
        CarromDraw.stroke(c, circle(cc, m.len(CarromBoard.outerR)), ink, Swift.max(0.8 * u, m.len(0.22)), shadow: glow)
        CarromDraw.fill(c, circle(cc, m.len(CarromBoard.centreR)), t.circle, shadow: glow)
        CarromDraw.stroke(c, circle(cc, m.len(CarromBoard.centreR)), ink, Swift.max(0.6 * u, m.len(0.18)), shadow: glow)
    }

    private static func centreArt(_ g: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ R: CGFloat, _ t: CarromBoardTheme, _ glow: CarromShadow?, _ u: CGFloat) {
        let ink = t.line
        let w = Swift.max(0.6 * u, R / 18)
        switch t.centre {
        case .COMPASS:
            CarromDraw.fill(g, star(cx, cy, 4, R * 0.92, R * 0.2), ink.opacity(0.75), shadow: glow)
            CarromDraw.fill(g, star(cx, cy, 4, R * 0.6, R * 0.16, -Double.pi / 4), t.circle.opacity(0.8), shadow: glow)
            CarromDraw.stroke(g, circle(cx, cy, R * 0.7), ink.opacity(0.5), w, shadow: glow)
        case .MANDALA:
            for i in 0..<16 { CarromDraw.stroke(g, petal(cx, cy, Double(i) * Double.pi / 8, R * 0.25, R * 0.92, R * 0.13), ink.opacity(0.6), w, shadow: glow) }
            for i in 0..<8 { CarromDraw.fill(g, petal(cx, cy, Double(i) * Double.pi / 4 + Double.pi / 8, R * 0.2, R * 0.6, R * 0.1), t.circle.opacity(0.55), shadow: glow) }
            CarromDraw.stroke(g, circle(cx, cy, R * 0.3), ink.opacity(0.6), w, shadow: glow)
        case .STAR:
            CarromDraw.stroke(g, star(cx, cy, 12, R * 0.92, R * 0.62), ink.opacity(0.7), w, shadow: glow)
            CarromDraw.stroke(g, star(cx, cy, 6, R * 0.6, R * 0.34), ink.opacity(0.6), w, shadow: glow)
            CarromDraw.stroke(g, circle(cx, cy, R * 0.36), ink.opacity(0.4), w, shadow: glow)
        case .RANGOLI:
            let colours = [CarromColor(0xF26B1D), CarromColor(0xE5177B), CarromColor(0xF6C315), CarromColor(0x2BB673), CarromColor(0x2D7FE0)]
            for i in 0..<12 { CarromDraw.fill(g, petal(cx, cy, Double(i) * Double.pi / 6, R * 0.3, R * 0.95, R * 0.16), colours[i % 5].opacity(0.75), shadow: glow) }
            for i in 0..<12 { CarromDraw.fill(g, petal(cx, cy, Double(i) * Double.pi / 6 + Double.pi / 12, R * 0.22, R * 0.6, R * 0.09), colours[(i + 2) % 5].opacity(0.85), shadow: glow) }
            for i in 0..<24 {
                let a = Double(i) * Double.pi / 12
                CarromDraw.fill(g, circle(cx + R * 0.98 * CGFloat(Foundation.cos(a)), cy + R * 0.98 * CGFloat(Foundation.sin(a)), R * 0.04), CarromColor.white.opacity(0.9), shadow: glow)
            }
        case .PULSE:
            for i in 1...4 {
                CarromDraw.stroke(g, circle(cx, cy, R * CGFloat(i) * 0.23), (i % 2 == 0 ? t.circle : ink).opacity(0.7), w, shadow: glow)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: cx - R, y: cy)); cross.addLine(to: CGPoint(x: cx + R, y: cy))
            cross.move(to: CGPoint(x: cx, y: cy - R)); cross.addLine(to: CGPoint(x: cx, y: cy + R))
            CarromDraw.stroke(g, cross, ink.opacity(0.45), w * 0.8, shadow: glow)
        case .PEACOCK:
            for i in 0..<8 {
                let a = Double(i) * Double.pi / 4
                CarromDraw.fill(g, petal(cx, cy, a, R * 0.25, R * 0.95, R * 0.2), CarromColor(0x1E4FB8).opacity(0.55), shadow: glow)
                CarromDraw.fill(g, petal(cx, cy, a, R * 0.45, R * 0.85, R * 0.1), CarromColor(0x2E9C6A).opacity(0.75), shadow: glow)
                CarromDraw.fill(g, circle(cx + R * 0.66 * CGFloat(Foundation.cos(a)), cy + R * 0.66 * CGFloat(Foundation.sin(a)), R * 0.07), CarromColor(0xEDBB40), shadow: glow)
            }
        case .SUN:
            CarromDraw.fill(g, star(cx, cy, 16, R * 0.95, R * 0.6), t.circle.opacity(0.45), shadow: glow)
            CarromDraw.fill(g, circle(cx, cy, R * 0.55), CarromColor(0xFFC65E).opacity(0.55), shadow: glow)
            CarromDraw.stroke(g, circle(cx, cy, R * 0.55), ink.opacity(0.55), w, shadow: glow)
        case .CANDY:
            for i in 0..<10 {
                let a0 = Double(i) * Double.pi / 5
                var slice = CarromDraw.arcPath(cx, cy, R * 0.9, a0, a0 + Double.pi / 5)
                slice.addLine(to: CGPoint(x: cx, y: cy))
                slice.closeSubpath()
                CarromDraw.fill(g, slice, (i % 2 == 0 ? CarromColor(0xFF8CC6) : CarromColor.white).opacity(0.8), shadow: glow)
            }
            CarromDraw.stroke(g, circle(cx, cy, R * 0.9), ink.opacity(0.6), w, shadow: glow)
        }
    }

    // MARK: Pieces

    /// A thick disc seen from above: soft shadow, visible edge, shaded face, motif, rim and gloss.
    static func puck(_ c: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ light: CarromColor, _ body: CarromColor, _ shade: CarromColor,
                     _ glow: CarromColor?, _ u: CGFloat, _ motif: (GraphicsContext) -> Void) {
        CarromDraw.fill(c, circle(cx + r * 0.16, cy + r * 0.32, r), CarromColor.black.opacity(0.45), blur: r * 0.28)
        if let glow { CarromDraw.fill(c, circle(cx, cy, r * 1.1), glow.opacity(0.9), blur: r * 0.55) }
        CarromDraw.fill(c, circle(cx, cy + r * 0.17, r), shade.mix(.black, 0.3))
        CarromDraw.fill(c, circle(cx, cy, r), .radial(cx - r * 0.35, cy - r * 0.42, [light, body, shade], r * 1.55))
        do {
            var g = c
            g.clip(to: circle(cx, cy, r * 0.96))
            motif(g)
        }
        CarromDraw.stroke(c, circle(cx, cy, r * 0.97), CarromColor.black.opacity(0.28), Swift.max(0.5 * u, r * 0.07))
        CarromDraw.stroke(c, CarromDraw.arcPath(cx, cy, r * 0.76, 196 * Double.pi / 180, 288 * Double.pi / 180), CarromColor.white.opacity(0.6), r * 0.13, cap: .round)
    }

    static func drawCoin(_ c: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ kind: CarromKind, _ set: CarromCoinSet, _ u: CGFloat, _ glow: CarromColor? = nil) {
        let face = set.face(kind)
        let ink = face.ink
        let neonGlow = set.motif == .NEON ? ink.opacity(0.7) : nil
        puck(c, cx, cy, r, face.light, face.body, face.shade, glow ?? neonGlow, u) { g in
            let w = Swift.max(0.5 * u, r * 0.08)
            switch set.motif {
            case .RINGS:
                CarromDraw.stroke(g, circle(cx, cy, r * 0.72), ink.opacity(0.7), w)
                CarromDraw.stroke(g, circle(cx, cy, r * 0.42), ink.opacity(0.55), w * 0.8)
                if kind == .QUEEN { CarromDraw.fill(g, star(cx, cy, 5, r * 0.3, r * 0.13), CarromColor(0xFFE08A)) }
            case .MANDALA:
                for i in 0..<8 { CarromDraw.stroke(g, petal(cx, cy, Double(i) * Double.pi / 4, r * 0.18, r * 0.8, r * 0.16), ink.opacity(0.85), w * 0.75) }
                CarromDraw.fill(g, circle(cx, cy, r * 0.16), ink)
            case .FACETS:
                for i in 0..<8 {
                    let a = Double(i) * Double.pi / 4
                    CarromDraw.stroke(g, CarromDraw.line(cx, cy, cx + r * CGFloat(Foundation.cos(a)), cy + r * CGFloat(Foundation.sin(a))), ink.opacity(0.45), w * 0.6)
                }
                CarromDraw.fill(g, star(cx, cy, 8, r * 0.5, r * 0.46, 0.0), ink.opacity(0.3))
            case .PETALS:
                for i in 0..<6 { CarromDraw.fill(g, petal(cx, cy, Double(i) * Double.pi / 3 - Double.pi / 2, r * 0.1, r * 0.8, r * 0.22), ink.opacity(0.55)) }
                CarromDraw.fill(g, circle(cx, cy, r * 0.14), CarromColor(0xFFD24D))
            case .NEON:
                CarromDraw.stroke(g, circle(cx, cy, r * 0.7), ink, Swift.max(0.8 * u, r * 0.16))
                CarromDraw.fill(g, circle(cx, cy, r * 0.2), ink.opacity(0.9))
            case .SWIRL:
                var sp = Path()
                for i in 0...40 {
                    let a = Double(i) * 0.42
                    let rr = r * 0.05 + r * 0.8 * CGFloat(i) / 40
                    let q = CGPoint(x: cx + rr * CGFloat(Foundation.cos(a)), y: cy + rr * CGFloat(Foundation.sin(a)))
                    if i == 0 { sp.move(to: q) } else { sp.addLine(to: q) }
                }
                CarromDraw.stroke(g, sp, ink.opacity(0.9), Swift.max(0.6 * u, r * 0.16), cap: .round)
            case .STAR:
                CarromDraw.fill(g, star(cx, cy, 5, r * 0.6, r * 0.26), ink.opacity(0.9))
            case .VEINS:
                var rng = CarromRandom(UInt64(kind.ordinal) + 5)
                for _ in 0..<3 {
                    var v = Path()
                    let a = rng.unit() * Double.pi * 2
                    v.move(to: CGPoint(x: cx + r * CGFloat(Foundation.cos(a)), y: cy + r * CGFloat(Foundation.sin(a))))
                    let ctrlX = cx + r * CGFloat(rng.unit() - 0.5)
                    let ctrlY = cy + r * CGFloat(rng.unit() - 0.5)
                    v.addQuadCurve(to: CGPoint(x: cx - r * CGFloat(Foundation.cos(a + 0.7)), y: cy - r * CGFloat(Foundation.sin(a + 0.7))),
                                   control: CGPoint(x: ctrlX, y: ctrlY))
                    CarromDraw.stroke(g, v, ink.opacity(0.55), w * 0.75)
                }
            }
        }
    }

    static func drawStriker(_ c: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ st: CarromStrikerStyle, _ u: CGFloat) {
        let a = st.inkA
        let b = st.inkB
        puck(c, cx, cy, r, st.light, st.body, st.shade, st.emblem == .PULSE ? st.rim.opacity(0.7) : nil, u) { g in
            CarromDraw.stroke(g, circle(cx, cy, r * 0.84), st.rim, Swift.max(0.8 * u, r * 0.12))
            switch st.emblem {
            case .COMPASS:
                CarromDraw.fill(g, star(cx, cy, 4, r * 0.72, r * 0.16), a)
                CarromDraw.fill(g, star(cx, cy, 4, r * 0.5, r * 0.12, -Double.pi / 4), b)
            case .SUNWHEEL:
                for i in 0..<12 {
                    let an = Double(i) * Double.pi / 6
                    CarromDraw.stroke(g, CarromDraw.line(cx + r * 0.2 * CGFloat(Foundation.cos(an)), cy + r * 0.2 * CGFloat(Foundation.sin(an)),
                                                         cx + r * 0.7 * CGFloat(Foundation.cos(an)), cy + r * 0.7 * CGFloat(Foundation.sin(an))),
                                      a, Swift.max(0.6 * u, r * 0.08))
                }
                CarromDraw.fill(g, circle(cx, cy, r * 0.22), b)
            case .PETAL:
                for i in 0..<8 { CarromDraw.fill(g, petal(cx, cy, Double(i) * Double.pi / 4, r * 0.08, r * 0.72, r * 0.2), (i % 2 == 0 ? a : b).opacity(0.9)) }
                CarromDraw.fill(g, circle(cx, cy, r * 0.14), CarromColor(0xFFD24D))
            case .BOLT:
                CarromDraw.fill(g, polygon(cx, cy, r, [(0.12, -0.66), (-0.34, 0.08), (-0.02, 0.08), (-0.14, 0.66), (0.34, -0.12), (0.02, -0.12)]), a)
            case .PEACOCK:
                CarromDraw.fill(g, petal(cx, cy, -Double.pi / 2, -r * 0.6, r * 0.66, r * 0.55), CarromColor(0x2E9C6A))
                CarromDraw.fill(g, circle(cx, cy - r * 0.12, r * 0.32), b)
                CarromDraw.fill(g, circle(cx, cy - r * 0.12, r * 0.2), a)
            case .WAVE:
                for i in 0..<3 {
                    var w = Path()
                    let y = cy + r * (CGFloat(i) * 0.3 - 0.3)
                    w.move(to: CGPoint(x: cx - r * 0.62, y: y))
                    w.addCurve(to: CGPoint(x: cx + r * 0.62, y: y), control1: CGPoint(x: cx - r * 0.2, y: y - r * 0.24), control2: CGPoint(x: cx + r * 0.2, y: y + r * 0.24))
                    CarromDraw.stroke(g, w, i == 1 ? b : a, Swift.max(0.8 * u, r * 0.12), cap: .round)
                }
            case .CROWN:
                CarromDraw.fill(g, polygon(cx, cy, r, [(-0.5, 0.3), (-0.55, -0.3), (-0.26, -0.02), (0, -0.46), (0.26, -0.02), (0.55, -0.3), (0.5, 0.3)]), a)
                CarromDraw.fill(g, circle(cx, cy + r * 0.1, r * 0.08), CarromColor(0xE0115F))
            case .PULSE:
                for i in 1...3 { CarromDraw.stroke(g, circle(cx, cy, r * 0.22 * CGFloat(i)), i % 2 == 0 ? b : a, Swift.max(0.6 * u, r * 0.08)) }
            }
        }
    }

    private static func polygon(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        for (i, q) in pts.enumerated() {
            let pt = CGPoint(x: cx + q.0 * r, y: cy + q.1 * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Seconds on a monotonic clock; every time in the session and its drawing uses it.
func carromNow() -> Double { CACurrentMediaTime() }

/// Renders a GraphicsContext drawing into a bitmap at the device scale (the Android `Bitmap` + `Canvas` twin).
@MainActor
enum CarromRaster {
    static func image(width: CGFloat, height: CGFloat, scale: CGFloat, _ draw: @escaping (GraphicsContext, CGSize) -> Void) -> CGImage? {
        let w = Swift.max(1, width)
        let h = Swift.max(1, height)
        let view = Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, size in draw(ctx, size) }
            .frame(width: w, height: h)
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.isOpaque = false
        return r.cgImage
    }
}

/// The static board, drawn once per design and size into a bitmap, never while discs move.
@MainActor
enum CarromPlates {
    private static var cache: [String: CGImage] = [:]
    private static var order: [String] = []

    static func key(_ theme: CarromBoardTheme, _ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) -> String {
        "\(theme.id)-\(Int((width * scale).rounded()))-\(Int((height * scale).rounded()))"
    }

    /// A plate already rendered, without rendering (safe inside a view body).
    static func cached(_ theme: CarromBoardTheme, _ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) -> CGImage? {
        cache[key(theme, width, height, scale)]
    }

    static func plate(_ theme: CarromBoardTheme, _ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) -> CGImage? {
        let key = key(theme, width, height, scale)
        if let hit = cache[key] {
            if let i = order.firstIndex(of: key) { order.remove(at: i); order.append(key) }
            return hit
        }
        let image = CarromRaster.image(width: width, height: height, scale: scale) { c, size in
            CarromArt.drawBoard(c, CarromMetrics(size.width, size.height), theme)
        }
        if let image {
            cache[key] = image
            order.append(key)
            while order.count > 14 { cache.removeValue(forKey: order.removeFirst()) }
        }
        return image
    }
}

/// Pre-rendered pieces, so drawing 20 moving discs each frame stays cheap.
@MainActor
enum CarromSprites {
    /// A sprite covers this many radii either side of the centre (room for the shadow and glow).
    nonisolated static let PAD: CGFloat = 1.75

    private static var cache: [String: CGImage] = [:]

    static func coinKey(_ kind: CarromKind, _ set: CarromCoinSet, _ radius: CGFloat, _ scale: CGFloat, glow: CarromColor? = nil) -> String {
        let g = glow.map { "\($0.r)-\($0.g)-\($0.b)-\($0.a)" } ?? "0"
        return "c\(set.id)-\(kind.ordinal)-\(Int(radius * 10))-\(Int(scale * 10))-\(g)"
    }

    static func strikerKey(_ style: CarromStrikerStyle, _ radius: CGFloat, _ scale: CGFloat) -> String {
        "s\(style.id)-\(Int(radius * 10))-\(Int(scale * 10))"
    }

    /// A sprite already rendered, without rendering (safe inside a view body).
    static func cached(_ key: String) -> CGImage? { cache[key] }

    static func coin(_ kind: CarromKind, _ set: CarromCoinSet, _ radius: CGFloat, _ scale: CGFloat, glow: CarromColor? = nil) -> CGImage? {
        sprite(coinKey(kind, set, radius, scale, glow: glow), radius, scale) { c, x, y in
            CarromArt.drawCoin(c, x, y, radius, kind, set, 1, glow)
        }
    }

    static func striker(_ style: CarromStrikerStyle, _ radius: CGFloat, _ scale: CGFloat) -> CGImage? {
        sprite(strikerKey(style, radius, scale), radius, scale) { c, x, y in
            CarromArt.drawStriker(c, x, y, radius, style, 1)
        }
    }

    private static func sprite(_ key: String, _ r: CGFloat, _ scale: CGFloat, _ draw: @escaping (GraphicsContext, CGFloat, CGFloat) -> Void) -> CGImage? {
        if let hit = cache[key] { return hit }
        let side = Swift.max(1, r * PAD * 2)
        let image = CarromRaster.image(width: side, height: side, scale: scale) { c, size in draw(c, size.width / 2, size.height / 2) }
        if let image {
            if cache.count > 120 { cache.removeAll() }
            cache[key] = image
        }
        return image
    }

    /// Draws a sprite centred on (x, y), turned by [rotationDeg] and scaled, at [alpha].
    nonisolated static func draw(_ c: GraphicsContext, _ image: GraphicsContext.ResolvedImage?, _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat,
                     scale: CGFloat = 1, alpha: Double = 1, rotationDeg: Double = 0) {
        guard let image else { return }
        let r = radius * PAD * scale
        var g = c
        g.translateBy(x: x, y: y)
        if rotationDeg != 0 { g.rotate(by: .degrees(rotationDeg)) }
        let a = Swift.max(0, Swift.min(1, alpha))
        if a < 1 { g.opacity = a }
        g.draw(image, in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
    }
}
