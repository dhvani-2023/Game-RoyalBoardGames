import Foundation
import Observation
import GameKit

/// A shot being played back: the physics ran to the end on release, and the board draws its 60 fps frames in real
/// time.
final class CarromPlayback {
    let start: Double
    let frames: [[Float]]
    let kinds: [CarromKind]
    /// Which discs were on the board when the shot began.
    let live: [Bool]
    let pocketed: [CarromPhysics.Pocketed]
    let duration: Double
    /// Per disc, where and when it dropped (precomputed so drawing a frame allocates nothing).
    let dropped: [CarromPhysics.Pocketed?]
    /// Simulated seconds per real second (Extras: the instant replay plays at 0.4×).
    let rate: Double

    init(_ start: Double, _ frames: [[Float]], _ kinds: [CarromKind], _ live: [Bool], _ pocketed: [CarromPhysics.Pocketed], _ duration: Double,
         rate: Double = 1.0) {
        self.rate = rate
        self.start = start
        self.frames = frames
        self.kinds = kinds
        self.live = live
        self.pocketed = pocketed
        self.duration = duration
        var d = [CarromPhysics.Pocketed?](repeating: nil, count: kinds.count)
        for p in pocketed where p.disc < d.count { d[p.disc] = p }
        dropped = d
    }

    /// Coins finish sinking a moment after the last one drops.
    var end: Double { start + duration / rate + 0.35 }
}

struct CarromAim: Equatable {
    let angle: Double
    let power: Double

    init(_ angle: Double, _ power: Double) {
        self.angle = angle
        self.power = power
    }
}

/// A short effect drawn by the piece layer, in board centimetres.
final class CarromEffect {
    enum Kind {
        case FloatText(String, CarromColor)
        case Ring(CarromColor)
        case Sparks(Double)
        /// A coin coming back onto the board.
        case Pop(Int)
    }

    let id: Int
    let kind: Kind
    let at: CarromVec
    let start: Double
    let duration: Double

    init(_ id: Int, _ kind: Kind, _ at: CarromVec, _ start: Double, _ duration: Double) {
        self.id = id
        self.kind = kind
        self.at = at
        self.start = start
        self.duration = duration
    }

    func progress(_ now: Double) -> Double { Swift.min(1.0, Swift.max(0.0, (now - start) / duration)) }
    func isActive(_ now: Double) -> Bool { now >= start && now < start + duration }
}

/// Banner icons, mapped to symbols by the view.
enum CarromBannerIcon { case CROWN, WARNING, UNDO, SPARKLES, TIMER }

struct CarromBanner: Equatable {
    let id: Int
    let text: String
    let icon: CarromBannerIcon
    let tint: CarromColor
}

struct CarromToss: Equatable {
    let id: Int
    let seat: Int
}

/// One Carrom match: the rules table plus striker placement, aiming, shot playback, computer players, banners, the
/// shot clock and autosave. Observable throughout; every task runs on the main actor and stale ones bail out on
/// [turnToken].
@MainActor
@Observable
final class CarromSession {
    enum Phase { case INTRO, READY, AIMING, ROLLING, BETWEEN, OVER }

    let config: CarromConfig

    /// Set by the view from the app's Reduce Motion setting.
    @ObservationIgnored var reduceMotion = false

    private(set) var match: CarromMatch
    private(set) var phase: Phase = .INTRO
    private(set) var slide: Double = 0.0
    private(set) var aim: CarromAim? = nil
    private(set) var guide = CarromGuide()
    private(set) var blocked = false
    private(set) var playback: CarromPlayback? = nil
    /// Extras: the last shot as played, and its physics events, for the instant replay.
    private(set) var lastShot: CarromPlayback? = nil
    @ObservationIgnored private(set) var lastShotEvents: [CarromPhysics.Event] = []
    @ObservationIgnored private(set) var lastShotStriker = -1
    /// Extras: the instant replay being shown (see `CarromExtras.swift`).
    var replay: CarromPlayback? = nil
    private(set) var introStart: Double? = nil
    private(set) var effects: [CarromEffect] = []
    private(set) var banner: CarromBanner? = nil
    private(set) var toss: CarromToss? = nil
    /// Quarter turns clockwise applied to the board, so the shooter sits at the bottom.
    private(set) var viewTurns = 0
    private(set) var clockEnds: Double? = nil
    private(set) var fine = false
    /// Until when the piece layer must redraw every frame.
    private(set) var animationEnd: Double = -Double.infinity

    private var pausedState = false
    var paused: Bool {
        get { pausedState }
        set {
            pausedState = newValue
            if newValue { bank() } else { resumedAt = carromNow() }
        }
    }

    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var turnToken = 0
    @ObservationIgnored private var elapsedBanked: Double
    @ObservationIgnored private var resumedAt = carromNow()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var chargeLevel = -1
    @ObservationIgnored private var discarded = false
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTask = 0

    /// Every seat plays itself (the reference's `-debugAutoplay`); off in shipping builds.
    @ObservationIgnored private let autoplay = false

    init(_ config: CarromConfig) {
        self.config = config
        let saved = config.resume ? CarromStore.saved : nil
        let m = saved?.match ?? CarromMatch.create(config.options, config.seats.count, Int.random(in: 0..<Swift.max(1, config.seats.count)))
        if config.practice { m.table.practice = true }
        match = m
        elapsedBanked = config.resume ? (saved?.elapsed ?? 0.0) : 0.0
    }

    // MARK: State for the view

    var table: CarromTable { match.table }
    var currentSeat: CarromSeat { config.seats[table.turn] }
    var isBotTurn: Bool { currentSeat.isBot || autoplay }
    var people: Int { config.seats.filter { !$0.isBot }.count }
    var viewSide: Int { ((viewTurns % 4) + 4) % 4 }
    var strikerPoint: CarromVec { table.strikerSpot(slide) }
    /// A person may place and aim right now.
    var canControl: Bool { (phase == .READY || phase == .AIMING) && !isBotTurn && !paused && replay == nil }
    /// The slider under the board works when the shooter sits at the bottom.
    var sliderActive: Bool { canControl && viewSide == table.side }
    var elapsed: Double { elapsedBanked + ((paused || phase == .OVER) ? 0.0 : carromNow() - resumedAt) }
    /// True while the piece layer needs to redraw every frame.
    func animating(_ now: Double = carromNow()) -> Bool { playback != nil || replay != nil || introStart != nil || animationEnd > now }

    func unitName(_ unit: Int) -> String { table.teams ? CarromStore.teamNames[unit] : config.seats[unit].player.name }

    func seats(_ ofUnit: Int) -> [Int] { config.seats.indices.filter { table.unit($0) == ofUnit } }

    // MARK: Flow

    func start() {
        if running { return }
        running = true
        resumedAt = carromNow()
        CarromSound.warmUp()
        if config.resume && table.winner != nil && !match.isOver {
            phase = .BETWEEN // saved between boards
            return
        }
        if config.resume && table.strokes > 0 {
            introStart = nil
            beginTurn(fresh: true)
            return
        }
        let toss = (!config.resume || table.strokes == 0) && !config.practice
        launch { try await self.intro(toss: toss) }
    }

    /// The match is being thrown away (restart): never save it again.
    func discard() {
        discarded = true
    }

    /// Stops every task (the screen left).
    func dispose() {
        turnToken += 1
        disposed = true
        for t in tasks.values { t.cancel() }
        tasks.removeAll()
    }

    private func intro(toss: Bool) async throws {
        phase = .INTRO
        if toss {
            nextID += 1
            self.toss = CarromToss(id: nextID, seat: table.turn)
            CarromSound.play(.Toss)
            try await sleep(reduceMotion || autoplay ? 0.4 : 1.4)
            self.toss = nil
        }
        rack()
        try await sleep(reduceMotion || autoplay ? 0.2 : 0.75)
        introStart = nil
        beginTurn(fresh: true)
    }

    private func rack() {
        introStart = carromNow()
        mark(carromNow() + 0.8)
        CarromSound.play(.Rack)
    }

    private func beginTurn(fresh: Bool) {
        if match.isOver || table.winner != nil { return }
        turnToken += 1
        phase = .READY
        aim = nil
        fine = false
        guide = CarromGuide()
        chargeLevel = -1
        let seat = currentSeat
        if !seat.isBot && !autoplay {
            // Turn the board so the shooter's base line is at the bottom, by the slider.
            setView(config.options.turnBoard ? seat.side : 0)
        } else if people == 0 || autoplay {
            setView(0)
        }
        slide = table.freeSlide(fresh ? 0.0 : slide)
        blocked = !table.strikerFits(slide)
        if isBotTurn {
            let token = turnToken
            launch { try await self.botTurn(token) }
        } else {
            startClock()
        }
    }

    private func setView(_ side: Int) {
        var delta = (side - viewSide + 4) % 4
        if delta == 3 { delta = -1 }
        viewTurns += delta
    }

    private func waitWhilePaused() async throws {
        while (paused || replay != nil) && !disposed { try await Task.sleep(nanoseconds: 150_000_000) }
    }

    // MARK: A person's input

    func slideTo(_ value: Double) {
        if !canControl || phase != .READY { return }
        let old = slide
        slide = CarromMath.max(-1.0, CarromMath.min(1.0, value))
        if Kt.toInt((old * CarromBoard.slideMax).rounded(.down)) != Kt.toInt((slide * CarromBoard.slideMax).rounded(.down)) {
            Haptics.play(.Tick)
            CarromSound.play(.Tick, throttle: 0.02)
        }
        let nowBlocked = !table.strikerFits(slide)
        if blocked != nowBlocked { blocked = nowBlocked }
    }

    func setAim(_ angle: Double, _ power: Double, _ fine: Bool) {
        if !canControl || blocked { return }
        if phase != .AIMING { phase = .AIMING }
        if self.fine != fine { self.fine = fine }
        let a = CarromAim(CarromBoard.clampAim(angle, table.side), CarromMath.max(0.0, CarromMath.min(1.0, power)))
        aim = a
        guide = CarromGuide.compute(table, slide, a.angle, config.options.aimGuide)
        let level = Kt.toInt(a.power * 5.99)
        if level != chargeLevel {
            if level > chargeLevel { CarromSound.play(.Charge(level), throttle: 0.01) }
            chargeLevel = level
        }
    }

    func cancelAim() {
        if phase != .AIMING { return }
        phase = .READY
        aim = nil
        fine = false
        guide = CarromGuide()
        chargeLevel = -1
    }

    func release() {
        guard canControl, let a = aim, a.power >= 0.05, !blocked else { cancelAim(); return }
        shoot(CarromShot(slide, a.angle, a.power))
    }

    // MARK: Shots

    private func shoot(_ shot: CarromShot) {
        turnToken += 1
        replay = nil
        clockEnds = nil
        phase = .ROLLING
        aim = nil
        fine = false
        guide = CarromGuide()
        Haptics.play(.Medium)
        CarromSound.play(.Release)
        let sim = table.simulate(shot, record: true)
        let start = carromNow() + 0.02
        let pb = CarromPlayback(
            start, sim.run.frames, sim.discs.map(\.kind), table.coins.map(\.live) + [true],
            sim.run.pocketed, sim.run.duration
        )
        playback = pb
        lastShot = pb
        lastShotEvents = sim.run.events
        lastShotStriker = sim.striker
        mark(pb.end)
        scheduleFeedback(sim.run, sim.discs, sim.striker, start)
        launch {
            try await self.sleep(pb.end - carromNow())
            try await self.finishShot(sim)
        }
    }

    /// Sounds, haptics and sparks at the moments the physics recorded.
    private func scheduleFeedback(_ run: CarromPhysics.Run, _ discs: [CarromDisc], _ striker: Int, _ start: Double) {
        for event in run.events {
            switch event.kind {
            case .HIT:
                if event.strength > 900 {
                    add(.Sparks(event.strength), event.at, start + event.time, 0.35)
                }
            case .POCKET:
                let kind = discs[event.disc].kind
                let colour: CarromColor
                switch kind {
                case .QUEEN: colour = CarromColor(0xFFD24D)
                case .STRIKER: colour = CarromColor(0xFF4D4D)
                default: colour = .white
                }
                let pocket = CarromBoard.pockets[event.pocket]
                add(.Ring(colour), pocket, start + event.time, 0.6)
                if match.mode == .FREESTYLE && kind != .STRIKER && !table.practice {
                    let value: Int
                    switch kind {
                    case .WHITE: value = 20
                    case .BLACK: value = 10
                    default: value = 50
                    }
                    add(.FloatText("+\(value)", kind == .QUEEN ? CarromColor(0xFFD24D) : .white), pocket * 0.86, start + event.time + 0.05, 0.9)
                }
            case .FRAME:
                break
            }
        }
        let events = run.events
        launch {
            for event in events {
                let wait = start + event.time - carromNow()
                if wait > 0 { try await self.sleep(wait) }
                switch event.kind {
                case .HIT:
                    let level = event.strength > 1600 ? 3 : (event.strength > 700 ? 2 : (event.strength > 180 ? 1 : 0))
                    let isStriker = event.disc == striker || event.other == striker
                    CarromSound.play(isStriker ? .Strike(level) : .Clack(level), throttle: 0.015)
                    if level >= 2 { Haptics.play(.Tick) }
                case .FRAME:
                    if event.strength > 25 {
                        let level = event.strength > 160 ? 2 : (event.strength > 70 ? 1 : 0)
                        CarromSound.play(.Frame(level), throttle: 0.04)
                    }
                case .POCKET:
                    CarromSound.play(.Pocket, throttle: 0.05)
                    Haptics.play(.Medium)
                }
            }
        }
    }

    private func finishShot(_ sim: CarromSimulation) async throws {
        let m = match.deepCopy()
        let stroke = m.table.apply(sim.discs, sim.run, sim.striker)
        match = m
        playback = nil
        // Coins that came back (dues, the queen-first rule, an uncovered queen) pop onto the board.
        var popped = false
        for (i, coin) in table.coins.enumerated() where coin.live && !sim.discs[i].live {
            add(.Pop(i), coin.p, carromNow() + 0.15, 0.45)
            popped = true
        }
        if popped { CarromSound.play(.Pop) }
        let pause = react(stroke)
        save()
        try await sleep(pause)
        if stroke.boardOver {
            finishBoard()
        } else if stroke.continues {
            beginTurn(fresh: false)
        } else {
            nextTurn()
        }
    }

    /// Banners and sounds for what a stroke did. Returns how long to let it sink in.
    private func react(_ s: CarromStroke) -> Double {
        let seatColour = CarromColor.player(config.seats[s.seat].player)
        let own = match.mode == .FREESTYLE ? s.pocketed.count : s.pocketed.filter { $0 == table.colour(table.unit(s.seat)) }.count
        if s.queenFirst && match.tournament {
            foul()
            CarromSound.play(.Foul)
            show("Queen first! Board lost", .CROWN, CarromColor(0xE0115F))
            return 1.1
        }
        if s.foul {
            foul()
            CarromSound.play(.Foul)
            show(match.mode == .FREESTYLE ? "Foul! −10" : "Foul! A coin comes back", .WARNING, CarromColor(0xE0115F))
            return 1.0
        }
        if s.queenFirst {
            foul()
            show("Queen first! Coin back", .CROWN, CarromColor(0xE0115F))
            return 1.0
        }
        if s.queenCovered {
            Haptics.play(.Success)
            CarromSound.play(.Cover)
            show("Queen covered!", .CROWN, CarromColor(0xF0A21C))
            return 0.9
        }
        if s.queenWaiting {
            CarromSound.play(.Queen)
            show("Queen! Cover it now", .CROWN, CarromColor(0xE0115F))
            return 0.8
        }
        if s.queenReturned {
            show("The Queen goes back", .UNDO, CarromColor(0x6C63FF))
            return 0.8
        }
        if s.pocketed.count >= 2 && own >= 2 {
            CarromSound.play(.Combo(s.pocketed.count))
            show(s.pocketed.count >= 4 ? "Quadruple!" : (s.pocketed.count == 3 ? "Triple!" : "Double!"), .SPARKLES, seatColour)
            return 0.7
        }
        return s.pocketed.isEmpty ? 0.25 : 0.4
    }

    private func foul() { Haptics.play(.Warning) }

    private func nextTurn() {
        if match.isOver { return }
        CarromSound.play(.Turn)
        beginTurn(fresh: true)
    }

    // MARK: Computer players

    private func botTurn(_ token: Int) async throws {
        let seat = currentSeat
        let level = seat.isBot ? seat.difficulty : CarromDifficulty.HARD
        let snapshot = table.deepCopy()
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        let begun = carromNow()
        let plan = await Task.detached(priority: .userInitiated) { CarromBot.plan(snapshot, level, seed) }.value
        try Task.checkCancellation()
        let fast = config.options.fastBots || autoplay
        let think = autoplay ? 0.05 : (fast ? 0.3 : (reduceMotion ? 0.5 : 0.75))
        let left = think - (carromNow() - begun)
        if left > 0 { try await sleep(left) }
        try await waitWhilePaused()
        if token != turnToken || phase != .READY { return }

        // Glide the striker to its spot, then grow the aim so people can follow.
        let from = slide
        let to = table.freeSlide(plan.shot.slide)
        let glide = fast ? 6 : 14
        for i in 1...glide {
            let t = Double(i) / Double(glide)
            slide = from + (to - from) * (t * t * (3 - 2 * t))
            try await Task.sleep(nanoseconds: 28_000_000)
        }
        blocked = !table.strikerFits(slide)
        let grow = fast ? 6 : 16
        for i in 1...grow {
            let a = CarromAim(CarromBoard.clampAim(plan.shot.angle, table.side), plan.shot.power * Double(i) / Double(grow))
            aim = a
            guide = CarromGuide.compute(table, slide, a.angle, config.options.aimGuide == .OFF ? .OFF : .SHORT)
            try await Task.sleep(nanoseconds: 28_000_000)
        }
        try await sleep(fast ? 0.08 : 0.3)
        try await waitWhilePaused()
        if token != turnToken || !(phase == .READY || phase == .AIMING) { return }
        shoot(CarromShot(to, plan.shot.angle, plan.shot.power))
    }

    // MARK: Shot clock

    private func startClock() {
        let seconds = config.options.clockSeconds
        if seconds <= 0 { clockEnds = nil; return }
        clockEnds = carromNow() + Double(seconds)
        let token = turnToken
        launch {
            while true {
                try await Task.sleep(nanoseconds: 250_000_000)
                if token != self.turnToken { return }
                if self.paused || self.replay != nil { self.clockEnds = self.clockEnds.map { $0 + 0.25 }; continue }
                if let end = self.clockEnds, carromNow() >= end, self.phase == .READY || self.phase == .AIMING {
                    try await self.timeOut()
                    return
                }
            }
        }
    }

    private func timeOut() async throws {
        turnToken += 1
        clockEnds = nil
        aim = nil
        guide = CarromGuide()
        let m = match.deepCopy()
        m.table.timeOut()
        match = m
        foul()
        show("Time's up", .TIMER, CarromColor(0x6C63FF))
        save()
        try await sleep(0.8)
        nextTurn()
    }

    // MARK: Boards and the match

    private func finishBoard() {
        let m = match.deepCopy()
        let over = m.finishBoard()
        match = m
        Haptics.play(.Success)
        if over {
            bank()
            phase = .OVER
            CarromSound.play(.Win)
            CarromStore.saved = nil
        } else {
            phase = .BETWEEN
            CarromSound.play(.Cover)
            save()
            if autoplay { launch { try await self.sleep(1.0); self.nextBoard() } }
        }
    }

    func nextBoard() {
        if phase != .BETWEEN { return }
        let m = match.deepCopy()
        m.nextBoard()
        match = m
        lastShot = nil
        launch { try await self.intro(toss: false) }
    }

    /// Extras: the practice board's re-rack button (logic in `CarromPractice`).
    func rerack() {
        if !config.practice || phase != .READY || !running { return }
        turnToken += 1
        clockEnds = nil
        replay = nil
        lastShot = nil
        let m = match.deepCopy()
        m.table = CarromPractice.rack(match)
        match = m
        launch { try await self.intro(toss: false) }
    }

    // MARK: Helpers

    /// Kotlin `scope.launch`: a main-actor task, cancelled by [dispose].
    private func launch(_ body: @escaping @MainActor () async throws -> Void) {
        if disposed { return }
        nextTask += 1
        let id = nextTask
        let task = Task { @MainActor [weak self] in
            do { try await body() } catch {}
            self?.tasks.removeValue(forKey: id)
        }
        tasks[id] = task
    }

    private func sleep(_ seconds: Double) async throws {
        if seconds > 0 {
            let ms = UInt64(seconds * 1000)
            if ms > 0 { try await Task.sleep(nanoseconds: ms * 1_000_000) }
        }
    }

    private func add(_ kind: CarromEffect.Kind, _ at: CarromVec, _ start: Double, _ duration: Double) {
        nextID += 1
        let now = carromNow()
        effects = effects.filter { $0.start + $0.duration >= now } + [CarromEffect(nextID, kind, at, start, duration)]
        mark(start + duration)
    }

    func mark(_ until: Double) {
        if until > animationEnd { animationEnd = until }
    }

    private func show(_ text: String, _ icon: CarromBannerIcon, _ tint: CarromColor) {
        nextID += 1
        let b = CarromBanner(id: nextID, text: text, icon: icon, tint: tint)
        banner = b
        launch {
            try await self.sleep(1.3)
            if self.banner?.id == b.id { self.banner = nil }
        }
    }

    private func bank() {
        if phase == .OVER { return }
        let now = carromNow()
        elapsedBanked += now - resumedAt
        resumedAt = now
    }

    /// Saves the match while the board is at rest, so it can be resumed later.
    func save() {
        if discarded || config.practice || match.isOver || phase == .ROLLING { return }
        CarromStore.saved = CarromStore.SavedMatch(config.copy(resume: true), match, elapsed, Days.nowMillis())
    }

    /// The match summary for the party history.
    var record: PartyMatchRecord {
        let names = config.seats.map { "\($0.player.avatar) \($0.player.name)" }
        let winner: String? = match.winner.map { unit in
            table.teams ? CarromStore.teamNames[unit] : "\(config.seats[unit].player.avatar) \(config.seats[unit].player.name)"
        }
        let points = match.winner.map { match.scores[$0] } ?? 0
        let detail = "\(match.mode.title) · \(config.seats.count) players · \(points) pts"
        return PartyMatchRecord(kind: GameKind.CARROM.id, players: names, winner: winner, detail: detail)
    }
}
