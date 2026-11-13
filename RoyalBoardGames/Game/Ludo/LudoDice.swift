import SwiftUI
import GameKit

/// Pip spots for each face, in unit face coordinates (from the reference die).
let ludoPips: [Int: [(Double, Double)]] = [
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
]

/// A 3D vector for the tumbling die (screen space: x right, y down, z toward the viewer).
struct LudoV3 {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func + (a: LudoV3, o: LudoV3) -> LudoV3 { LudoV3(a.x + o.x, a.y + o.y, a.z + o.z) }
    static func * (a: LudoV3, k: Double) -> LudoV3 { LudoV3(a.x * k, a.y * k, a.z * k) }
    func dot(_ o: LudoV3) -> Double { x * o.x + y * o.y + z * o.z }
}

struct LudoAngles: Equatable {
    var rx: Double
    var ry: Double
    var rz: Double

    init(_ rx: Double, _ ry: Double, _ rz: Double) {
        self.rx = rx
        self.ry = ry
        self.rz = rz
    }
}

/// The die's hand-written rotation matrices and face tables.
enum LudoDieMath {
    /// Rotation: y first, then x, then z (screen space: x right, y down, z toward the viewer).
    static func rotate(_ v: LudoV3, _ a: LudoAngles) -> LudoV3 {
        var x = v.x * cos(a.ry) + v.z * sin(a.ry)
        var z = -v.x * sin(a.ry) + v.z * cos(a.ry)
        var y = v.y
        let y2 = y * cos(a.rx) - z * sin(a.rx)
        let z2 = y * sin(a.rx) + z * cos(a.rx)
        y = y2; z = z2
        let x3 = x * cos(a.rz) - y * sin(a.rz)
        let y3 = x * sin(a.rz) + y * cos(a.rz)
        x = x3; y = y3
        return LudoV3(x, y, z)
    }

    static func unrotate(_ v: LudoV3, _ a: LudoAngles) -> LudoV3 {
        // Inverse order: z, then x, then y, each by the negative angle.
        var x = v.x * cos(-a.rz) - v.y * sin(-a.rz)
        var y = v.x * sin(-a.rz) + v.y * cos(-a.rz)
        var z = v.z
        let y2 = y * cos(-a.rx) - z * sin(-a.rx)
        let z2 = y * sin(-a.rx) + z * cos(-a.rx)
        y = y2; z = z2
        let x3 = x * cos(-a.ry) + z * sin(-a.ry)
        let z3 = -x * sin(-a.ry) + z * cos(-a.ry)
        x = x3; z = z3
        return LudoV3(x, y, z)
    }

    /// The six faces: outward normal and the face value (opposite faces add up to 7).
    static let faceNormals: [(Int, LudoV3)] = [
        (1, LudoV3(0.0, 0.0, 1.0)), (6, LudoV3(0.0, 0.0, -1.0)),
        (3, LudoV3(1.0, 0.0, 0.0)), (4, LudoV3(-1.0, 0.0, 0.0)),
        (2, LudoV3(0.0, -1.0, 0.0)), (5, LudoV3(0.0, 1.0, 0.0)),
    ]

    /// Angles that turn each face to the viewer.
    static let restAngles: [Int: LudoAngles] = [
        1: LudoAngles(0.0, 0.0, 0.0), 6: LudoAngles(0.0, .pi, 0.0),
        3: LudoAngles(0.0, -.pi / 2, 0.0), 4: LudoAngles(0.0, .pi / 2, 0.0),
        2: LudoAngles(-.pi / 2, 0.0, 0.0), 5: LudoAngles(.pi / 2, 0.0, 0.0),
    ]

    /// Each face's in-plane axes, chosen so the face reads upright once it faces the viewer.
    static let faceAxes: [Int: (LudoV3, LudoV3)] = {
        var out: [Int: (LudoV3, LudoV3)] = [:]
        for (value, _) in faceNormals {
            let a = restAngles[value]!
            out[value] = (unrotate(LudoV3(1.0, 0.0, 0.0), a), unrotate(LudoV3(0.0, 1.0, 0.0), a))
        }
        return out
    }()

    static func tumble(_ t: Double) -> LudoAngles { LudoAngles(t * 9.0 + 0.6, t * 12.5 + 0.3, t * 3.2) }

    static func nearestForward(_ from: Double, _ base: Double) -> Double {
        let turns = ((from - base) / (2 * .pi)).rounded(.up)
        return base + turns * 2 * .pi
    }

    static func lerpAngles(_ a: LudoAngles, _ b: LudoAngles, _ p: Double) -> LudoAngles {
        LudoAngles(a.rx + (b.rx - a.rx) * p, a.ry + (b.ry - a.ry) * p, a.rz + (b.rz - a.rz) * p)
    }

    static let lightDir: LudoV3 = {
        let v = LudoV3(-0.4, -0.6, 0.7)
        let n = v.dot(v).squareRoot()
        return LudoV3(v.x / n, v.y / n, v.z / n)
    }()

    static func pipColors(_ value: Int, _ pip: LudoColor) -> (LudoColor, LudoColor) {
        value == 6 ? (ludoHex(0xE8455B), ludoHex(0xB0182F)) : (pip.mix(.White, 0.2), pip)
    }

    /// Android `CornerPathEffect(radius)`: each corner is cut back by up to `radius` and joined with a quadratic curve.
    static func roundedPolygon(_ pts: [CGPoint], _ radius: CGFloat) -> Path {
        var path = Path()
        let n = pts.count
        guard n >= 3 else { return path }
        func toward(_ a: CGPoint, _ b: CGPoint, _ d: CGFloat) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max((dx * dx + dy * dy).squareRoot(), 0.0001)
            let k = min(d, len / 2) / len
            return CGPoint(x: a.x + dx * k, y: a.y + dy * k)
        }
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            let a = toward(cur, prev, radius)
            let b = toward(cur, next, radius)
            if i == 0 { path.move(to: a) } else { path.addLine(to: a) }
            path.addQuadCurve(to: b, control: cur)
        }
        path.closeSubpath()
        return path
    }
}

/// A die that tumbles in 3D while rolling, settles on its value and bounces when it lands.
/// At rest it draws the reference's flat face (rounded, glossy, radial pips).
struct LudoDie: View {
    let value: Int
    let rolling: Bool
    let landTick: Int
    let pip: LudoColor
    let size: CGFloat

    @State private var rollStart = ludoNow()
    @State private var settleFrom: LudoAngles? = nil
    @State private var settleStart = 0.0
    @State private var wasRolling = false
    @State private var bounce: CGFloat = 1
    @State private var firstTick: Int? = nil

    private var settleDuration: Double { LocalReduceMotion.current ? 0.12 : 0.32 }

    var body: some View {
        let animating = rolling || settleFrom != nil
        // The canvas is larger than the die so the hop and the shadow are never clipped.
        TimelineView(.animation(minimumInterval: nil, paused: !animating)) { timeline in
            // Captured inside the Canvas closure, or SwiftUI sees unchanged captures and skips the redraw.
            let tick = timeline.date
            Canvas { ctx, sz in
                _ = tick
                draw(&ctx, CGPoint(x: sz.width / 2, y: sz.height / 2), ludoNow())
            }
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .frame(width: size, height: size)
        .scaleEffect(bounce)
        .onAppear {
            if firstTick == nil { firstTick = landTick }
            if rolling { beginRoll() }
        }
        .onChange(of: rolling) { _, now in
            if now {
                beginRoll()
            } else if wasRolling {
                wasRolling = false
                settleFrom = LudoDieMath.tumble(ludoNow() - rollStart)
                settleStart = ludoNow()
                let id = settleStart
                DispatchQueue.main.asyncAfter(deadline: .now() + settleDuration + 0.02) {
                    if settleStart == id { settleFrom = nil }
                }
            }
        }
        .onChange(of: landTick) { _, tick in
            if tick == firstTick { return }
            // spring(0.6, 900) to 1.22, then to 0.94, then spring(0.7, 500) to 1.
            withAnimation(.compose(dampingRatio: 0.6, stiffness: 900)) { bounce = 1.22 } completion: {
                withAnimation(.compose(dampingRatio: 0.6, stiffness: 900)) { bounce = 0.94 } completion: {
                    withAnimation(.compose(dampingRatio: 0.7, stiffness: 500)) { bounce = 1 }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func beginRoll() {
        wasRolling = true
        rollStart = ludoNow()
        settleFrom = nil
    }

    private func draw(_ ctx: inout GraphicsContext, _ center: CGPoint, _ now: Double) {
        let px = size
        if rolling {
            let t = now - rollStart
            let hop = -CGFloat(abs(sin(t * 14))) * 5
            let scale = CGFloat(0.86 + 0.08 * abs(sin(t * 16)))
            drawDieShadow(&ctx, center, px, tight: true, lift: -hop)
            drawCube(&ctx, LudoDieMath.tumble(t), px * scale, CGPoint(x: center.x, y: center.y + hop))
        } else if let from = settleFrom, now - settleStart < settleDuration {
            let rest = LudoDieMath.restAngles[min(max(value, 1), 6)]!
            let target = LudoAngles(LudoDieMath.nearestForward(from.rx, rest.rx), LudoDieMath.nearestForward(from.ry, rest.ry), LudoDieMath.nearestForward(from.rz, 0.0))
            // tween(320, FastOutSlowInEasing)
            let p = ludoEase(0.4, 0, 0.2, 1, (now - settleStart) / settleDuration)
            drawDieShadow(&ctx, center, px, tight: p < 0.5, lift: 0)
            drawCube(&ctx, LudoDieMath.lerpAngles(from, target, p), px * CGFloat(0.9 + 0.1 * p), center)
        } else {
            drawDieShadow(&ctx, center, px, tight: false, lift: 0)
            drawLudoFlatFace(&ctx, value, pip, px, CGPoint(x: center.x - px / 2, y: center.y - px / 2))
        }
    }

    private func drawDieShadow(_ ctx: inout GraphicsContext, _ center: CGPoint, _ px: CGFloat, tight: Bool, lift: CGFloat) {
        let spread: CGFloat = tight ? 0.34 : 0.44
        let w = px * spread * 2 * min(max(1 - lift / (px * 2), 0.6), 1)
        let y = center.y + px * 0.5 + (tight ? 2 : 4) - px * 0.06
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - w / 2, y: y - px * 0.08, width: w, height: px * 0.16)),
                 with: .radialGradient(Gradient(colors: [.black.opacity(0.3), .clear]), center: CGPoint(x: center.x, y: y), startRadius: 0, endRadius: max(w / 2, 0.01)))
    }

    /// A shaded perspective cube with pips on every visible face.
    private func drawCube(_ ctx: inout GraphicsContext, _ angles: LudoAngles, _ px: CGFloat, _ c: CGPoint) {
        let hs = px * 0.5 * 0.82
        let d = 5.0
        func project(_ p: LudoV3) -> CGPoint {
            let r = LudoDieMath.rotate(p, angles)
            let f = CGFloat(d / (d - r.z))
            return CGPoint(x: c.x + CGFloat(r.x) * hs * f, y: c.y + CGFloat(r.y) * hs * f)
        }
        let corner = hs * 0.32
        let edgeWidth = max(1 / 3, px * 0.02)
        let unit: [(Double, Double)] = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
        for (faceValue, normal) in LudoDieMath.faceNormals {
            let n = LudoDieMath.rotate(normal, angles)
            if n.z <= 0.02 { continue }
            let (u, v) = LudoDieMath.faceAxes[faceValue]!
            let corners = unit.map { (a, b) in project(normal + u * a + v * b) }
            let path = LudoDieMath.roundedPolygon(corners, corner)
            let lit = min(max(0.62 + 0.38 * max(0.0, n.dot(LudoDieMath.lightDir)), 0), 1)
            let top = ludoHex(0xB9B4C8).mix(.White, lit)
            let bottom = ludoHex(0xA8A2BC).mix(ludoHex(0xE6E2F0), lit)
            ctx.fill(path, with: .linearGradient(Gradient(colors: [top.color, bottom.color]), startPoint: corners[0], endPoint: corners[2]))
            ctx.stroke(path, with: .color(.black.opacity(0.1)), lineWidth: edgeWidth)
            // Pips, as projected circles so they foreshorten with the face.
            let (light, dark) = LudoDieMath.pipColors(faceValue, pip)
            let pipColor = light.mix(dark, 1 - lit * 0.6).color
            var dots = Path()
            for (x, y) in ludoPips[faceValue]! {
                let cu = (x - 0.5) * 2 * 0.92
                let cv = (y - 0.5) * 2 * 0.92
                let r = 0.18 * 0.92
                for k in 0..<14 {
                    let a = Double(k) / 14.0 * 2 * .pi
                    let q = project(normal * 1.001 + u * (cu + cos(a) * r) + v * (cv + sin(a) * r))
                    if k == 0 { dots.move(to: q) } else { dots.addLine(to: q) }
                }
                dots.closeSubpath()
            }
            ctx.fill(dots, with: .color(pipColor))
        }
    }
}

/// The reference's resting die: rounded square, soft gradient, glossy pips (red on a 6).
func drawLudoFlatFace(_ ctx: inout GraphicsContext, _ value: Int, _ pip: LudoColor, _ px: CGFloat, _ origin: CGPoint) {
    let corner = px * 0.24
    let rect = CGRect(x: origin.x, y: origin.y, width: px, height: px)
    ctx.fill(Path(roundedRect: rect, cornerRadius: corner),
             with: .linearGradient(Gradient(colors: [.white, ludoHex(0xE6E2F0).color]), startPoint: origin, endPoint: CGPoint(x: origin.x + px, y: origin.y + px)))
    let onePx: CGFloat = 1 / 3
    ctx.stroke(Path(roundedRect: rect.insetBy(dx: onePx / 2, dy: onePx / 2), cornerRadius: corner), with: .color(.black.opacity(0.08)), lineWidth: onePx)
    let (light, dark) = LudoDieMath.pipColors(value, pip)
    for (x, y) in ludoPips[min(max(value, 1), 6)] ?? [] {
        let c = CGPoint(x: origin.x + CGFloat(x) * px, y: origin.y + CGFloat(y) * px)
        let r = px * 0.09
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [light.color, dark.color]), center: CGPoint(x: c.x - r, y: c.y - r), startRadius: 0, endRadius: px * 0.12))
    }
}

/// A faint die face for seats waiting their turn, `side` points across (its stroke may spill over, like Compose).
struct LudoGhostDie: View {
    let value: Int
    let color: Color
    var side: CGFloat = 18

    var body: some View {
        Canvas { ctx, size in
            let px = side
            let o = CGPoint(x: (size.width - px) / 2, y: (size.height - px) / 2)
            ctx.stroke(Path(roundedRect: CGRect(x: o.x, y: o.y, width: px, height: px), cornerRadius: px * 0.22), with: .color(color), lineWidth: px * 0.09)
            var dots = Path()
            for (x, y) in ludoPips[min(max(value, 1), 6)] ?? [] {
                let r = px * 0.085
                dots.addEllipse(in: CGRect(x: o.x + CGFloat(x) * px - r, y: o.y + CGFloat(y) * px - r, width: r * 2, height: r * 2))
            }
            ctx.fill(dots, with: .color(color))
        }
        .frame(width: side + 6, height: side + 6)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
