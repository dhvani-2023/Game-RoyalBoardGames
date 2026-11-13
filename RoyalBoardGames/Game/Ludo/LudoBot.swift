import Foundation

/// The computer player: scores every legal move and picks the best (docs/LUDO_SPEC.md §5).
/// Easy plays loosely, Normal uses the full scorer, Hard also weighs the real odds of each
/// opponent roll before moving. It only ever sees the current board, never future rolls.
enum LudoBot {
    static func choose(_ moves: [LudoMove], _ engine: LudoEngine, _ difficulty: LudoDifficulty, _ rng: LudoRandom) -> LudoMove? {
        guard let first = moves.first else { return nil }
        if moves.count == 1 { return first }
        if difficulty == .EASY && rng.nextDouble() < 0.45 {
            return moves.random(rng)
        }
        var best = first
        var bestScore = -Double.infinity
        for move in moves {
            let s = score(move, engine, difficulty) + rng.nextDouble() * 0.5
            if s > bestScore {
                best = move
                bestScore = s
            }
        }
        return best
    }

    static func score(_ move: LudoMove, _ engine: LudoEngine, _ difficulty: LudoDifficulty) -> Double {
        let g = engine.geometry
        let arm = engine.seatArms[move.seat]
        let hard = difficulty == .HARD
        var s = 0.0
        if move.to == g.homeStep { s += 60 }
        if move.comesOut { s += 45 }
        s += Double(move.captures.count) * 80
        let careful = difficulty != .EASY
        if let index = g.trackIndex(arm, move.to) {
            if engine.isSafe(index) {
                s += 18
            } else if careful {
                s -= threat(index, move.seat, engine, exact: hard) * (hard ? 1.0 : 14.0)
            }
        } else if move.to > g.lastTrackStep {
            s += 25
        }
        // Moving a token out of danger is worth something too.
        if careful && move.from >= 0 {
            if let fromIndex = g.trackIndex(arm, move.from), !engine.isSafe(fromIndex) {
                s += threat(fromIndex, move.seat, engine, exact: hard) * (hard ? 0.85 : 12.0)
            }
        }
        if hard {
            // Tokens far along are worth more to keep, and a long way round to lose.
            s += Double(move.to) * 0.35
            if move.captures.contains(where: { engine.steps[$0.seat][$0.token] > g.lastTrackStep / 2 }) { s += 25 }
        } else {
            s += Double(move.to) * 0.3
        }
        return s
    }

    /// Danger on a square: with `exact`, the chance an opponent can hit it next turn (scaled to
    /// the token's worth); otherwise the number of opponent tokens 1–6 squares behind.
    static func threat(_ index: Int, _ seat: Int, _ engine: LudoEngine, exact: Bool) -> Double {
        let g = engine.geometry
        var count = 0.0
        var chance = 0.0
        for other in 0..<engine.seatCount {
            if other == seat || engine.isFinished(other) { continue }
            for token in engine.steps[other].indices {
                guard let from = engine.trackIndex(other, token) else { continue }
                let distance = ((index - from) % g.trackLength + g.trackLength) % g.trackLength
                // The opponent's route must reach this square before turning home.
                let room = g.lastTrackStep - engine.steps[other][token]
                if distance < 1 || distance > room { continue }
                if distance <= 6 {
                    count += 1
                    chance += 1.0 / 6
                } else if distance <= 12 {
                    chance += 1.0 / 36
                }
            }
            // Yard tokens can come out and hit the square in front of their start.
            if engine.steps[other].contains(-1) {
                if let start = g.trackIndex(engine.seatArms[other], 0) {
                    let distance = ((index - start) % g.trackLength + g.trackLength) % g.trackLength
                    if (1...6).contains(distance) { chance += 1.0 / 36 }
                }
            }
        }
        return exact ? min(1.0, chance) * 95 : count
    }
}
