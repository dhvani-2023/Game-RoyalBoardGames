import Foundation
import GameKit

/// Computer opponent. The reference app has no chess bot (it is pass-and-play only), so this is new:
/// a small negamax alpha-beta search over `ChessPosition` with material + piece-square evaluation,
/// capture-first move ordering and a short capture-only quiescence search.
///
/// Strength comes from `depthFor` (Easy 1, Normal 2, Hard 3) plus a little randomness on lower levels
/// so games don't repeat. Pure Swift on value types: runs on a background task and unit-tests on macOS.
/// Bit-exact with the Kotlin bot for the same `KotlinRandom` seed. A cancelled task stops searching early.
enum ChessBot {
    private static let MATE = 100_000

    /// Search depth (plies) and evaluation noise (centipawns) per level index (0 easy, 1 normal, 2 hard).
    static func depthFor(_ level: Int) -> Int {
        switch level {
        case 0: 1
        case 1: 2
        default: 3
        }
    }

    private static func noiseFor(_ level: Int) -> Int {
        switch level {
        case 0: 90
        case 1: 25
        default: 6
        }
    }

    private static func quiescenceFor(_ level: Int) -> Int {
        switch level {
        case 0: 0
        case 1: 2
        default: 4
        }
    }

    /// Kotlin `Random.Default`: a fresh, randomly seeded generator.
    static func defaultRandom() -> KotlinRandom { KotlinRandom(Int64.random(in: Int64.min...Int64.max)) }

    static func bestMove(_ position: ChessPosition, _ level: Int, _ random: KotlinRandom = ChessBot.defaultRandom()) -> ChessMove? {
        let moves = ordered(position.legalMoves())
        if moves.isEmpty { return nil }
        let depth = depthFor(level)
        let noise = noiseFor(level)
        let qDepth = quiescenceFor(level)
        var best: ChessMove? = nil
        var bestNoisy = 0
        let beta = MATE * 2
        for move in moves {
            // A move can only win if its noisy score beats the best one, so search with a window that
            // is just wide enough for that; anything at or below it is a bound, not a real score.
            let windowAlpha = best == nil ? -MATE * 2 : bestNoisy - 2 * noise - 1
            let raw = -search(position.applying(move), depth - 1, -beta, -windowAlpha, 1, qDepth)
            let noisy = raw + (noise > 0 ? random.nextInt(-noise, noise + 1) : 0)
            if raw > windowAlpha && (best == nil || noisy > bestNoisy) {
                bestNoisy = noisy
                best = move
            }
        }
        return best
    }

    /// Static evaluation from `color`'s point of view, in centipawns (used to decide on draw offers).
    static func evaluate(_ position: ChessPosition, _ color: ChessColor) -> Int {
        let white = evaluateWhite(position)
        return color == .WHITE ? white : -white
    }

    private static func search(_ position: ChessPosition, _ depth: Int, _ alphaIn: Int, _ beta: Int, _ ply: Int, _ qDepth: Int) -> Int {
        if Task.isCancelled { return 0 }
        let moves = position.legalMoves()
        if moves.isEmpty {
            return position.isInCheck(position.sideToMove) ? -MATE + ply : 0
        }
        if position.halfmoveClock >= 100 || position.hasInsufficientMaterial { return 0 }
        if depth <= 0 { return quiescence(position, alphaIn, beta, qDepth) }
        var alpha = alphaIn
        for move in ordered(moves) {
            let score = -search(position.applying(move), depth - 1, -beta, -alpha, ply + 1, qDepth)
            if score >= beta { return score }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    private static func quiescence(_ position: ChessPosition, _ alphaIn: Int, _ beta: Int, _ depth: Int) -> Int {
        let stand = evaluate(position, position.sideToMove)
        if depth <= 0 { return stand }
        if stand >= beta { return stand }
        var alpha = max(alphaIn, stand)
        let captures = ordered(position.legalMoves().filter { $0.isCapture || $0.promotion != nil })
        for move in captures {
            let score = -quiescence(position.applying(move), -beta, -alpha, depth - 1)
            if score >= beta { return score }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    /// Captures first (most valuable victim first), then promotions, then the rest (stable, like `sortedByDescending`).
    private static func ordered(_ moves: [ChessMove]) -> [ChessMove] {
        moves.chessStableSorted(descendingBy: { m in
            var s = 0
            if let captured = m.captured { s += 1000 + PIECE[captured.ordinal] }
            if let promotion = m.promotion { s += PIECE[promotion.ordinal] }
            if m.castle != nil { s += 50 }
            return s
        })
    }

    // MARK: Evaluation

    private static let PIECE: [Int] = [100, 320, 330, 500, 900, 0]

    // Piece-square tables from White's side, a1 = index 0 (rank 1 first).
    private static let PAWN_T: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, -20, -20, 10, 10, 5,
        5, -5, -10, 0, 0, -10, -5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, 5, 10, 25, 25, 10, 5, 5,
        10, 10, 20, 30, 30, 20, 10, 10,
        50, 50, 50, 50, 50, 50, 50, 50,
        0, 0, 0, 0, 0, 0, 0, 0,
    ]
    private static let KNIGHT_T: [Int] = [
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50,
    ]
    private static let BISHOP_T: [Int] = [
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -20, -10, -10, -10, -10, -10, -10, -20,
    ]
    private static let ROOK_T: [Int] = [
        0, 0, 0, 5, 5, 0, 0, 0,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        5, 10, 10, 10, 10, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0,
    ]
    private static let QUEEN_T: [Int] = [
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -10, 5, 5, 5, 5, 5, 0, -10,
        0, 0, 5, 5, 5, 5, 0, -5,
        -5, 0, 5, 5, 5, 5, 0, -5,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20,
    ]
    private static let KING_T: [Int] = [
        20, 30, 10, 0, 0, 10, 30, 20,
        20, 20, 0, 0, 0, 0, 20, 20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
    ]
    private static let KING_END_T: [Int] = [
        -50, -30, -30, -30, -30, -30, -30, -50,
        -30, -30, 0, 0, 0, 0, -30, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -20, -10, 0, 0, -10, -20, -30,
        -50, -40, -30, -20, -20, -30, -40, -50,
    ]

    private static func evaluateWhite(_ position: ChessPosition) -> Int {
        let board = position.board
        var score = 0
        var heavy = 0
        for case let p? in board where p.kind == .QUEEN || p.kind == .ROOK { heavy += 1 }
        let endgame = heavy <= 2
        for sq in 0..<64 {
            guard let p = board[sq] else { continue }
            // Mirror the square for Black so tables read from each side's own back rank.
            let idx = p.color == .WHITE ? sq : (7 - ChessSquare.rank(sq)) * 8 + ChessSquare.file(sq)
            let tableValue: Int
            switch p.kind {
            case .PAWN: tableValue = PAWN_T[idx]
            case .KNIGHT: tableValue = KNIGHT_T[idx]
            case .BISHOP: tableValue = BISHOP_T[idx]
            case .ROOK: tableValue = ROOK_T[idx]
            case .QUEEN: tableValue = QUEEN_T[idx]
            case .KING: tableValue = endgame ? KING_END_T[idx] : KING_T[idx]
            }
            let v = PIECE[p.kind.ordinal] + tableValue
            score += p.color == .WHITE ? v : -v
        }
        return score
    }
}
