import Foundation

/// 8-Ball or 9-Ball (the reference's `PoolGame` enum; renamed so it doesn't clash with the module object).
enum PoolVariant: String, Codable, CaseIterable, Sendable {
    case EIGHT, NINE

    var title: String { self == .EIGHT ? "8-Ball" : "9-Ball" }
    var blurb: String { self == .EIGHT ? "Solids or stripes, then the 8" : "Hit the lowest first, sink the 9 to win" }
}

enum PoolGroup: String, Codable, CaseIterable, Sendable {
    case SOLIDS, STRIPES

    var title: String { self == .SOLIDS ? "solids" : "stripes" }
    func has(_ n: Int) -> Bool { self == .SOLIDS ? (1...7).contains(n) : (9...15).contains(n) }
    var other: PoolGroup { self == .SOLIDS ? .STRIPES : .SOLIDS }
    var numbers: [Int] { self == .SOLIDS ? Array(1...7) : Array(9...15) }
}

enum PoolDifficulty: String, Codable, CaseIterable, Sendable {
    case EASY, NORMAL, HARD

    var title: String {
        switch self {
        case .EASY: return "Easy"
        case .NORMAL: return "Normal"
        case .HARD: return "Hard"
        }
    }
}

enum PoolMatchLength: String, Codable, CaseIterable, Sendable {
    case ONE, RACE_TO_3, RACE_TO_5

    var title: String {
        switch self {
        case .ONE: return "1 rack"
        case .RACE_TO_3: return "Race to 3"
        case .RACE_TO_5: return "Race to 5"
        }
    }

    var target: Int {
        switch self {
        case .ONE: return 1
        case .RACE_TO_3: return 3
        case .RACE_TO_5: return 5
        }
    }
}

enum PoolAimGuide: String, Codable, CaseIterable, Sendable {
    case FULL, SHORT, OFF

    var title: String {
        switch self {
        case .FULL: return "Full"
        case .SHORT: return "Short"
        case .OFF: return "Off"
        }
    }
}

// MARK: - Decoding with defaults (kotlinx: ignoreUnknownKeys, coerceInputValues, defaults)

extension KeyedDecodingContainer {
    /// A missing or null value falls back to the default, like kotlinx.serialization with defaults.
    func poolValue<T: Decodable>(_ key: Key, _ def: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? def()
    }

    /// An unknown enum member falls back to the default (kotlinx `coerceInputValues`).
    func poolEnum<T: RawRepresentable>(_ key: Key, _ def: T) -> T where T.RawValue == String {
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return def }
        return T(rawValue: raw) ?? def
    }
}

/// Every field has a default, so adding options never resets the rest of a saved setup.
struct PoolOptions: Equatable, Codable, Sendable {
    var game: PoolVariant = .EIGHT
    var length: PoolMatchLength = .RACE_TO_3
    var winnerBreaks: Bool = false
    var tableSize: PoolTableSize = .BAR
    var callEight: Bool = true
    /// Ball in hand after a break scratch is behind the head string (otherwise anywhere).
    var kitchenAfterScratch: Bool = true
    /// 9-Ball: three fouls in a row lose the rack.
    var threeFouls: Bool = false
    var aimGuide: PoolAimGuide = .FULL
    /// Seconds per shot, 0 for no clock.
    var shotClock: Int = 0
    var fastBots: Bool = false

    init(game: PoolVariant = .EIGHT, length: PoolMatchLength = .RACE_TO_3, winnerBreaks: Bool = false,
         tableSize: PoolTableSize = .BAR, callEight: Bool = true, kitchenAfterScratch: Bool = true,
         threeFouls: Bool = false, aimGuide: PoolAimGuide = .FULL, shotClock: Int = 0, fastBots: Bool = false) {
        self.game = game; self.length = length; self.winnerBreaks = winnerBreaks; self.tableSize = tableSize
        self.callEight = callEight; self.kitchenAfterScratch = kitchenAfterScratch; self.threeFouls = threeFouls
        self.aimGuide = aimGuide; self.shotClock = shotClock; self.fastBots = fastBots
    }

    private enum CodingKeys: String, CodingKey {
        case game, length, winnerBreaks, tableSize, callEight, kitchenAfterScratch, threeFouls, aimGuide, shotClock, fastBots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = c.poolEnum(.game, .EIGHT)
        length = c.poolEnum(.length, .RACE_TO_3)
        winnerBreaks = try c.poolValue(.winnerBreaks, false)
        tableSize = c.poolEnum(.tableSize, .BAR)
        callEight = try c.poolValue(.callEight, true)
        kitchenAfterScratch = try c.poolValue(.kitchenAfterScratch, true)
        threeFouls = try c.poolValue(.threeFouls, false)
        aimGuide = c.poolEnum(.aimGuide, .FULL)
        shotClock = try c.poolValue(.shotClock, 0)
        fastBots = try c.poolValue(.fastBots, false)
    }
}

struct PoolShot: Equatable, Codable, Sendable {
    var angle: Double = 0.0
    var power: Double = 0.0
    /// Cue tip offset, −0.5…0.5 each way: x right english, y follow (negative draw).
    var spin: Vec2 = Vec2.ZERO
    /// Where the cue ball goes first, with ball in hand.
    var place: Vec2? = nil
    /// The called pocket for the 8.
    var call: Int? = nil

    init(_ angle: Double = 0.0, _ power: Double = 0.0, _ spin: Vec2 = Vec2.ZERO, _ place: Vec2? = nil, _ call: Int? = nil) {
        self.angle = angle; self.power = power; self.spin = spin; self.place = place; self.call = call
    }

    init(angle: Double = 0.0, power: Double = 0.0, spin: Vec2 = Vec2.ZERO, place: Vec2? = nil, call: Int? = nil) {
        self.init(angle, power, spin, place, call)
    }

    private enum CodingKeys: String, CodingKey { case angle, power, spin, place, call }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        angle = try c.poolValue(.angle, 0.0)
        power = try c.poolValue(.power, 0.0)
        spin = try c.poolValue(.spin, Vec2.ZERO)
        place = try c.decodeIfPresent(Vec2.self, forKey: .place)
        call = try c.decodeIfPresent(Int.self, forKey: .call)
    }
}

struct PoolSeatStats: Equatable, Codable, Sendable {
    var potted: Int = 0
    var fouls: Int = 0
    var bestRun: Int = 0
    var breakAndRuns: Int = 0
    var shots: Int = 0

    init(potted: Int = 0, fouls: Int = 0, bestRun: Int = 0, breakAndRuns: Int = 0, shots: Int = 0) {
        self.potted = potted; self.fouls = fouls; self.bestRun = bestRun; self.breakAndRuns = breakAndRuns; self.shots = shots
    }

    func copy() -> PoolSeatStats { self }

    private enum CodingKeys: String, CodingKey { case potted, fouls, bestRun, breakAndRuns, shots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        potted = try c.poolValue(.potted, 0)
        fouls = try c.poolValue(.fouls, 0)
        bestRun = try c.poolValue(.bestRun, 0)
        breakAndRuns = try c.poolValue(.breakAndRuns, 0)
        shots = try c.poolValue(.shots, 0)
    }
}

/// What one shot did, for banners, sounds and stats.
struct PoolStroke: Sendable {
    var seat = 0
    var potted: [Int] = []
    var foul = false
    var why = ""
    var continues = false
    var rackOver = false
    var won = false
    var groupsSet: PoolGroup? = nil
    var respotted: Int? = nil
    var scratch = false
    var timedOut = false
}

/// One rack in progress. A value type: copies are the reference's struct copies ([clone]).
struct PoolTableState: Codable, Sendable {
    var game: PoolVariant = .EIGHT
    var size: PoolTableSize = .BAR
    var seats: Int = 2
    var teams: Bool = false
    var callEight: Bool = true
    var kitchenAfterScratch: Bool = true
    var threeFouls: Bool = false
    var balls: [PoolBall] = []
    var turn: Int = 0
    var breaker: Int = 0
    var broken: Bool = false
    /// Groups per unit (8-Ball).
    var groups: [PoolGroup?] = [nil, nil]
    var ballInHand: Bool = true
    var kitchenOnly: Bool = true
    /// Unit that won the rack.
    var winner: Int? = nil
    var foulStreak: [Int] = [0, 0]
    var stats: [PoolSeatStats] = [PoolSeatStats(), PoolSeatStats()]
    var shots: Int = 0
    /// Pots in the current visit, and whether the breaker is still on the break visit.
    var streak: Int = 0
    var breakVisit: Bool = true
    /// Extras: a practice table (one player, no fouls or turns). Never saved.
    var practice: Bool = false

    init() {}

    static func create(_ game: PoolVariant, _ options: PoolOptions, _ seats: Int, _ breaker: Int, _ seed: Int64) -> PoolTableState {
        let teams = game == .EIGHT && seats == 4
        let t = PoolTableGeometry.of(options.tableSize)
        var s = PoolTableState()
        s.game = game
        s.size = options.tableSize
        s.seats = seats
        s.teams = teams
        s.callEight = options.callEight
        s.kitchenAfterScratch = options.kitchenAfterScratch
        s.threeFouls = options.threeFouls
        s.balls = game == .EIGHT ? PoolRack.eight(t, seed) : PoolRack.nine(t, seed)
        s.turn = breaker
        s.breaker = breaker
        s.groups = [PoolGroup?](repeating: nil, count: teams ? 2 : seats)
        s.foulStreak = [Int](repeating: 0, count: seats)
        s.stats = [PoolSeatStats](repeating: PoolSeatStats(), count: seats)
        return s
    }

    func clone() -> PoolTableState { self }

    var geometry: PoolTableGeometry { PoolTableGeometry.of(size) }
    var units: Int { teams ? 2 : seats }
    /// 8-Ball with four players is two teams: seats 0 and 2 against 1 and 3.
    func unit(_ ofSeat: Int) -> Int { teams ? ofSeat % 2 : ofSeat }
    var unitNow: Int { unit(turn) }
    var cue: PoolBall { balls[0] }
    func ball(_ n: Int) -> PoolBall? { balls.first { $0.n == n && $0.live } }
    func left(_ g: PoolGroup) -> Int { balls.filter { $0.live && g.has($0.n) }.count }
    var lowest: Int? { balls.filter { $0.live && $0.n > 0 }.map { $0.n }.min() }
    var isOver: Bool { winner != nil }

    /// The shooter's group, if set.
    var groupNow: PoolGroup? { game == .EIGHT ? groups[unitNow] : nil }

    /// On the 8: their group is cleared.
    var onEight: Bool { game == .EIGHT && groupNow.map { left($0) == 0 } == true }

    /// Balls the shooter may legally hit first.
    func legalFirst() -> [Int] {
        if practice { return PoolPractice.legalFirst(self) }
        switch game {
        case .NINE:
            return lowest.map { [$0] } ?? []
        case .EIGHT:
            if let g = groupNow {
                let mine = balls.filter { $0.live && g.has($0.n) }.map { $0.n }
                return mine.isEmpty ? [8] : mine
            } else {
                return balls.filter { $0.live && $0.n != 0 && $0.n != 8 }.map { $0.n }
            }
        }
    }

    /// Where the cue ball may go with ball in hand.
    func free(_ p: Vec2) -> Bool {
        let t = geometry
        if !t.onTable(p) { return false }
        if kitchenOnly && !t.inKitchen(p) { return false }
        return balls.allSatisfy { !$0.live || $0.n == 0 || ($0.p - p).length >= 2 * PoolTableGeometry.R + 0.05 }
    }

    /// The nearest free spot to [p] for the cue ball.
    func freeSpot(_ near: Vec2) -> Vec2 {
        let p = near
        let t = geometry
        var q = Vec2(poolMax(-t.a + 3, poolMin(kitchenOnly ? t.headString : t.a - 3, p.x)), poolMax(-t.b + 3, poolMin(t.b - 3, p.y)))
        if free(q) { return q }
        for ring in 1...30 {
            for k in 0..<(ring * 8) {
                let a = Double(k) / Double(ring * 8) * 2 * Double.pi
                q = p + Vec2(PoolSM.cos(a), PoolSM.sin(a)) * Double(ring) * 1.5
                if free(q) { return q }
            }
        }
        return PoolRack.cueBall(t).p
    }

    mutating func respot(_ n: Int) {
        guard let i = balls.firstIndex(where: { $0.n == n }) else { return }
        var p = geometry.footSpot
        while !balls.allSatisfy({ !$0.live || $0.n == n || ($0.p - p).length >= 2 * PoolTableGeometry.R + 0.05 }) {
            p = Vec2(p.x + 0.5, p.y)
        }
        balls[i] = PoolBall(n, p)
    }

    /// The physics run for a shot, without changing the table.
    func simulate(_ shot: PoolShot, _ record: Bool) -> ([PoolBall], PoolPhysics.Run) {
        var b = balls
        if ballInHand, let place = shot.place, free(place) { b[0].p = place }
        b[0].live = true
        PoolPhysics.strike(&b[0], shot.angle, shot.power, shot.spin)
        let run = PoolPhysics.run(&b, geometry, record)
        return (b, run)
    }

    mutating func play(_ shot: PoolShot) -> PoolStroke {
        let legal = legalFirst()
        let (b, run) = simulate(shot, false)
        return apply(b, run, shot, legal)
    }

    /// Applies a finished physics run (from [simulate], with [legal] taken before the shot).
    mutating func apply(_ after: [PoolBall], _ run: PoolPhysics.Run, _ shot: PoolShot, _ legal: [Int]) -> PoolStroke {
        if practice { return PoolPractice.apply(&self, after, run) }
        var s = PoolStroke()
        s.seat = turn
        let wasBreak = !broken
        balls = after.map { var b = $0; b.stop(); return b }
        broken = true
        shots += 1
        stats[turn].shots += 1
        ballInHand = false
        kitchenOnly = false
        let potted = run.potted.map { after[$0.ball].n }
        s.potted = potted
        let objects = potted.filter { $0 != 0 }
        s.scratch = potted.contains(0)

        // Fouls.
        let first = run.firstHit
        if s.scratch {
            s.foul = true; s.why = "Scratch"
        } else if first == nil {
            s.foul = true; s.why = "No ball hit"
        } else if let f = first, !legal.contains(f) {
            s.foul = true
            s.why = game == .NINE ? "Hit the \(legal.first ?? 1) first" : (f == 8 ? "Hit the 8 too early" : "Wrong ball first")
        } else if !wasBreak && objects.isEmpty && !run.railAfterContact {
            s.foul = true; s.why = "No cushion after contact"
        }
        if wasBreak && !s.foul && objects.isEmpty && run.cushionBalls.subtracting([0]).count < 4 {
            s.foul = true; s.why = "Weak break"
        }

        let me = turn
        let myUnit = unitNow
        switch game {
        case .EIGHT:
            if objects.contains(8) {
                if wasBreak {
                    respot(8)
                    s.respotted = 8
                } else {
                    let g = groups[myUnit]
                    let clearedBefore = g.map { gr in left(gr) == 0 && !objects.contains { gr.has($0) } } ?? false
                    let pocket = run.potted.first { after[$0.ball].n == 8 }?.pocket
                    let calledRight = !callEight || shot.call == nil || pocket == shot.call
                    s.won = clearedBefore && !s.foul && calledRight
                    if !s.won {
                        s.why = s.foul ? "The 8 on a foul" : (!clearedBefore ? "The 8 went down early" : "The 8 in the wrong pocket")
                    }
                    winner = s.won ? myUnit : (teams ? 1 - myUnit : (me + 1) % seats)
                    s.rackOver = true
                    finishVisit(s.won)
                    return s
                }
            }
            if !s.foul && !wasBreak && groups[myUnit] == nil {
                if let f = objects.first(where: { $0 != 8 }) {
                    let g: PoolGroup = (1...7).contains(f) ? .SOLIDS : .STRIPES
                    for u in 0..<units { groups[u] = u == myUnit ? g : g.other }
                    s.groupsSet = g
                }
            }
            let mine = groups[myUnit].map { g in objects.filter { g.has($0) }.count } ?? objects.filter { $0 != 8 }.count
            s.continues = !s.foul && (mine > 0 || (wasBreak && !objects.isEmpty))
            let mineGroup = groups[myUnit]
            stats[me].potted += objects.filter { $0 != 8 && (mineGroup?.has($0) ?? true) }.count
        case .NINE:
            if objects.contains(9) {
                if s.foul {
                    respot(9)
                    s.respotted = 9
                } else {
                    s.won = true
                    winner = myUnit
                    s.rackOver = true
                    stats[me].potted += objects.count
                    finishVisit(true)
                    return s
                }
            }
            s.continues = !s.foul && !objects.isEmpty
            stats[me].potted += objects.filter { $0 != 9 }.count
        }

        if s.scratch { balls[0] = PoolRack.cueBall(geometry) }
        if s.foul {
            stats[me].fouls += 1
            foulStreak[me] += 1
            ballInHand = true
            kitchenOnly = wasBreak && s.scratch && kitchenAfterScratch
            if game == .NINE && threeFouls && foulStreak[me] >= 3 {
                s.why = "Three fouls in a row"
                winner = (me + 1) % seats
                s.rackOver = true
                return s
            }
        } else {
            foulStreak[me] = 0
        }
        if s.continues {
            streak += objects.count
        } else {
            finishVisit(false)
            turn = (turn + 1) % seats
        }
        if ballInHand { balls[0].p = freeSpot(balls[0].p) }
        return s
    }

    /// The shot clock ran out: the next player has ball in hand.
    mutating func timeOut() -> PoolStroke {
        var s = PoolStroke()
        s.seat = turn
        s.timedOut = true
        s.foul = true
        s.why = "Time's up"
        stats[turn].fouls += 1
        finishVisit(false)
        turn = (turn + 1) % seats
        ballInHand = true
        kitchenOnly = !broken
        return s
    }

    private mutating func finishVisit(_ won: Bool) {
        stats[turn].bestRun = max(stats[turn].bestRun, streak)
        if won && breakVisit && turn == breaker { stats[turn].breakAndRuns += 1 }
        streak = 0
        breakVisit = false
    }

    private enum CodingKeys: String, CodingKey {
        case game, size, seats, teams, callEight, kitchenAfterScratch, threeFouls, balls, turn, breaker, broken, groups,
             ballInHand, kitchenOnly, winner, foulStreak, stats, shots, streak, breakVisit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = c.poolEnum(.game, .EIGHT)
        size = c.poolEnum(.size, .BAR)
        seats = try c.poolValue(.seats, 2)
        teams = try c.poolValue(.teams, false)
        callEight = try c.poolValue(.callEight, true)
        kitchenAfterScratch = try c.poolValue(.kitchenAfterScratch, true)
        threeFouls = try c.poolValue(.threeFouls, false)
        balls = try c.poolValue(.balls, [])
        turn = try c.poolValue(.turn, 0)
        breaker = try c.poolValue(.breaker, 0)
        broken = try c.poolValue(.broken, false)
        groups = try c.poolValue(.groups, [nil, nil])
        ballInHand = try c.poolValue(.ballInHand, true)
        kitchenOnly = try c.poolValue(.kitchenOnly, true)
        winner = try c.decodeIfPresent(Int.self, forKey: .winner)
        foulStreak = try c.poolValue(.foulStreak, [0, 0])
        stats = try c.poolValue(.stats, [PoolSeatStats(), PoolSeatStats()])
        shots = try c.poolValue(.shots, 0)
        streak = try c.poolValue(.streak, 0)
        breakVisit = try c.poolValue(.breakVisit, true)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(game, forKey: .game)
        try c.encode(size, forKey: .size)
        try c.encode(seats, forKey: .seats)
        try c.encode(teams, forKey: .teams)
        try c.encode(callEight, forKey: .callEight)
        try c.encode(kitchenAfterScratch, forKey: .kitchenAfterScratch)
        try c.encode(threeFouls, forKey: .threeFouls)
        try c.encode(balls, forKey: .balls)
        try c.encode(turn, forKey: .turn)
        try c.encode(breaker, forKey: .breaker)
        try c.encode(broken, forKey: .broken)
        try c.encode(groups, forKey: .groups)
        try c.encode(ballInHand, forKey: .ballInHand)
        try c.encode(kitchenOnly, forKey: .kitchenOnly)
        try c.encode(winner, forKey: .winner)
        try c.encode(foulStreak, forKey: .foulStreak)
        try c.encode(stats, forKey: .stats)
        try c.encode(shots, forKey: .shots)
        try c.encode(streak, forKey: .streak)
        try c.encode(breakVisit, forKey: .breakVisit)
    }
}

/// A whole match: one rack or a race. A value type: copies are the reference's struct copies ([clone]).
struct PoolMatch: Codable, Sendable {
    var options: PoolOptions = PoolOptions()
    var game: PoolVariant = .EIGHT
    var seats: Int = 2
    var teams: Bool = false
    var table: PoolTableState = PoolTableState()
    var rack: Int = 1
    var wins: [Int] = [0, 0]
    var winner: Int? = nil
    var totals: [PoolSeatStats] = [PoolSeatStats(), PoolSeatStats()]
    var seed: Int64 = 1

    init() {}

    static func create(_ options: PoolOptions, _ seats: Int, _ firstBreak: Int, _ seed: Int64) -> PoolMatch {
        let game: PoolVariant = seats == 3 ? .NINE : options.game
        let teams = game == .EIGHT && seats == 4
        var m = PoolMatch()
        m.options = options
        m.game = game
        m.seats = seats
        m.teams = teams
        m.table = PoolTableState.create(game, options, seats, firstBreak, seed)
        m.wins = [Int](repeating: 0, count: teams ? 2 : seats)
        m.totals = [PoolSeatStats](repeating: PoolSeatStats(), count: seats)
        m.seed = seed
        return m
    }

    func clone() -> PoolMatch { self }

    var units: Int { teams ? 2 : seats }
    var isOver: Bool { winner != nil }
    var target: Int { options.length.target }

    /// Records a finished rack. Returns true when the match is over too.
    mutating func finishRack() -> Bool {
        guard let w = table.winner else { return false }
        wins[w] += 1
        for i in totals.indices {
            let s = table.stats[i]
            totals[i].potted += s.potted
            totals[i].fouls += s.fouls
            totals[i].shots += s.shots
            totals[i].breakAndRuns += s.breakAndRuns
            totals[i].bestRun = max(totals[i].bestRun, s.bestRun)
        }
        if wins[w] >= target { winner = w }
        return winner != nil
    }

    mutating func nextRack() {
        let w = table.winner ?? 0
        let breaker: Int
        if options.winnerBreaks {
            // The winning side's last shooter breaks.
            let t = table
            breaker = t.unit(t.turn) == w ? t.turn : ((0..<seats).first { t.unit($0) == w } ?? 0)
        } else {
            breaker = (table.breaker + 1) % seats
        }
        rack += 1
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        table = PoolTableState.create(game, options, seats, breaker, seed)
    }

    private enum CodingKeys: String, CodingKey { case options, game, seats, teams, table, rack, wins, winner, totals, seed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        options = try c.poolValue(.options, PoolOptions())
        game = c.poolEnum(.game, .EIGHT)
        seats = try c.poolValue(.seats, 2)
        teams = try c.poolValue(.teams, false)
        table = try c.poolValue(.table, PoolTableState())
        rack = try c.poolValue(.rack, 1)
        wins = try c.poolValue(.wins, [0, 0])
        winner = try c.decodeIfPresent(Int.self, forKey: .winner)
        totals = try c.poolValue(.totals, [PoolSeatStats(), PoolSeatStats()])
        seed = try c.poolValue(.seed, 1)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(options, forKey: .options)
        try c.encode(game, forKey: .game)
        try c.encode(seats, forKey: .seats)
        try c.encode(teams, forKey: .teams)
        try c.encode(table, forKey: .table)
        try c.encode(rack, forKey: .rack)
        try c.encode(wins, forKey: .wins)
        try c.encode(winner, forKey: .winner)
        try c.encode(totals, forKey: .totals)
        try c.encode(seed, forKey: .seed)
    }
}
