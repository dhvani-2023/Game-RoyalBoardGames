import Foundation
import GameKit
import Observation
import QuartzCore

/// Monotonic clock in seconds, shared by the session and the token layer.
@inline(__always) func ludoNow() -> Double { CACurrentMediaTime() }

/// A short animation drawn by the board's token layer.
final class LudoAnim {
    enum Kind {
        /// A token hopping square by square (or jumping out of its yard when `from` is −1).
        case Hop(seat: Int, token: Int, from: Int, to: Int)
        /// A captured token, still on its square until `delay`, then flying back to its yard.
        case Knock(seat: Int, token: Int, from: Int, delay: Double)
        /// A ring and sparks at a board point (cell units), in a seat's colour.
        case Burst(at: LPoint, arm: Int, big: Bool)
    }

    let id: Int
    let kind: Kind
    let start: Double
    let duration: Double

    init(_ id: Int, _ kind: Kind, _ start: Double, _ duration: Double) {
        self.id = id
        self.kind = kind
        self.start = start
        self.duration = duration
    }

    func progress(_ now: Double) -> Double { min(max((now - start) / duration, 0.0), 1.0) }
    func isActive(_ now: Double) -> Bool { now < start + duration }
}

struct LudoBanner: Equatable {
    enum Icon { case STOP, HAND, BOLT, HOUSE }

    let id: Int
    let text: String
    let icon: Icon
    /// Board arm whose colour tints the banner, or nil for gold.
    let arm: Int?
}

/// One Ludo match: the engine plus dice, turn pacing, computer players, animations and autosave.
@MainActor
@Observable
final class LudoSession {
    enum Phase { case ROLL, ROLLING, CHOOSE, MOVING, OVER }

    let config: LudoConfig
    var reduceMotion: Bool

    private(set) var engine: LudoEngine
    private(set) var phase: Phase = .ROLL
    private(set) var diceValue: Int = 6
    private(set) var legal: [LudoMove] = []
    private(set) var anims: [LudoAnim] = []
    private(set) var banner: LudoBanner? = nil
    /// A token the player is pressing on, to preview its move.
    var preview: LudoMove? = nil

    private var pausedState = false
    var paused: Bool {
        get { pausedState }
        set {
            if newValue == pausedState { return }
            pausedState = newValue
            if newValue { bank() } else { resumedAt = ludoNow() }
        }
    }

    /// Bumped when the die lands, for its bounce.
    private(set) var landTick: Int = 0
    /// Bumped on a capture, for the board shake.
    private(set) var captureTick: Int = 0
    /// Bumped on a bonus roll from a capture or reaching home, for the "+1 roll" badge.
    private(set) var extraTick: Int = 0
    /// The token layer keeps drawing every frame until this time.
    private(set) var animationEnd: Double = 0.0

    @ObservationIgnored private let dice = FairDice()
    @ObservationIgnored private let botRandom: LudoRandom = LudoSystemRandom()
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var elapsedBanked = 0.0
    @ObservationIgnored private var resumedAt = ludoNow()
    @ObservationIgnored private var running = false
    /// Set when the match is thrown away (restart), so closing the screen doesn't save it again.
    @ObservationIgnored private var abandoned = false
    @ObservationIgnored private var jobs: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var jobSerial = 0
    @ObservationIgnored private var disposed = false

    var geometry: LudoGeometry { engine.geometry }
    var currentSeat: LudoSeat { config.seats[engine.current] }
    var isBotTurn: Bool { currentSeat.isBot }

    var elapsed: Double { elapsedBanked + ((paused || phase == .OVER) ? 0.0 : ludoNow() - resumedAt) }
    /// True while the token layer needs to redraw every frame.
    var animating: Bool { phase == .CHOOSE || phase == .MOVING || animationEnd > ludoNow() }

    private var hopTime: Double { reduceMotion ? 0.07 : (config.rules.fastBots && isBotTurn ? 0.1 : 0.15) }
    private var thinkTime: Double { config.rules.fastBots ? 0.25 : (reduceMotion ? 0.4 : 0.7) }

    init(_ config: LudoConfig, _ reduceMotion: Bool) {
        self.config = config
        self.reduceMotion = reduceMotion
        engine = LudoEngine(config.arms, config.seats.map { $0.arm }, config.rules)
        let saved = config.resume ? LudoStore.saved : nil
        if let saved, saved.engine.seatCount == config.seats.count {
            engine = saved.engine
            elapsedBanked = saved.elapsed
        }
        if let last = engine.stats[engine.current].recent.last { diceValue = last }
    }

    func dispose() {
        disposed = true
        for job in jobs.values { job.cancel() }
        jobs.removeAll()
    }

    /// Drops this match and its save (restart).
    func abandon() {
        abandoned = true
        LudoStore.saved = nil
    }

    /// Kotlin `delay((seconds * 1000).toLong())`; throws when the match is closed, which ends the flow.
    private func sleep(_ seconds: Double) async throws {
        let ms = UInt64(max(0, seconds * 1000))
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    /// Kotlin `scope.launch { … }` on the main thread.
    private func launch(_ body: @escaping @MainActor () async throws -> Void) {
        if disposed { return }
        jobSerial += 1
        let id = jobSerial
        jobs[id] = Task { @MainActor [weak self] in
            do { try await body() } catch {}
            self?.jobs[id] = nil
        }
    }

    // MARK: Flow

    /// Starts play (a computer's turn runs on its own).
    func start() {
        if running { return }
        running = true
        resumedAt = ludoNow()
        LudoSound.warmUp()
        if let pending = engine.pendingRoll {
            // A saved match mid-choice: show the moves again.
            legal = engine.legalMoves(pending)
            diceValue = pending
            phase = .CHOOSE
            if isBotTurn { launch { [unowned self] in try await self.botMove() } }
            return
        }
        launch { [unowned self] in try await self.continueTurn() }
    }

    /// A person taps their dice.
    func rollTapped() {
        if phase != .ROLL || isBotTurn || paused || engine.isOver { return }
        launch { [unowned self] in try await self.roll() }
    }

    /// A person taps a token: plays its move if it has one.
    func tapToken(_ seat: Int, _ token: Int) {
        if phase != .CHOOSE || isBotTurn || seat != engine.current { return }
        guard let move = move(seat, token) else { return }
        launch { [unowned self] in try await self.play(move) }
    }

    /// The legal move for a token right now (any yard token takes the "come out" move).
    func move(_ seat: Int, _ token: Int) -> LudoMove? {
        if seat != engine.current { return nil }
        if let m = legal.first(where: { $0.token == token }) { return m }
        if engine.steps[seat][token] < 0 { return legal.first { $0.comesOut } }
        return nil
    }

    private func waitWhilePaused() async throws {
        while paused && !Task.isCancelled { try await sleep(0.15) }
    }

    private func continueTurn() async throws {
        if engine.isOver { return }
        phase = .ROLL
        if isBotTurn {
            try await sleep(thinkTime)
            try await waitWhilePaused()
            try await roll()
        }
    }

    private func roll() async throws {
        if phase != .ROLL || engine.isOver { return }
        phase = .ROLLING
        Haptics.play(.Light)
        LudoSound.play(.Shake)
        mark(ludoNow() + 0.7)
        try await sleep(reduceMotion ? 0.2 : 0.62)
        let value = dice.roll()
        diceValue = value
        landTick += 1
        Haptics.play(.Medium)
        LudoSound.play(.Land)
        if value == 6 { LudoSound.play(.Six) }
        let roller = engine.current
        var next = engine.copy()
        let outcome = next.roll(value)
        engine = next
        switch outcome {
        case .ThreeSixes:
            Haptics.play(.Warning)
            LudoSound.play(.ThreeSixes)
            show("Three 6s! Turn lost", .STOP, nil)
            try await sleep(1.1)
            try await nextTurn()
        case .NoMoves(let again):
            // Waiting in the yard for a 6 is normal; only call out tokens that are stuck.
            let stuck = engine.steps[roller].contains { $0 >= 0 && $0 < geometry.homeStep }
            if stuck || again {
                try await sleep(0.25)
                show(again ? "No moves · roll again" : "No moves", .HAND, config.seats[roller].arm)
                try await sleep(0.7)
            } else {
                try await sleep(0.45)
            }
            if again { try await continueTurn() } else { try await nextTurn() }
        case .Moves(let moves):
            legal = moves
            phase = .CHOOSE
            if isBotTurn {
                try await botMove()
            } else if config.rules.autoMove && moves.count == 1 {
                try await sleep(0.35)
                try await play(moves[0])
            } else if moves.count > 1 && Set(moves.map { $0.to }).count == 1 && moves.allSatisfy({ $0.from == moves[0].from }) {
                // Tokens sharing a square all lead to the same place: no real choice.
                try await sleep(0.35)
                try await play(moves[0])
            }
        }
    }

    private func botMove() async throws {
        try await sleep(thinkTime * 0.8)
        try await waitWhilePaused()
        if phase != .CHOOSE { return }
        let moves = legal
        let snapshot = engine
        let difficulty = currentSeat.difficulty
        guard let move = LudoBot.choose(moves, snapshot, difficulty, botRandom) else { return }
        try await play(move)
    }

    private func play(_ move: LudoMove) async throws {
        if phase != .CHOOSE { return }
        legal = []
        preview = nil
        phase = .MOVING
        let g = geometry
        let arm = config.seats[move.seat].arm
        let now = ludoNow()
        let travel = move.comesOut ? (reduceMotion ? 0.15 : 0.42) : Double(move.to - move.from) * hopTime
        add(.Hop(seat: move.seat, token: move.token, from: move.from, to: move.to), now, travel)
        let landing = move.to == g.homeStep ? g.homeSpot(arm, 0, 1) : g.routePoint(arm, max(move.to, 0))
        for ref in move.captures {
            let victimArm = config.seats[ref.seat].arm
            add(.Knock(seat: ref.seat, token: ref.token, from: engine.steps[ref.seat][ref.token], delay: travel), now, travel + (reduceMotion ? 0.3 : 0.65))
            add(.Burst(at: landing, arm: victimArm, big: true), now + travel, 0.6)
        }
        if move.comesOut {
            LudoSound.play(.ComeOut)
            add(.Burst(at: landing, arm: arm, big: false), now + travel, 0.45)
        } else {
            let hops = move.to - move.from
            let hop = hopTime
            launch { [unowned self] in
                for step in 0..<hops {
                    LudoSound.play(.Hop(step))
                    Haptics.play(.Tick)
                    try await self.sleep(hop)
                }
            }
        }
        var next = engine.copy()
        let result = next.apply(move)
        engine = next
        try await sleep(travel)

        if !result.captured.isEmpty {
            captureTick += 1
            Haptics.play(.Heavy)
            LudoSound.play(.Capture)
            show(result.captured.count > 1 ? "Double capture!" : "Captured!", .BOLT, arm)
            try await sleep(reduceMotion ? 0.3 : 0.65)
        } else if result.reachedHome {
            Haptics.play(.Success)
            LudoSound.play(.Home)
            add(.Burst(at: landing, arm: arm, big: true), ludoNow(), 0.7)
            show(result.seatFinished ? "\(config.seats[move.seat].player.name) is home!" : "Home!", .HOUSE, arm)
            try await sleep(0.55)
        } else {
            if let index = g.trackIndex(arm, move.to), engine.isSafe(index), !move.comesOut { LudoSound.play(.Safe) }
        }
        save()

        if result.gameOver {
            finish()
        } else if result.extraRoll {
            if !result.captured.isEmpty || result.reachedHome {
                LudoSound.play(.Extra)
                extraTick += 1
            }
            try await continueTurn()
        } else {
            try await nextTurn()
        }
    }

    private func nextTurn() async throws {
        if engine.isOver { return }
        LudoSound.play(.Turn)
        try await continueTurn()
    }

    private func finish() {
        bank()
        phase = .OVER
        Haptics.play(.Success)
        LudoSound.play(.Win)
        LudoStore.saved = nil
    }

    // MARK: Helpers

    private func add(_ kind: LudoAnim.Kind, _ start: Double, _ duration: Double) {
        nextID += 1
        let now = ludoNow()
        anims = anims.filter { $0.isActive(now) } + [LudoAnim(nextID, kind, start, duration)]
        mark(start + duration)
    }

    /// Keeps the token layer drawing until `time`.
    private func mark(_ time: Double) {
        if time > animationEnd { animationEnd = time }
    }

    private func show(_ text: String, _ icon: LudoBanner.Icon, _ arm: Int?) {
        nextID += 1
        let b = LudoBanner(id: nextID, text: text, icon: icon, arm: arm)
        banner = b
        launch { [unowned self] in
            try await self.sleep(1.3)
            if self.banner?.id == b.id { self.banner = nil }
        }
    }

    private func bank() {
        if phase == .OVER { return }
        let now = ludoNow()
        elapsedBanked += now - resumedAt
        resumedAt = now
    }

    /// Saves the match after every move, so it can be resumed later.
    func save() {
        if engine.isOver || !running || abandoned { return }
        LudoStore.saved = LudoStore.SavedMatch(config.copy(resume: true), engine, elapsed, Days.nowMillis())
    }

    /// Adds the match to the party history.
    func record() {
        let winner = engine.ranks.first.map { config.seats[$0].player }
        let minutes = max(1, Kt.roundToInt(elapsed / 60))
        let detail = "\(config.seats.count) players · \(config.rules.quick ? "Quick" : "Classic") · \(minutes) min"
        PartyStore.record(GameKind.LUDO, config.seats.map { $0.player }, winner, detail)
    }
}
