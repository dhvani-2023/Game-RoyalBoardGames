import SwiftUI
import GameKit

/// Hand-drawn emblem pieces shared by the splash, onboarding and app icon:
/// the crowned 8-ball, a die, a Ludo pawn and a carrom coin. Draw into a `RoyalDraw` (Canvas) context.
enum RoyalArt {
    private static let ringColors = [Royal.GoldLight, Royal.Gold, Royal.GoldMid, Royal.GoldDark, Royal.GoldMid, Royal.Gold, Royal.GoldLight]

    /// Gold ring + black 8-ball + crown, matching the launcher icon. `ring` 0…1 draws the ring progressively.
    static func emblem(_ d: RoyalDraw, _ center: CGPoint, _ radius: CGFloat, ring: CGFloat = 1, crown: CGFloat = 1) {
        if ring > 0 { goldRing(d, center, radius, ring) }
        eightBall(d, center, radius * 0.84)
        if crown > 0 { self.crown(d, CGPoint(x: center.x, y: center.y - radius * 1.02), radius * 0.62 * crown) }
    }

    /// The emblem's gold ring (sweep gradient arc from 12 o'clock).
    static func goldRing(_ d: RoyalDraw, _ center: CGPoint, _ radius: CGFloat, _ progress: CGFloat) {
        let w = radius * 0.16
        d.arc(RoyalDraw.sweep(ringColors, center), -90, 360 * Double(progress), false,
              CGPoint(x: center.x - radius + w / 2, y: center.y - radius + w / 2),
              CGSize(width: radius * 2 - w, height: radius * 2 - w), stroke: w)
    }

    static func eightBall(_ d: RoyalDraw, _ center: CGPoint, _ r: CGFloat, number: Bool = true) {
        guard r > 0 else { return }
        d.circle(RoyalDraw.radial([Color(argb: 0xFF4A5170), Color(argb: 0xFF161A2B), Color(argb: 0xFF03040A)],
                                  CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.35), r * 1.4), r, center)
        if number {
            let dd = r * 0.44
            let dc = CGPoint(x: center.x, y: center.y - r * 0.08)
            d.circle(RoyalDraw.radial([Color.White, Color(argb: 0xFFE9DFC8)], CGPoint(x: dc.x - dd * 0.3, y: dc.y - dd * 0.3), dd * 1.3), dd, dc)
            let sw = dd * 0.2
            d.circle(Color(argb: 0xFF10131F), dd * 0.28, CGPoint(x: dc.x, y: dc.y - dd * 0.33), stroke: sw)
            d.circle(Color(argb: 0xFF10131F), dd * 0.35, CGPoint(x: dc.x, y: dc.y + dd * 0.3), stroke: sw)
        }
        // gloss
        d.oval(RoyalDraw.vertical([Color.white.opacity(0.45), .clear], center.y - r * 0.95, center.y - r * 0.2),
               CGPoint(x: center.x - r * 0.6, y: center.y - r * 0.92), CGSize(width: r * 1.0, height: r * 0.6))
    }

    static func crown(_ d: RoyalDraw, _ baseCenter: CGPoint, _ w: CGFloat) {
        guard w > 0 else { return }
        let h = w * 0.62
        let l = baseCenter.x - w / 2
        let b = baseCenter.y
        var path = Path()
        path.move(to: CGPoint(x: l, y: b))
        path.addLine(to: CGPoint(x: l + w * 0.07, y: b - h * 0.95))
        path.addLine(to: CGPoint(x: l + w * 0.30, y: b - h * 0.45))
        path.addLine(to: CGPoint(x: l + w * 0.5, y: b - h * 1.2))
        path.addLine(to: CGPoint(x: l + w * 0.70, y: b - h * 0.45))
        path.addLine(to: CGPoint(x: l + w * 0.93, y: b - h * 0.95))
        path.addLine(to: CGPoint(x: l + w, y: b))
        path.closeSubpath()
        d.path(path, RoyalDraw.vertical([Color(argb: 0xFFFFF1BF), Royal.Gold, Color(argb: 0xFFD08A22)], b - h * 1.2, b))
        d.path(path, Royal.Wood, stroke: w * 0.035, join: .round)
        d.circle(Royal.Ruby, w * 0.07, CGPoint(x: l + w * 0.5, y: b - h * 1.2))
        d.circle(Royal.Ruby, w * 0.055, CGPoint(x: l + w * 0.07, y: b - h * 0.95))
        d.circle(Royal.Ruby, w * 0.055, CGPoint(x: l + w * 0.93, y: b - h * 0.95))
        d.roundRect(Royal.Ruby, CGPoint(x: l + w * 0.42, y: b - h * 0.32), CGSize(width: w * 0.16, height: h * 0.2), w * 0.03)
    }

    private static let pips: [[(CGFloat, CGFloat)]] = [
        [(0, 0)],
        [(-1, -1), (1, 1)],
        [(-1, -1), (0, 0), (1, 1)],
        [(-1, -1), (1, -1), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
    ]

    /// Ivory die with red pips; `value` 1…6, rotated by `angle` degrees.
    static func die(_ d: RoyalDraw, _ center: CGPoint, _ size: CGFloat, _ value: Int, angle: Double = 0, pip: Color = Royal.Ruby) {
        d.rotated(angle, center) { d in
            let tl = CGPoint(x: center.x - size / 2, y: center.y - size / 2)
            let s = CGSize(width: size, height: size)
            d.roundRect(Color.black.opacity(0.35), CGPoint(x: tl.x + size * 0.05, y: tl.y + size * 0.08), s, size * 0.22)
            d.roundRect(RoyalDraw.linear([Color.White, Color(argb: 0xFFEDE3CC)], tl, CGPoint(x: tl.x + size, y: tl.y + size)), tl, s, size * 0.22)
            d.roundRect(Color.white.opacity(0.7 * 0.35), CGPoint(x: tl.x + size * 0.06, y: tl.y + size * 0.05),
                        CGSize(width: size * 0.88, height: size * 0.3), size * 0.15)
            let p = size * 0.09
            let o = size * 0.26
            for (x, y) in pips[min(max(value, 1), 6) - 1] {
                d.circle(pip, p, CGPoint(x: center.x + x * o, y: center.y + y * o))
            }
        }
    }

    /// Glossy Ludo pawn standing on `base`.
    static func pawn(_ d: RoyalDraw, _ base: CGPoint, _ h: CGFloat, _ color: Color) {
        let dark = lerp(color, Color.Black, Float(0.35))
        let light = lerp(color, Color.White, Float(0.35))
        d.oval(Color.black.opacity(0.35), CGPoint(x: base.x - h * 0.34, y: base.y - h * 0.06), CGSize(width: h * 0.68, height: h * 0.16))
        var body = Path()
        body.move(to: CGPoint(x: base.x - h * 0.3, y: base.y))
        body.addCurve(to: CGPoint(x: base.x - h * 0.1, y: base.y - h * 0.62),
                      control1: CGPoint(x: base.x - h * 0.28, y: base.y - h * 0.3),
                      control2: CGPoint(x: base.x - h * 0.1, y: base.y - h * 0.45))
        body.addLine(to: CGPoint(x: base.x + h * 0.1, y: base.y - h * 0.62))
        body.addCurve(to: CGPoint(x: base.x + h * 0.3, y: base.y),
                      control1: CGPoint(x: base.x + h * 0.1, y: base.y - h * 0.45),
                      control2: CGPoint(x: base.x + h * 0.28, y: base.y - h * 0.3))
        body.closeSubpath()
        d.path(body, RoyalDraw.horizontal([dark, light, color, dark], base.x - h * 0.3, base.x + h * 0.3))
        d.circle(RoyalDraw.radial([light, color, dark], CGPoint(x: base.x - h * 0.06, y: base.y - h * 0.8), h * 0.24), h * 0.2,
                 CGPoint(x: base.x, y: base.y - h * 0.76))
        d.circle(Color.white.opacity(0.6), h * 0.05, CGPoint(x: base.x - h * 0.07, y: base.y - h * 0.83))
    }

    /// Turned wooden carrom coin.
    static func coin(_ d: RoyalDraw, _ center: CGPoint, _ r: CGFloat, light: Bool) {
        let base = light ? Color(argb: 0xFFF3E2C0) : Color(argb: 0xFF2A1A12)
        let edge = light ? Color(argb: 0xFFC9A877) : Color(argb: 0xFF120B07)
        d.circle(Color.black.opacity(0.35), r, CGPoint(x: center.x + r * 0.1, y: center.y + r * 0.15))
        d.circle(RoyalDraw.radial([lerp(base, Color.White, Float(0.3)), base, edge], CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.3), r * 1.4), r, center)
        d.circle(edge.copy(alpha: 0.6), r * 0.68, center, stroke: r * 0.08)
        d.circle(edge.copy(alpha: 0.4), r * 0.38, center, stroke: r * 0.06)
    }
}

/// The emblem as a standalone view (fills its frame).
struct RoyalEmblem: View {
    var ring: CGFloat = 1
    var crown: CGFloat = 1

    init(ring: CGFloat = 1, crown: CGFloat = 1) {
        self.ring = ring
        self.crown = crown
    }

    var body: some View {
        Canvas { ctx, size in
            let d = RoyalDraw(ctx, size)
            RoyalArt.emblem(d, CGPoint(x: size.width / 2, y: size.height * 0.56), min(size.width, size.height) * 0.4, ring: ring, crown: crown)
        }
    }
}
