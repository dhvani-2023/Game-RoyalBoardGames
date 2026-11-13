import SwiftUI
import UIKit

// Compose → SwiftUI glue shared by the design system and the shell: colour maths (Compose `lerp` works in Oklab),
// easing curves, closed-form springs for timeline-driven animation, and a small DrawScope-style Canvas helper.

// MARK: - Colour

extension Color {
    /// Compose `Color.White` etc.
    static let White = Color(argb: 0xFFFFFFFF)
    static let Black = Color(argb: 0xFF000000)
    static let Transparent = Color(argb: 0x00000000)
    static let Gray = Color(argb: 0xFF888888)
    static let DarkGray = Color(argb: 0xFF444444)
    static let LightGray = Color(argb: 0xFFCCCCCC)

    /// sRGB components 0…1 (r, g, b, a).
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// Compose `color.copy(alpha = x)`: sets (does not multiply) the alpha.
    func copy(alpha: Double) -> Color {
        let c = rgba
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: alpha)
    }

    func copy(alpha: Float) -> Color { copy(alpha: Double(alpha)) }
}

/// Compose `lerp(start, stop, fraction)` for colours: interpolates in Oklab, alpha linearly. Results are memoized.
func lerp(_ start: Color, _ stop: Color, _ fraction: Float) -> Color {
    OklabMath.cached(start, stop, Double(fraction))
}

func lerp(_ start: Color, _ stop: Color, _ fraction: Double) -> Color {
    OklabMath.cached(start, stop, fraction)
}

enum OklabMath {
    private struct Key: Hashable { let a: Color; let b: Color; let t: Double }
    private static let lock = NSLock()
    private static var memo: [Key: Color] = [:]

    static func cached(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let k = Key(a: a, b: b, t: t)
        lock.lock()
        if let c = memo[k] { lock.unlock(); return c }
        lock.unlock()
        let c = lerp(a.rgba, b.rgba, t)
        lock.lock()
        if memo.count > 4096 { memo.removeAll(keepingCapacity: true) }
        memo[k] = c
        lock.unlock()
        return c
    }

    private static func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func toSrgb(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    static func toLab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let lr = toLinear(r), lg = toLinear(g), lb = toLinear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func toRgb(_ L: Double, _ A: Double, _ B: Double) -> (Double, Double, Double) {
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (min(1, max(0, toSrgb(r))), min(1, max(0, toSrgb(g))), min(1, max(0, toSrgb(b))))
    }

    static func lerp(_ a: (r: Double, g: Double, b: Double, a: Double), _ b: (r: Double, g: Double, b: Double, a: Double), _ t: Double) -> Color {
        let la = toLab(a.r, a.g, a.b), lb = toLab(b.r, b.g, b.b)
        let L = la.0 + (lb.0 - la.0) * t
        let A = la.1 + (lb.1 - la.1) * t
        let B = la.2 + (lb.2 - la.2) * t
        let rgb = toRgb(L, A, B)
        return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: a.a + (b.a - a.a) * t)
    }
}

// MARK: - Shapes

/// Compose `RoundedCornerShape(r.dp)` (circular corners).
func RoundedCornerShape(_ radius: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .circular) }

// MARK: - Easing (Compose curves)

/// Compose `CubicBezierEasing(a, b, c, d)`.
struct CubicBezierEasing {
    let a: Double, b: Double, c: Double, d: Double
    init(_ a: Double, _ b: Double, _ c: Double, _ d: Double) { self.a = a; self.b = b; self.c = c; self.d = d }

    private func bez(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
        3 * p1 * (1 - t) * (1 - t) * t + 3 * p2 * (1 - t) * t * t + t * t * t
    }

    func transform(_ fraction: Double) -> Double {
        if fraction <= 0 { return 0 }
        if fraction >= 1 { return 1 }
        var lo = 0.0, hi = 1.0, t = fraction
        for _ in 0..<40 {
            let x = bez(a, c, t)
            if abs(x - fraction) < 1e-7 { break }
            if x < fraction { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(b, d, t)
    }

    /// The same curve as a SwiftUI animation.
    func animation(_ duration: Double) -> Animation { .timingCurve(a, b, c, d, duration: duration) }
}

enum Easing {
    static let FastOutSlowIn = CubicBezierEasing(0.4, 0.0, 0.2, 1.0)
    static let LinearOutSlowIn = CubicBezierEasing(0.0, 0.0, 0.2, 1.0)
    static let FastOutLinearIn = CubicBezierEasing(0.4, 0.0, 1.0, 1.0)
}

extension Animation {
    /// Compose `tween(ms)` (FastOutSlowIn).
    static func tween(_ ms: Int, delay: Int = 0) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: Double(ms) / 1000).delay(Double(delay) / 1000)
    }

    /// Compose `tween(ms, easing = LinearEasing)`.
    static func linearTween(_ ms: Int) -> Animation { .linear(duration: Double(ms) / 1000) }

    /// Compose `spring()` defaults (dampingRatio 1, stiffness 1500).
    static var composeDefaultSpring: Animation { .compose(dampingRatio: 1, stiffness: 1500) }
}

/// Closed-form Compose spring from 0 to 1 at rest, for timeline-driven drawing (splash, onboarding).
struct SpringCurve {
    let dampingRatio: Double
    let stiffness: Double

    init(dampingRatio: Double = 1, stiffness: Double = 1500) {
        self.dampingRatio = dampingRatio
        self.stiffness = stiffness
    }

    /// Value at `t` seconds after start (overshoots for dampingRatio < 1).
    func value(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        let w = stiffness.squareRoot()
        let z = dampingRatio
        if z < 1 {
            let wd = w * (1 - z * z).squareRoot()
            let e = exp(-z * w * t)
            return 1 - e * (cos(wd * t) + (z * w / wd) * sin(wd * t))
        } else if z == 1 {
            return 1 - exp(-w * t) * (1 + w * t)
        } else {
            let s = (z * z - 1).squareRoot()
            let r1 = -w * (z - s), r2 = -w * (z + s)
            let c2 = r1 / (r1 - r2)
            let c1 = 1 - c2
            return 1 - (c1 * exp(r1 * t) + c2 * exp(r2 * t))
        }
    }

    /// When the motion stays within Compose's 0.01 visibility threshold of the target.
    var settleTime: Double {
        let w = stiffness.squareRoot()
        let z = dampingRatio
        if z < 1 {
            let amp = 1 / (1 - z * z).squareRoot()
            return log(amp / 0.01) / (z * w)
        }
        var t = 0.0
        while t < 10 && abs(1 - value(t)) > 0.01 { t += 0.005 }
        return t
    }
}

// MARK: - Canvas (Compose DrawScope-style helpers)

/// Thin wrapper over `GraphicsContext` with Compose `DrawScope` call shapes (angles in degrees, clockwise).
struct RoyalDraw {
    var ctx: GraphicsContext
    let size: CGSize

    init(_ ctx: GraphicsContext, _ size: CGSize) {
        self.ctx = ctx
        self.size = size
    }

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var minDimension: CGFloat { min(size.width, size.height) }
    var maxDimension: CGFloat { max(size.width, size.height) }

    static func vertical(_ colors: [Color], _ startY: CGFloat, _ endY: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: startY), endPoint: CGPoint(x: 0, y: endY))
    }

    static func horizontal(_ colors: [Color], _ startX: CGFloat, _ endX: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: startX, y: 0), endPoint: CGPoint(x: endX, y: 0))
    }

    static func linear(_ colors: [Color], _ start: CGPoint, _ end: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: start, endPoint: end)
    }

    static func radial(_ colors: [Color], _ center: CGPoint, _ radius: CGFloat) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: colors), center: center, startRadius: 0, endRadius: max(0.0001, radius))
    }

    /// Compose `Brush.sweepGradient` (starts at 3 o'clock, clockwise).
    static func sweep(_ colors: [Color], _ center: CGPoint) -> GraphicsContext.Shading {
        .conicGradient(Gradient(colors: colors), center: center, angle: .zero)
    }

    func circle(_ shading: GraphicsContext.Shading, _ radius: CGFloat, _ center: CGPoint, stroke: CGFloat? = nil) {
        guard radius > 0 else { return }
        let p = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        if let stroke { ctx.stroke(p, with: shading, lineWidth: stroke) } else { ctx.fill(p, with: shading) }
    }

    func circle(_ color: Color, _ radius: CGFloat, _ center: CGPoint, stroke: CGFloat? = nil) {
        circle(.color(color), radius, center, stroke: stroke)
    }

    func oval(_ shading: GraphicsContext.Shading, _ topLeft: CGPoint, _ size: CGSize, stroke: CGFloat? = nil) {
        let p = Path(ellipseIn: CGRect(origin: topLeft, size: size))
        if let stroke { ctx.stroke(p, with: shading, lineWidth: stroke) } else { ctx.fill(p, with: shading) }
    }

    func oval(_ color: Color, _ topLeft: CGPoint, _ size: CGSize, stroke: CGFloat? = nil) {
        oval(.color(color), topLeft, size, stroke: stroke)
    }

    func rect(_ shading: GraphicsContext.Shading, _ topLeft: CGPoint = .zero, _ size: CGSize? = nil) {
        ctx.fill(Path(CGRect(origin: topLeft, size: size ?? self.size)), with: shading)
    }

    func roundRect(_ shading: GraphicsContext.Shading, _ topLeft: CGPoint, _ size: CGSize, _ corner: CGFloat, stroke: CGFloat? = nil) {
        let p = Path(roundedRect: CGRect(origin: topLeft, size: size), cornerRadius: corner, style: .circular)
        if let stroke { ctx.stroke(p, with: shading, lineWidth: stroke) } else { ctx.fill(p, with: shading) }
    }

    func roundRect(_ color: Color, _ topLeft: CGPoint, _ size: CGSize, _ corner: CGFloat, stroke: CGFloat? = nil) {
        roundRect(.color(color), topLeft, size, corner, stroke: stroke)
    }

    func line(_ shading: GraphicsContext.Shading, _ start: CGPoint, _ end: CGPoint, _ width: CGFloat, cap: CGLineCap = .butt) {
        var p = Path()
        p.move(to: start)
        p.addLine(to: end)
        ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: width, lineCap: cap))
    }

    func line(_ color: Color, _ start: CGPoint, _ end: CGPoint, _ width: CGFloat, cap: CGLineCap = .butt) {
        line(.color(color), start, end, width, cap: cap)
    }

    /// Compose `drawArc(startAngle, sweepAngle, useCenter, topLeft, size, style)`; degrees, 0 = 3 o'clock, clockwise.
    func arc(_ shading: GraphicsContext.Shading, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool,
             _ topLeft: CGPoint, _ size: CGSize, stroke: CGFloat? = nil, cap: CGLineCap = .butt) {
        let p = RoyalDraw.arcPath(startAngle, sweepAngle, useCenter, CGRect(origin: topLeft, size: size))
        if let stroke { ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: stroke, lineCap: cap)) } else { ctx.fill(p, with: shading) }
    }

    static func arcPath(_ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        // Elliptical arcs: draw a unit-circle arc scaled to the rect.
        let t = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: rx, y: ry)
        var unit = Path()
        if useCenter { unit.move(to: .zero) }
        unit.addRelativeArc(center: .zero, radius: 1, startAngle: .degrees(startAngle), delta: .degrees(sweepAngle))
        if useCenter { unit.closeSubpath() }
        p.addPath(unit, transform: t)
        return p
    }

    func path(_ path: Path, _ shading: GraphicsContext.Shading, stroke: CGFloat? = nil, join: CGLineJoin = .miter) {
        if let stroke { ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: stroke, lineJoin: join)) } else { ctx.fill(path, with: shading) }
    }

    func path(_ path: Path, _ color: Color, stroke: CGFloat? = nil, join: CGLineJoin = .miter) {
        self.path(path, .color(color), stroke: stroke, join: join)
    }

    /// Compose `rotate(degrees, pivot) { … }`.
    func rotated(_ degrees: Double, _ pivot: CGPoint, _ body: (RoyalDraw) -> Void) {
        var c = ctx
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .degrees(degrees))
        c.translateBy(x: -pivot.x, y: -pivot.y)
        body(RoyalDraw(c, size))
    }

    /// Compose `withTransform({ … })` / `translate` style scoped drawing.
    func scoped(_ transform: (inout GraphicsContext) -> Void, _ body: (RoyalDraw) -> Void) {
        var c = ctx
        transform(&c)
        body(RoyalDraw(c, size))
    }
}

// MARK: - Layout

/// Compose `Modifier.fillMaxWidth(fraction)`: proposes `fraction` of the offered width to its content,
/// reports the full offered width and the content's height, and aligns the content inside.
struct FractionWidthLayout: Layout {
    let fraction: CGFloat
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let h = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w * fraction, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cw = bounds.width * fraction
        let x: CGFloat
        switch alignment {
        case .trailing: x = bounds.maxX - cw
        case .center: x = bounds.minX + (bounds.width - cw) / 2
        default: x = bounds.minX
        }
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: cw, height: bounds.height))
            s.place(at: CGPoint(x: x, y: bounds.midY - sz.height / 2), proposal: ProposedViewSize(width: cw, height: sz.height))
        }
    }
}
