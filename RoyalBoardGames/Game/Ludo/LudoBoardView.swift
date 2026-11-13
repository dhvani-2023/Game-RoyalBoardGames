import SwiftUI
import GameKit

// MARK: - Drawing helpers

/// CoreGraphics helpers for Ludo's pre-rendered art (board plates, token sprites, glows).
/// Every image is drawn in points with a y-down transform into a bitmap at the device scale, so
/// shadow and blur sizes are given to CoreGraphics in pixels (its base space), like Android's Paint.
enum LudoCG {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Renders `draw` (y-down, in points) into a `width`×`height` point image at `scale`.
    static func image(_ width: CGFloat, _ height: CGFloat, _ scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        let pw = max(1, Int((width * scale).rounded(.up)))
        let ph = max(1, Int((height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    static func polygon(_ points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        for (i, q) in points.enumerated() { if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
        p.closeSubpath()
        return p
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil) }

    static func fill(_ g: CGContext, _ path: CGPath, _ color: LudoColor) {
        g.addPath(path)
        g.setFillColor(color.cg)
        g.fillPath()
    }

    static func stroke(_ g: CGContext, _ path: CGPath, _ color: LudoColor, _ width: CGFloat, join: CGLineJoin = .miter, cap: CGLineCap = .butt) {
        g.addPath(path)
        g.setStrokeColor(color.cg)
        g.setLineWidth(width)
        g.setLineJoin(join)
        g.setLineCap(cap)
        g.strokePath()
    }

    private static func gradient(_ colors: [LudoColor]) -> CGGradient {
        CGGradient(colorsSpace: sRGB, colors: colors.map(\.cg) as CFArray, locations: nil)!
    }

    /// Compose `Brush.linearGradient(colors, start, end)` (clamped at both ends).
    static func fillLinear(_ g: CGContext, _ path: CGPath, _ colors: [LudoColor], _ start: CGPoint, _ end: CGPoint) {
        g.saveGState()
        g.addPath(path)
        g.clip()
        g.drawLinearGradient(gradient(colors), start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        g.restoreGState()
    }

    /// Compose `Brush.radialGradient(colors, center, radius)` (clamped outside the radius).
    static func fillRadial(_ g: CGContext, _ path: CGPath, _ colors: [LudoColor], _ center: CGPoint, _ radius: CGFloat) {
        g.saveGState()
        g.addPath(path)
        g.clip()
        g.drawRadialGradient(gradient(colors), startCenter: center, startRadius: 0, endCenter: center, endRadius: max(radius, 0.01),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        g.restoreGState()
    }

    /// Android blur radius (px) → CoreGraphics shadow blur (px): sigma = 0.57735·r + 0.5, blur = 2·sigma.
    static func shadowBlur(_ radiusPx: CGFloat) -> CGFloat { 2 * (0.57735 * radiusPx + 0.5) }

    /// `drawBlurred`: a blurred fill or stroke (`BlurMaskFilter`), drawn as an offset shadow so only the blur shows.
    static func blurred(_ g: CGContext, _ path: CGPath, _ color: LudoColor, _ blurPt: CGFloat, _ scale: CGFloat, strokeWidth: CGFloat? = nil) {
        if blurPt <= 0 { return }
        let away: CGFloat = 4096
        g.saveGState()
        g.setShadow(offset: CGSize(width: away * scale, height: 0), blur: shadowBlur(blurPt * scale), color: color.cg)
        g.translateBy(x: -away, y: 0)
        g.addPath(path)
        if let strokeWidth {
            g.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            g.setLineWidth(strokeWidth)
            g.setLineJoin(.round)
            g.strokePath()
        } else {
            g.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            g.fillPath()
        }
        g.restoreGState()
    }
}

extension LudoTransform {
    /// Kotlin `o(p)`: a board point on screen.
    func o(_ p: LPoint) -> CGPoint {
        let s = screen(p)
        return CGPoint(x: s.x, y: s.y)
    }

    /// Kotlin `path(points)`: a closed polygon of board points.
    func path(_ points: [LPoint]) -> CGPath { LudoCG.polygon(points.map(o)) }
}

/// Cubic-bezier easing (Compose `CubicBezierEasing`), e.g. FastOutSlowIn = (0.4, 0, 0.2, 1).
func ludoEase(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
    if t <= 0 { return 0 }
    if t >= 1 { return 1 }
    func bx(_ s: Double) -> Double { 3 * x1 * s * (1 - s) * (1 - s) + 3 * x2 * s * s * (1 - s) + s * s * s }
    func by(_ s: Double) -> Double { 3 * y1 * s * (1 - s) * (1 - s) + 3 * y2 * s * s * (1 - s) + s * s * s }
    var lo = 0.0, hi = 1.0
    for _ in 0..<40 {
        let mid = (lo + hi) / 2
        if bx(mid) < t { lo = mid } else { hi = mid }
    }
    return by((lo + hi) / 2)
}

// MARK: - Board plate

/// Pre-rendered art (board plates, yard glows), rendered once off the main thread and kept by key.
@MainActor
final class LudoImageCache {
    static let shared = LudoImageCache()

    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private var pending: [String: Task<CGImage?, Never>] = [:]

    func cached(_ key: String) -> CGImage? { images[key] }

    /// The image for `key`, drawing it with `make` on a background thread the first time.
    func render(_ key: String, _ make: @escaping @Sendable () -> CGImage?) async -> CGImage? {
        if let img = images[key] { return img }
        if let job = pending[key] { return await job.value }
        let job = Task.detached(priority: .userInitiated) { make() }
        pending[key] = job
        let img = await job.value
        pending[key] = nil
        if let img, images[key] == nil {
            images[key] = img
            order.append(key)
            if order.count > 24 { images[order.removeFirst()] = nil }
        }
        return img
    }

    /// Key of a board plate: design, board, turn, seats in play, size and scale.
    static func plateKey(_ geometry: LudoGeometry, _ theme: LudoTheme, _ shift: Int, _ armsInPlay: Set<Int>, _ size: CGSize, _ scale: CGFloat) -> String {
        "plate.\(theme.id).\(geometry.arms).\(shift).\(armsInPlay.sorted()).\(Int((size.width * 2).rounded())).\(Int((size.height * 2).rounded())).\(scale)"
    }
}

/// The static board: rim, yards, arms, safe stars, start arrows and the centre.
func drawLudoPlate(_ g: CGContext, _ t: LudoTransform, _ theme: LudoTheme, _ armsInPlay: Set<Int>, _ scale: CGFloat) {
    let geo = t.geometry
    let s = CGFloat(t.cell)
    let px = 1 / scale
    let plate = CGMutablePath()
    for k in 0..<geo.arms {
        plate.addPath(t.path(geo.yard(k)))
        for v in 0..<6 { for u in -1...1 { plate.addPath(t.path(geo.cellCorners(k, v, u))) } }
    }
    plate.addPath(t.path(geo.centreOutline))
    // Drop shadow under the whole plate.
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -s * 0.5 * scale), blur: LudoCG.shadowBlur(s * 0.9 * scale), color: LudoColor.Black.copy(alpha: 0.45).cg)
    LudoCG.fill(g, plate, theme.rim)
    g.restoreGState()
    LudoCG.stroke(g, plate, theme.rim, s * 0.6, join: .round)

    for k in 0..<geo.arms {
        let inPlay = armsInPlay.contains(k)
        let color = theme.color(k, geo.arms)
        // Yard.
        let yardPts = geo.yard(k)
        let yard = t.path(yardPts)
        let ya = inPlay ? 1.0 : 0.3
        LudoCG.fillLinear(g, yard, [color.copy(alpha: ya), color.mix(.Black, 0.28).copy(alpha: ya)], t.o(yardPts[0]), t.o(geo.yardCenter(k)))
        if !inPlay { LudoCG.fill(g, yard, theme.cell.copy(alpha: 0.35)) }
        let c = t.o(geo.yardCenter(k))
        let r = s * CGFloat(geo.yardPlateRadius)
        let plateColor = theme.yardPlate.copy(alpha: inPlay ? 1 : 0.55)
        if geo.arms == 4 {
            LudoCG.fill(g, CGPath(roundedRect: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), cornerWidth: r * 0.3, cornerHeight: r * 0.3, transform: nil), plateColor)
        } else {
            LudoCG.fill(g, LudoCG.circle(c, r), plateColor)
        }
        for token in 0..<4 {
            let q = t.o(geo.yardSpot(k, token))
            let rr = s * 0.42
            LudoCG.fill(g, LudoCG.circle(q, rr), color.copy(alpha: inPlay ? 0.85 : 0.25))
            LudoCG.stroke(g, LudoCG.circle(q, rr), LudoColor.Black.copy(alpha: 0.08), px)
        }
        if theme.glow { LudoCG.stroke(g, yard, color.copy(alpha: inPlay ? 0.85 : 0.2), s * 0.12) }

        // Arm cells.
        for v in 0..<6 {
            for u in -1...1 {
                let cell = t.path(geo.cellCorners(k, v, u))
                let home = u == 0 && v <= 4
                let start = u == -1 && v == 4
                let tint = home || start
                LudoCG.fill(g, cell, tint ? color.copy(alpha: inPlay ? (theme.isDark ? 0.8 : 1) : 0.35) : theme.cell)
                LudoCG.stroke(g, cell, theme.glow && tint ? color.copy(alpha: inPlay ? 1 : 0.3) : theme.line,
                              theme.glow ? s * 0.06 : max(0.6 * px, s * 0.045))
            }
        }
        drawLudoStar(g, t.o(geo.point(k, 3.0, 1.0)), s * 0.36, theme.star, px)
        drawLudoStartArrow(g, t, k, LudoColor.White.copy(alpha: inPlay ? 0.95 : 0.5))
    }

    // Centre triangles, one per arm, then a hub.
    for k in 0..<geo.arms {
        let tri = geo.homeTriangle(k)
        let color = theme.color(k, geo.arms).copy(alpha: armsInPlay.contains(k) ? 1 : 0.4)
        LudoCG.fillLinear(g, t.path(tri), [color, color.mix(.Black, 0.22).copy(alpha: color.alpha)], t.o(tri[0]), t.o(LPoint.Zero))
    }
    let o = t.o(LPoint.Zero)
    LudoCG.fill(g, LudoCG.circle(o, s * 0.5), LudoColor.White.copy(alpha: 0.92))
    LudoCG.stroke(g, LudoCG.circle(o, s * 0.5), LudoColor.Black.copy(alpha: 0.1), px)
}

private func drawLudoStar(_ g: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: LudoColor, _ px: CGFloat) {
    var pts: [CGPoint] = []
    for i in 0..<10 {
        let a = Double(i) * Double.pi / 5 - Double.pi / 2
        let rr = i % 2 == 0 ? r : r * 0.45
        pts.append(CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr))
    }
    LudoCG.stroke(g, LudoCG.polygon(pts), color, max(0.9 * px, r * 0.17), join: .round)
}

/// The start square's arrow, pointing the way tokens leave (toward the centre).
private func drawLudoStartArrow(_ g: CGContext, _ t: LudoTransform, _ arm: Int, _ color: LudoColor) {
    let geo = t.geometry
    let s = CGFloat(t.cell)
    let c = t.o(geo.point(arm, 4.0, -1.0))
    let d = t.rotate(geo.direction(arm))
    let fx = CGFloat(-d.dx)
    let fy = CGFloat(-d.dy)
    let nx = -fy
    let ny = fx
    let path = LudoCG.polygon([
        CGPoint(x: c.x + fx * s * 0.3, y: c.y + fy * s * 0.3),
        CGPoint(x: c.x - fx * s * 0.2 + nx * s * 0.22, y: c.y - fy * s * 0.2 + ny * s * 0.22),
        CGPoint(x: c.x - fx * s * 0.2 - nx * s * 0.22, y: c.y - fy * s * 0.2 - ny * s * 0.22),
    ])
    LudoCG.fill(g, path, color)
}

/// The static board: rim, yards, arms, safe stars, start arrows and the centre (pre-rendered once per size and design,
/// off the main thread; the previous image stays up meanwhile).
struct LudoBoardPlate: View {
    let geometry: LudoGeometry
    let theme: LudoTheme
    let shift: Int
    let armsInPlay: Set<Int>

    @Environment(\.displayScale) private var scale
    @State private var shown: CGImage? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let key = LudoImageCache.plateKey(geometry, theme, shift, armsInPlay, size, scale)
            let img = LudoImageCache.shared.cached(key) ?? shown
            ZStack {
                if let img {
                    Image(decorative: img, scale: scale)
                        .resizable()
                        .interpolation(.high)
                }
            }
            .frame(width: size.width, height: size.height)
            .task(id: key) {
                guard size.width >= 1, size.height >= 1 else { return }
                let (g, theme, shift, arms, scale) = (geometry, theme, shift, armsInPlay, scale)
                let img = await LudoImageCache.shared.render(key) {
                    LudoCG.image(size.width, size.height, scale) { ctx in
                        drawLudoPlate(ctx, LudoTransform(g, shift, Double(size.width), Double(size.height)), theme, arms, scale)
                    }
                }
                if let img { shown = img }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tokens

/// Token bodies pre-rendered per design, colour and size; each frame only blits them.
@MainActor
final class LudoTokenSprites {
    static let shared = LudoTokenSprites()

    private struct Key: Hashable {
        let style: LudoTheme.TokenStyle
        let color: LudoColor
        let size: Int
        let scale: CGFloat
    }

    private var images: [Key: CGImage] = [:]

    /// The sprite covers ±`extent`·s around the token's origin.
    static let extent: CGFloat = 0.72

    func sprite(_ s: CGFloat, _ color: LudoColor, _ style: LudoTheme.TokenStyle, _ scale: CGFloat) -> CGImage? {
        let key = Key(style: style, color: color, size: Int((s * 4).rounded()), scale: scale)
        if let img = images[key] { return img }
        let side = s * Self.extent * 2
        let img = LudoCG.image(side, side, scale) { g in
            g.translateBy(x: side / 2, y: side / 2)
            drawLudoTokenBody(g, s, color, style, scale)
        }
        if let img {
            if images.count > 160 { images.removeAll() }
            images[key] = img
        }
        return img
    }
}

/// The pawn itself (everything Kotlin draws inside `withTransform`), around (0, 0).
func drawLudoTokenBody(_ g: CGContext, _ s: CGFloat, _ color: LudoColor, _ style: LudoTheme.TokenStyle, _ scale: CGFloat) {
    let px = 1 / scale
    let w = s * 0.78
    let h = s * 0.95
    let light = color.mix(.White, 0.3)
    let dark = color.mix(.Black, 0.32)
    if style == .CANDY {
        // A round candy drop with a swirl.
        let r = w * 0.52
        let center = CGPoint(x: 0, y: -h * 0.12)
        LudoCG.fillRadial(g, LudoCG.circle(center, r), [light, color, dark], CGPoint(x: -r * 0.3, y: -h * 0.12 - r * 0.4), r * 1.3)
        let swirl = CGMutablePath()
        // Compose arcTo(rect, 200°, 180°): clockwise on screen from 200°.
        swirl.addArc(center: center, radius: r * 0.55, startAngle: 200 * .pi / 180, endAngle: 380 * .pi / 180, clockwise: false)
        LudoCG.stroke(g, swirl, LudoColor.White.copy(alpha: 0.75), r * 0.18, cap: .round)
        LudoCG.stroke(g, LudoCG.circle(center, r), LudoColor.White.copy(alpha: 0.9), max(0.8 * px, s * 0.06))
        return
    }
    let base = CGMutablePath()
    base.move(to: CGPoint(x: -w * 0.5, y: h * 0.3))
    base.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.3), control: CGPoint(x: 0, y: h * 0.52))
    base.addLine(to: CGPoint(x: w * 0.2, y: -h * 0.1))
    base.addLine(to: CGPoint(x: -w * 0.2, y: -h * 0.1))
    base.closeSubpath()
    if style == .NEON {
        LudoCG.fill(g, base, ludoHex(0x15123A))
    } else {
        LudoCG.fillLinear(g, base, [light, dark], CGPoint(x: -w, y: 0), CGPoint(x: w, y: 0))
    }
    let outline: LudoColor
    switch style {
    case .NEON: outline = color
    case .GOLD: outline = ludoHex(0xF2CF6B)
    case .STONE: outline = ludoHex(0x3A2F1C).copy(alpha: 0.6)
    default: outline = LudoColor.White.copy(alpha: 0.9)
    }
    if style == .NEON { LudoCG.blurred(g, base, color, s * 0.08, scale, strokeWidth: s * 0.1) }
    LudoCG.stroke(g, base, outline, max(0.8 * px, s * (style == .GOLD ? 0.08 : 0.06)))
    if style == .GOLD {
        let line = CGMutablePath()
        line.move(to: CGPoint(x: -w * 0.34, y: h * 0.12))
        line.addLine(to: CGPoint(x: w * 0.34, y: h * 0.12))
        LudoCG.stroke(g, line, ludoHex(0xF2CF6B), max(0.8 * px, s * 0.07))
    }
    let hr = w * 0.36
    let hc = CGPoint(x: 0, y: -h * 0.22)
    let head = LudoCG.circle(hc, hr)
    switch style {
    case .PEARL:
        LudoCG.fillRadial(g, head, [.White, ludoHex(0xF4ECFF), ludoHex(0xC9C2D9)], CGPoint(x: -hr * 0.35, y: -h * 0.22 - hr * 0.4), hr * 1.3)
    case .NEON:
        LudoCG.fill(g, head, color)
        LudoCG.blurred(g, head, color.copy(alpha: 0.8), s * 0.12, scale)
    case .STONE:
        LudoCG.fillRadial(g, head, [color.mix(.White, 0.2), color, dark], CGPoint(x: -hr * 0.2, y: -h * 0.22 - hr * 0.2), hr * 1.2)
    default:
        LudoCG.fillRadial(g, head, [color.mix(.White, 0.55), color, dark], CGPoint(x: -hr * 0.35, y: -h * 0.22 - hr * 0.4), hr * 1.3)
    }
    LudoCG.stroke(g, head, outline, max(0.8 * px, s * 0.06))
    if style != .STONE {
        LudoCG.fill(g, CGPath(ellipseIn: CGRect(x: -hr * 0.55, y: -h * 0.22 - hr * 0.72, width: hr * 0.62, height: hr * 0.4), transform: nil),
                    LudoColor.White.copy(alpha: 0.75))
    }
}

/// Draws a pawn in a theme's material: its ground shadow, then the pre-rendered body lifted, squashed or spun.
@MainActor
func drawLudoToken(_ ctx: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ color: LudoColor, _ style: LudoTheme.TokenStyle, _ scale: CGFloat,
                   lift: CGFloat = 0, squash: CGFloat = 0, spin: Double = 0, alpha: Double = 1) {
    let w = s * 0.78
    let h = s * 0.95
    // Ground shadow stays on the square while the token lifts.
    let shadowScale = max(0.45, 1 - lift / (s * 1.6))
    ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.5 * shadowScale, y: c.y + h * 0.24, width: w * shadowScale, height: h * 0.24 * shadowScale)),
             with: .color(LudoColor.Black.copy(alpha: 0.3 * alpha).color))
    guard let sprite = LudoTokenSprites.shared.sprite(s, color, style, scale) else { return }
    var g = ctx
    g.translateBy(x: c.x, y: c.y - lift)
    if spin != 0 { g.rotate(by: .radians(spin)) }
    if squash != 0 { g.scaleBy(x: 1 + squash * 0.18, y: 1 - squash * 0.18) }
    if alpha < 1 { g.opacity = alpha }
    let e = s * LudoTokenSprites.extent
    g.draw(Image(decorative: sprite, scale: scale), in: CGRect(x: -e, y: -e, width: e * 2, height: e * 2))
}

/// Where every token rests, with tokens sharing a square fanned out: (point, scale).
func ludoRestingPoints(_ engine: LudoEngine, _ config: LudoConfig) -> [LudoTokenRef: (LPoint, Double)] {
    let g = engine.geometry
    var groupKeys: [String] = []
    var groups: [String: [LudoTokenRef]] = [:]
    var out: [LudoTokenRef: (LPoint, Double)] = [:]
    for seat in 0..<engine.seatCount {
        let arm = config.seats[seat].arm
        let home = engine.steps[seat].indices.filter { engine.steps[seat][$0] == g.homeStep }
        for token in engine.steps[seat].indices {
            let step = engine.steps[seat][token]
            let ref = LudoTokenRef(seat, token)
            if step < 0 {
                out[ref] = (g.yardSpot(arm, token), 1.0)
            } else if step == g.homeStep {
                let slot = max(home.firstIndex(of: token) ?? -1, 0)
                out[ref] = (g.homeSpot(arm, slot, home.count), 0.72)
            } else {
                let key = g.trackIndex(arm, step).map { "t\($0)" } ?? "l\(arm).\(step)"
                if groups[key] == nil { groupKeys.append(key); groups[key] = [] }
                groups[key]!.append(ref)
            }
        }
    }
    let fan: [[(Double, Double)]] = [
        [(0.0, 0.0)],
        [(-0.2, -0.08), (0.2, 0.08)],
        [(-0.22, 0.1), (0.22, 0.1), (0.0, -0.16)],
        [(-0.2, -0.16), (0.2, -0.16), (-0.2, 0.16), (0.2, 0.16)],
    ]
    for key in groupKeys {
        let refs = groups[key]!
        let first = refs[0]
        let base = g.routePoint(config.seats[first.seat].arm, engine.steps[first.seat][first.token])
        let pattern = fan[min(refs.count, 4) - 1]
        for (i, ref) in refs.enumerated() {
            let (ox, oy) = pattern[i % pattern.count]
            out[ref] = (LPoint(base.x + ox, base.y + oy), refs.count > 1 ? 0.76 : 1.0)
        }
    }
    return out
}

private func ludoRouteOrHome(_ g: LudoGeometry, _ arm: Int, _ step: Int) -> LPoint {
    step == g.homeStep ? g.homeSpot(arm, 0, 1) : g.routePoint(arm, step)
}

/// Tokens, move highlights, previews and effects, redrawn every frame only while something moves.
struct LudoTokenLayer: View {
    let session: LudoSession
    let theme: LudoTheme

    @Environment(\.displayScale) private var scale
    @State private var wake = 0

    var body: some View {
        // Read everything the drawing depends on here, so a change redraws even while the timeline is paused.
        let engine = session.engine
        let phase = session.phase
        let legal = session.legal
        let preview = session.preview
        let anims = session.anims
        let end = session.animationEnd
        let live = session.animating
        let reduceMotion = session.reduceMotion
        let config = session.config
        let scale = scale
        let _ = wake
        // Resting spots only change with the engine: sort them once (back to front), not every frame.
        let order = LudoTransform(engine.geometry, config.shift, 2, 2)
        let resting = ludoRestingPoints(engine, config).map { ($0.key, $0.value) }.sorted { order.screen($0.1.0).y < order.screen($1.1.0).y }
        TimelineView(.animation(minimumInterval: nil, paused: !live)) { timeline in
            // Captured inside the Canvas closure, or SwiftUI sees unchanged captures and skips the redraw.
            let tick = timeline.date
            Canvas { ctx, size in
                _ = tick
                drawLudoTokens(&ctx, size, config, engine, phase, legal, preview, anims, resting, reduceMotion, theme, ludoNow(), scale)
            }
        }
        .task(id: end) {
            // Wake once the last effect is over, so the timeline can pause.
            let wait = end - ludoNow()
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64((wait + 0.03) * 1e9))
                wake &+= 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private func drawLudoTokens(_ ctx: inout GraphicsContext, _ size: CGSize, _ config: LudoConfig, _ engine: LudoEngine, _ phase: LudoSession.Phase,
                            _ legal: [LudoMove], _ preview: LudoMove?, _ anims: [LudoAnim], _ resting: [(LudoTokenRef, (LPoint, Double))],
                            _ reduceMotion: Bool, _ theme: LudoTheme, _ now: Double, _ scale: CGFloat) {
    let g = engine.geometry
    let t = LudoTransform(g, config.shift, Double(size.width), Double(size.height))
    let s = CGFloat(t.cell)

    // Animated tokens are drawn on their own, not at their resting spot.
    func isMoving(_ ref: LudoTokenRef) -> Bool {
        for anim in anims where anim.isActive(now) {
            switch anim.kind {
            case let .Hop(seat, token, _, _): if seat == ref.seat && token == ref.token { return true }
            case let .Knock(seat, token, _, _): if seat == ref.seat && token == ref.token { return true }
            case .Burst: break
            }
        }
        return false
    }

    // Move highlights for the seat to play.
    var legalTokens = Set<Int>()
    if phase == .CHOOSE {
        for move in legal {
            if move.comesOut {
                for i in engine.steps[move.seat].indices where engine.steps[move.seat][i] < 0 { legalTokens.insert(i) }
            } else {
                legalTokens.insert(move.token)
            }
        }
    }
    let pulse = CGFloat(0.5 + 0.5 * sin(now * 6))

    // Preview of a held token's move.
    if let move = preview {
        let arm = config.seats[move.seat].arm
        var path = Path()
        let from = move.comesOut ? g.yardSpot(arm, move.token) : g.routePoint(arm, move.from)
        path.move(to: t.o(from))
        let lo = max(0, move.from + 1), hi = max(0, move.to)
        if lo <= hi { for step in lo...hi { path.addLine(to: t.o(ludoRouteOrHome(g, arm, step))) } }
        let end = t.o(ludoRouteOrHome(g, arm, move.to))
        let index = g.trackIndex(arm, move.to)
        let risky = index != nil && !engine.isSafe(index!) && LudoBot.threat(index!, move.seat, engine, exact: false) > 0
        let tint = move.captures.isEmpty ? (risky ? ludoHex(0xFF5C6E) : .White) : ludoHex(0xFFC94A)
        ctx.stroke(path, with: .color(tint.copy(alpha: 0.95).color),
                   style: StrokeStyle(lineWidth: s * 0.14, lineCap: .round, lineJoin: .round, dash: [0.1 / scale, s * 0.48]))
        ctx.stroke(Path(ellipseIn: CGRect(x: end.x - s * 0.48, y: end.y - s * 0.48, width: s * 0.96, height: s * 0.96)),
                   with: .color(tint.color), lineWidth: s * 0.12)
    }

    // Resting tokens, back to front so lower ones overlap upper ones.
    for (ref, placed) in resting where !isMoving(ref) {
        let arm = config.seats[ref.seat].arm
        let color = theme.color(arm, g.arms)
        let q = t.o(placed.0)
        var lift: CGFloat = 0
        if ref.seat == engine.current && legalTokens.contains(ref.token) {
            lift = s * 0.18 * pulse
            for (i, alpha) in [0.7, 0.3].enumerated() {
                let r = s * (0.5 + CGFloat(i) * 0.18 + 0.06 * pulse)
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y + s * 0.16 - r * 0.5, width: r * 2, height: r)),
                           with: .color((theme.isDark ? color : .White).copy(alpha: alpha).color), lineWidth: s * 0.08)
            }
        }
        drawLudoToken(&ctx, CGPoint(x: q.x, y: q.y - s * 0.08), s * CGFloat(placed.1), color, theme.token, scale, lift: lift)
    }

    // Moving tokens and effects.
    for anim in anims where anim.isActive(now) {
        let p = anim.progress(now)
        switch anim.kind {
        case let .Hop(seat, token, from, to):
            let arm = config.seats[seat].arm
            let color = theme.color(arm, g.arms)
            if from < 0 {
                // A big jump out of the yard onto the start square.
                let a = t.o(g.yardSpot(arm, token))
                let b = t.o(g.routePoint(arm, 0))
                let e = CGFloat(1 - pow(1 - p, 2))
                let q = CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
                drawLudoToken(&ctx, CGPoint(x: q.x, y: q.y - s * 0.08), s, color, theme.token, scale,
                              lift: CGFloat(sin(p * .pi)) * s * 1.3, squash: p > 0.9 ? CGFloat((1 - p) * 10 * 0.5) : 0)
            } else {
                let hops = Double(max(to - from, 1))
                let x = p * hops
                let i = min(Int(x), Int(hops) - 1)
                let f = x - Double(i)
                let a = t.o(ludoRouteOrHome(g, arm, from + i))
                let b = t.o(ludoRouteOrHome(g, arm, from + i + 1))
                let q = CGPoint(x: a.x + (b.x - a.x) * CGFloat(f), y: a.y + (b.y - a.y) * CGFloat(f))
                let squash: CGFloat = f > 0.85 ? CGFloat((f - 0.85) / 0.15 * 0.6) : (f < 0.12 ? CGFloat((1 - f / 0.12) * 0.4) : 0)
                drawLudoToken(&ctx, CGPoint(x: q.x, y: q.y - s * 0.08), s, color, theme.token, scale,
                              lift: CGFloat(sin(f * .pi)) * s * 0.55, squash: reduceMotion ? 0 : squash)
            }
        case let .Knock(seat, token, from, delay):
            let arm = config.seats[seat].arm
            let color = theme.color(arm, g.arms)
            let a = t.o(g.routePoint(arm, from))
            let b = t.o(g.yardSpot(arm, token))
            let elapsed = now - anim.start
            if elapsed < delay {
                drawLudoToken(&ctx, CGPoint(x: a.x, y: a.y - s * 0.08), s, color, theme.token, scale)
            } else {
                let kk = min(1.0, (elapsed - delay) / max(0.01, anim.duration - delay))
                let q = CGPoint(x: a.x + (b.x - a.x) * CGFloat(kk), y: a.y + (b.y - a.y) * CGFloat(kk))
                let arc: CGFloat = reduceMotion ? 0 : CGFloat(sin(kk * .pi)) * s * 3
                drawLudoToken(&ctx, CGPoint(x: q.x, y: q.y - s * 0.08), s, color, theme.token, scale,
                              lift: arc, spin: reduceMotion ? 0 : kk * 4 * .pi, alpha: reduceMotion ? 1 - kk * 0.3 : 1)
            }
        case let .Burst(at, arm, big):
            let color = theme.color(arm, g.arms)
            let c = t.o(at)
            let pf = CGFloat(p)
            let r = s * (0.4 + pf * (big ? 1.8 : 1.1))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(color.copy(alpha: Double(1 - pf)).color), lineWidth: max(0.001, s * 0.16 * (1 - pf)))
            let n = big ? 10 : 6
            var white = Path()
            var tinted = Path()
            let d0 = s * (0.4 + pf * 1.2)
            let d1 = d0 + s * 0.35 * (1 - pf)
            for j in 0..<n {
                let ang = Double(j) / Double(n) * 2 * .pi + 0.4
                let ca = CGFloat(cos(ang)), sa = CGFloat(sin(ang))
                if j % 2 == 0 {
                    white.move(to: CGPoint(x: c.x + ca * d0, y: c.y + sa * d0))
                    white.addLine(to: CGPoint(x: c.x + ca * d1, y: c.y + sa * d1))
                } else {
                    tinted.move(to: CGPoint(x: c.x + ca * d0, y: c.y + sa * d0))
                    tinted.addLine(to: CGPoint(x: c.x + ca * d1, y: c.y + sa * d1))
                }
            }
            let style = StrokeStyle(lineWidth: s * 0.1, lineCap: .round)
            ctx.stroke(white, with: .color(LudoColor.White.copy(alpha: Double(1 - pf)).color), style: style)
            ctx.stroke(tinted, with: .color(color.copy(alpha: Double(1 - pf)).color), style: style)
        }
    }
}

// MARK: - Active yard glow

/// The blurred ring around a yard, pre-rendered once per board size, arm and colour.
enum LudoYardGlow {
    static func key(_ geometry: LudoGeometry, _ shift: Int, _ arm: Int, _ color: LudoColor, _ size: CGSize, _ scale: CGFloat) -> String {
        "glow.\(geometry.arms).\(shift).\(arm).\(color.r).\(color.g).\(color.b).\(Int((size.width * 2).rounded())).\(Int((size.height * 2).rounded())).\(scale)"
    }

    /// Where the glow image sits on the board: the yard's bounds plus room for the blur.
    static func rect(_ geometry: LudoGeometry, _ shift: Int, _ arm: Int, _ size: CGSize) -> CGRect {
        let t = LudoTransform(geometry, shift, Double(size.width), Double(size.height))
        let pts = geometry.yard(arm).map(t.o)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let margin = CGFloat(t.cell) * 1.3
        return CGRect(x: xs.min()! - margin, y: ys.min()! - margin, width: xs.max()! - xs.min()! + margin * 2, height: ys.max()! - ys.min()! + margin * 2)
    }

    static func draw(_ geometry: LudoGeometry, _ shift: Int, _ arm: Int, _ color: LudoColor, _ size: CGSize, _ scale: CGFloat) -> CGImage? {
        let r = rect(geometry, shift, arm, size)
        return LudoCG.image(r.width, r.height, scale) { g in
            g.translateBy(x: -r.minX, y: -r.minY)
            let t = LudoTransform(geometry, shift, Double(size.width), Double(size.height))
            let yard = t.path(geometry.yard(arm))
            let cell = CGFloat(t.cell)
            LudoCG.blurred(g, yard, color, cell * 0.5, scale, strokeWidth: cell * 0.4)
            LudoCG.stroke(g, yard, .White, cell * 0.14)
        }
    }
}

// MARK: - Ambient

/// A light touch of life per design: shimmer, pulse, sprinkles, bubbles or fireflies.
struct LudoAmbientLayer: View {
    let theme: LudoTheme

    @State private var start = ludoNow()

    private static let sprinkleColors: [LudoColor] = [0xFFFFFF, 0xFF6B9A, 0xFFD45C, 0x6AB8FF, 0x6FD99A].map { ludoHex($0) }

    var body: some View {
        if theme.ambient != .NONE && !LocalReduceMotion.current {
            // About 30 frames a second is plenty for drifting particles.
            TimelineView(.animation(minimumInterval: 0.032, paused: false)) { timeline in
                let tick = timeline.date
                Canvas { ctx, size in
                    _ = tick
                    draw(&ctx, size, ludoNow() - start)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        for i in 0..<26 {
            let seed = Double((i * 7919) % 997) / 997
            let seed2 = Double((i * 104_729) % 991) / 991
            switch theme.ambient {
            case .BUBBLES:
                let speed = 18 + seed * 30
                let y = h - (t * speed + seed2 * h).truncatingRemainder(dividingBy: h + 40)
                let x = seed * w + sin(t * 1.2 + seed * 9) * 10
                let r = 2 + seed2 * 5
                ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.35)), lineWidth: 1)
            case .SPRINKLES:
                let speed = 14 + seed * 22
                let y = (t * speed + seed2 * h).truncatingRemainder(dividingBy: h + 20) - 10
                let x = seed * w
                var g = ctx
                g.translateBy(x: x, y: y)
                g.rotate(by: .radians((t * (0.5 + seed)) + seed * 6))
                g.fill(Path(roundedRect: CGRect(x: -4, y: -1.5, width: 8, height: 3), cornerRadius: 1.5),
                       with: .color(Self.sprinkleColors[i % Self.sprinkleColors.count].copy(alpha: 0.7).color))
            case .FIREFLIES:
                let x = (seed + sin(t * 0.13 + seed * 20) * 0.08) * w
                let y = (seed2 + cos(t * 0.11 + seed2 * 20) * 0.08) * h
                let glow = 0.3 + 0.7 * max(0.0, sin(t * 1.6 + seed * 12))
                let c = CGPoint(x: x, y: y)
                let col = ludoHex(0xE8F59A)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
                         with: .radialGradient(Gradient(colors: [col.copy(alpha: glow * 0.8).color, col.copy(alpha: glow * 0.35).color, .clear]),
                                               center: c, startRadius: 0, endRadius: 6))
            case .SHIMMER:
                let x = seed * w
                let y = seed2 * h
                let a = max(0.0, sin(t * 1.1 + seed * 14)) * 0.5
                var p = Path()
                p.move(to: CGPoint(x: x, y: y - 4))
                p.addLine(to: CGPoint(x: x, y: y + 4))
                p.move(to: CGPoint(x: x - 4, y: y))
                p.addLine(to: CGPoint(x: x + 4, y: y))
                ctx.stroke(p, with: .color(ludoHex(0xF2CF6B).copy(alpha: a).color), lineWidth: 1.2)
            case .PULSE:
                let x = seed * w
                let y = seed2 * h
                let a = max(0.0, sin(t * 0.8 + seed * 10)) * 0.35
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(ludoHex(0xC77DFF).copy(alpha: a).color))
            case .NONE:
                break
            }
        }
    }
}

/// A soft pattern of dice dots behind the table.
struct DiceDotPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 46
            let dot: CGFloat = 5
            var path = Path()
            var row = 0
            var y: CGFloat = 0
            while y <= size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : gap / 2
                while x <= size.width {
                    path.addEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                    x += gap
                }
                y += gap
                row += 1
            }
            ctx.fill(path, with: .color(.white.opacity(0.06)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Artwork

/// The Ludo card art: a tilted board with pawns and a bouncing die.
struct LudoArtwork: View {
    @Environment(\.displayScale) private var scale
    @State private var bob: Double = 0

    private static let geometry = LudoGeometry(4)
    private static let arms: Set<Int> = [0, 1, 2, 3]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                LudoBoardPlate(geometry: Self.geometry, theme: .classic, shift: 0, armsInPlay: Self.arms)
                    .frame(width: size * 0.92, height: size * 0.92)
                    // Compose rotationX = 24° with cameraDistance 3 (≈ 216 pt away).
                    .rotation3DEffect(.degrees(24), axis: (x: 1, y: 0, z: 0), perspective: max(0.1, size * 0.92 / 216))
                    .offset(y: size * 0.06)
                Canvas { ctx, sz in
                    let s = sz.width * 0.16
                    let pawns: [(CGFloat, CGFloat, UInt32)] = [(0.3, 0.42, 0xF0453A), (0.62, 0.36, 0x2DB45A), (0.5, 0.6, 0x2E8BEF)]
                    for (x, y, col) in pawns {
                        drawLudoToken(&ctx, CGPoint(x: sz.width * x, y: sz.height * y), s, ludoHex(col), .GLOSS, scale)
                    }
                }
                .frame(width: size, height: size)
                LudoDie(value: 6, rolling: false, landTick: 0, pip: ludoHex(0x7A1A14), size: size * 0.3)
                    .rotationEffect(.degrees(-12 * bob + 8 * (1 - bob)))
                    .offset(x: size * 0.36, y: size * 0.3 - 6 * bob)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear {
            if LocalReduceMotion.current { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.3).repeatForever(autoreverses: true)) { bob = 1 }
        }
        .accessibilityHidden(true)
    }
}
