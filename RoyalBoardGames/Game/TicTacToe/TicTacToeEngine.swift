import Foundation
import GameKit

/// Stored as "x" / "o" (Kotlin `@SerialName`).
enum TTTMark: String, CaseIterable, Codable, Hashable, Sendable {
    case X = "x"
    case O = "o"

    var other: TTTMark { self == .X ? .O : .X }
    var label: String { self == .X ? "X" : "O" }
}

/// One 3×3 round. A value type like the reference struct; `copy()` is a plain value copy.
struct TicTacToeBoard: Hashable, Sendable {
    static let lines: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
        [0, 3, 6], [1, 4, 7], [2, 5, 8],
        [0, 4, 8], [2, 4, 6],
    ]

    struct Win: Hashable, Sendable {
        let mark: TTTMark
        let line: [Int]
    }

    private(set) var cells: [TTTMark?] = Array(repeating: nil, count: 9)
    private(set) var turn: TTTMark

    init(_ starting: TTTMark = .X) {
        turn = starting
    }

    /// Kotlin `copy()`.
    func copy() -> TicTacToeBoard { self }

    /// The winning mark and line, if any.
    var win: Win? {
        for line in Self.lines {
            guard let mark = cells[line[0]] else { continue }
            if cells[line[1]] == mark && cells[line[2]] == mark { return Win(mark: mark, line: line) }
        }
        return nil
    }

    var isDraw: Bool { win == nil && cells.allSatisfy { $0 != nil } }
    var isOver: Bool { win != nil || isDraw }
    var moveCount: Int { cells.reduce(0) { $0 + ($1 != nil ? 1 : 0) } }

    func canPlay(_ index: Int) -> Bool { index >= 0 && index < 9 && cells[index] == nil && !isOver }

    /// Places the current mark; returns false for occupied cells or a finished round.
    @discardableResult
    mutating func play(_ index: Int) -> Bool {
        if !canPlay(index) { return false }
        cells[index] = turn
        if !isOver { turn = turn.other }
        return true
    }
}

/// A single game or a best-of-N match. Starters alternate each round.
struct TicTacToeMatch: Hashable, Sendable {
    let bestOf: Int
    private(set) var board = TicTacToeBoard(.X)
    private(set) var xWins = 0
    private(set) var oWins = 0
    private(set) var draws = 0
    private(set) var round = 1
    private(set) var roundStarter: TTTMark = .X

    init(_ bestOf: Int) {
        self.bestOf = max(1, bestOf)
    }

    /// Kotlin `copy()`.
    func copy() -> TicTacToeMatch { self }

    var winsNeeded: Int { bestOf / 2 + 1 }

    var matchWinner: TTTMark? {
        if xWins >= winsNeeded { return .X }
        if oWins >= winsNeeded { return .O }
        return nil
    }

    var isMatchOver: Bool { matchWinner != nil }

    func wins(_ mark: TTTMark) -> Int { mark == .X ? xWins : oWins }

    /// Plays in the current round and scores the round when it ends.
    @discardableResult
    mutating func play(_ index: Int) -> Bool {
        if isMatchOver || !board.play(index) { return false }
        if let w = board.win {
            if w.mark == .X { xWins += 1 } else { oWins += 1 }
        } else if board.isDraw {
            draws += 1
        }
        return true
    }

    /// Starts the next round; the other player goes first.
    mutating func nextRound() {
        if !board.isOver || isMatchOver { return }
        round += 1
        roundStarter = roundStarter.other
        board = TicTacToeBoard(roundStarter)
    }

    /// Clears the current round without scoring it.
    mutating func restartRound() {
        if let w = board.win {
            if w.mark == .X { xWins -= 1 } else { oWins -= 1 }
        } else if board.isDraw {
            draws -= 1
        }
        board = TicTacToeBoard(roundStarter)
    }

    mutating func restartMatch() {
        board = TicTacToeBoard(.X)
        xWins = 0
        oWins = 0
        draws = 0
        round = 1
        roundStarter = .X
    }
}

/// The computer opponent. Hard plays perfectly (full minimax, quickest win, random among equals);
/// Normal always wins or blocks when it can but sometimes strays; Easy mostly plays at random.
/// Bit-exact with the Kotlin bot for the same `KotlinRandom` seed.
enum TicTacToeBot {
    /// Kotlin `Random.Default`: a fresh, randomly seeded generator.
    static func defaultRandom() -> KotlinRandom { KotlinRandom(Int64.random(in: Int64.min...Int64.max)) }

    static func choose(_ board: TicTacToeBoard, _ level: BotLevel, _ rng: KotlinRandom = TicTacToeBot.defaultRandom()) -> Int? {
        let empty = (0..<9).filter { board.canPlay($0) }
        if empty.isEmpty { return nil }
        let me = board.turn
        let winning = finishing(board, me)
        let blocking = finishing(board, me.other)
        switch level {
        case .EASY:
            if let winning, rng.nextDouble() < 0.5 { return winning }
            if let blocking, rng.nextDouble() < 0.35 { return blocking }
            return empty.kotlinRandom(rng)
        case .NORMAL:
            if let winning { return winning }
            if let blocking { return blocking }
            if rng.nextDouble() < 0.3 { return empty.kotlinRandom(rng) }
            return best(board, rng)
        case .HARD:
            return best(board, rng)
        }
    }

    /// A cell that completes a line for `mark`, if any.
    private static func finishing(_ board: TicTacToeBoard, _ mark: TTTMark) -> Int? {
        for line in TicTacToeBoard.lines {
            let marks = line.map { board.cells[$0] }
            if marks.filter({ $0 == mark }).count == 2, marks.filter({ $0 == nil }).count == 1, let i = marks.firstIndex(where: { $0 == nil }) {
                return line[i]
            }
        }
        return nil
    }

    /// A minimax-optimal cell, random among equally good ones.
    static func best(_ board: TicTacToeBoard, _ rng: KotlinRandom = TicTacToeBot.defaultRandom()) -> Int? {
        let me = board.turn
        var bestScore = Int.min
        var bestCells: [Int] = []
        for i in 0..<9 {
            if !board.canPlay(i) { continue }
            var next = board.copy()
            next.play(i)
            let s = minimax(next, me, 1)
            if s > bestScore {
                bestScore = s
                bestCells.removeAll()
                bestCells.append(i)
            } else if s == bestScore {
                bestCells.append(i)
            }
        }
        return bestCells.isEmpty ? nil : bestCells.kotlinRandom(rng)
    }

    // The search runs on bitmasks (same rules, same order as playing on `TicTacToeBoard` copies).
    private static let lineMasks: [Int] = TicTacToeBoard.lines.map { $0.reduce(0) { $0 | (1 << $1) } }

    private static func minimax(_ board: TicTacToeBoard, _ me: TTTMark, _ depth: Int) -> Int {
        var x = 0
        var o = 0
        for i in 0..<9 {
            switch board.cells[i] {
            case .X: x |= 1 << i
            case .O: o |= 1 << i
            case nil: break
            }
        }
        return minimax(x, o, board.turn, me == .X, depth)
    }

    /// Kotlin `minimax(board, me, depth)` with X/O cells as bitmasks.
    private static func minimax(_ x: Int, _ o: Int, _ turn: TTTMark, _ meIsX: Bool, _ depth: Int) -> Int {
        // board.win: the first complete line decides the mark.
        for m in lineMasks {
            if x & m == m { return meIsX ? 10 - depth : depth - 10 }
            if o & m == m { return meIsX ? depth - 10 : 10 - depth }
        }
        let filled = x | o
        if filled == 0x1FF { return 0 }
        let maximizing = (turn == .X) == meIsX
        var best = maximizing ? Int.min : Int.max
        for i in 0..<9 where filled & (1 << i) == 0 {
            let nx = turn == .X ? x | (1 << i) : x
            let no = turn == .O ? o | (1 << i) : o
            // play(): the turn passes only if the round isn't over; a finished child returns before reading it.
            let s = minimax(nx, no, turn.other, meIsX, depth + 1)
            best = maximizing ? max(best, s) : min(best, s)
        }
        return best
    }
}
