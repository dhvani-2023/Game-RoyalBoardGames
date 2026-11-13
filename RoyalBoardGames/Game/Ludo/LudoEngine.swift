import Foundation
import GameKit

struct LudoRules: Codable, Equatable, Hashable {
    /// Quick: two tokens each, starting on their start squares.
    var quick: Bool = false
    /// Play on for 2nd, 3rd… instead of stopping at the first winner.
    var allPlaces: Bool = false
    /// A 1 also brings a token out.
    var oneOrSix: Bool = false
    var captureBonus: Bool = true
    /// Two tokens of one colour on a square block other colours.
    var blockades: Bool = false
    var safeStars: Bool = true
    var autoMove: Bool = true
    var fastBots: Bool = false

    var tokens: Int { quick ? 2 : 4 }

    init(quick: Bool = false, allPlaces: Bool = false, oneOrSix: Bool = false, captureBonus: Bool = true,
         blockades: Bool = false, safeStars: Bool = true, autoMove: Bool = true, fastBots: Bool = false) {
        self.quick = quick
        self.allPlaces = allPlaces
        self.oneOrSix = oneOrSix
        self.captureBonus = captureBonus
        self.blockades = blockades
        self.safeStars = safeStars
        self.autoMove = autoMove
        self.fastBots = fastBots
    }

    private enum CodingKeys: String, CodingKey { case quick, allPlaces, oneOrSix, captureBonus, blockades, safeStars, autoMove, fastBots }

    /// Missing or invalid fields fall back to their defaults (kotlinx `coerceInputValues`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LudoRules()
        quick = (try? c.decodeIfPresent(Bool.self, forKey: .quick)) ?? d.quick
        allPlaces = (try? c.decodeIfPresent(Bool.self, forKey: .allPlaces)) ?? d.allPlaces
        oneOrSix = (try? c.decodeIfPresent(Bool.self, forKey: .oneOrSix)) ?? d.oneOrSix
        captureBonus = (try? c.decodeIfPresent(Bool.self, forKey: .captureBonus)) ?? d.captureBonus
        blockades = (try? c.decodeIfPresent(Bool.self, forKey: .blockades)) ?? d.blockades
        safeStars = (try? c.decodeIfPresent(Bool.self, forKey: .safeStars)) ?? d.safeStars
        autoMove = (try? c.decodeIfPresent(Bool.self, forKey: .autoMove)) ?? d.autoMove
        fastBots = (try? c.decodeIfPresent(Bool.self, forKey: .fastBots)) ?? d.fastBots
    }
}

enum LudoDifficulty: String, Codable, CaseIterable, Hashable {
    case EASY = "easy"
    case NORMAL = "normal"
    case HARD = "hard"

    /// `name.lowercase().replaceFirstChar { it.uppercase() }`
    var title: String {
        switch self {
        case .EASY: return "Easy"
        case .NORMAL: return "Normal"
        case .HARD: return "Hard"
        }
    }

    /// Kotlin `entries`.
    static var entries: [LudoDifficulty] { allCases }
}

/// One seat at the table.
struct LudoSeat: Codable, Equatable {
    var player: PartyPlayer
    /// The board arm this seat plays from (it sets the colour).
    var arm: Int
    var isBot: Bool
    var difficulty: LudoDifficulty = .NORMAL

    var id: String { player.id }

    init(_ player: PartyPlayer, _ arm: Int, isBot: Bool, difficulty: LudoDifficulty = .NORMAL) {
        self.player = player
        self.arm = arm
        self.isBot = isBot
        self.difficulty = difficulty
    }

    private enum CodingKeys: String, CodingKey { case player, arm, isBot, difficulty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        player = try c.decode(PartyPlayer.self, forKey: .player)
        arm = try c.decode(Int.self, forKey: .arm)
        isBot = try c.decode(Bool.self, forKey: .isBot)
        difficulty = (try? c.decodeIfPresent(LudoDifficulty.self, forKey: .difficulty)) ?? .NORMAL
    }

    static func == (a: LudoSeat, b: LudoSeat) -> Bool {
        a.player.id == b.player.id && a.player.name == b.player.name && a.player.avatar == b.player.avatar
            && a.player.colorIndex == b.player.colorIndex && a.arm == b.arm && a.isBot == b.isBot && a.difficulty == b.difficulty
    }
}

struct LudoSeatStats: Codable, Equatable {
    var rolls: Int = 0
    var sixes: Int = 0
    var captures: Int = 0
    var captured: Int = 0
    /// Last few rolls, newest last.
    var recent: [Int] = []

    init(rolls: Int = 0, sixes: Int = 0, captures: Int = 0, captured: Int = 0, recent: [Int] = []) {
        self.rolls = rolls
        self.sixes = sixes
        self.captures = captures
        self.captured = captured
        self.recent = recent
    }

    private enum CodingKeys: String, CodingKey { case rolls, sixes, captures, captured, recent }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rolls = (try? c.decodeIfPresent(Int.self, forKey: .rolls)) ?? 0
        sixes = (try? c.decodeIfPresent(Int.self, forKey: .sixes)) ?? 0
        captures = (try? c.decodeIfPresent(Int.self, forKey: .captures)) ?? 0
        captured = (try? c.decodeIfPresent(Int.self, forKey: .captured)) ?? 0
        recent = (try? c.decodeIfPresent([Int].self, forKey: .recent)) ?? []
    }
}

struct LudoTokenRef: Codable, Equatable, Hashable {
    let seat: Int
    let token: Int

    init(_ seat: Int, _ token: Int) {
        self.seat = seat
        self.token = token
    }
}

/// A token move, already checked against the rules.
struct LudoMove: Equatable {
    let seat: Int
    let token: Int
    let from: Int
    let to: Int
    /// Opponent tokens this move sends home, as (seat, token).
    let captures: [LudoTokenRef]

    var comesOut: Bool { from < 0 }
}

/// The whole game: pure and deterministic, serializable so matches can be saved and tested.
/// Steps: −1 = in the yard, 0 = start square … `geometry.homeStep` = home.
///
/// A struct, so every copy is a true value copy (Kotlin replaces its immutable lists on each change
/// to get the same effect from `copy()`).
struct LudoEngine: Codable, Equatable {
    let arms: Int
    let seatArms: [Int]
    let rules: LudoRules
    var steps: [[Int]]
    var current: Int = 0
    var sixes: Int = 0
    var pendingRoll: Int? = nil
    /// Seats in finishing order.
    var ranks: [Int] = []
    var stats: [LudoSeatStats]
    var isOver: Bool = false
    var turnCount: Int = 0

    /// The primary constructor (what deserialization uses).
    init(arms: Int, seatArms: [Int], rules: LudoRules, steps: [[Int]], current: Int = 0, sixes: Int = 0,
         pendingRoll: Int? = nil, ranks: [Int] = [], stats: [LudoSeatStats], isOver: Bool = false, turnCount: Int = 0) {
        self.arms = arms
        self.seatArms = seatArms
        self.rules = rules
        self.steps = steps
        self.current = current
        self.sixes = sixes
        self.pendingRoll = pendingRoll
        self.ranks = ranks
        self.stats = stats
        self.isOver = isOver
        self.turnCount = turnCount
        geo = LudoGeometry(arms)
    }

    init(_ arms: Int, _ seatArms: [Int], _ rules: LudoRules) {
        self.init(
            arms: arms == 6 ? 6 : 4,
            seatArms: seatArms,
            rules: rules,
            steps: Array(repeating: Array(repeating: rules.quick ? 0 : -1, count: rules.tokens), count: seatArms.count),
            stats: Array(repeating: LudoSeatStats(), count: seatArms.count)
        )
    }

    enum RollOutcome: Equatable {
        /// Pick one of these moves.
        case Moves(_ moves: [LudoMove])
        /// Nothing can move; `again` when the seat rolls once more (it rolled a 6).
        case NoMoves(again: Bool)
        /// The third 6 in a row: the turn is lost.
        case ThreeSixes

        var moves: [LudoMove]? {
            if case .Moves(let m) = self { return m }
            return nil
        }
    }

    struct MoveResult: Equatable {
        let captured: [LudoTokenRef]
        let reachedHome: Bool
        let seatFinished: Bool
        /// The same seat rolls again.
        let extraRoll: Bool
        let gameOver: Bool
    }

    private let geo: LudoGeometry
    var geometry: LudoGeometry { geo }
    var seatCount: Int { seatArms.count }

    /// Kotlin `copy()`: a struct copy is already independent.
    func copy() -> LudoEngine { self }

    // MARK: Codable (same field names as kotlinx.serialization; the geometry is transient)

    private enum CodingKeys: String, CodingKey { case arms, seatArms, rules, steps, current, sixes, pendingRoll, ranks, stats, isOver, turnCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let arms = try c.decode(Int.self, forKey: .arms)
        self.init(
            arms: arms,
            seatArms: try c.decode([Int].self, forKey: .seatArms),
            rules: try c.decode(LudoRules.self, forKey: .rules),
            steps: try c.decode([[Int]].self, forKey: .steps),
            current: (try? c.decodeIfPresent(Int.self, forKey: .current)) ?? 0,
            sixes: (try? c.decodeIfPresent(Int.self, forKey: .sixes)) ?? 0,
            pendingRoll: (try? c.decodeIfPresent(Int.self, forKey: .pendingRoll)) ?? nil,
            ranks: (try? c.decodeIfPresent([Int].self, forKey: .ranks)) ?? [],
            stats: try c.decode([LudoSeatStats].self, forKey: .stats),
            isOver: (try? c.decodeIfPresent(Bool.self, forKey: .isOver)) ?? false,
            turnCount: (try? c.decodeIfPresent(Int.self, forKey: .turnCount)) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(arms, forKey: .arms)
        try c.encode(seatArms, forKey: .seatArms)
        try c.encode(rules, forKey: .rules)
        try c.encode(steps, forKey: .steps)
        try c.encode(current, forKey: .current)
        try c.encode(sixes, forKey: .sixes)
        // kotlinx encodeDefaults writes the null too.
        if let pendingRoll { try c.encode(pendingRoll, forKey: .pendingRoll) } else { try c.encodeNil(forKey: .pendingRoll) }
        try c.encode(ranks, forKey: .ranks)
        try c.encode(stats, forKey: .stats)
        try c.encode(isOver, forKey: .isOver)
        try c.encode(turnCount, forKey: .turnCount)
    }

    static func == (a: LudoEngine, b: LudoEngine) -> Bool {
        a.arms == b.arms && a.seatArms == b.seatArms && a.rules == b.rules && a.steps == b.steps && a.current == b.current
            && a.sixes == b.sixes && a.pendingRoll == b.pendingRoll && a.ranks == b.ranks && a.stats == b.stats
            && a.isOver == b.isOver && a.turnCount == b.turnCount
    }

    // MARK: Queries

    func isFinished(_ seat: Int) -> Bool { steps[seat].allSatisfy { $0 == geometry.homeStep } }

    func tokensHome(_ seat: Int) -> Int { steps[seat].filter { $0 == geometry.homeStep }.count }

    /// Total steps travelled, for ordering seats that didn't finish.
    func progress(_ seat: Int) -> Int { steps[seat].reduce(0) { $0 + max($1, 0) } }

    /// Seats from first to last: finishers in order, then the rest by progress (a stable sort, like Kotlin's).
    var standings: [Int] {
        let rest = steps.indices.filter { !ranks.contains($0) }
        let sorted = rest.enumerated()
            .map { (offset: $0.offset, seat: $0.element, progress: progress($0.element)) }
            .sorted { $0.progress != $1.progress ? $0.progress > $1.progress : $0.offset < $1.offset }
            .map { $0.seat }
        return ranks + sorted
    }

    /// Track square of a token, or nil when it's in the yard, home lane or home.
    func trackIndex(_ seat: Int, _ token: Int) -> Int? { geometry.trackIndex(seatArms[seat], steps[seat][token]) }

    func isSafe(_ index: Int) -> Bool { geometry.isStart(index) || (rules.safeStars && geometry.isStar(index)) }

    /// Tokens of every seat on track square `index`.
    func tokens(onTrack: Int) -> [LudoTokenRef] {
        var out: [LudoTokenRef] = []
        for seat in steps.indices {
            for token in steps[seat].indices where trackIndex(seat, token) == onTrack {
                out.append(LudoTokenRef(seat, token))
            }
        }
        return out
    }

    /// A square another seat may not land on or pass.
    private func isBlockade(_ index: Int, against: Int) -> Bool {
        if !rules.blockades { return false }
        var counts: [Int: Int] = [:]
        for ref in tokens(onTrack: index) where ref.seat != against { counts[ref.seat, default: 0] += 1 }
        return counts.values.contains { $0 >= 2 }
    }

    /// Every legal move for the current seat with `roll`.
    func legalMoves(_ roll: Int) -> [LudoMove] {
        let seat = current
        let arm = seatArms[seat]
        let home = geometry.homeStep
        var moves: [LudoMove] = []
        var seenYard = false
        for token in steps[seat].indices {
            let from = steps[seat][token]
            let to: Int
            if from < 0 {
                if !(roll == 6 || (rules.oneOrSix && roll == 1)) || seenYard { continue }
                // One "come out" move is enough; yard tokens are interchangeable.
                seenYard = true
                to = 0
            } else {
                if from >= home || from + roll > home { continue }
                to = from + roll
            }
            // Blockades can't be passed or landed on.
            if rules.blockades && from >= 0 {
                var blocked = false
                if from + 1 <= to {
                    for step in (from + 1)...to {
                        if let index = geometry.trackIndex(arm, step), isBlockade(index, against: seat) { blocked = true; break }
                    }
                }
                if blocked { continue }
            } else if rules.blockades {
                if let index = geometry.trackIndex(arm, 0), isBlockade(index, against: seat) { continue }
            }
            var captures: [LudoTokenRef] = []
            if let index = geometry.trackIndex(arm, to), !isSafe(index) {
                captures = tokens(onTrack: index).filter { $0.seat != seat }
            }
            moves.append(LudoMove(seat: seat, token: token, from: from, to: to, captures: captures))
        }
        return moves
    }

    // MARK: Turn flow

    private mutating func updateStats(_ seat: Int, _ transform: (inout LudoSeatStats) -> Void) {
        transform(&stats[seat])
    }

    private mutating func setStep(_ seat: Int, _ token: Int, _ value: Int) {
        steps[seat][token] = value
    }

    /// Records a roll for the current seat and says what can happen next.
    @discardableResult
    mutating func roll(_ value: Int) -> RollOutcome {
        precondition(!isOver && pendingRoll == nil, "roll when a move is pending")
        updateStats(current) { s in
            s.rolls += 1
            s.recent = Array((s.recent + [value]).suffix(5))
        }
        if value == 6 {
            updateStats(current) { $0.sixes += 1 }
            sixes += 1
            if sixes == 3 {
                passTurn()
                return .ThreeSixes
            }
        } else {
            sixes = 0
        }
        let moves = legalMoves(value)
        if moves.isEmpty {
            if value == 6 { return .NoMoves(again: true) }
            passTurn()
            return .NoMoves(again: false)
        }
        pendingRoll = value
        return .Moves(moves)
    }

    /// Plays a move returned by the last roll.
    @discardableResult
    mutating func apply(_ move: LudoMove) -> MoveResult {
        precondition(move.seat == current && pendingRoll != nil, "apply without a matching roll")
        let roll = pendingRoll ?? 0
        pendingRoll = nil
        setStep(move.seat, move.token, move.to)
        for ref in move.captures {
            setStep(ref.seat, ref.token, rules.quick ? 0 : -1)
            updateStats(ref.seat) { $0.captured += 1 }
        }
        updateStats(move.seat) { $0.captures += move.captures.count }
        let reachedHome = move.to == geometry.homeStep
        let finished = reachedHome && isFinished(move.seat)
        if finished { ranks = ranks + [move.seat] }
        let playing = steps.indices.filter { !isFinished($0) }
        let over = finished && (!rules.allPlaces || playing.count <= 1)
        if over {
            // Playing for every place, the last seat left takes last place.
            if rules.allPlaces { ranks = ranks + playing }
            isOver = true
            return MoveResult(captured: move.captures, reachedHome: true, seatFinished: true, extraRoll: false, gameOver: true)
        }
        let extra = !finished && (roll == 6 || reachedHome || (rules.captureBonus && !move.captures.isEmpty))
        if extra {
            if roll != 6 { sixes = 0 }
        } else {
            passTurn()
        }
        return MoveResult(captured: move.captures, reachedHome: reachedHome, seatFinished: finished, extraRoll: extra, gameOver: false)
    }

    private mutating func passTurn() {
        sixes = 0
        pendingRoll = nil
        turnCount += 1
        if isOver { return }
        var next = current
        for _ in 0..<seatCount {
            next = (next + 1) % seatCount
            if !isFinished(next) { break }
        }
        current = next
    }
}

// MARK: - Random numbers

/// Kotlin's abstract `kotlin.random.Random`: every helper derives from `nextBits`, so a subclass that
/// only overrides `nextBits` (like `SeededDice`) gets the exact Kotlin `nextInt(until)` / `nextDouble()`.
protocol LudoRandom: AnyObject {
    func nextBits(_ bitCount: Int) -> Int32
}

extension LudoRandom {
    /// `Random.nextInt()` = `nextBits(32)`.
    func nextInt32() -> Int32 { nextBits(32) }

    /// `Random.nextInt(until)`.
    func nextInt(_ until: Int) -> Int { nextInt(0, until) }

    /// `Random.nextInt(from, until)` (the default implementation in kotlin.random.Random).
    func nextInt(_ from: Int, _ until: Int) -> Int {
        precondition(until > from, "Random range is empty: [\(from), \(until)).")
        let f = Int32(truncatingIfNeeded: from)
        let u = Int32(truncatingIfNeeded: until)
        let n = u &- f
        if n > 0 || n == Int32.min {
            let rnd: Int32
            if n & (0 &- n) == n {
                let bitCount = 31 - n.leadingZeroBitCount
                rnd = nextBits(bitCount)
            } else {
                var v: Int32
                var bits: Int32
                repeat {
                    bits = Int32(bitPattern: UInt32(bitPattern: nextInt32()) >> 1)
                    v = bits % n
                } while bits &- v &+ (n &- 1) < 0
                rnd = v
            }
            return Int(f &+ rnd)
        } else {
            while true {
                let rnd = nextInt32()
                if rnd >= f && rnd < u { return Int(rnd) }
            }
        }
    }

    /// `Random.nextDouble()` = `doubleFromParts(nextBits(26), nextBits(27))`.
    func nextDouble() -> Double {
        let hi26 = Int64(nextBits(26))
        let low27 = Int64(nextBits(27))
        return Double((hi26 << 27) &+ low27) / Double(Int64(1) << 53)
    }
}

extension Array {
    /// Kotlin `Collection.random(random)`.
    func random(_ rng: LudoRandom) -> Element {
        precondition(!isEmpty, "Collection is empty.")
        return self[rng.nextInt(count)]
    }
}

/// `Random.Default` for the computer players: unseeded system randomness.
final class LudoSystemRandom: LudoRandom {
    private var generator = SystemRandomNumberGenerator()

    func nextBits(_ bitCount: Int) -> Int32 {
        if bitCount == 0 { return 0 }
        let raw = generator.next() as UInt64
        return Int32(truncatingIfNeeded: Int64(bitPattern: raw >> UInt64(64 - bitCount)))
    }
}

/// Dice: secure random rolls in play, a seeded sequence in tests.
protocol LudoDice {
    func roll() -> Int
}

final class FairDice: LudoDice {
    private var generator = SystemRandomNumberGenerator()

    func roll() -> Int { Int.random(in: 0..<6, using: &generator) + 1 }
}

/// SplitMix64, for repeatable test games (bit-exact with the Kotlin `SeededDice`).
final class SeededDice: LudoRandom, LudoDice {
    private var mix: SplitMix64

    init(_ seed: Int64) {
        // Kotlin: state = seed + golden; every next() adds golden again before mixing.
        mix = SplitMix64(seed: UInt64(bitPattern: seed) &+ 0x9E37_79B9_7F4A_7C15)
    }

    func next() -> Int64 { mix.nextLong() }

    func nextBits(_ bitCount: Int) -> Int32 {
        if bitCount == 0 { return 0 }
        return Int32(truncatingIfNeeded: Int64(bitPattern: UInt64(bitPattern: next()) >> UInt64(64 - bitCount)))
    }

    func roll() -> Int { Int(UInt64(bitPattern: next()) % 6) + 1 }
}
