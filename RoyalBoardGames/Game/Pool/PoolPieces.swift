import SwiftUI
import GameKit

/// What the piece layer draws, read from the session once per frame.
struct PoolPieceSnapshot {
    let balls: [PoolBall]
    let orient: [Quat]
    let playback: PoolPlayback?
    let introStart: Double?
    let effects: [PoolEffect]
    let game: PoolVariant
    let cuePos: Vec2
    let ballInHand: Bool
    let kitchen: Bool
    let placing: Bool
    let cueValid: Bool
    let showCue: Bool
    let angle: Double
    let power: Double
    let strike: PoolStrike?
    let guide: PoolGuide
    let callPockets: Bool
    let call: Int?
    let ring: PoolRGBA?
    let reduceMotion: Bool

    @MainActor
    static func of(_ session: PoolSession, _ reduceMotion: Bool) -> PoolPieceSnapshot {
        let t = session.table
        // Extras: while the instant replay runs, the table shows only the replayed shot.
        let ready = session.phase == .READY && session.replay == nil
        return PoolPieceSnapshot(
            balls: t.balls, orient: session.orient, playback: session.replay ?? session.playback, introStart: session.introStart, effects: session.effects,
            game: t.game, cuePos: session.cuePos, ballInHand: ready && t.ballInHand, kitchen: t.kitchenOnly, placing: session.placing,
            cueValid: session.cueValid, showCue: ready && !session.placing, angle: session.angle, power: session.power, strike: session.strike,
            guide: session.guide, callPockets: ready && session.needsCall, call: session.call,
            ring: (ready && session.isBotTurn) ? poolPlayerColour(session.currentSeat.player) : nil, reduceMotion: reduceMotion
        )
    }
}

/// Balls, the cue, the aim guide and effects, drawn in points.
@MainActor
enum PoolPieceArt {
    private static let R = PoolTableGeometry.R
    private static let clear = PoolRGBA.black.alpha(0)

    private static func line(_ ctx: GraphicsContext, _ c: PoolRGBA, _ a: CGPoint, _ b: CGPoint, _ width: CGFloat,
                             cap: CGLineCap = .butt, dash: [CGFloat] = []) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        ctx.stroke(p, with: .color(c.color), style: StrokeStyle(lineWidth: width, lineCap: cap, dash: dash))
    }

    private static func radial(_ stops: [(Double, PoolRGBA)], _ center: CGPoint, _ radius: CGFloat) -> GraphicsContext.Shading {
        .radialGradient(Gradient(stops: stops.map { Gradient.Stop(color: $0.1.color, location: $0.0) }),
                        center: center, startRadius: 0, endRadius: max(0.0001, radius))
    }

    static func drawPieces(_ ctx: GraphicsContext, _ m: PoolTableMap, _ s: PoolPieceSnapshot, _ now: Double, _ cue: PoolCueStyle, _ scale: CGFloat) {
        let r = m.len(R)

        if s.ballInHand && s.kitchen { drawKitchen(ctx, m) }
        if s.callPockets { drawCalls(ctx, m, s, scale) }

        // Pocket pulses sit under the balls.
        for e in s.effects where e.isActive(now) {
            if case .Ring(let color) = e.kind {
                let q = e.progress(now)
                let pk = m.t.pockets.poolMinBy { ($0.c - e.at).length }
                let pr = m.len((pk?.r ?? 6.0) * (1.05 + q * 0.6))
                let c = m.pt(e.at)
                ctx.stroke(PoolArt.circle(c, pr), with: .color(color.alpha((1 - q) * 0.9).color), lineWidth: m.len(0.8) * CGFloat(1 - q * 0.6))
                ctx.fill(PoolArt.circle(c, pr * 0.9), with: .color(PoolRGBA.black.alpha((1 - q) * 0.6).color))
            }
        }

        if let pb = s.playback { drawPlayback(ctx, m, pb, s, now, scale) } else { drawResting(ctx, m, s, now, scale) }

        if s.showCue && s.playback == nil {
            drawGuide(ctx, m, s)
            if s.ballInHand { drawHand(ctx, m, s) }
            let d = Vec2(cos(s.angle), sin(s.angle))
            let gap = R + 0.8 + s.power * 26
            let tip = s.cuePos - d * gap
            if let ring = s.ring {
                // A soft halo round the cue ball while a computer lines up.
                let c = m.pt(s.cuePos)
                let outer = r * 1.8
                ctx.fill(PoolArt.circle(c, outer), with: radial([(0, clear), (0.5, clear), (0.75, ring.alpha(0.8)), (1, clear)], c, outer))
            }
            PoolCueSprites.drawCue(ctx, m.pt(tip), m.vec(d), m.len(142.0), m.len(2.6), cue, scale: scale)
        }
        if let st = s.strike { drawStrike(ctx, m, st, now, cue, scale) }

        for e in s.effects where e.isActive(now) {
            let q = e.progress(now)
            switch e.kind {
            case .Flash(let strength):
                let a = (1 - q) * min(1.0, strength / 500)
                let c = m.pt(e.at)
                let core = r * CGFloat(0.4 + q * 1.2)
                let rad = core + r * 0.4
                let w = PoolRGBA.white
                ctx.fill(PoolArt.circle(c, rad), with: radial([(0, w.alpha(a)), (Double(core / rad) * 0.7, w.alpha(a)), (Double(core / rad), w.alpha(a * 0.5)), (1, clear)], c, rad))
            case .Puff(let angle):
                drawPuff(ctx, m, e, q, angle)
            case .Pop:
                ctx.stroke(PoolArt.circle(m.pt(e.at), r * CGFloat(1.1 + q * 1.6)), with: .color(PoolRGBA.white.alpha(1 - q).color), lineWidth: 2)
            default:
                break
            }
        }
    }

    private static func drawKitchen(_ ctx: GraphicsContext, _ m: PoolTableMap) {
        let t = m.t
        let a = m.pt(-t.a, -t.b)
        let b = m.pt(t.headString, t.b)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        ctx.fill(Path(rect), with: .color(PoolRGBA.white.alpha(0.07).color))
        line(ctx, PoolRGBA.white.alpha(0.55), m.pt(t.headString, -t.b), m.pt(t.headString, t.b), 1.5, dash: [5, 4])
    }

    private static func drawCalls(_ ctx: GraphicsContext, _ m: PoolTableMap, _ s: PoolPieceSnapshot, _ scale: CGFloat) {
        for (i, pk) in m.t.pockets.enumerated() {
            let p = m.pt(pk.c)
            let r = m.len(pk.r * 1.25)
            if i == s.call {
                let ring = PoolArt.circle(p, r)
                PoolArt.glow(ctx, ring, poolHex(0xFFC94A), 8, 3)
                ctx.stroke(ring, with: .color(poolHex(0xFFD24D).color), lineWidth: 3)
                PoolArt.drawBall(ctx, p, m.len(R * 0.8), 8, PoolQuat.identity, m.vertical, false, 0, scale: scale)
            } else {
                ctx.stroke(PoolArt.circle(p, r), with: .color(PoolRGBA.white.alpha(0.45).color), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
    }

    private static func quat(_ row: [Float], _ i: Int) -> Quat {
        Quat(Double(row[4 * i]), Double(row[4 * i + 1]), Double(row[4 * i + 2]), Double(row[4 * i + 3]))
    }

    private static func drawResting(_ ctx: GraphicsContext, _ m: PoolTableMap, _ s: PoolPieceSnapshot, _ now: Double, _ scale: CGFloat) {
        let r = m.len(R)
        let intro = s.introStart.map { now - $0 }
        var popping: Double? = nil
        for e in s.effects where now < e.start + e.duration && e.kind == .Pop && (e.at - s.cuePos).length < 1 {
            popping = e.progress(now)
        }
        for (i, ball) in s.balls.enumerated() {
            if !ball.live { continue }
            let p = ball.n == 0 ? s.cuePos : ball.p
            var size = 1.0
            var alpha = 1.0
            if let intro, ball.n != 0 {
                // Each ball drops into the rack, back rows a touch later.
                let u = max(0.0, min(1.0, (intro - Double(i) * 0.02) / 0.3))
                size = 1 + 0.25 * (1 - u)
                alpha = u
            }
            if ball.n == 0, let pop = popping {
                if pop <= 0 { continue }
                size = pop < 0.7 ? pop / 0.7 * 1.15 : 1.15 - (pop - 0.7) / 0.3 * 0.15
            }
            let q = i < s.orient.count ? s.orient[i] : PoolQuat.identity
            PoolArt.drawBall(ctx, m.pt(p), r * CGFloat(size), ball.n, q, m.vertical, true, r * 0.5, alpha: alpha, shadow: true, scale: scale)
        }
        if let intro { drawRackFrame(ctx, m, s.game, intro) }
    }

    /// The triangle (or diamond) settles the balls, then lifts away.
    private static func drawRackFrame(_ ctx: GraphicsContext, _ m: PoolTableMap, _ game: PoolVariant, _ t: Double) {
        let fx = m.t.footSpot.x
        let d = R * 0.9
        let s3 = (3.0).squareRoot()
        let pts: [Vec2] = game == .EIGHT
            ? [Vec2(fx - 2 * d, 0.0), Vec2(fx + 4 * s3 * R + d, 4 * R + s3 * d), Vec2(fx + 4 * s3 * R + d, -(4 * R + s3 * d))]
            : [Vec2(fx - 2 * d, 0.0), Vec2(fx + 2 * s3 * R, 2 * R + 1.155 * d), Vec2(fx + 4 * s3 * R + 2 * d, 0.0), Vec2(fx + 2 * s3 * R, -(2 * R + 1.155 * d))]
        let lift = max(0.0, min(1.0, (t - 0.45) / 0.5))
        let centre = pts.reduce(Vec2.ZERO) { $0 + $1 } / Double(pts.count)
        var path = Path()
        for (i, p) in pts.enumerated() {
            let q = m.pt(centre + (p - centre) * (1 + lift * 0.12))
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        let opacity = 1 - lift
        if opacity <= 0 { return }
        let width = m.len(1.4)
        // Its shadow drops away as it lifts.
        let shadowPath = path.offsetBy(dx: 0, dy: CGFloat(2 + 8 * lift))
        let blur = CGFloat(4 + 10 * lift)
        for k in 1...3 {
            ctx.stroke(shadowPath, with: .color(PoolRGBA.black.alpha(0.5 * opacity * 0.22).color),
                       style: StrokeStyle(lineWidth: width + blur * CGFloat(k) * 0.6, lineJoin: .round))
        }
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [poolHex(0xE8C27A).alpha(opacity).color, poolHex(0x8A5A20).alpha(opacity).color]),
                                              startPoint: m.pt(pts[0]), endPoint: m.pt(pts[1])),
                   style: StrokeStyle(lineWidth: width, lineJoin: .round))
    }

    private static func drawPlayback(_ ctx: GraphicsContext, _ m: PoolTableMap, _ pb: PoolPlayback, _ s: PoolPieceSnapshot, _ now: Double, _ scale: CGFloat) {
        let real = max(0.0, now - pb.start)
        let t = pb.simTime(real)
        let last = pb.frames.count - 1
        if last < 0 { return }
        let r = m.len(R)
        /// Interpolated table position (cm) of ball [i] at simulated [time].
        func position(_ i: Int, _ time: Double) -> (Float, Float) {
            let f = time * 60
            let i0 = min(Kt.toInt(f), last)
            let i1 = min(i0 + 1, last)
            let frac = Float(f - Double(i0))
            let a = pb.frames[i0]
            let b = pb.frames[i1]
            return (a[2 * i] + (b[2 * i] - a[2 * i]) * frac, a[2 * i + 1] + (b[2 * i + 1] - a[2 * i + 1]) * frac)
        }
        func screen(_ o: (Float, Float)) -> CGPoint { m.pt(Double(o.0), Double(o.1)) }
        let frame = min(Kt.toInt(t * 60), last)
        for i in pb.numbers.indices {
            if !(i < pb.live.count ? pb.live[i] : true) { continue }
            let n = pb.numbers[i]
            let q = quat(pb.turns[frame], i)
            if let drop = pb.potted.last(where: { $0.ball == i }), t >= drop.time {
                // Sinking: into the hole, smaller and darker.
                let u = (t - drop.time) / 0.25
                if u >= 1 { continue }
                let at = screen(position(i, drop.time))
                let hole = m.pt(m.t.pockets[drop.pocket].c)
                let p = CGPoint(x: at.x + (hole.x - at.x) * CGFloat(u), y: at.y + (hole.y - at.y) * CGFloat(u))
                PoolArt.drawBall(ctx, p, r * CGFloat(1 - 0.4 * u), n, q, m.vertical, true, r * 0.5, alpha: 1 - u, scale: scale)
                continue
            }
            let now2 = position(i, t)
            // Fast balls leave a faint trail.
            if !s.reduceMotion && frame >= 3 {
                let back = pb.frames[frame - 3]
                let dx = now2.0 - back[2 * i]
                let dy = now2.1 - back[2 * i + 1]
                let speed = Double((dx * dx + dy * dy).squareRoot()) * 20
                if speed > 120 {
                    let colour = n == 0 ? PoolRGBA.white : PoolBallColour.colour(n)
                    line(ctx, colour.alpha(min(0.3, speed / 1800)), m.pt(back, i), screen(now2), r * 1.4, cap: .round)
                }
            }
            PoolArt.drawBall(ctx, screen(now2), r, n, q, m.vertical, true, r * 0.5, shadow: true, scale: scale)
        }
    }

    private static func drawGuide(_ ctx: GraphicsContext, _ m: PoolTableMap, _ s: PoolPieceSnapshot) {
        let g = s.guide
        guard let end = g.end else { return }
        let bad = poolHex(0xFF4D4D)
        line(ctx, PoolRGBA.white.alpha(0.85), m.pt(s.cuePos), m.pt(end), 1.6, cap: .round)
        guard let ghost = g.ghost else { return }
        let r = m.len(R)
        ctx.stroke(PoolArt.circle(m.pt(ghost), r), with: .color((g.legal ? PoolRGBA.white.alpha(0.9) : bad).color), lineWidth: 1.6)
        if !g.legal {
            let c = m.pt(ghost)
            let k = r * 0.5
            line(ctx, bad, CGPoint(x: c.x - k, y: c.y - k), CGPoint(x: c.x + k, y: c.y + k), 2, cap: .round)
            line(ctx, bad, CGPoint(x: c.x + k, y: c.y - k), CGPoint(x: c.x - k, y: c.y + k), 2, cap: .round)
            return
        }
        if let target = g.target, let objectEnd = g.objectEnd, target < s.balls.count {
            let from = m.pt(s.balls[target].p)
            let to = m.pt(objectEnd)
            line(ctx, PoolRGBA.white.alpha(0.9), from, to, 2, cap: .round)
            let dx = to.x - from.x
            let dy = to.y - from.y
            let l = max(0.01, hypot(dx, dy))
            let ux = dx / l
            let uy = dy / l
            var head = Path()
            head.move(to: CGPoint(x: to.x + ux * 5, y: to.y + uy * 5))
            head.addLine(to: CGPoint(x: to.x - uy * 3.5, y: to.y + ux * 3.5))
            head.addLine(to: CGPoint(x: to.x + uy * 3.5, y: to.y - ux * 3.5))
            head.closeSubpath()
            ctx.fill(head, with: .color(PoolRGBA.white.alpha(0.9).color))
        }
        if let cueEnd = g.cueEnd {
            line(ctx, PoolRGBA.white.alpha(0.45), m.pt(ghost), m.pt(cueEnd), 1.4, cap: .round, dash: [3, 3])
        }
    }

    /// Ball in hand: a ring with arrows round the cue ball, red while it touches a ball.
    private static func drawHand(_ ctx: GraphicsContext, _ m: PoolTableMap, _ s: PoolPieceSnapshot) {
        let c = m.pt(s.cuePos)
        let r = m.len(R)
        let colour = s.cueValid ? PoolRGBA.white : poolHex(0xFF4D4D)
        let ring = r * (s.placing ? 3.0 : 2.4)
        let ringPath = PoolArt.circle(c, ring)
        PoolArt.glow(ctx, ringPath, PoolRGBA.black.alpha(0.4), 3, 2)
        ctx.stroke(ringPath, with: .color(colour.alpha(0.9).color), lineWidth: 2)
        if s.placing { ctx.fill(ringPath, with: .color(colour.alpha(0.08).color)) }
        for k in 0..<4 {
            let a = Double(k) * Double.pi / 2
            let dx = CGFloat(cos(a))
            let dy = CGFloat(sin(a))
            let bx = c.x + dx * (ring + 3)
            let by = c.y + dy * (ring + 3)
            var arrow = Path()
            arrow.move(to: CGPoint(x: bx + dx * 7, y: by + dy * 7))
            arrow.addLine(to: CGPoint(x: bx - dy * 4.5, y: by + dx * 4.5))
            arrow.addLine(to: CGPoint(x: bx + dy * 4.5, y: by - dx * 4.5))
            arrow.closeSubpath()
            PoolArt.glow(ctx, arrow, PoolRGBA.black.alpha(0.4), 2)
            ctx.fill(arrow, with: .color(colour.color))
        }
    }

    /// The cue drives through the ball, then follows through and fades.
    private static func drawStrike(_ ctx: GraphicsContext, _ m: PoolTableMap, _ st: PoolStrike, _ now: Double, _ cue: PoolCueStyle, _ scale: CGFloat) {
        let t = now - st.start
        if t >= 0.45 || t < 0 { return }
        let d = Vec2(cos(st.angle), sin(st.angle))
        let pulled = R + 0.8 + st.power * 26
        let gap: Double
        var alpha = 1.0
        if t < 0.07 {
            let u = t / 0.07
            gap = pulled + (R - 1.2 - pulled) * u * u
        } else {
            gap = R - 1.2 - min(1.0, (t - 0.07) / 0.1) * 1.5
            alpha = max(0.0, 1 - (t - 0.12) / 0.33)
        }
        PoolCueSprites.drawCue(ctx, m.pt(st.at - d * gap), m.vec(d), m.len(142.0), m.len(2.6), cue, alpha: alpha, scale: scale)
    }

    private static func drawPuff(_ ctx: GraphicsContext, _ m: PoolTableMap, _ e: PoolEffect, _ q: Double, _ angle: Double) {
        let rng = PoolRandom(Int64(e.id))
        let opacity = (1 - q) * 0.8
        let colour = poolHex(0x8CC4FF).alpha(opacity).color
        for _ in 0..<9 {
            let a = angle + Double.pi + (rng.unit() - 0.5) * 1.4
            let dist = (0.5 + rng.unit() * 3.5) * q
            let p = e.at + Vec2(cos(a), sin(a)) * dist
            ctx.fill(PoolArt.circle(m.pt(p), m.len(0.25 + rng.unit() * 0.35) * CGFloat(1 + q)), with: .color(colour))
        }
    }
}
