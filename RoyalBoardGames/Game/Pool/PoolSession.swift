import SwiftUI
import Observation
import QuartzCore
import GameKit

/// Seconds on the monotonic clock (the same base as display-link frame times).
func poolNow() -> Double { CACurrentMediaTime() }

/// Kotlin `sleep(seconds)`: suspends unless the time is already up; throws when the job is cancelled.
private func sleep(_ seconds: Double) async throws {
    if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(max(0, Kt.toLong(seconds * 1000))) * 1_000_000) }
}

/// Kotlin `delay(ms)`.
private func delay(_ ms: Int) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
}

/// The player's seat colour as an sRGB value (for tints mixed with `lerp`).
func poolPlayerColour(_ player: PartyPlayer) -> PoolRGBA {
    let n = PartyStyle.tokenArgb.count
    return PoolRGBA(argb: PartyStyle.tokenArgb[((player.colorIndex % n) + n) % n])
}

/// A shot being played back: the physics ran to the end on release, and the table draws its
/// 60 fps frames in real time, with each ball's orientation for the rolling numbers.
final class PoolPlayback: @unchecked Sendable {
    let start: Double
    let frames: [[Float]]
    /// Per frame, each ball's orientation as (x, y, z, w).
    let turns: [[Float]]
    let numbers: [Int]
    /// Which balls were on the table when the shot began.
    let live: [Bool]
    let potted: [PoolPhysics.Potted]
    let duration: Double
    /// The last ball's final half second plays slowly: simulated time `slowFrom…slowTo`.
    let slowFrom: Double?
    let slowTo: Double
    /// Speed of the slow part (Extras: instant replay plays the whole shot at 0.4×).
    let slowRate: Double

    init(_ start: Double, _ frames: [[Float]], _ turns: [[Float]], _ numbers: [Int], _ live: [Bool],
         _ potted: [PoolPhysics.Potted], _ duration: Double, _ slowFrom: Double?, _ slowTo: Double,
         slowRate: Double = PoolPlayback.SLOW_RATE) {
        self.slowRate = slowRate
        self.start = start
        self.frames = frames
        self.turns = turns
        self.numbers = numbers
        self.live = live
        self.potted = potted
        self.duration = duration
        self.slowFrom = slowFrom
        self.slowTo = slowTo
    }

    /// Real seconds since the start, as simulated seconds.
    func simTime(_ real: Double) -> Double {
        guard let a = slowFrom, real > a else { return real }
        let slowReal = (slowTo - a) / slowRate
        if real <= a + slowReal { return a + (real - a) * slowRate }
        return slowTo + (real - a - slowReal)
    }

    /// Simulated seconds, as real seconds since the start.
    func realTime(_ sim: Double) -> Double {
        guard let a = slowFrom, sim > a else { return sim }
        if sim <= slowTo { return a + (sim - a) / slowRate }
        return a + (slowTo - a) / slowRate + (sim - slowTo)
    }

    /// Balls finish sinking a moment after the last one drops.
    var end: Double { start + realTime(duration) + 0.35 }

    static let SLOW_RATE = 0.35
}

/// The cue thrusting through the cue ball.
struct PoolStrike: Equatable {
    let start: Double
    let angle: Double
    let power: Double
    let at: Vec2
}

// BEGIN PoolGuide

/// What the aim guide shows: the cue ball's line to the first ball or cushion, the ghost ball,
/// the object ball's line and the cue ball's deflection. No bank predictions.
struct PoolGuide: Equatable, Sendable {
    var end: Vec2? = nil
    var ghost: Vec2? = nil
    var target: Int? = nil
    var legal: Bool = true
    var objectEnd: Vec2? = nil
    var cueEnd: Vec2? = nil
    /// The pocket the object ball is heading for, if it's close to one.
    var pocket: Int? = nil

    static func compute(_ t: PoolTableState, _ cue: Vec2, _ angle: Double, _ spin: Vec2, _ style: PoolAimGuide, _ legal: [Int]) -> PoolGuide {
        let R = PoolTableGeometry.R
        let geo = t.geometry
        let d = Vec2(PoolSM.cos(angle), PoolSM.sin(angle))
        func toWall(_ from: Vec2, _ dir: Vec2) -> Double {
            let ax = geo.a - R
            let by = geo.b - R
            var w = Double.infinity
            if dir.x > 1e-9 { w = poolMin(w, (ax - from.x) / dir.x) } else if dir.x < -1e-9 { w = poolMin(w, (-ax - from.x) / dir.x) }
            if dir.y > 1e-9 { w = poolMin(w, (by - from.y) / dir.y) } else if dir.y < -1e-9 { w = poolMin(w, (-by - from.y) / dir.y) }
            return poolMax(0.0, w)
        }
        var best = Double.infinity
        var hit: Int? = nil
        for (i, b) in t.balls.enumerated() {
            if !b.live || b.n == 0 { continue }
            let m = b.p - cue
            let proj = m.dot(d)
            if proj <= 0 { continue }
            let perp2 = m.dot(m) - proj * proj
            if perp2 >= 4 * R * R { continue }
            let along = proj - (4 * R * R - perp2).squareRoot()
            if along < best { best = poolMax(0.0, along); hit = i }
        }
        let wall = toWall(cue, d)
        if style == .OFF {
            if let h = hit, best < wall { return PoolGuide(target: h, legal: legal.contains(t.balls[h].n)) }
            return PoolGuide()
        }
        guard let h = hit, best < wall else { return PoolGuide(end: cue + d * wall) }
        let ball = t.balls[h]
        let ghost = cue + d * best
        let n = (ball.p - ghost).normalized
        let cut = poolMax(0.0, d.dot(n))
        // Which pocket the object ball is heading for.
        var bestAngle = 0.13
        var pocket: Int? = nil
        for (pi, aim) in geo.aimPoints.enumerated() {
            let toP = (aim - ball.p).normalized
            let off = PoolSM.acos(poolMax(-1.0, poolMin(1.0, toP.dot(n))))
            if off < bestAngle { bestAngle = off; pocket = pi }
        }
        var base = PoolGuide(end: ghost, ghost: ghost, target: h, legal: legal.contains(ball.n), pocket: pocket)
        if style != .FULL { return base }
        let objectLength = poolMin(toWall(ball.p, n), 12 + 30 * cut * cut)
        // The cue ball leaves along the tangent line, bent forward by follow or back by draw.
        let tangent = d - n * cut
        var after = tangent + d * (spin.y * 1.4 * cut)
        if after.length < 0.02 { after = d * (spin.y >= 0 ? 0.02 : -0.02) }
        let dir = after.normalized
        let cueLength = poolMin(toWall(ghost, dir), 6 + 16 * poolMin(1.0, after.length))
        base.objectEnd = ball.p + n * objectLength
        base.cueEnd = ghost + dir * cueLength
        return base
    }
}

// END PoolGuide

/// A short effect drawn by the piece layer, in table centimetres.
struct PoolEffect: Equatable {
    enum Kind: Equatable {
        /// A dark pulse round a pocket as a ball drops.
        case Ring(color: PoolRGBA)
        /// A bright flash at a hard contact.
        case Flash(strength: Double)
        /// Chalk dust where the tip met the ball, flying back along [angle].
        case Puff(angle: Double)
        /// The cue ball coming back for ball in hand.
        case Pop
    }

    let id: Int
    let kind: Kind
    let at: Vec2
    let start: Double
    let duration: Double

    func progress(_ now: Double) -> Double { min(1.0, max(0.0, (now - start) / duration)) }
    func isActive(_ now: Double) -> Bool { now >= start && now < start + duration }
}

enum PoolBannerIcon { case Trophy, Warning, Solids, Stripes, Respot, Sparkles, Tap, Timer }

struct PoolBanner: Equatable {
    let id: Int
    let text: String
    var detail: String? = nil
    let icon: PoolBannerIcon
    let tint: PoolRGBA
}

struct PoolToss: Equatable {
    let id: Int
    let seat: Int
}

/// One Pool match: the rules table plus aiming, power, spin, ball in hand, calling the 8, shot
/// playback, the return chute, computer players, banners, the shot clock and autosave.
/// Jobs (the Kotlin coroutines) run on the main actor; [turnToken] cancels stale ones and [dispose] all of them.
@MainActor
@Observable
final class PoolSession {
    enum Phase { case INTRO, READY, ROLLING, BETWEEN, OVER }

    let config: PoolConfig

    /// Set by the view from the app's Reduce Motion setting.
    @ObservationIgnored var reduceMotion = false

    private var aimGuideState: PoolAimGuide
    /// Adjustable from the pause sheet; starts from the setup's choices.
    var aimGuide: PoolAimGuide {
        get { aimGuideState }
        set { aimGuideState = newValue; refreshGuide() }
    }
    var fastBots: Bool

    @ObservationIgnored private var elapsedBanked = 0.0
    private(set) var match: PoolMatch
    private(set) var phase: Phase = .INTRO
    /// Direction the cue ball will travel, in table radians.
    private(set) var angle = 0.0
    /// How far the cue is pulled back, 0…1.
    private(set) var power = 0.0
    private(set) var pulling = false
    /// Tip offset, within the safe ring of radius 0.5.
    private(set) var spin = Vec2.ZERO
    /// The cue ball's spot: where it rests, or where it's being placed with ball in hand.
    private(set) var cuePos: Vec2
    private(set) var placing = false
    private(set) var call: Int? = nil
    private(set) var guide = PoolGuide()
    private(set) var playback: PoolPlayback? = nil
    /// Extras: the last shot as played, and its physics events, for the instant replay.
    private(set) var lastShot: PoolPlayback? = nil
    @ObservationIgnored private(set) var lastShotEvents: [PoolPhysics.Event] = []
    /// Extras: the instant replay being shown (see `PoolExtras.swift`).
    var replay: PoolPlayback? = nil
    /// Each ball's orientation at rest, by ball index.
    private(set) var orient: [Quat]
    /// Pocketed balls in the order they came down the return.
    private(set) var chute: [Int]
    private(set) var strike: PoolStrike? = nil
    private(set) var introStart: Double? = nil
    private(set) var effects: [PoolEffect] = []
    private(set) var banner: PoolBanner? = nil
    private(set) var toss: PoolToss? = nil
    private(set) var clockEnds: Double? = nil
    /// How the last rack was decided, for the cards.
    private(set) var finish = ""
    private var pausedState = false
    var paused: Bool {
        get { pausedState }
        set { pausedState = newValue; if newValue { bank() } else { resumedAt = poolNow() } }
    }

    /// Bumped whenever a timed animation starts, so the piece layer runs its frame loop.
    private(set) var animationEpoch = 0
    /// Bumped on a hard break, for the table shake.
    private(set) var shakeTick = 0
    private(set) var wheelTick = 0

    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var turnToken = 0
    @ObservationIgnored private var animationEnd = 0.0
    @ObservationIgnored private var resumedAt = poolNow()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var callPicked = false
    @ObservationIgnored private var lastWheelStep = 0
    @ObservationIgnored private var lastSeat = -1
    @ObservationIgnored private var discarded = false
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var jobs: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var jobSeq = 0

    /// Every seat plays itself (debug).
    @ObservationIgnored private let autoplay = PoolSession.debugAutoplay

    init(config: PoolConfig) {
        self.config = config
        aimGuideState = config.options.aimGuide
        fastBots = config.options.fastBots
        let (initial, elapsed) = PoolSession.initialMatch(config)
        var m = initial
        if config.practice { m.table.practice = true }
        match = m
        elapsedBanked = elapsed
        cuePos = m.table.cue.p
        orient = m.table.balls.map { PoolQuat.start($0.n) }
        chute = PoolSession.pocketed(m.table)
    }

    private static func initialMatch(_ config: PoolConfig) -> (PoolMatch, Double) {
        if config.resume, let saved = PoolStore.saved { return (saved.match, saved.elapsed) }
        var seed = Int64.random(in: Int64.min...Int64.max)
        if seed == 0 { seed = 1 }
        return (PoolMatch.create(config.options, config.seats.count, Int.random(in: 0..<config.seats.count), seed), 0.0)
    }

    // MARK: State for the view

    var table: PoolTableState { match.table }
    var currentSeat: PoolSeat { config.seats[table.turn] }
    var isBotTurn: Bool { currentSeat.isBot || autoplay }
    var people: Int { config.seats.filter { !$0.isBot }.count }
    /// A person may aim, place and shoot right now.
    var canControl: Bool { phase == .READY && !isBotTurn && !paused && replay == nil }
    var elapsed: Double { elapsedBanked + ((paused || phase == .OVER) ? 0.0 : poolNow() - resumedAt) }
    /// True while the piece layer needs to redraw every frame.
    var animating: Bool { playback != nil || replay != nil || introStart != nil || animationEnd > poolNow() }
    /// The shooter must name a pocket for the 8.
    var needsCall: Bool { table.callEight && table.onEight && phase == .READY }
    var cueValid: Bool { !table.ballInHand || table.free(cuePos) }
    /// The ball the shooter must play: the lowest in 9-Ball, the 8 when on it.
    var ballOn: Int? { table.game == .NINE ? table.lowest : (table.onEight ? 8 : nil) }

    func unitName(_ unit: Int) -> String { table.teams ? PoolStore.teamNames[unit] : config.seats[unit].player.name }

    func seats(_ ofUnit: Int) -> [Int] { config.seats.indices.filter { table.unit($0) == ofUnit } }

    // MARK: Jobs (coroutines)

    private func launch(_ body: @escaping @MainActor () async throws -> Void) {
        if disposed { return }
        jobSeq += 1
        let id = jobSeq
        let task = Task { @MainActor [weak self] in
            do { try await body() } catch {}
            self?.jobs[id] = nil
        }
        jobs[id] = task
    }

    /// The screen went away: stop every job (the Kotlin scope is cancelled with the composition).
    func dispose() {
        disposed = true
        turnToken += 1
        for (_, j) in jobs { j.cancel() }
        jobs.removeAll()
    }

    // MARK: Flow

    func start() {
        if running { return }
        running = true
        resumedAt = poolNow()
        PoolSound.warmUp()
        if config.resume && table.winner != nil && !match.isOver {
            phase = .BETWEEN // saved between racks
            return
        }
        if config.resume && table.shots > 0 {
            beginTurn()
            return
        }
        let showToss = !config.resume && match.rack == 1 && !config.practice
        launch { try await self.intro(showToss) }
    }

    private func intro(_ showToss: Bool) async throws {
        phase = .INTRO
        if showToss {
            nextID += 1
            toss = PoolToss(id: nextID, seat: table.turn)
            PoolSound.play(PoolSound.toss)
            try await sleep(reduceMotion || autoplay ? 0.4 : 1.5)
            toss = nil
        }
        introStart = poolNow()
        mark(poolNow() + 1)
        PoolSound.play(PoolSound.rack)
        try await sleep(reduceMotion || autoplay ? 0.25 : 1.0)
        introStart = nil
        beginTurn()
    }

    private func beginTurn() {
        if match.isOver || table.winner != nil { return }
        turnToken += 1
        phase = .READY
        power = 0.0
        pulling = false
        placing = false
        spin = Vec2.ZERO
        call = nil
        callPicked = false
        cuePos = table.cue.p
        if table.turn != lastSeat {
            if lastSeat >= 0 { Haptics.play(.Tick); PoolSound.play(PoolSound.turn) }
            lastSeat = table.turn
        }
        // Start pointing at the nearest ball the shooter may hit, or at the rack on the break.
        let legal = table.legalFirst()
        let t = table
        let from = cuePos
        let target: Vec2? = t.broken ? legal.compactMap { t.ball($0) }.poolMinBy { ($0.p - from).length }?.p : t.geometry.footSpot
        if let target { angle = PoolSM.atan2(target.y - cuePos.y, target.x - cuePos.x) }
        refreshGuide()
        if isBotTurn {
            let token = turnToken
            launch { try await self.botTurn(token) }
        } else {
            startClock()
        }
    }

    private func refreshGuide() {
        guide = PoolGuide.compute(
            table, cuePos, angle, spin,
            (isBotTurn && aimGuide == .FULL) ? .SHORT : aimGuide,
            table.legalFirst()
        )
        if needsCall && !callPicked { call = guide.pocket }
    }

    private func waitWhilePaused() async throws {
        while (paused || replay != nil) && !Task.isCancelled { try await delay(150) }
    }

    // MARK: A person's input

    /// Drag on the table: the cue swings round the cue ball to point at the finger.
    func aim(_ at: Vec2) {
        if !canControl || pulling || placing { return }
        let d = at - cuePos
        if d.length <= 0.5 { return }
        angle = PoolSM.atan2(d.y, d.x)
        refreshGuide()
    }

    /// The fine-tune wheel, in radians; ticks every tenth of a degree.
    func nudge(_ delta: Double) {
        if !canControl || pulling { return }
        angle = ieeeRemainder(angle + delta, 2 * Double.pi)
        let step = Kt.toInt(floor(angle * 1800 / Double.pi))
        if step != lastWheelStep {
            lastWheelStep = step
            wheelTick += 1
            Haptics.play(.Tick)
            PoolSound.play(PoolSound.tick, 0.025)
        }
        refreshGuide()
    }

    /// Kotlin `setPower` (JvmName changePower).
    func setPower(_ p: Double) {
        if !canControl || placing { return }
        let old = power
        power = poolMax(0.0, poolMin(1.0, p))
        pulling = power > 0.015
        if Kt.toInt(old * 10) != Kt.toInt(power * 10) { PoolSound.play(PoolSound.tick, 0.02) }
    }

    /// Letting go of the power bar shoots; slid back to the top it cancels.
    func releasePower() {
        if !canControl { return }
        if power < 0.03 || !cueValid {
            power = 0.0
            pulling = false
            return
        }
        if needsCall && call == nil {
            power = 0.0
            pulling = false
            show("Call your pocket", "Tap the pocket for the 8", .Tap, poolHex(0xF0A21C))
            return
        }
        shoot(PoolShot(angle, power, spin, table.ballInHand ? cuePos : nil, needsCall ? call : nil))
    }

    /// The touch was taken away mid-pull: put the cue back without shooting.
    func cancelPull() {
        if !canControl || !pulling { return }
        power = 0.0
        pulling = false
    }

    /// Kotlin `setSpin` (JvmName changeSpin).
    func setSpin(_ s: Vec2) {
        if !canControl { return }
        let l = s.length
        let clamped = l > 0.5 ? s * (0.5 / l) : s
        if (clamped - spin).length > 0.02 { PoolSound.play(PoolSound.chalk, 0.3) }
        spin = clamped
        refreshGuide()
    }

    func beginPlace() {
        if !canControl || !table.ballInHand || pulling { return }
        placing = true
    }

    /// Drags the cue ball with ball in hand, kept on the cloth (and in the kitchen when it must be).
    func place(_ at: Vec2) {
        if !canControl || !placing { return }
        let geo = table.geometry
        let R = PoolTableGeometry.R
        let maxX = table.kitchenOnly ? geo.headString : geo.a - R
        cuePos = Vec2(poolMax(-geo.a + R, poolMin(maxX, at.x)), poolMax(-geo.b + R, poolMin(geo.b - R, at.y)))
        refreshGuide()
    }

    func endPlace() {
        if !placing { return }
        placing = false
        if !table.free(cuePos) { cuePos = table.freeSpot(cuePos) }
        PoolSound.play(PoolSound.place)
        refreshGuide()
    }

    func callPocket(_ pocket: Int) {
        if !canControl || !needsCall { return }
        call = pocket
        callPicked = true
        PoolSound.play(PoolSound.call)
    }

    // MARK: Shots

    // BEGIN PoolPrepare
    struct Prepared: @unchecked Sendable {
        let balls: [PoolBall]
        let run: PoolPhysics.Run
        let turns: [[Float]]
        let rested: [Quat]
    }

    /// The whole shot simulated at once (off the main thread), with each ball's orientation per frame.
    nonisolated static func prepare(_ snapshot: PoolTableState, _ shot: PoolShot, _ startOrient: [Quat]) -> Prepared {
        let (balls, run) = snapshot.simulate(shot, true)
        // Orientations frame by frame, rolled from each ball's travel.
        var q = startOrient
        var turns: [[Float]] = []
        turns.reserveCapacity(run.frames.count)
        for f in run.frames.indices {
            if f > 0 {
                let a = run.frames[f]
                let b = run.frames[f - 1]
                for i in q.indices {
                    let dx = a[2 * i] - b[2 * i]
                    let dy = a[2 * i + 1] - b[2 * i + 1]
                    if dx != 0 || dy != 0 { q[i] = PoolQuat.roll(q[i], Double(dx), Double(dy)) }
                }
            }
            var row = [Float](repeating: 0, count: q.count * 4)
            for i in q.indices {
                row[4 * i] = Float(q[i].x); row[4 * i + 1] = Float(q[i].y)
                row[4 * i + 2] = Float(q[i].z); row[4 * i + 3] = Float(q[i].w)
            }
            turns.append(row)
        }
        return Prepared(balls: balls, run: run, turns: turns, rested: q)
    }
    // END PoolPrepare

    private func shoot(_ shot: PoolShot) {
        turnToken += 1
        replay = nil
        clockEnds = nil
        phase = .ROLLING
        pulling = false
        placing = false
        Haptics.play(.Medium)
        let wasBreak = !table.broken
        let legal = table.legalFirst()
        let from = shot.place ?? table.cue.p
        let strikeStart = poolNow()
        strike = PoolStrike(start: strikeStart, angle: shot.angle, power: shot.power, at: from)
        power = 0.0
        PoolSound.play(wasBreak && shot.power > 0.7 ? PoolSound.breakShot : PoolSound.cue(min(3, Kt.toInt(shot.power * 4))))
        if wasBreak { Haptics.play(.Heavy) }
        add(.Puff(angle: shot.angle), from - Vec2(PoolSM.cos(shot.angle), PoolSM.sin(shot.angle)) * PoolTableGeometry.R, strikeStart + 0.07, 0.5)
        mark(strikeStart + 0.45)

        let snapshot = table.clone()
        var startOrient = orient
        if table.ballInHand && shot.place != nil { startOrient[0] = PoolQuat.start(0) }
        let reduce = reduceMotion
        let initialOrient = startOrient
        launch {
            let prepared = await Task.detached(priority: .userInitiated) {
                PoolSession.prepare(snapshot, shot, initialOrient)
            }.value
            try Task.checkCancellation()
            let balls = prepared.balls
            let run = prepared.run
            // The 8 (or 9) going down after the break plays its last half second slowly.
            var slowFrom: Double? = nil
            var slowTo = 0.0
            let decider = snapshot.game == .EIGHT ? 8 : 9
            if !reduce && !wasBreak {
                if let drop = run.potted.first(where: { balls[$0.ball].n == decider }) {
                    slowTo = drop.time
                    slowFrom = poolMax(0.0, drop.time - 0.5)
                }
            }
            let start = poolMax(strikeStart + 0.08, poolNow())
            let pb = PoolPlayback(
                start, run.frames, prepared.turns, balls.map { $0.n }, snapshot.balls.map { $0.live },
                run.potted, run.duration, slowFrom, slowTo
            )
            self.playback = pb
            self.lastShot = pb
            self.lastShotEvents = run.events
            self.mark(pb.end)
            self.scheduleFeedback(run, balls, pb, wasBreak)
            try await sleep(pb.end - poolNow())
            try await self.finishShot(balls, run, shot, legal, prepared.rested, wasBreak)
        }
    }

    /// Sounds, haptics, flashes and the return chute at the moments the physics recorded.
    private func scheduleFeedback(_ run: PoolPhysics.Run, _ balls: [PoolBall], _ pb: PoolPlayback, _ wasBreak: Bool) {
        let start = pb.start
        let geo = table.geometry
        for event in run.events {
            let at = start + pb.realTime(event.time)
            switch event.kind {
            case .Hit:
                if event.strength > 260 { add(.Flash(strength: event.strength), event.at, at, 0.25) }
            case .Pocket:
                let n = balls[event.ball].n
                add(.Ring(color: n == 0 ? poolHex(0xFF4D4D) : PoolBallColour.colour(n)), geo.pockets[event.pocket].c, at, 0.6)
            default:
                break
            }
        }
        let events = run.events
        launch {
            var shook = false
            for event in events {
                try await sleep(start + pb.realTime(event.time) - poolNow())
                switch event.kind {
                case .Hit:
                    let level = event.strength > 400 ? 3 : (event.strength > 150 ? 2 : (event.strength > 40 ? 1 : 0))
                    PoolSound.play(PoolSound.click(level), 0.012)
                    if wasBreak && !shook && event.strength > 300 && !self.reduceMotion {
                        shook = true
                        self.shakeTick += 1
                    }
                case .Cushion:
                    if event.strength > 15 {
                        PoolSound.play(PoolSound.cushion(event.strength > 200 ? 2 : (event.strength > 60 ? 1 : 0)), 0.04)
                    }
                case .Jaw:
                    if event.strength > 20 { PoolSound.play(PoolSound.jaw, 0.08) }
                case .Pocket:
                    PoolSound.play(PoolSound.pocket, 0.05)
                    Haptics.play(.Light)
                    let n = balls[event.ball].n
                    if n != 0 {
                        // Down the return to the chute.
                        self.launch {
                            try await sleep(self.reduceMotion ? 0.1 : 0.3)
                            if !self.chute.contains(n) { self.chute = self.chute + [n] }
                            PoolSound.play(PoolSound.chute, 0.2)
                            try await sleep(0.45)
                            PoolSound.play(PoolSound.stack, 0.05)
                        }
                    }
                }
            }
        }
    }

    private func finishShot(_ balls: [PoolBall], _ run: PoolPhysics.Run, _ shot: PoolShot, _ legal: [Int], _ orientations: [Quat], _ wasBreak: Bool) async throws {
        var m = match.clone()
        let stroke = m.table.apply(balls, run, shot, legal)
        match = m
        playback = nil
        strike = nil
        // Where the cue ball came to rest (the reference left it at the old spot until the next turn).
        cuePos = table.cue.p
        var o = orientations
        if let n = stroke.respotted {
            if let i = table.balls.firstIndex(where: { $0.n == n }) {
                o[i] = PoolQuat.start(n)
                chute = chute.filter { $0 != n }
                add(.Pop, table.balls[i].p, poolNow() + 0.1, 0.45)
            }
        }
        // Keep the chute in step with the table (the rules may have brought a ball back).
        let t = table
        var c = chute.filter { n in !t.balls.contains { $0.n == n && $0.live } }
        for n in PoolSession.pocketed(t) where !c.contains(n) { c.append(n) }
        chute = c
        if stroke.scratch && !stroke.rackOver {
            o[0] = PoolQuat.start(0)
            add(.Pop, table.cue.p, poolNow() + 0.15, 0.45)
            PoolSound.play(PoolSound.place)
        }
        orient = o
        let pause = react(stroke, wasBreak)
        save()
        try await sleep(pause)
        if stroke.rackOver { finishRack() } else { beginTurn() }
    }

    /// Banners and sounds for what a stroke did. Returns how long to let it sink in.
    private func react(_ s: PoolStroke, _ wasBreak: Bool) -> Double {
        let seat = config.seats[s.seat]
        let name = seat.player.name
        let decider = table.game == .EIGHT ? 8 : 9
        if s.rackOver {
            let unit = table.winner ?? 0
            if s.won {
                if table.game == .EIGHT {
                    finish = table.callEight ? "Sank the 8 in the called pocket" : "Sank the 8"
                } else {
                    finish = (s.potted.count > 1 && s.potted.first != 9) ? "Sank the 9 on a combination" : "Sank the 9"
                }
                if wasBreak { finish = "Sank the 9 on the break" }
                show("\(name) sinks the \(decider)!", nil, .Trophy, poolHex(0xF0A21C))
            } else {
                finish = "\(name): \(s.why.lowercased())"
                Haptics.play(.Warning)
                PoolSound.play(PoolSound.foul)
                show(s.why, "\(unitName(unit)) win\(table.teams ? "" : "s") the rack", .Warning, poolHex(0xE0115F))
            }
            return 1.4
        }
        if s.foul {
            Haptics.play(.Warning)
            PoolSound.play(PoolSound.foul)
            show("Foul · ball in hand", s.why, .Warning, poolHex(0xE0115F))
            return 1.1
        }
        if let g = s.groupsSet {
            let who = table.teams ? unitName(table.unit(s.seat)) : name
            show("\(who): \(g.title)", g == .SOLIDS ? "1 to 7, then the 8" : "9 to 15, then the 8",
                 g == .SOLIDS ? .Solids : .Stripes, poolPlayerColour(config.seats[s.seat].player))
            return 0.9
        }
        if s.respotted == 8 {
            show("The 8 is spotted", nil, .Respot, poolHex(0x6C63FF))
            return 0.9
        }
        let objects = s.potted.filter { $0 != 0 }
        if wasBreak && objects.count >= 2 {
            show("Great break!", "\(objects.count) balls down", .Sparkles, poolPlayerColour(config.seats[s.seat].player))
            return 0.8
        }
        if objects.count >= 2 && s.continues {
            show(objects.count >= 3 ? "Triple!" : "Double!", nil, .Sparkles, poolPlayerColour(config.seats[s.seat].player))
            return 0.6
        }
        return objects.isEmpty ? 0.25 : 0.35
    }

    // MARK: Computer players

    private func botTurn(_ token: Int) async throws {
        let seat = currentSeat
        let level: PoolDifficulty = seat.isBot ? seat.difficulty : .HARD
        let snapshot = table.clone()
        let seed = Int64.random(in: Int64.min...Int64.max)
        let begun = poolNow()
        let plan = await Task.detached(priority: .userInitiated) { PoolBot.plan(snapshot, level, seed) }.value
        try Task.checkCancellation()
        let fast = fastBots || autoplay
        let speed = autoplay ? 0.25 : (fast ? 0.5 : 1.0)
        let think = autoplay ? 0.05 : (fast ? 0.3 : (reduceMotion ? 0.5 : 0.7))
        let left = think - (poolNow() - begun)
        if left > 0 { try await sleep(left) }
        try await waitWhilePaused()
        if token != turnToken || phase != .READY { return }

        // Ball in hand: carry the cue ball to its spot.
        if table.ballInHand, let place = plan.shot.place {
            let from = cuePos
            let steps = max(4, Kt.toInt(14 * speed))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let e = t * t * (3 - 2 * t)
                cuePos = from + (place - from) * e
                refreshGuide()
                try await delay(28)
            }
            if token != turnToken { return }
            PoolSound.play(PoolSound.place)
        }
        // Swing to the line, the short way round.
        let from = angle
        let delta = ieeeRemainder(plan.shot.angle - from, 2 * Double.pi)
        let swing = max(4, Kt.toInt(18 * speed))
        for i in 1...swing {
            let t = Double(i) / Double(swing)
            let e = t * t * (3 - 2 * t)
            angle = from + delta * e
            refreshGuide()
            try await delay(28)
        }
        spin = plan.shot.spin
        if needsCall { call = plan.shot.call ?? guide.pocket; callPicked = true }
        refreshGuide()
        try await waitWhilePaused()
        if token != turnToken || phase != .READY { return }
        // Pull back, then strike.
        let pull = max(4, Kt.toInt(20 * speed))
        for i in 1...pull {
            let t = Double(i) / Double(pull)
            power = plan.shot.power * (1 - PoolSM.pow(1 - t, 2))
            pulling = true
            try await delay(28)
        }
        try await sleep(0.15 * speed)
        try await waitWhilePaused()
        if token != turnToken || phase != .READY { return }
        var shot = plan.shot
        shot.place = table.ballInHand ? cuePos : nil
        if !needsCall { shot.call = nil } else if shot.call == nil { shot.call = call }
        shoot(shot)
    }

    // MARK: Shot clock

    private func startClock() {
        let seconds = config.options.shotClock
        if seconds <= 0 { clockEnds = nil; return }
        clockEnds = poolNow() + Double(seconds)
        let token = turnToken
        launch {
            while true {
                try await delay(250)
                if token != self.turnToken { return }
                if self.paused || self.replay != nil { self.clockEnds = self.clockEnds.map { $0 + 0.25 }; continue }
                if let end = self.clockEnds, poolNow() >= end, self.phase == .READY {
                    try await self.timeOut()
                    return
                }
            }
        }
    }

    private func timeOut() async throws {
        turnToken += 1
        clockEnds = nil
        power = 0.0
        pulling = false
        placing = false
        var m = match.clone()
        _ = m.table.timeOut()
        match = m
        Haptics.play(.Warning)
        PoolSound.play(PoolSound.foul)
        show("Time's up", "Ball in hand for the next player", .Timer, poolHex(0x6C63FF))
        save()
        try await sleep(0.9)
        beginTurn()
    }

    // MARK: Racks and the match

    private func finishRack() {
        var m = match.clone()
        let over = m.finishRack()
        match = m
        Haptics.play(.Success)
        if over {
            bank()
            phase = .OVER
            PoolSound.play(PoolSound.win)
            PoolStore.saved = nil
        } else {
            phase = .BETWEEN
            PoolSound.play(PoolSound.rackWon)
            save()
            if autoplay { launch { try await delay(1000); self.nextRack() } }
        }
    }

    func nextRack() {
        if phase != .BETWEEN { return }
        var m = match.clone()
        m.nextRack()
        match = m
        lastShot = nil
        chute = []
        orient = table.balls.map { PoolQuat.start($0.n) }
        cuePos = table.cue.p
        lastSeat = -1
        launch { try await self.intro(false) }
    }

    /// Extras: the practice table's re-rack button (logic in `PoolPractice`).
    func rerack() {
        if !config.practice || phase != .READY || !running { return }
        turnToken += 1
        clockEnds = nil
        replay = nil
        lastShot = nil
        match = PoolPractice.rerack(match)
        chute = []
        orient = table.balls.map { PoolQuat.start($0.n) }
        cuePos = table.cue.p
        launch { try await self.intro(false) }
    }

    // MARK: Helpers

    private func add(_ kind: PoolEffect.Kind, _ at: Vec2, _ start: Double, _ duration: Double) {
        nextID += 1
        let now = poolNow()
        effects = effects.filter { $0.start + $0.duration >= now } + [PoolEffect(id: nextID, kind: kind, at: at, start: start, duration: duration)]
        mark(start + duration)
    }

    func mark(_ until: Double) {
        if until > animationEnd { animationEnd = until }
        animationEpoch += 1
    }

    private func show(_ text: String, _ detail: String?, _ icon: PoolBannerIcon, _ tint: PoolRGBA) {
        nextID += 1
        let b = PoolBanner(id: nextID, text: text, detail: detail, icon: icon, tint: tint)
        banner = b
        launch {
            try await delay(1500)
            if self.banner?.id == b.id { self.banner = nil }
        }
    }

    private func bank() {
        if phase == .OVER { return }
        elapsedBanked += poolNow() - resumedAt
        resumedAt = poolNow()
    }

    /// Restarting: forget the saved match and never save this one again.
    func discard() {
        discarded = true
        if !config.practice { PoolStore.saved = nil }
    }

    /// Saves the match while the balls are at rest, so it can be resumed later.
    func save() {
        if discarded || config.practice || match.isOver || phase == .ROLLING || (phase == .INTRO && table.shots <= 0) { return }
        PoolStore.saved = PoolStore.SavedMatch(config.copy(resume: true), match, elapsed, Days.nowMillis())
    }

    /// The match summary for the party history.
    var record: PartyMatchRecord {
        let names = config.seats.map { "\($0.player.avatar) \($0.player.name)" }
        let winner: String? = match.winner.map { unit in
            table.teams ? PoolStore.teamNames[unit] : "\(config.seats[unit].player.avatar) \(config.seats[unit].player.name)"
        }
        var detail = "\(match.game.title) · \(config.seats.count) players"
        if match.target > 1, let w = match.winner {
            let best = match.wins.enumerated().filter { $0.offset != w }.map { $0.element }.max() ?? 0
            detail += " · won \(match.wins[w])–\(best)"
        }
        return PartyMatchRecord(kind: GameKind.POOL.id, players: names, winner: winner, detail: detail)
    }

    /// Debug: every seat plays itself.
    static var debugAutoplay = false

    private static func pocketed(_ t: PoolTableState) -> [Int] { t.balls.filter { !$0.live && $0.n != 0 }.map { $0.n } }
}
