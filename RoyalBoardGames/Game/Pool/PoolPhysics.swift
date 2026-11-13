import Foundation

/// A ball on the table. (wx, wy, wz) is its spin: x and y roll or slide it, z is side spin (english).
struct PoolBall: Equatable, Codable, Sendable {
    /// 0 cue, 1–7 solids, 8, 9–15 stripes.
    var n: Int = 0
    var x: Double = 0.0
    var y: Double = 0.0
    var vx: Double = 0.0
    var vy: Double = 0.0
    var wx: Double = 0.0
    var wy: Double = 0.0
    var wz: Double = 0.0
    var live: Bool = true

    init(n: Int = 0, x: Double = 0.0, y: Double = 0.0, vx: Double = 0.0, vy: Double = 0.0,
         wx: Double = 0.0, wy: Double = 0.0, wz: Double = 0.0, live: Bool = true) {
        self.n = n; self.x = x; self.y = y; self.vx = vx; self.vy = vy
        self.wx = wx; self.wy = wy; self.wz = wz; self.live = live
    }

    init(_ n: Int, _ p: Vec2) { self.init(n: n, x: p.x, y: p.y) }

    var p: Vec2 {
        get { Vec2(x, y) }
        set { x = newValue.x; y = newValue.y }
    }

    var v: Vec2 { Vec2(vx, vy) }

    var moving: Bool { vx != 0.0 || vy != 0.0 || wx != 0.0 || wy != 0.0 || wz != 0.0 }

    mutating func stop() { vx = 0.0; vy = 0.0; wx = 0.0; wy = 0.0; wz = 0.0 }

    func copy() -> PoolBall { self }

    private enum CodingKeys: String, CodingKey { case n, x, y, vx, vy, wx, wy, wz, live }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.0
        vx = try c.decodeIfPresent(Double.self, forKey: .vx) ?? 0.0
        vy = try c.decodeIfPresent(Double.self, forKey: .vy) ?? 0.0
        wx = try c.decodeIfPresent(Double.self, forKey: .wx) ?? 0.0
        wy = try c.decodeIfPresent(Double.self, forKey: .wy) ?? 0.0
        wz = try c.decodeIfPresent(Double.self, forKey: .wz) ?? 0.0
        live = try c.decodeIfPresent(Bool.self, forKey: .live) ?? true
    }
}

/// Fixed-step ball physics with spin: sliding to natural roll, follow and draw, side spin with
/// squirt, cut and spin throw, and english off the cushions. Deterministic, so saves, the
/// computers' look-ahead and the tests agree.
enum PoolPhysics {
    static let g = 981.0
    /// Ball on cloth while sliding (Alciatore).
    static let muSlide = 0.2
    /// Rolling resistance, a touch above 0.01 so shots settle briskly.
    static let muRoll = 0.016
    static let spinDecay = 11.0
    static let eBall = 0.94
    static let muBall = 0.06
    static let eCushion = 0.78
    static let muCushion = 0.18
    /// cm/s: a hard break, about 38 km/h.
    static let maxSpeed = 1050.0
    static let powerCurve = 1.6
    /// 16 substeps per 60 fps frame keeps every step under 0.8 cm: nothing tunnels.
    static let substeps = 16
    static let dt = 1.0 / 960
    static let maxTime = 20.0

    static func speed(forPower: Double) -> Double { maxSpeed * PoolSM.pow(poolMax(0.02, poolMin(1.0, forPower)), powerCurve) }
    static func power(forSpeed: Double) -> Double { PoolSM.pow(poolMax(0.0, poolMin(1.0, forSpeed / maxSpeed)), 1 / powerCurve) }

    enum Kind: Sendable { case Hit, Cushion, Jaw, Pocket }

    struct Event: Sendable {
        let kind: Kind
        let time: Double
        let strength: Double
        let ball: Int
        let other: Int
        let at: Vec2
        /// For [Kind.Pocket]: which pocket.
        let pocket: Int

        init(_ kind: Kind, _ time: Double, _ strength: Double, _ ball: Int, other: Int = -1, at: Vec2, pocket: Int = -1) {
            self.kind = kind
            self.time = time
            self.strength = strength
            self.ball = ball
            self.other = other
            self.at = at
            self.pocket = pocket
        }
    }

    struct Potted: Equatable, Sendable {
        let ball: Int
        let pocket: Int
        let time: Double

        init(_ ball: Int, _ pocket: Int, _ time: Double) {
            self.ball = ball
            self.pocket = pocket
            self.time = time
        }
    }

    final class Run: @unchecked Sendable {
        /// Positions at 60 fps: one array per frame of (x, y) pairs in ball order.
        var frames: [[Float]] = []
        var events: [Event] = []
        /// Balls (by index) in the order they dropped.
        var potted: [Potted] = []
        /// Number of the first object ball the cue ball met.
        var firstHit: Int? = nil
        var railAfterContact = false
        /// Numbers of the balls that touched a cushion (for the break rule).
        var cushionBalls = Set<Int>()
        var duration = 0.0

        init() {}
    }

    /// Cue tip offset [spin] (−0.5…0.5 of a radius each way: x right english, y follow) sets the spin.
    static func strike(_ cue: inout PoolBall, _ angle: Double, _ power: Double, _ spin: Vec2) {
        let V = speed(forPower: power)
        let d = Vec2(PoolSM.cos(angle), PoolSM.sin(angle))
        let v = d.rotated(-spin.x * 0.035) * V
        cue.vx = v.x; cue.vy = v.y
        let R = PoolTableGeometry.R
        let roll = 2.5 * spin.y * V / R
        let axis = Vec2(-d.y, d.x)
        cue.wx = axis.x * roll
        cue.wy = axis.y * roll
        cue.wz = -2.5 * spin.x * V / R
    }

    static func run(_ balls: inout [PoolBall], _ t: PoolTableGeometry, _ record: Bool) -> Run {
        let run = Run()
        var time = 0.0
        var step = 0
        func snap() -> [Float] {
            var f = [Float](repeating: 0, count: balls.count * 2)
            for i in balls.indices { f[2 * i] = Float(balls[i].x); f[2 * i + 1] = Float(balls[i].y) }
            return f
        }
        if record { run.frames.append(snap()) }
        while time < maxTime {
            let moving = advance(&balls, t, run, time)
            time += dt
            step += 1
            if record && step % substeps == 0 { run.frames.append(snap()) }
            if !moving { break }
        }
        if record { run.frames.append(snap()) }
        run.duration = time
        return run
    }

    /// One substep. Returns whether anything is still moving.
    static func advance(_ balls: inout [PoolBall], _ t: PoolTableGeometry, _ run: Run, _ time: Double) -> Bool {
        let R = PoolTableGeometry.R
        let cushions = t.cushions
        let pockets = t.pockets
        let count = balls.count
        return balls.withUnsafeMutableBufferPointer { bp -> Bool in
            var moving = false
            for i in 0..<count {
                if !bp[i].live || !bp[i].moving { continue }
                var b = bp[i]
                // The contact point's slip on the cloth.
                let ux = b.vx - R * b.wy
                let uy = b.vy + R * b.wx
                let slip = (ux * ux + uy * uy).squareRoot()
                if slip > 0.4 {
                    let dv = muSlide * g * dt
                    if 3.5 * dv >= slip {
                        b.vx -= ux * (2.0 / 7.0)
                        b.vy -= uy * (2.0 / 7.0)
                        b.wx = -b.vy / R
                        b.wy = b.vx / R
                    } else {
                        let uhx = ux / slip
                        let uhy = uy / slip
                        b.vx -= uhx * dv
                        b.vy -= uhy * dv
                        let k = 2.5 * dv / R
                        b.wx += -uhy * k
                        b.wy += uhx * k
                    }
                } else {
                    let s = (b.vx * b.vx + b.vy * b.vy).squareRoot()
                    let ns = s - muRoll * g * dt
                    if ns <= 0 {
                        b.vx = 0.0; b.vy = 0.0
                        b.wx = 0.0; b.wy = 0.0
                    } else {
                        b.vx *= ns / s
                        b.vy *= ns / s
                        b.wx = -b.vy / R
                        b.wy = b.vx / R
                    }
                }
                if b.wz != 0.0 {
                    let dz = spinDecay * dt
                    b.wz = abs(b.wz) <= dz ? 0.0 : b.wz - (b.wz > 0 ? dz : -dz)
                }
                b.x += b.vx * dt
                b.y += b.vy * dt
                bp[i] = b
                moving = true
            }
            for i in 0..<count {
                if !bp[i].live || (bp[i].vx == 0.0 && bp[i].vy == 0.0) { continue }
                var b = bp[i]
                for s in cushions {
                    let abx = s.qx - s.px
                    let aby = s.qy - s.py
                    let u = poolMax(0.0, poolMin(1.0, ((b.x - s.px) * abx + (b.y - s.py) * aby) / (abx * abx + aby * aby)))
                    let cx = s.px + abx * u
                    let cy = s.py + aby * u
                    let dx = b.x - cx
                    let dy = b.y - cy
                    let d = (dx * dx + dy * dy).squareRoot()
                    if !(d < R && d > 1e-9) { continue }
                    let nx = dx / d
                    let ny = dy / d
                    b.x = cx + nx * R
                    b.y = cy + ny * R
                    let vn = b.vx * nx + b.vy * ny
                    if !(vn < 0) { continue }
                    let tx = -ny
                    let ty = nx
                    let vt = b.vx * tx + b.vy * ty
                    // Running english grips the cushion and changes the rebound.
                    let slipT = vt + R * b.wz
                    let jn = (1 + eCushion) * -vn
                    let jt = poolMax(-muCushion * jn, poolMin(muCushion * jn, slipT * 2.0 / 7.0))
                    b.vx = nx * (-eCushion * vn) + tx * (vt - jt)
                    b.vy = ny * (-eCushion * vn) + ty * (vt - jt)
                    b.wz -= 2.5 * jt / R
                    b.wx *= 0.7
                    b.wy *= 0.7
                    run.cushionBalls.insert(b.n)
                    if run.firstHit != nil { run.railAfterContact = true }
                    run.events.append(Event(s.jaw ? .Jaw : .Cushion, time, -vn, i, at: Vec2(cx, cy)))
                }
                bp[i] = b
            }
            for i in 0..<count {
                if !bp[i].live { continue }
                let bx = bp[i].x
                let by = bp[i].y
                var dropped = -1
                for pi in pockets.indices {
                    let pk = pockets[pi]
                    let dx = bx - pk.c.x
                    let dy = by - pk.c.y
                    if (dx * dx + dy * dy).squareRoot() < pk.r { dropped = pi; break }
                }
                // Anything past the cushion line in a pocket's throat has gone in.
                if dropped < 0 && (abs(bx) > t.a + 2 * R || abs(by) > t.b + 2 * R) {
                    let bpos = Vec2(bx, by)
                    dropped = Array(pockets.indices).poolMinBy { (pockets[$0].c - bpos).length } ?? -1
                }
                if dropped >= 0 {
                    bp[i].live = false
                    bp[i].stop()
                    run.potted.append(Potted(i, dropped, time))
                    run.events.append(Event(.Pocket, time, 0.0, i, at: bp[i].p, pocket: dropped))
                }
            }
            // Contacts are resolved a few passes over, so a packed rack passes the break's energy on
            // through every ball in one substep, as real racks do.
            for _ in 0..<4 {
                var touched = false
                for i in 0..<count {
                    if !bp[i].live { continue }
                    for j in (i + 1)..<count {
                        if !bp[j].live { continue }
                        if !(bp[i].moving || bp[j].moving) { continue }
                        let dx = bp[j].x - bp[i].x
                        let dy = bp[j].y - bp[i].y
                        let d2 = dx * dx + dy * dy
                        if !(d2 < 4 * R * R && d2 > 1e-12) { continue }
                        let d = d2.squareRoot()
                        let nx = dx / d
                        let ny = dy / d
                        let overlap = 2 * R - d
                        bp[i].x -= nx * (overlap / 2); bp[i].y -= ny * (overlap / 2)
                        bp[j].x += nx * (overlap / 2); bp[j].y += ny * (overlap / 2)
                        let vn = (bp[i].vx - bp[j].vx) * nx + (bp[i].vy - bp[j].vy) * ny
                        if !(vn > 0) { continue }
                        let jn = (1 + eBall) / 2 * vn
                        bp[i].vx -= nx * jn; bp[i].vy -= ny * jn
                        bp[j].vx += nx * jn; bp[j].vy += ny * jn
                        // Cut and spin throw: friction between the balls, within the friction cone.
                        let tx = -ny
                        let ty = nx
                        let slip = (bp[i].vx - bp[j].vx) * tx + (bp[i].vy - bp[j].vy) * ty + R * (bp[i].wz + bp[j].wz)
                        let jt = poolMax(-muBall * jn, poolMin(muBall * jn, slip / 7))
                        bp[i].vx -= tx * jt; bp[i].vy -= ty * jt
                        bp[j].vx += tx * jt; bp[j].vy += ty * jt
                        bp[i].wz -= 2.5 * jt / R
                        bp[j].wz -= 2.5 * jt / R
                        moving = true
                        touched = true
                        run.events.append(Event(.Hit, time, jn, i, other: j, at: Vec2(bp[i].x + nx * R, bp[i].y + ny * R)))
                        if run.firstHit == nil {
                            if bp[i].n == 0 { run.firstHit = bp[j].n } else if bp[j].n == 0 { run.firstHit = bp[i].n }
                        }
                    }
                }
                if !touched { break }
            }
            return moving
        }
    }

    // MARK: Planning helpers (closed forms of the same slide-then-roll model)

    /// A stun (no spin) slides until it rolls at 5/7 of its speed, then rolls to a stop.
    private static var slideK: Double { (24.0 / 49.0) / (2 * muSlide * g) }

    static func stunTravel(_ v0: Double) -> Double { v0 * v0 * (slideK + (25.0 / 49.0) / (2 * muRoll * g)) }

    static func stunSpeed(_ toTravel: Double) -> Double {
        (poolMax(0.0, toTravel) / (slideK + (25.0 / 49.0) / (2 * muRoll * g))).squareRoot()
    }

    /// Launch speed for a stun to still be doing [arriving] after distance [after].
    static func stunLaunch(_ arriving: Double, _ after: Double) -> Double {
        let v1 = arriving
        let x = after
        // Still sliding when it gets there?
        let sliding = (v1 * v1 + 2 * muSlide * g * x).squareRoot()
        if x <= sliding * sliding * slideK && v1 >= sliding * 5 / 7 { return sliding }
        return ((v1 * v1 + 2 * muRoll * g * x) / (25.0 / 49.0 + (24.0 / 49.0) * muRoll / muSlide)).squareRoot()
    }
}
