import Foundation

/// A computer's chosen shot, with the geometry behind it for the aim guide.
struct PoolPlan: Sendable {
    var shot: PoolShot
    var target: Int = -1
    var pocket: Int = -1
    var ghost: Vec2 = Vec2.ZERO
    var score: Double = 0.0

    init(_ shot: PoolShot, target: Int = -1, pocket: Int = -1, ghost: Vec2 = Vec2.ZERO, score: Double = 0.0) {
        self.shot = shot
        self.target = target
        self.pocket = pocket
        self.ghost = ghost
        self.score = score
    }
}

/// Computer players: ghost-ball planning, then each promising shot is played in the real engine and
/// scored. From scattered positions Easy pockets its own ball 35% of the time, Normal 63% and Hard 81%.
enum PoolBot {
    static func noise(_ level: PoolDifficulty) -> (Double, Double) {
        switch level {
        case .EASY: return (1.5 * Double.pi / 180, 0.12)
        case .NORMAL: return (0.55 * Double.pi / 180, 0.05)
        case .HARD: return (0.2 * Double.pi / 180, 0.02)
        }
    }

    static func clear(_ t: PoolTableState, _ a: Vec2, _ b: Vec2, _ except: Set<Int>) -> Bool {
        let ab = b - a
        let l2 = ab.dot(ab)
        for ball in t.balls {
            if !ball.live || except.contains(ball.n) { continue }
            let u = l2 > 0 ? poolMax(0.0, poolMin(1.0, (ball.p - a).dot(ab) / l2)) : 0.0
            if (a + ab * u - ball.p).length < 2 * PoolTableGeometry.R - 0.05 { return false }
        }
        return true
    }

    /// Ghost-ball shots for every legal ball and pocket, from where the cue ball is (or could be placed).
    static func candidates(_ t: PoolTableState) -> [PoolPlan] {
        let R = PoolTableGeometry.R
        let geo = t.geometry
        var list: [PoolPlan] = []
        let targets = t.game == .NINE ? (t.lowest.map { [$0] } ?? []) : t.legalFirst()
        for n in targets {
            guard let ball = t.ball(n) else { continue }
            for (pi, aim) in geo.aimPoints.enumerated() {
                let toP = aim - ball.p
                let lp = toP.length
                let u = toP / lp
                // Side pockets only take balls coming in fairly square.
                if pi >= 4 && abs(u.y) < 0.55 { continue }
                let ghost = ball.p - u * 2.0 * R
                var cue = t.cue.p
                if t.ballInHand {
                    var spot = ghost - u * 26.0
                    var tries = 0
                    while !t.free(spot) && tries < 12 {
                        spot = ghost - u.rotated(Double(tries % 2 == 0 ? tries : -tries) * 0.12) * (26.0 - Double(tries))
                        tries += 1
                    }
                    if !t.free(spot) { continue }
                    cue = spot
                }
                let toG = ghost - cue
                let lg = toG.length
                if lg <= 1 { continue }
                let dir = toG / lg
                let cut = dir.dot(u)
                if !(cut > 0.26 && clear(t, cue, ghost, [0, n]) && clear(t, ball.p, aim, [n])) { continue }
                // The object ball leaves as a stun: it slides, then rolls to the pocket with margin.
                let objectSpeed = PoolPhysics.stunSpeed(lp + 10)
                let atContact = objectSpeed / poolMax(0.3, cut) / ((1 + PoolPhysics.eBall) / 2)
                let v0 = PoolPhysics.stunLaunch(atContact, lg) * 1.04
                let heuristic = cut * cut * 100 - (lg + lp) * 0.25 - (v0 > PoolPhysics.maxSpeed ? 40.0 : 0.0)
                let call: Int? = n == 8 ? pi : nil
                list.append(
                    PoolPlan(
                        PoolShot(angle: PoolSM.atan2(dir.y, dir.x), power: PoolPhysics.power(forSpeed: v0), place: t.ballInHand ? cue : nil, call: call),
                        target: n, pocket: pi, ghost: ghost, score: heuristic
                    )
                )
            }
        }
        return list.poolSortedByDescending { $0.score }
    }

    /// Legal balls the cue ball can see straight on: a cheap measure of the position left.
    static func leave(_ t: PoolTableState) -> Int {
        t.legalFirst().compactMap { t.ball($0) }.filter { clear(t, t.cue.p, $0.p, [0, $0.n]) }.count
    }

    static func value(_ before: PoolTableState, _ after: PoolTableState, _ r: PoolStroke, _ position: Bool) -> Double {
        let me = before.unitNow
        if let w = after.winner { return w == me ? 5000.0 : -5000.0 }
        var v = r.continues ? 60.0 : 0.0
        if r.foul { v -= 220 }
        let g = before.game == .EIGHT ? after.groups[me] : nil
        if let g {
            v += Double(r.potted.filter { g.has($0) }.count) * 100.0
            v -= Double(r.potted.filter { $0 != 0 && $0 != 8 && !g.has($0) }.count) * 40.0
        } else {
            v += Double(r.potted.filter { $0 != 0 }.count) * 90.0
        }
        if position && r.continues { v += Double(min(4, leave(after))) * 8.0 }
        return v
    }

    static func evaluate(_ t: PoolTableState, _ s: PoolShot, _ position: Bool) -> Double {
        var copy = t.clone()
        let r = copy.play(s)
        return value(t, copy, r, position)
    }

    static func breakShot(_ t: PoolTableState, _ level: PoolDifficulty, _ rng: PoolRandom) -> PoolPlan {
        let geo = t.geometry
        let place = Vec2(geo.headString - 4, (rng.unit() - 0.5) * 8)
        let dir = (geo.footSpot - place).normalized
        let power = level == .EASY ? 0.86 : 1.0
        return PoolPlan(PoolShot(angle: PoolSM.atan2(dir.y, dir.x) + rng.normal() * noise(level).0 * 0.6, power: power, place: place))
    }

    static func plan(_ t: PoolTableState, _ level: PoolDifficulty, _ seed: Int64) -> PoolPlan {
        let rng = PoolRandom(seed)
        if !t.broken { return breakShot(t, level, rng) }
        let all = candidates(t)
        let count: Int
        switch level {
        case .EASY: count = 4
        case .NORMAL: count = 8
        case .HARD: count = 12
        }
        var best: PoolPlan? = nil
        for c in all.prefix(count) {
            var options = [c.shot]
            if level == .HARD {
                // Hard also tries follow and draw for position.
                var follow = c.shot
                follow.spin = Vec2(0.0, 0.35)
                options.append(follow)
                var draw = c.shot
                draw.spin = Vec2(0.0, -0.35)
                draw.power = poolMin(1.0, c.shot.power * 1.12)
                options.append(draw)
            }
            for s in options {
                let v = evaluate(t, s, level == .HARD)
                if best == nil || v > best!.score {
                    var b = c
                    b.shot = s
                    b.score = v
                    best = b
                }
            }
        }
        var chosen = best ?? safety(t)
        let n = noise(level)
        let angle = chosen.shot.angle + rng.normal() * n.0
        let power = poolMax(0.05, poolMin(1.0, chosen.shot.power * (1 + rng.normal() * n.1)))
        chosen.shot.angle = angle
        chosen.shot.power = power
        return chosen
    }

    /// No pot: a roll into a legal ball, firm enough to reach a cushion.
    static func safety(_ t: PoolTableState) -> PoolPlan {
        let cueP = t.cue.p
        let first = t.legalFirst().compactMap { t.ball($0) }.poolMinBy { ($0.p - cueP).length }
        let dir = first.map { ($0.p - cueP).normalized } ?? Vec2(1.0, 0.0)
        return PoolPlan(PoolShot(angle: PoolSM.atan2(dir.y, dir.x), power: 0.42, place: t.ballInHand ? t.cue.p : nil), target: first?.n ?? -1, score: -1.0)
    }
}
