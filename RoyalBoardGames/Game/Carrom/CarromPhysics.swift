import Foundation

/// Fixed-step disc physics. Deterministic: the same shot always gives the same result, so saves, the computers'
/// look-ahead and the tests all agree. Every operation runs in the Kotlin order on plain Doubles, so a shot plays
/// out bit for bit as on Android.
enum CarromPhysics {
    /// Rolling friction as a deceleration a0 + k·speed (cm/s²). With these, a full-power striker runs three and a
    /// half lengths of the board (ICF law A.1) in about 2.6 s.
    static let a0 = 22.0
    static let k = 0.58
    static let eCoin = 0.92
    static let eStriker = 0.86
    static let eFrame = 0.72
    static let frameGrip = 0.95
    static let maxSpeed = 300.0
    /// 8 substeps per 60 fps frame keeps every step under 0.7 cm: nothing tunnels.
    static let substeps = 8
    static let dt = 1.0 / 480
    static let maxTime = 15.0
    /// Soft shots stay controllable: 30% power slides about 17 cm, 70% about 1.6 m.
    static let powerCurve = 1.8

    static func speedForPower(_ power: Double) -> Double {
        maxSpeed * CarromFdLibm.pow(CarromMath.max(0.0, CarromMath.min(1.0, power)), powerCurve)
    }

    static func powerForSpeed(_ speed: Double) -> Double {
        CarromFdLibm.pow(CarromMath.max(0.0, CarromMath.min(1.0, speed / maxSpeed)), 1 / powerCurve)
    }

    enum EventKind: Int { case HIT, FRAME, POCKET }

    struct Event {
        let kind: EventKind
        let time: Double
        /// Impulse for hits (g·cm/s), speed into the frame for bounces.
        let strength: Double
        let disc: Int
        let other: Int
        let at: CarromVec
        /// The pocket, for [EventKind.POCKET].
        let pocket: Int

        init(_ kind: EventKind, _ time: Double, _ strength: Double, _ disc: Int, _ other: Int = -1, at: CarromVec, pocket: Int = -1) {
            self.kind = kind
            self.time = time
            self.strength = strength
            self.disc = disc
            self.other = other
            self.at = at
            self.pocket = pocket
        }
    }

    struct Pocketed: Equatable {
        let disc: Int
        let pocket: Int
        let time: Double

        init(_ disc: Int, _ pocket: Int, _ time: Double) {
            self.disc = disc
            self.pocket = pocket
            self.time = time
        }
    }

    final class Run {
        /// Positions at 60 fps, one array per frame: x0, y0, x1, y1… in disc order.
        var frames: [[Float]] = []
        var events: [Event] = []
        /// Discs in the order they dropped, with their pocket and time.
        var pocketed: [Pocketed] = []
        var firstContact: Int? = nil
        var duration = 0.0

        init() {}
    }

    private static func snapshot(_ d: [CarromDisc]) -> [Float] {
        var out = [Float](repeating: 0, count: d.count * 2)
        for i in d.indices {
            out[2 * i] = Float(d[i].x)
            out[2 * i + 1] = Float(d[i].y)
        }
        return out
    }

    /// Plays a shot until everything stops. [record] keeps 60 fps frames for playback.
    @discardableResult
    static func run(_ d: inout [CarromDisc], _ striker: Int?, _ record: Bool) -> Run {
        let run = Run()
        var t = 0.0
        var step = 0
        if record { run.frames.append(snapshot(d)) }
        while t < maxTime {
            let moving = advance(&d, run, striker, t)
            t += dt
            step += 1
            if record && step % substeps == 0 { run.frames.append(snapshot(d)) }
            if !moving { break }
        }
        if record { run.frames.append(snapshot(d)) }
        run.duration = t
        return run
    }

    /// One substep. Returns whether anything is still moving.
    @discardableResult
    static func advance(_ d: inout [CarromDisc], _ run: Run, _ striker: Int?, _ time: Double) -> Bool {
        let count = d.count
        return d.withUnsafeMutableBufferPointer { b -> Bool in
            var moving = false
            for i in 0..<count {
                if !b[i].live { continue }
                let s = (b[i].vx * b[i].vx + b[i].vy * b[i].vy).squareRoot()
                if s == 0.0 { continue }
                let ns = s - (a0 + k * s) * dt
                if ns <= 0 { b[i].vx = 0.0; b[i].vy = 0.0; continue }
                let f = ns / s
                b[i].vx *= f; b[i].vy *= f
                b[i].x += b[i].vx * dt; b[i].y += b[i].vy * dt
                moving = true
            }
            let h = CarromBoard.half
            let pockets = CarromBoard.pockets
            let pocketR = CarromBoard.pocketR
            for i in 0..<count {
                if !b[i].live { continue }
                let r = b[i].r
                if b[i].x < -h + r { b[i].x = -h + r; if b[i].vx < 0 { bounce(&b[i], true, run, i, time) } }
                if b[i].x > h - r { b[i].x = h - r; if b[i].vx > 0 { bounce(&b[i], true, run, i, time) } }
                if b[i].y < -h + r { b[i].y = -h + r; if b[i].vy < 0 { bounce(&b[i], false, run, i, time) } }
                if b[i].y > h - r { b[i].y = h - r; if b[i].vy > 0 { bounce(&b[i], false, run, i, time) } }
                for pi in 0..<pockets.count {
                    let pc = pockets[pi]
                    let dx = b[i].x - pc.x
                    let dy = b[i].y - pc.y
                    if (dx * dx + dy * dy).squareRoot() < pocketR {
                        b[i].live = false
                        b[i].vx = 0.0; b[i].vy = 0.0
                        run.pocketed.append(Pocketed(i, pi, time))
                        run.events.append(Event(.POCKET, time, 0.0, i, at: b[i].p, pocket: pi))
                        break
                    }
                }
            }
            for i in 0..<count {
                if !b[i].live { continue }
                var j = i + 1
                while j < count {
                    defer { j += 1 }
                    if !b[j].live { continue }
                    let dx = b[j].x - b[i].x
                    let dy = b[j].y - b[i].y
                    let ar = b[i].r
                    let rr = ar + b[j].r
                    let dist2 = dx * dx + dy * dy
                    if dist2 >= rr * rr || dist2 < 1e-12 { continue }
                    let dist = dist2.squareRoot()
                    let nx = dx / dist
                    let ny = dy / dist
                    let mi = b[i].m
                    let mj = b[j].m
                    let overlap = rr - dist
                    let si = overlap * mj / (mi + mj)
                    let sj = overlap * mi / (mi + mj)
                    b[i].x -= nx * si; b[i].y -= ny * si
                    b[j].x += nx * sj; b[j].y += ny * sj
                    let vn = (b[i].vx - b[j].vx) * nx + (b[i].vy - b[j].vy) * ny
                    if vn <= 0 { continue }
                    let e = (b[i].kind == .STRIKER || b[j].kind == .STRIKER) ? eStriker : eCoin
                    let jn = (1 + e) * vn / (1 / mi + 1 / mj)
                    b[i].vx -= nx * (jn / mi); b[i].vy -= ny * (jn / mi)
                    b[j].vx += nx * (jn / mj); b[j].vy += ny * (jn / mj)
                    moving = true
                    run.events.append(Event(.HIT, time, jn, i, j, at: CarromVec(b[i].x + nx * ar, b[i].y + ny * ar)))
                    if run.firstContact == nil, let striker, i == striker || j == striker {
                        run.firstContact = i == striker ? j : i
                    }
                }
            }
            return moving
        }
    }

    private static func bounce(_ disc: inout CarromDisc, _ x: Bool, _ run: Run, _ i: Int, _ time: Double) {
        let speed = Swift.abs(x ? disc.vx : disc.vy)
        if x {
            disc.vx *= -eFrame; disc.vy *= frameGrip
        } else {
            disc.vy *= -eFrame; disc.vx *= frameGrip
        }
        run.events.append(Event(.FRAME, time, speed, i, at: disc.p))
    }

    // MARK: Planning helpers (the computers use the same friction model)

    /// Distance a free disc slides from speed v until it stops.
    static func travel(_ v: Double) -> Double {
        CarromMath.max(0.0, (v - a0 / k * CarromFdLibm.log(1 + k * v / a0)) / k)
    }

    /// The speed that slides exactly distance x.
    static func speedToTravel(_ x: Double) -> Double {
        var lo = 0.0
        var hi = 3000.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if travel(mid) < x { lo = mid } else { hi = mid }
        }
        return hi
    }

    /// Launch speed that still has speed [arriving] after sliding distance [after].
    static func launch(_ arriving: Double, _ after: Double) -> Double { speedToTravel(travel(arriving) + after) }
}
