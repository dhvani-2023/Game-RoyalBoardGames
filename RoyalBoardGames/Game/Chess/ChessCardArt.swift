import SwiftUI
import GameKit

private let RippleGold = Color(argb: 0xFFFFD66B)
private let SparkGold = Color(argb: 0xFFFFF1BF)

/// "Royal Duel" card art: a walnut-and-ivory board in perspective under a spotlight.
/// The two kings face off at the back while a white knight leaps in L-shapes around the front,
/// landing with a gold ripple and sparks. One 3.6 s loop. Fills the (square) frame it is given.
struct ChessCardArt: View {
    @State private var start = Date()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let reduce = LocalReduceMotion.current
        let scale = max(1, displayScale)
        ZStack {
            // Static stage (halo + board): its closure captures nothing that changes, so it is drawn once.
            Canvas { ctx, size in
                let w = min(size.width, size.height)
                let origin = CGPoint(x: (size.width - w) / 2, y: (size.height - w) / 2)
                let c = CGPoint(x: origin.x + w * 0.5, y: origin.y + w * 0.38)
                let r = w * 0.62
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color(argb: 0xFFFFE9A8).copy(alpha: 0.55), .clear]), center: c, startRadius: 0, endRadius: r))
                DuelBoard(origin: origin, w: w).drawBoard(ctx, size)
            }
            TimelineView(.animation(paused: reduce)) { tl in
                let time = reduce ? 0.9 : RoyalBackdrop.loop(tl.date.timeIntervalSince(start), 3.6)
                Canvas { ctx, size in
                    ChessCardArt.drawScene(ctx, size, time, scale)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Placed {
        let piece: ChessPiece
        let u: CGFloat
        let v: CGFloat
        let lift: CGFloat
        let scale: CGFloat
    }

    private static let stops: [(CGFloat, CGFloat)] = [(0.5, 3.5), (1.5, 1.5), (3.5, 2.5), (2.5, 0.5)]

    private static func drawScene(_ ctx: GraphicsContext, _ size: CGSize, _ time: Double, _ scale: CGFloat) {
        let w = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - w) / 2, y: (size.height - w) / 2)
        let board = DuelBoard(origin: origin, w: w)

        // Knight path: four squares visited in L-jumps, front rows (row 2–3 of 4).
        let t = CGFloat(time)
        let segment: CGFloat = 0.25
        let i = min(3, max(0, Int(t / segment)))
        let local = (t - CGFloat(i) * segment) / segment
        let jump = min(1, max(0, (local - 0.35) / 0.4)) // rest, then leap
        let ease = jump * jump * (3 - 2 * jump)
        let from = stops[i]
        let to = stops[(i + 1) % stops.count]
        let u = from.0 + (to.0 - from.0) * ease
        let v = from.1 + (to.1 - from.1) * ease
        let hop = CGFloat(sin(Double(jump) * Double.pi)) * w * 0.16

        var pieces = [
            Placed(piece: ChessPiece(.KING, .BLACK), u: 2.5, v: 0.5, lift: 0, scale: 1.0),
            Placed(piece: ChessPiece(.QUEEN, .BLACK), u: 0.5, v: 1.2, lift: 0, scale: 0.9),
            Placed(piece: ChessPiece(.KING, .WHITE), u: 1.5, v: 3.3, lift: 0, scale: 1.0),
            Placed(piece: ChessPiece(.KNIGHT, .WHITE), u: u, v: v, lift: hop, scale: 0.92),
        ]
        // Back-to-front so nearer pieces overlap farther ones (stable, like Kotlin sortBy).
        pieces = pieces.chessStableSorted(descendingBy: { -Int(($0.v * 1000).rounded()) })
        for p in pieces { board.drawPiece(ctx, p.piece, p.u, p.v, p.lift, p.scale, scale) }

        // Landing ripple + sparks just after touchdown.
        let land = min(1, max(0, (local - 0.75) / 0.25))
        if jump >= 1 && land >= 0.001 && land <= 0.999 {
            let c = board.project(to.0, to.1)
            let s = board.scaleAt(to.1)
            let grow = 0.4 + land
            let ring = CGRect(x: c.x - w * 0.11 * s * grow, y: c.y - w * 0.04 * s * grow, width: w * 0.22 * s * grow, height: w * 0.08 * s * grow)
            var o = ctx
            o.opacity = Double((1 - land) * 0.9)
            o.stroke(Path(ellipseIn: ring), with: .color(RippleGold), lineWidth: w * 0.012)
            o.opacity = Double(1 - land)
            for k in 0..<6 {
                let a = Double(k) * Double.pi / 3 + 0.3
                let d = w * 0.1 * s * land
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * d, y: c.y - abs(CGFloat(sin(a))) * d - w * 0.03 * land)
                let r = w * 0.01
                o.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(SparkGold))
            }
        }
    }
}

/// A 4×4 board projected as a trapezoid (near edge wide, far edge narrow).
private struct DuelBoard {
    let origin: CGPoint
    let w: CGFloat

    private var top: CGFloat { w * 0.30 }
    private var bottom: CGFloat { w * 0.88 }
    private var farHalf: CGFloat { w * 0.30 }
    private var nearHalf: CGFloat { w * 0.47 }
    private var cx: CGFloat { w * 0.5 }

    /// Grid point for board coords u (0..4 across) and v (0..4 far→near).
    func project(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let f = v / 4
        let y = top + (bottom - top) * (f * (0.8 + 0.2 * f))
        let half = farHalf + (nearHalf - farHalf) * f
        return CGPoint(x: origin.x + cx + (u / 4 - 0.5) * 2 * half, y: origin.y + y)
    }

    func scaleAt(_ v: CGFloat) -> CGFloat { 0.72 + 0.28 * (v / 4) }

    private func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: c)
        p.addLine(to: d)
        p.closeSubpath()
        return p
    }

    func drawBoard(_ ctx: GraphicsContext, _ size: CGSize) {
        let rim = quad(project(-0.25, -0.25), project(4.25, -0.25), project(4.25, 4.25), project(-0.25, 4.25))
        // thickness under the near edge
        let n1 = project(-0.25, 4.25)
        let n2 = project(4.25, 4.25)
        let edge = quad(n1, n2, CGPoint(x: n2.x, y: n2.y + w * 0.05), CGPoint(x: n1.x, y: n1.y + w * 0.05))
        ctx.fill(Path(ellipseIn: CGRect(x: n1.x - w * 0.02, y: n1.y - w * 0.02, width: n2.x - n1.x + w * 0.04, height: w * 0.1)),
                 with: .color(Color.black.opacity(0.45)))
        ctx.fill(edge, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF5A3216), Color(argb: 0xFF2A1608)]),
                                             startPoint: CGPoint(x: 0, y: n1.y), endPoint: CGPoint(x: 0, y: n1.y + w * 0.05)))
        ctx.fill(rim, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF8E5A31), Color(argb: 0xFF6B3E1F), Color(argb: 0xFF4A2711)]),
                                            startPoint: CGPoint(x: 0, y: origin.y + top), endPoint: CGPoint(x: 0, y: origin.y + bottom)))
        // Compose verticalGradient with default bounds spans the whole drawing area.
        ctx.stroke(rim, with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFE9A8), Color(argb: 0xFFB8741A)]),
                                              startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)), lineWidth: w * 0.008)
        let light = Color(argb: 0xFFF3E4C6)
        let dark = Color(argb: 0xFF9A6438)
        for r in 0..<4 {
            for c in 0..<4 {
                let cf = CGFloat(c), rf = CGFloat(r)
                let p = quad(project(cf, rf), project(cf + 1, rf), project(cf + 1, rf + 1), project(cf, rf + 1))
                ctx.fill(p, with: .color((r + c) % 2 == 0 ? light : dark))
            }
        }
        // glossy sheen across the far half
        let g1 = project(0, 0), g2 = project(4, 0), g3 = project(4, 1.6), g4 = project(0, 1.6)
        ctx.fill(quad(g1, g2, g3, g4), with: .linearGradient(Gradient(colors: [Color.white.opacity(0.22), .clear]),
                                                             startPoint: CGPoint(x: 0, y: g1.y), endPoint: CGPoint(x: 0, y: g3.y)))
    }

    func drawPiece(_ ctx: GraphicsContext, _ piece: ChessPiece, _ u: CGFloat, _ v: CGFloat, _ lift: CGFloat, _ pieceScale: CGFloat, _ displayScale: CGFloat) {
        let base = project(u, v)
        let s = scaleAt(v) * pieceScale
        let px = max(8 / displayScale, w * 0.34 * s)
        // Render each piece once at a fixed size (bucketed to the card width) and scale on draw;
        // a per-frame size would re-render bitmaps every frame while the knight moves.
        let cachePx = max(16, Int((w * 0.34 * displayScale).rounded()) / 16 * 16)
        // contact shadow shrinks while airborne
        let air = min(1, max(0, lift / (w * 0.16)))
        var shadow = ctx
        shadow.opacity = Double(0.38 * (1 - air * 0.6))
        shadow.fill(Path(ellipseIn: CGRect(x: base.x - px * 0.3 * (1 - air * 0.4), y: base.y - px * 0.07,
                                           width: px * 0.6 * (1 - air * 0.4), height: px * 0.14)),
                    with: .color(.black))
        let img = ChessPieceArt.image(piece, cachePx, displayScale)
        ctx.draw(Image(decorative: img, scale: displayScale),
                 in: CGRect(x: base.x - px / 2, y: base.y - px * 0.92 - lift, width: px, height: px))
    }
}
