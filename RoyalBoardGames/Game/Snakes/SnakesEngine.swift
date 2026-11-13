import Foundation

struct SnakesRules: Codable, Hashable {
    var requireSixToStart: Bool = false
    var exactRollToFinish: Bool = true
    var extraTurnOnSix: Bool = true

    init(requireSixToStart: Bool = false, exactRollToFinish: Bool = true, extraTurnOnSix: Bool = true) {
        self.requireSixToStart = requireSixToStart
        self.exactRollToFinish = exactRollToFinish
        self.extraTurnOnSix = extraTurnOnSix
    }

    /// Kotlin `copy(...)`.
    func copy(requireSixToStart: Bool? = nil, exactRollToFinish: Bool? = nil, extraTurnOnSix: Bool? = nil) -> SnakesRules {
        SnakesRules(
            requireSixToStart: requireSixToStart ?? self.requireSixToStart,
            exactRollToFinish: exactRollToFinish ?? self.exactRollToFinish,
            extraTurnOnSix: extraTurnOnSix ?? self.extraTurnOnSix
        )
    }

    private enum CodingKeys: String, CodingKey { case requireSixToStart, exactRollToFinish, extraTurnOnSix }

    /// Missing fields fall back to their defaults (kotlinx `ignoreUnknownKeys` + defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SnakesRules()
        requireSixToStart = (try? c.decodeIfPresent(Bool.self, forKey: .requireSixToStart)) ?? d.requireSixToStart
        exactRollToFinish = (try? c.decodeIfPresent(Bool.self, forKey: .exactRollToFinish)) ?? d.exactRollToFinish
        extraTurnOnSix = (try? c.decodeIfPresent(Bool.self, forKey: .extraTurnOnSix)) ?? d.extraTurnOnSix
    }
}

/// The 1–100 board shared by every theme.
enum SnakesBoard {
    static let SIZE = 10
    static let LAST_SQUARE = 100

    // Layout from docs/research/snakes/layout_anneal.py (seed 15): no snake or ladder crosses
    // another, no end square sits on another feature, and a solo game takes about 39 rolls,
    // the same pace as the classic printed board.

    /// Ladder bottom → top, in the Kotlin map's insertion order.
    static let ladderPairs: [(Int, Int)] = [(7, 47), (20, 39), (28, 49), (40, 60), (51, 90), (55, 75), (58, 78), (76, 97)]

    /// Snake head → tail, in the Kotlin map's insertion order.
    static let snakePairs: [(Int, Int)] = [(26, 5), (30, 9), (43, 3), (44, 24), (56, 35), (93, 69), (95, 68), (99, 80)]

    /// Ladder bottom → top (lookups only; iterate `ladderPairs` for Kotlin's order).
    static let ladders: [Int: Int] = Dictionary(uniqueKeysWithValues: ladderPairs)

    /// Snake head → tail (lookups only; iterate `snakePairs` for Kotlin's order).
    static let snakes: [Int: Int] = Dictionary(uniqueKeysWithValues: snakePairs)

    /// Display row (0 = top) and column for a square. Rows alternate direction so the path snakes.
    static func cell(_ square: Int) -> (first: Int, second: Int) {
        let index = max(1, min(LAST_SQUARE, square)) - 1
        let rowFromBottom = index / SIZE
        let offset = index % SIZE
        let col = rowFromBottom % 2 == 0 ? offset : SIZE - 1 - offset
        return (SIZE - 1 - rowFromBottom, col)
    }

    static func square(_ row: Int, _ col: Int) -> Int {
        let rowFromBottom = SIZE - 1 - row
        let offset = rowFromBottom % 2 == 0 ? col : SIZE - 1 - col
        return rowFromBottom * SIZE + offset + 1
    }

    static func destination(_ square: Int) -> Int { ladders[square] ?? snakes[square] ?? square }
}

/// Everything that happened on one dice roll, for animation and notifications.
struct SnakesMove: Equatable {
    let player: Int
    let roll: Int
    let from: Int
    /// Squares stepped on, in order, before any snake or ladder.
    let steps: [Int]
    let jump: Jump?
    let to: Int
    let outcome: Outcome
    /// Same player rolls again.
    let extraTurn: Bool
    /// Whose turn it is after this move.
    let nextPlayer: Int

    enum Jump: Equatable {
        case Ladder(from: Int, to: Int)
        case Snake(from: Int, to: Int)

        var from: Int {
            switch self {
            case let .Ladder(from, _), let .Snake(from, _): return from
            }
        }

        var to: Int {
            switch self {
            case let .Ladder(_, to), let .Snake(_, to): return to
            }
        }
    }

    enum Outcome: Equatable {
        case Moved
        /// "Six to start" rule: stayed off the board.
        case NeedSix
        /// Exact-finish rule: the roll would pass 100.
        case Overshoot(needed: Int)
        /// Third six in a row: turn forfeited without moving.
        case ThreeSixes
        case Finished(place: Int)
    }
}

/// Rules engine for 2–6 players, deterministic given the dice values.
/// (The reference names this struct `SnakesGame`; on Android that name belongs to the module object.)
final class SnakesMatch {
    let playerCount: Int
    let rules: SnakesRules

    /// 0 = not on the board yet.
    private(set) var positions: [Int]
    /// Player indices in finishing order.
    private(set) var finishOrder: [Int] = []
    private(set) var current = 0
    private(set) var sixStreak = 0
    private(set) var turnCount = 0

    init(_ playerCount: Int, _ rules: SnakesRules) {
        precondition((2...6).contains(playerCount), "Snakes & Ladders needs 2–6 players")
        self.playerCount = playerCount
        self.rules = rules
        positions = Array(repeating: 0, count: playerCount)
    }

    /// Starts from given positions (used by tests and save/resume).
    convenience init(
        _ playerCount: Int,
        _ rules: SnakesRules,
        _ positions: [Int],
        _ current: Int = 0,
        _ finishOrder: [Int] = [],
        _ sixStreak: Int = 0,
        _ turnCount: Int = 0
    ) {
        self.init(playerCount, rules)
        precondition(positions.count == playerCount && positions.allSatisfy { (0...SnakesBoard.LAST_SQUARE).contains($0) })
        self.positions = positions
        self.current = current
        self.finishOrder = finishOrder
        self.sixStreak = sixStreak
        self.turnCount = turnCount
    }

    func copy() -> SnakesMatch { SnakesMatch(playerCount, rules, positions, current, finishOrder, sixStreak, turnCount) }

    /// Ends when only one player is still on the board.
    var isOver: Bool { finishOrder.count >= playerCount - 1 }

    func hasFinished(_ player: Int) -> Bool { finishOrder.contains(player) }

    /// Finishers first, then everyone else by how far along they are.
    var standings: [Int] {
        let rest = (0..<playerCount).filter { !finishOrder.contains($0) }
            .sorted { a, b in positions[a] == positions[b] ? a < b : positions[a] > positions[b] }
        return finishOrder + rest
    }

    /// Applies a dice roll (1–6) for the current player.
    @discardableResult
    func roll(_ value: Int) -> SnakesMove {
        precondition((1...6).contains(value), "Dice show 1–6")
        precondition(!isOver, "Game is over")
        let player = current
        let from = positions[player]
        turnCount += 1
        sixStreak = value == 6 ? sixStreak + 1 : 0

        if rules.extraTurnOnSix && sixStreak == 3 {
            sixStreak = 0
            return finish(player, value, from, [], nil, from, .ThreeSixes, false)
        }

        if from == 0 && rules.requireSixToStart && value != 6 {
            return finish(player, value, from, [], nil, from, .NeedSix, false)
        }

        var target = from + value
        if target > SnakesBoard.LAST_SQUARE {
            if rules.exactRollToFinish {
                let extra = rules.extraTurnOnSix && value == 6
                return finish(player, value, from, [], nil, from, .Overshoot(needed: SnakesBoard.LAST_SQUARE - from), extra)
            }
            target = SnakesBoard.LAST_SQUARE
        }

        let steps = Array((from + 1)...target)
        var to = target
        var jump: SnakesMove.Jump? = nil
        let top = SnakesBoard.ladders[target]
        let tail = SnakesBoard.snakes[target]
        if let top {
            jump = .Ladder(from: target, to: top)
            to = top
        } else if let tail {
            jump = .Snake(from: target, to: tail)
            to = tail
        }
        positions[player] = to

        if to == SnakesBoard.LAST_SQUARE {
            finishOrder.append(player)
            sixStreak = 0
            if isOver {
                if let last = (0..<playerCount).first(where: { !finishOrder.contains($0) }) { finishOrder.append(last) }
            }
            return finish(player, value, from, steps, jump, to, .Finished(place: (finishOrder.firstIndex(of: player) ?? -1) + 1), false)
        }

        let extra = rules.extraTurnOnSix && value == 6
        return finish(player, value, from, steps, jump, to, .Moved, extra)
    }

    private func finish(
        _ player: Int, _ roll: Int, _ from: Int, _ steps: [Int], _ jump: SnakesMove.Jump?, _ to: Int,
        _ outcome: SnakesMove.Outcome, _ extraTurn: Bool
    ) -> SnakesMove {
        if !extraTurn {
            sixStreak = 0
            advanceTurn()
        }
        return SnakesMove(player: player, roll: roll, from: from, steps: steps, jump: jump, to: to, outcome: outcome,
                          extraTurn: extraTurn, nextPlayer: current)
    }

    private func advanceTurn() {
        if isOver { return }
        var next = current
        repeat {
            next = (next + 1) % playerCount
        } while finishOrder.contains(next)
        current = next
    }
}

/// A point in board cell units: x = column + 0.5, y = row + 0.5 (row 0 at the top).
struct BoardPoint: Equatable, Hashable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Board geometry in cell units.
enum SnakesGeometry {
    static let snakeHeads: [Int] = SnakesBoard.snakes.keys.sorted()
    static let ladderBottoms: [Int] = SnakesBoard.ladders.keys.sorted()

    static func center(_ square: Int) -> BoardPoint {
        let (row, col) = SnakesBoard.cell(square)
        return BoardPoint(Double(col) + 0.5, Double(row) + 0.5)
    }

    /// Waiting spot below the board for players who haven't entered yet.
    static func startPoint(_ slot: Int) -> BoardPoint { BoardPoint(0.45 + Double(slot) * 0.62, 10.55) }

    /// A point on a snake's wavy body, from the head (t = 0) to the tip of the tail (t = 1).
    /// Both ends sit exactly on their squares' centres, so a sliding token lands cleanly.
    static func snakePoint(_ head: Int, _ t: Double) -> BoardPoint {
        let tail = SnakesBoard.snakes[head] ?? head
        let a = center(head)
        let b = center(tail)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let index = max(snakeHeads.firstIndex(of: head) ?? -1, 0)
        // About one S-bend every 2.5 cells; neighbouring snakes bend opposite ways.
        let halfWaves = max(2.0, swiftRound(length / 1.25))
        let amplitude = min(0.42, 0.2 + length * 0.03) * (index % 2 == 0 ? 1.0 : -1.0)
        let offset = amplitude * sin(Double.pi * halfWaves * t) * (0.55 + 0.45 * sin(Double.pi * t))
        return BoardPoint(a.x + dx * t - dy / length * offset, a.y + dy * t + dx / length * offset)
    }

    /// Points along a snake, head first.
    static func snakeSpine(_ head: Int, _ samples: Int) -> [BoardPoint] {
        (0...samples).map { snakePoint(head, Double($0) / Double(samples)) }
    }

    /// Straight-line distance from head to tail, in cells.
    static func snakeLength(_ head: Int) -> Double {
        let a = center(head)
        let b = center(SnakesBoard.snakes[head] ?? head)
        return hypot(b.x - a.x, b.y - a.y)
    }

    /// Swift's `.rounded()` (half away from zero), written like the Kotlin helper.
    private static func swiftRound(_ v: Double) -> Double { v >= 0 ? (v + 0.5).rounded(.down) : -((-v + 0.5).rounded(.down)) }
}
