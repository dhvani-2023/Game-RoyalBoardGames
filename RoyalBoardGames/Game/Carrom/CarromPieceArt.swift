import SwiftUI
import GameKit

/// What the piece layer draws, read from the session once per frame.
struct PieceSnapshot {
    let coins: [CarromDisc]
    let playback: CarromPlayback?
    let introStart: Double?
    let effects: [CarromEffect]
    let striker: CarromVec?
    let ring: CarromColor?
    let aim: CarromAim?
    let guide: CarromGuide
    /// Counter-turn for sprites and text (degrees), so lighting and labels stay upright.
    let counter: Double
    /// During the coin toss the rack waits off the board, then slides in.
    let hideCoins: Bool
}

/// Pre-rendered pieces at the current board size.
struct PieceSprites {
    let white: CGImage
    let black: CGImage
    let queen: CGImage
    let striker: CGImage
    let scale: CGFloat

    func image(_ kind: CarromKind) -> CGImage {
        switch kind {
        case .WHITE: return white
        case .BLACK: return black
        case .QUEEN: return queen
        case .STRIKER: return striker
        }
    }
}

/// Coins, the striker, the aim guide and effects.
enum CarromPieceArt {
    private static let accent = CarromColor(0xFFE45C)

    static func draw(_ c: GraphicsContext, _ m: CarromMetrics, _ s: PieceSnapshot, _ now: Double, _ sprites: PieceSprites) {
        let u = m.u
        let resolved: [GraphicsContext.ResolvedImage] = CarromKind.allCases.map {
            c.resolve(Image(decorative: sprites.image($0), scale: sprites.scale))
        }
        let rCoin = m.len(CarromBoard.coinR)
        let rStriker = m.len(CarromBoard.strikerR)
        func book(_ kind: CarromKind, _ x: CGFloat, _ y: CGFloat, _ scale: CGFloat = 1, _ alpha: Double = 1) {
            CarromSprites.draw(c, resolved[kind.ordinal], x, y, kind == .STRIKER ? rStriker : rCoin, scale: scale, alpha: alpha, rotationDeg: s.counter)
        }

        // Pocket glows sit under the pieces.
        for e in s.effects {
            if !e.isActive(now) { continue }
            guard case .Ring(let color) = e.kind else { continue }
            let q = e.progress(now)
            let p = m.pt(e.at)
            let glowR = m.len(CarromBoard.pocketR * (1.3 + q))
            CarromDraw.fill(c, CarromArt.circle(p, glowR), color.opacity(0.9 * (1 - q)), blur: m.len(1.2))
            CarromDraw.stroke(c, CarromArt.circle(p, m.len(CarromBoard.pocketR * (1.1 + q * 0.8))), color.opacity(1 - q), 2 * u)
        }

        if let pb = s.playback {
            drawPlayback(c, m, pb, now, book)
        } else {
            drawResting(c, m, s, now, book)
        }

        if let striker = s.striker {
            let p = m.pt(striker)
            let r = rStriker
            if let ring = s.ring {
                CarromDraw.stroke(c, CarromArt.circle(p, r * 1.22), ring, r * 0.28, blur: r * 0.35)
            }
            drawGuide(c, m, s)
            book(.STRIKER, p.x, p.y)
            if let aim = s.aim { drawArrow(c, m, striker, aim) }
        }

        for e in s.effects {
            if !e.isActive(now) { continue }
            let q = e.progress(now)
            switch e.kind {
            case .Sparks(let strength):
                drawSparks(c, m, e, q, strength)
            case .FloatText(let text, let color):
                let p = m.pt(e.at)
                let alpha = q < 0.7 ? 1.0 : (1 - q) / 0.3
                var g = c
                g.translateBy(x: p.x, y: p.y - CGFloat(q) * m.len(5.0))
                g.rotate(by: .degrees(s.counter))
                g.opacity = Swift.max(0, Swift.min(1, alpha))
                g.addFilter(.shadow(color: Color.black.opacity(0.6 * alpha), radius: 2.5 * u, x: 0, y: u))
                g.draw(Text(verbatim: text).font(RoyalFonts.display(m.len(3.0))).foregroundColor(color.color), at: .zero, anchor: .center)
            default:
                break
            }
        }
    }

    private static func drawResting(_ c: GraphicsContext, _ m: CarromMetrics, _ s: PieceSnapshot, _ now: Double,
                                    _ book: (CarromKind, CGFloat, CGFloat, CGFloat, Double) -> Void) {
        if s.hideCoins { return }
        var popping: [Int: Double] = [:]
        for e in s.effects {
            if case .Pop(let index) = e.kind, now < e.start + e.duration { popping[index] = e.progress(now) }
        }
        let intro = s.introStart.map { now - $0 }
        for (i, coin) in s.coins.enumerated() {
            if !coin.live { continue }
            var p = m.pt(coin.p)
            var scale: CGFloat = 1
            if let q = popping[i] {
                if q <= 0 { continue }
                // A little overshoot as it lands back on the board.
                scale = CGFloat(q < 0.7 ? q / 0.7 * 1.15 : 1.15 - (q - 0.7) / 0.3 * 0.15)
            }
            if let intro {
                // The rack slides in from the pockets, coin by coin.
                let uu = Swift.max(0.0, Swift.min(1.0, (intro - Double(i) * 0.014) / 0.5))
                let e = CGFloat(1 - Foundation.pow(1 - uu, 3))
                let from = m.pt(CarromBoard.pockets[i % 4] * 0.92)
                p = CGPoint(x: from.x + (p.x - from.x) * e, y: from.y + (p.y - from.y) * e)
                if uu <= 0 { continue }
            }
            book(coin.kind, p.x, p.y, scale, 1)
        }
    }

    private static func drawPlayback(_ c: GraphicsContext, _ m: CarromMetrics, _ pb: CarromPlayback, _ now: Double,
                                     _ book: (CarromKind, CGFloat, CGFloat, CGFloat, Double) -> Void) {
        let t = Swift.max(0.0, now - pb.start) * pb.rate
        let last = pb.frames.count - 1
        if last < 0 { return }
        func pos(_ disc: Int, _ time: Double, _ k: Int) -> Float {
            let f = time * 60
            let i0 = Swift.min(Kt.toInt(f), last)
            let i1 = Swift.min(i0 + 1, last)
            let frac = Float(f - Double(i0))
            let a = pb.frames[i0][2 * disc + k]
            return a + (pb.frames[i1][2 * disc + k] - a) * frac
        }
        let i0 = Swift.min(Kt.toInt(t * 60), last)
        for disc in pb.kinds.indices {
            let kind = pb.kinds[disc]
            if let drop = pb.dropped[disc] {
                if t >= drop.time {
                    // Sinking: slides into the hole, shrinking and darkening.
                    let q = (t - drop.time) / 0.3
                    if q >= 1 { continue }
                    let at = m.pt(pos(disc, drop.time, 0), pos(disc, drop.time, 1))
                    let hole = m.pt(CarromBoard.pockets[drop.pocket])
                    let qf = CGFloat(q)
                    book(kind, at.x + (hole.x - at.x) * qf, at.y + (hole.y - at.y) * qf, 1 - 0.45 * qf, Double(1 - qf))
                    continue
                }
            } else if !(disc < pb.live.count ? pb.live[disc] : true) {
                // Discs already pocketed before the shot stay hidden; they never move in the frames.
                continue
            }
            let nx = pos(disc, t, 0)
            let ny = pos(disc, t, 1)
            let now2 = m.pt(nx, ny)
            // Fast discs leave a faint trail.
            if i0 >= 3 {
                let bx = pb.frames[i0 - 3][2 * disc]
                let by = pb.frames[i0 - 3][2 * disc + 1]
                let dx = nx - bx
                let dy = ny - by
                let speed = Double((dx * dx + dy * dy).squareRoot()) * 20
                if speed > 55 {
                    let back = m.pt(bx, by)
                    let r = m.len(kind == .STRIKER ? CarromBoard.strikerR : CarromBoard.coinR)
                    CarromDraw.stroke(c, CarromDraw.line(back.x, back.y, now2.x, now2.y), CarromColor.white.opacity(Swift.min(0.35, speed / 600)), r * 1.3, cap: .round)
                }
            }
            book(kind, now2.x, now2.y, 1, 1)
        }
    }

    private static func drawGuide(_ c: GraphicsContext, _ m: CarromMetrics, _ s: PieceSnapshot) {
        let u = m.u
        let g = s.guide
        if g.path.count <= 1 { return }
        var path = Path()
        path.move(to: m.pt(g.path[0]))
        for p in g.path.dropFirst() { path.addLine(to: m.pt(p)) }
        CarromDraw.stroke(c, path, CarromColor.white.opacity(0.9), 1.8 * u, cap: .round, dash: [1 * u, 5 * u])
        if let ghost = g.ghost {
            CarromDraw.stroke(c, CarromArt.circle(m.pt(ghost), m.len(CarromBoard.strikerR)), CarromColor.white.opacity(0.75), 1.2 * u, dash: [3 * u, 3 * u])
        }
        if let coin = g.coin, let end = g.coinEnd, s.coins.indices.contains(coin) {
            let a = m.pt(s.coins[coin].p)
            let b = m.pt(end)
            CarromDraw.stroke(c, CarromDraw.line(a.x, a.y, b.x, b.y), accent, 2 * u, cap: .round)
        }
        if let pocket = g.pocket {
            CarromDraw.stroke(c, CarromArt.circle(m.pt(CarromBoard.pockets[pocket]), m.len(CarromBoard.pocketR * 1.3)), accent, 2 * u)
        }
    }

    /// Pull-back aim: a range ring, and an arrow whose length and colour show the power.
    private static func drawArrow(_ c: GraphicsContext, _ m: CarromMetrics, _ s: CarromVec, _ aim: CarromAim) {
        let u = m.u
        let cc = m.pt(s)
        let r = m.len(CarromBoard.strikerR)
        CarromDraw.stroke(c, CarromArt.circle(cc, r * 4.4), CarromColor.white.opacity(0.35), u, dash: [2 * u, 4 * u])
        if aim.power <= 0.01 { return }
        let dx = CGFloat(Foundation.cos(aim.angle))
        let dy = CGFloat(Foundation.sin(aim.angle))
        let len = r * (1.6 + 2.8 * CGFloat(aim.power))
        let bx = cc.x + dx * r * 1.15
        let by = cc.y + dy * r * 1.15
        let tx = cc.x + dx * len
        let ty = cc.y + dy * len
        let hot = aim.power > 0.75 ? CarromColor(0xFF3B30) : (aim.power > 0.45 ? CarromColor(0xFF9500) : CarromColor(0x34C759))
        let glow = CarromShadow(hot.opacity(0.8), 4 * u)
        CarromDraw.stroke(c, CarromDraw.line(bx, by, tx, ty), CarromPaint.linear(bx, by, tx, ty, [accent, hot]), r * 0.42, cap: .round, shadow: glow)
        let nx = -dy
        let ny = dx
        var head = Path()
        head.move(to: CGPoint(x: tx + dx * r * 0.7, y: ty + dy * r * 0.7))
        head.addLine(to: CGPoint(x: tx + nx * r * 0.48, y: ty + ny * r * 0.48))
        head.addLine(to: CGPoint(x: tx - nx * r * 0.48, y: ty - ny * r * 0.48))
        head.closeSubpath()
        CarromDraw.fill(c, head, hot, shadow: glow)
        let fx = cc.x - dx * len * 0.9
        let fy = cc.y - dy * len * 0.9
        CarromDraw.stroke(c, CarromDraw.line(cc.x, cc.y, fx, fy), CarromColor.white.opacity(0.5), 1.4 * u, dash: [2 * u, 3 * u])
        CarromDraw.stroke(c, CarromArt.circle(fx, fy, r * 0.55), CarromColor.white.opacity(0.8), 1.4 * u)
    }

    private static func drawSparks(_ c: GraphicsContext, _ m: CarromMetrics, _ e: CarromEffect, _ q: Double, _ strength: Double) {
        let u = m.u
        var rng = CarromRandom(UInt64(e.id))
        let cc = m.pt(e.at)
        let alpha = 1 - q
        let count = strength > 1600 ? 10 : 6
        var lines = Path()
        for _ in 0..<count {
            let a = rng.unit() * 2 * Double.pi
            let r0 = m.len(0.6 + q * 2)
            let r1 = r0 + m.len(0.8 + rng.unit() * 1.4) * CGFloat(1 - q * 0.5)
            let ca = CGFloat(Foundation.cos(a))
            let sa = CGFloat(Foundation.sin(a))
            lines.move(to: CGPoint(x: cc.x + r0 * ca, y: cc.y + r0 * sa))
            lines.addLine(to: CGPoint(x: cc.x + r1 * ca, y: cc.y + r1 * sa))
        }
        CarromDraw.stroke(c, lines, CarromColor(0xFFF2B0).opacity(alpha), 1.5 * u, cap: .round, shadow: CarromShadow(CarromColor(0xFFD24D).opacity(alpha), 3 * u))
    }
}
