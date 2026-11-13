import Foundation
import GameKit

/// A small seeded generator (SplitMix64), so computer turns can be replayed in tests.
struct CarromRandom {
    private var mix: SplitMix64

    init(_ seed: UInt64) { mix = SplitMix64(seed: seed) }

    var state: UInt64 { mix.state }

    mutating func next() -> UInt64 { mix.nextRaw() }

    mutating func unit() -> Double { Double(Int64(bitPattern: next() >> 11)) / Double(Int64(1) << 53) }

    mutating func normal() -> Double {
        let a = (-2 * CarromFdLibm.log(CarromMath.max(unit(), 1e-12))).squareRoot()
        return a * CarromFdLibm.cos(2 * Double.pi * unit())
    }
}

/// A computer's chosen shot, with the geometry behind it for the aim guide.
struct CarromPlan {
    var shot: CarromShot
    var target: Int = -1
    var pocket: Int = -1
    var ghost: CarromVec = CarromVec.ZERO
    var score: Double = 0.0

    init(shot: CarromShot, target: Int = -1, pocket: Int = -1, ghost: CarromVec = CarromVec.ZERO, score: Double = 0.0) {
        self.shot = shot
        self.target = target
        self.pocket = pocket
        self.ghost = ghost
        self.score = score
    }
}

/// Computer players: ghost-disc planning, then each promising shot is played in the real engine and scored.
/// Measured in docs/research/carrom/sim-results.md: from scattered positions Easy pockets its own coin 26% of the
/// time, Normal 64% and Hard 89%.
enum CarromBot {
    struct Noise {
        let angle: Double
        let power: Double
        let slide: Double

        init(_ angle: Double, _ power: Double, _ slide: Double) {
            self.angle = angle
            self.power = power
            self.slide = slide
        }
    }

    static func noise(_ level: CarromDifficulty) -> Noise {
        switch level {
        case .EASY: return Noise(2.4 * Double.pi / 180, 0.10, 0.03)
        case .NORMAL: return Noise(0.9 * Double.pi / 180, 0.045, 0.012)
        case .HARD: return Noise(0.35 * Double.pi / 180, 0.02, 0.005)
        }
    }

    static func jitter(_ s: CarromShot, _ level: CarromDifficulty, _ rng: inout CarromRandom) -> CarromShot {
        let n = noise(level)
        // Errors apply to the launch speed, then convert back through the power curve.
        let speed = CarromPhysics.speedForPower(s.power) * (1 + rng.normal() * n.power)
        let slide = CarromMath.max(-1.0, CarromMath.min(1.0, s.slide + rng.normal() * n.slide))
        let angle = s.angle + rng.normal() * n.angle
        return CarromShot(slide: slide, angle: angle, power: CarromPhysics.powerForSpeed(speed))
    }

    static func clear(_ t: CarromTable, _ from: CarromVec, _ to: CarromVec, _ radius: Double, _ except: Int) -> Bool {
        let ab = to - from
        let l2 = ab.dot(ab)
        for i in t.coins.indices {
            let c = t.coins[i]
            if !c.live || i == except { continue }
            let cp = c.p
            let u = l2 > 0 ? CarromMath.max(0.0, CarromMath.min(1.0, (cp - from).dot(ab) / l2)) : 0.0
            if (from + ab * u - cp).length < radius - 0.02 { return false }
        }
        return true
    }

    /// Ghost-disc shots: for every free striker spot, allowed coin and pocket, where the striker must meet the coin
    /// to send it into the pocket, with both paths clear.
    static func candidates(_ t: CarromTable) -> [CarromPlan] {
        let fwd = CarromBoard.forward(t.side)
        let transfer = (1 + CarromPhysics.eStriker) * CarromBoard.strikerM / (CarromBoard.strikerM + CarromBoard.coinM)
        let targets = t.targets()
        var list: [CarromPlan] = []
        for step in 0...24 {
            let slide = -1 + Double(step) / 12
            if !t.strikerFits(slide) { continue }
            let s = t.strikerSpot(slide)
            for ti in targets {
                let c = t.coins[ti].p
                for (pi, p) in CarromBoard.pockets.enumerated() {
                    let toP = p - c
                    let lp = toP.length
                    let u = toP / lp
                    let ghost = c - u * (CarromBoard.coinR + CarromBoard.strikerR)
                    let toG = ghost - s
                    let lg = toG.length
                    if lg <= 0.5 { continue }
                    let dir = toG / lg
                    if dir.dot(fwd) <= -0.05 { continue }
                    let cut = dir.dot(u)
                    if !(cut > 0.25 &&
                        clear(t, s, ghost, CarromBoard.coinR + CarromBoard.strikerR, ti) &&
                        clear(t, c, p, 2 * CarromBoard.coinR, ti)) { continue }
                    let coinSpeed = CarromPhysics.speedToTravel(lp + 2.5)
                    let v0 = CarromPhysics.launch(coinSpeed / (cut * transfer), lg) * 1.1
                    let heuristic = cut * cut * 100 - (lg + lp) * 0.45 - (v0 > CarromPhysics.maxSpeed ? 30.0 : 0.0)
                    list.append(CarromPlan(
                        shot: CarromShot(slide, CarromFdLibm.atan2(dir.y, dir.x), CarromPhysics.powerForSpeed(v0)),
                        target: ti, pocket: pi, ghost: ghost, score: heuristic
                    ))
                }
            }
        }
        // sortedByDescending: stable, compared like java.lang.Double.
        let order = list.indices.sorted { a, b in
            let c = CarromMath.compare(list[b].score, list[a].score)
            return c != 0 ? c < 0 : a < b
        }
        return order.map { list[$0] }
    }

    /// How good a stroke was for the shooter.
    static func value(_ before: CarromTable, _ after: CarromTable, _ r: CarromStroke) -> Double {
        let me = before.unitNow
        if let w = after.winner { return w == me ? 2000.0 : -2000.0 }
        var v = r.continues ? 30.0 : 0.0
        if r.foul { v -= 160 }
        switch before.mode {
        case .FREESTYLE:
            v += Double(r.points) * 2.2
            if r.queenWaiting { v += 40 }
        case .CLASSIC, .POOL:
            let mine = before.colour(me)
            let theirs = before.colour(1 - me)
            v += Double(r.pocketed.filter { $0 == mine }.count) * 100.0
            v -= Double(r.pocketed.filter { $0 == theirs }.count) * 60.0
            if r.queenCovered { v += 140 }
            if r.queenWaiting { v += 45 }
            if r.queenFirst { v -= 130 }
        }
        return v
    }

    static func evaluate(_ t: CarromTable, _ shot: CarromShot) -> Double {
        let copy = t.deepCopy()
        let r = copy.play(shot)
        return value(t, copy, r)
    }

    static func breakShot(_ t: CarromTable, _ level: CarromDifficulty, _ rng: inout CarromRandom) -> CarromPlan {
        let options: [(Double, Double)] = [(0.0, 0.0), (0.18, -0.02), (-0.18, 0.02), (0.35, -0.035), (-0.35, 0.035), (0.1, 0.012)]
        let tries = level == .HARD ? options.count : (level == .NORMAL ? 3 : 1)
        let power = level == .EASY ? 0.93 : 1.0
        var best = CarromPlan(shot: CarromShot(0.0, 0.0, power), score: -Double.infinity)
        for (slide, offset) in options.prefix(tries) {
            let s = t.strikerSpot(slide)
            let aim = (CarromVec.ZERO - s).normalized.rotated(offset)
            let shot = CarromShot(slide, CarromFdLibm.atan2(aim.y, aim.x), power)
            let v = tries == 1 ? 0.0 : evaluate(t, shot)
            if v > best.score { best = CarromPlan(shot: shot, score: v) }
        }
        best.shot = jitter(best.shot, level, &rng)
        return best
    }

    static func plan(_ t: CarromTable, _ level: CarromDifficulty, _ seed: UInt64) -> CarromPlan {
        var rng = CarromRandom(seed)
        if !t.broken { return breakShot(t, level, &rng) }
        let all = candidates(t)
        let pool = Array(all.prefix(level == .EASY ? 5 : (level == .NORMAL ? 12 : 26)))
        var best: CarromPlan? = nil
        for original in pool {
            var c = original
            var v = evaluate(t, c.shot)
            if level == .HARD {
                for _ in 0..<2 { v += evaluate(t, jitter(c.shot, .HARD, &rng)) }
                v /= 3
            }
            c.score = v
            if best == nil || v > best!.score { best = c }
        }
        if level == .EASY && !pool.isEmpty && rng.unit() < 0.35 {
            best = pool[Kt.toInt(rng.unit() * Double(pool.count)) % pool.count]
        }
        var chosen = best ?? safety(t)
        chosen.shot = jitter(chosen.shot, level, &rng)
        return chosen
    }

    /// Nothing pottable: knock the nearest allowed coin softly towards the middle.
    static func safety(_ t: CarromTable) -> CarromPlan {
        let slide = t.freeSlide(0.0)
        let s = t.strikerSpot(slide)
        var near: Int? = nil
        var nearest = 0.0
        for i in t.targets() {
            let d = (t.coins[i].p - s).length
            if near == nil || nearest > d { near = i; nearest = d }
        }
        let aim = near.map { (t.coins[$0].p - s).normalized } ?? CarromBoard.forward(t.side)
        return CarromPlan(shot: CarromShot(slide, CarromFdLibm.atan2(aim.y, aim.x), 0.62), score: -1.0)
    }
}
