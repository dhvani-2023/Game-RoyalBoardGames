import SwiftUI
import GameKit

private let NeonX = Color(argb: 0xFFFF4FD8)
private let NeonO = Color(argb: 0xFF3CF0FF)
private let NeonGrid = Color(argb: 0xFF9B8CFF)
private let NeonWin = Color(argb: 0xFFFFD66B)

/// "Neon Arcade" card art: a dark glass tile with a glowing grid. X and O strokes draw themselves in,
/// X completes the diagonal, a gold line sweeps through with sparks, then the board fades and replays.
/// One 4.4 s loop. Fills the (square) frame it is given.
struct TicTacToeCardArt: View {
    @State private var start = Date()

    var body: some View {
        let reduce = LocalReduceMotion.current
        ZStack {
            // Tile + neon grid never change: this closure captures nothing that changes, so it is drawn once.
            Canvas { ctx, size in
                let g = NeonGeometry(size.width, size.height)
                var c = ctx
                c.rotate(-7, around: g.center)
                let tl = g.tl, tile = g.tile, w = g.w
                let corner = tile * 0.18
                c.fill(Path(roundedRect: CGRect(x: tl.x, y: tl.y + w * 0.03, width: tile, height: tile), cornerRadius: corner),
                       with: .color(Color.black.opacity(0.45)))
                let tileRect = Path(roundedRect: CGRect(x: tl.x, y: tl.y, width: tile, height: tile), cornerRadius: corner)
                c.fill(tileRect, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF2A1F5C), Color(argb: 0xFF120D2E), Color(argb: 0xFF07051A)]),
                                                       startPoint: tl, endPoint: CGPoint(x: tl.x + tile, y: tl.y + tile)))
                c.stroke(tileRect, with: .linearGradient(Gradient(colors: [NeonGrid.copy(alpha: 0.9), NeonX.copy(alpha: 0.5), NeonO.copy(alpha: 0.7)]),
                                                         startPoint: tl, endPoint: CGPoint(x: tl.x + tile, y: tl.y + tile)), lineWidth: w * 0.012)
                c.fill(Path(roundedRect: CGRect(x: tl.x + tile * 0.06, y: tl.y + tile * 0.04, width: tile * 0.88, height: tile * 0.3), cornerRadius: tile * 0.14),
                       with: .color(Color.white.opacity(0.08)))
                for k in 1...2 {
                    let x = g.g0.x + g.cell * CGFloat(k)
                    let y = g.g0.y + g.cell * CGFloat(k)
                    neon(c, CGPoint(x: x, y: g.g0.y), CGPoint(x: x, y: g.g0.y + g.grid), NeonGrid, w * 0.018, 0.9)
                    neon(c, CGPoint(x: g.g0.x, y: y), CGPoint(x: g.g0.x + g.grid, y: y), NeonGrid, w * 0.018, 0.9)
                }
            }
            TimelineView(.animation(paused: reduce)) { tl in
                let time = reduce ? 0.82 : RoyalBackdrop.loop(tl.date.timeIntervalSince(start), 4.4)
                Canvas { ctx, size in
                    TicTacToeCardArt.drawMarks(ctx, size, CGFloat(time))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // (cell index, isX) in play order: X4 O1 X0 O2 X8, so X completes the 0-4-8 diagonal.
    private static let script: [(Int, Bool)] = [(4, true), (1, false), (0, true), (2, false), (8, true)]

    private static func drawMarks(_ ctx: GraphicsContext, _ size: CGSize, _ time: CGFloat) {
        let geo = NeonGeometry(size.width, size.height)
        let w = geo.w, tl = geo.tl, tile = geo.tile, g0 = geo.g0, cell = geo.cell, grid = geo.grid
        let fade: CGFloat = time > 0.9 ? 1 - (time - 0.9) / 0.1 : 1
        var c = ctx
        c.rotate(-7, around: geo.center)
        // marks
        let step: CGFloat = 0.13
        for (i, item) in script.enumerated() {
            let (index, isX) = item
            let p = min(1, max(0, (time - 0.04 - CGFloat(i) * step) / (step * 0.8)))
            if p <= 0 { continue }
            let center = CGPoint(x: g0.x + cell * (CGFloat(index % 3) + 0.5), y: g0.y + cell * (CGFloat(index / 3) + 0.5))
            let r = cell * 0.28
            if isX {
                let a = min(1, p * 2)
                let b = min(1, max(0, (p - 0.5) * 2))
                neon(c, CGPoint(x: center.x - r, y: center.y - r), CGPoint(x: center.x - r + 2 * r * a, y: center.y - r + 2 * r * a), NeonX, w * 0.03, fade)
                if b > 0 {
                    neon(c, CGPoint(x: center.x + r, y: center.y - r), CGPoint(x: center.x + r - 2 * r * b, y: center.y - r + 2 * r * b), NeonX, w * 0.03, fade)
                }
            } else {
                let arc = RoyalDraw.arcPath(-90, 360 * Double(p), false, CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                var o = c
                for (width, alpha) in [(w * 0.075, 0.12), (w * 0.05, 0.22)] {
                    o.opacity = alpha * Double(fade)
                    o.stroke(arc, with: .color(NeonO), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
                o.opacity = Double(fade)
                o.stroke(arc, with: .color(NeonO), style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round))
                o.opacity = 0.7 * Double(fade)
                o.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: w * 0.01, lineCap: .round))
            }
        }

        // winning sweep on the 0-4-8 diagonal
        let winStart = 0.04 + CGFloat(script.count) * step
        let win = min(1, max(0, (time - winStart) / 0.12))
        if win > 0 {
            let a = CGPoint(x: g0.x + cell * 0.2, y: g0.y + cell * 0.2)
            let b = CGPoint(x: g0.x + grid - cell * 0.2, y: g0.y + grid - cell * 0.2)
            let tip = CGPoint(x: a.x + (b.x - a.x) * win, y: a.y + (b.y - a.y) * win)
            neon(c, a, tip, NeonWin, w * 0.04, fade)
            if win >= 1 {
                let burst = min(1, max(0, (time - winStart - 0.12) / 0.18))
                let ctr = CGPoint(x: g0.x + grid / 2, y: g0.y + grid / 2)
                let dotR = w * 0.014
                var o = c
                o.opacity = Double((1 - burst) * fade)
                for k in 0..<10 {
                    let ang = Double(k) * 2 * Double.pi / 10
                    let d = w * 0.22 * burst
                    let p = CGPoint(x: ctr.x + CGFloat(cos(ang)) * d, y: ctr.y + CGFloat(sin(ang)) * d)
                    o.fill(Path(ellipseIn: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(NeonWin))
                }
                o.opacity = Double(0.25 * (1 - burst) * fade)
                o.stroke(Path(roundedRect: CGRect(x: tl.x, y: tl.y, width: tile, height: tile), cornerRadius: tile * 0.18),
                         with: .color(NeonWin), lineWidth: w * 0.03)
            }
        }
    }
}

/// Shared layout for the static and animated layers.
private struct NeonGeometry {
    let w: CGFloat
    let o: CGPoint
    let center: CGPoint
    let tile: CGFloat
    let tl: CGPoint
    let grid: CGFloat
    let g0: CGPoint
    let cell: CGFloat

    init(_ width: CGFloat, _ height: CGFloat) {
        w = min(width, height)
        o = CGPoint(x: (width - w) / 2, y: (height - w) / 2)
        center = CGPoint(x: o.x + w / 2, y: o.y + w / 2)
        tile = w * 0.86
        tl = CGPoint(x: o.x + (w - tile) / 2, y: o.y + (w - tile) / 2)
        grid = tile - tile * 0.14 * 2
        g0 = CGPoint(x: tl.x + tile * 0.14, y: tl.y + tile * 0.14)
        cell = grid / 3
    }
}

private extension GraphicsContext {
    /// Compose `rotate(degrees, pivot)`.
    mutating func rotate(_ degrees: Double, around pivot: CGPoint) {
        translateBy(x: pivot.x, y: pivot.y)
        rotate(by: .degrees(degrees))
        translateBy(x: -pivot.x, y: -pivot.y)
    }
}

/// A neon tube: soft wide glow layers, the coloured core and a white-hot centre.
/// Alpha goes through the context's opacity, so drawing a frame creates no colours.
private func neon(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat, _ alpha: CGFloat) {
    var p = Path()
    p.move(to: a)
    p.addLine(to: b)
    let al = Double(alpha)
    var c = ctx
    c.opacity = 0.10 * al
    c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width * 3.2, lineCap: .round))
    c.opacity = 0.22 * al
    c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width * 2.0, lineCap: .round))
    c.opacity = al
    c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    c.opacity = 0.75 * al
    c.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: width * 0.35, lineCap: .round))
}
