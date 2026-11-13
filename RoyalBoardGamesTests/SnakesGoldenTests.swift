import XCTest
import GameKit
@testable import RoyalBoardGames

/// Golden values dumped from the JVM by Golden/source/SnakesGoldenDump.kt: SeededRandom streams, board and snake
/// geometry, 120 complete matches driven by java.util.Random dice (every roll, the standings after each roll),
/// the ten themes and the Compose colour mixes the board art uses. Integer and RNG results must match 100%;
/// snake curves (libm sin) to 1e-12 cells; Oklab mixes to ±1 per 8-bit channel.
final class SnakesGoldenTests: XCTestCase {
    // MARK: Golden file

    struct Golden: Decodable {
        struct Seeded: Decodable {
            let seed: Int64
            let values: [Int64]
        }

        struct Body: Decodable {
            let head: Int
            let length: Int64
            let samples: Int
            let spine: [[Int64]]
            let ride: [[Int64]]
        }

        struct Geometry: Decodable {
            let cells: [[Int]]
            let clamped: [[Int]]
            let destinations: [Int]
            let ladders: [[Int]]
            let snakes: [[Int]]
            let heads: [Int]
            let bottoms: [Int]
            let centers: [[Int64]]
            let starts: [[Int64]]
            let bodies: [Body]
        }

        struct Trace: Decodable {
            let players: Int
            let rules: [Bool]
            let seed: Int64
            let count: Int
            let hash: String
            let moves: [String]?
            let positions: [Int]
            let finishOrder: [Int]
            let standings: [Int]
            let current: Int
            let sixStreak: Int
            let turnCount: Int
            let isOver: Bool
        }

        struct Theme: Decodable {
            let id: Int
            let name: String
            let emoji: String
            let tagline: String
            let background: [UInt32]
            let frame: UInt32
            let cellA: UInt32
            let cellB: UInt32
            let numberColor: UInt32
            let numberColorB: UInt32
            let isDark: Bool
            let snakeColors: [[UInt32]]
            let snakePattern: String
            let rails: [UInt32]
            let rung: UInt32
            let stripe: UInt32?
            let glow: UInt32?
            let knots: Bool
            let accent: UInt32
            let backdrop: String
        }

        let seeded: [Seeded]
        let geometry: Geometry
        let traces: [Trace]
        let themes: [Theme]
        /// [base argb, other argb, fraction float bits, Compose result argb].
        let mixes: [[Int64]]
    }

    private static var cached: Golden?

    private func golden() throws -> Golden {
        if let g = Self.cached { return g }
        let bundle = Bundle(for: SnakesGoldenTests.self)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/snakes_golden.json")
        let candidates = [
            bundle.url(forResource: "snakes_golden", withExtension: "json"),
            bundle.url(forResource: "snakes_golden", withExtension: "json", subdirectory: "Golden"),
            source,
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("snakes_golden.json not found")
        }
        let g = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        Self.cached = g
        return g
    }

    private func bits(_ d: Double) -> Int64 { Int64(bitPattern: d.bitPattern) }
    private func double(_ b: Int64) -> Double { Double(bitPattern: UInt64(bitPattern: b)) }

    private func argb(_ c: SnakesColor) -> UInt32 {
        func q(_ v: Double) -> UInt32 { UInt32(max(0, min(255, Int((v * 255 + 0.5).rounded(.down))))) }
        return (q(c.a) << 24) | (q(c.r) << 16) | (q(c.g) << 8) | q(c.b)
    }

    // MARK: Random

    func testSeededRandomMatchesTheJVM() throws {
        for s in try golden().seeded {
            let r = SeededRandom(s.seed)
            let mine = (0..<s.values.count).map { _ in bits(r.next()) }
            XCTAssertEqual(mine, s.values, "SeededRandom(\(s.seed))")
            XCTAssertEqual(SeededRandom.sequence(s.seed, s.values.count).map(bits), s.values, "sequence(\(s.seed))")
        }
    }

    // MARK: Geometry

    func testBoardGeometryMatchesTheJVM() throws {
        let g = try golden().geometry
        XCTAssertEqual(g.cells.count, 100)
        for square in 1...100 {
            let c = SnakesBoard.cell(square)
            XCTAssertEqual([c.first, c.second], g.cells[square - 1], "cell(\(square))")
            let p = SnakesGeometry.center(square)
            XCTAssertEqual([bits(p.x), bits(p.y)], g.centers[square - 1], "center(\(square))")
        }
        for row in g.clamped {
            let c = SnakesBoard.cell(row[0])
            XCTAssertEqual([c.first, c.second], [row[1], row[2]], "cell(\(row[0]))")
        }
        XCTAssertEqual((0...100).map { SnakesBoard.destination($0) }, g.destinations)
        XCTAssertEqual(SnakesBoard.ladderPairs.map { [$0.0, $0.1] }, g.ladders, "ladders in Kotlin map order")
        XCTAssertEqual(SnakesBoard.snakePairs.map { [$0.0, $0.1] }, g.snakes, "snakes in Kotlin map order")
        XCTAssertEqual(SnakesGeometry.snakeHeads, g.heads)
        XCTAssertEqual(SnakesGeometry.ladderBottoms, g.bottoms)
        for slot in 0..<6 {
            let p = SnakesGeometry.startPoint(slot)
            XCTAssertEqual([bits(p.x), bits(p.y)], g.starts[slot], "startPoint(\(slot))")
        }
    }

    func testSnakeBodiesMatchTheJVM() throws {
        var exact = 0
        var total = 0
        for body in try golden().geometry.bodies {
            let length = SnakesGeometry.snakeLength(body.head)
            XCTAssertEqual(length, double(body.length), accuracy: 1e-12, "snakeLength(\(body.head))")
            let samples = max(60, Kt.toInt(length * 36))
            XCTAssertEqual(samples, body.samples, "samples(\(body.head))")
            let spine = SnakesGeometry.snakeSpine(body.head, body.samples)
            XCTAssertEqual(spine.count, body.spine.count)
            let ride = (1...32).map { SnakesGeometry.snakePoint(body.head, Double($0) / 32) }
            for (mine, theirs) in zip(spine + ride, body.spine + body.ride) {
                total += 1
                if bits(mine.x) == theirs[0] && bits(mine.y) == theirs[1] { exact += 1 }
                XCTAssertEqual(mine.x, double(theirs[0]), accuracy: 1e-12, "snake \(body.head) x")
                XCTAssertEqual(mine.y, double(theirs[1]), accuracy: 1e-12, "snake \(body.head) y")
            }
        }
        print("Snakes golden: \(exact)/\(total) snake-curve points bit-identical to the JVM (the rest differ only in libm sin)")
    }

    // MARK: Matches

    private func line(_ m: SnakesMove) -> String {
        let j: String
        switch m.jump {
        case let .Ladder(from, to)?: j = "L\(from)>\(to)"
        case let .Snake(from, to)?: j = "S\(from)>\(to)"
        case nil: j = "-"
        }
        let o: String
        switch m.outcome {
        case .Moved: o = "M"
        case .NeedSix: o = "N"
        case let .Overshoot(needed): o = "O\(needed)"
        case .ThreeSixes: o = "T"
        case let .Finished(place): o = "F\(place)"
        }
        return "\(m.player) \(m.roll) \(m.from) \(m.steps.map(String.init).joined(separator: ".")) \(j) \(m.to) \(o) \(m.extraTurn ? 1 : 0) \(m.nextPlayer)"
    }

    func testSeededMatchesReplayTheJVM() throws {
        let traces = try golden().traces
        XCTAssertEqual(traces.count, 120)
        for t in traces {
            let rules = SnakesRules(requireSixToStart: t.rules[0], exactRollToFinish: t.rules[1], extraTurnOnSix: t.rules[2])
            let rnd = JavaRandom(t.seed)
            let game = SnakesMatch(t.players, rules)
            var lines: [String] = []
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            while !game.isOver && lines.count < 5000 {
                let m = game.roll(rnd.nextInt(6) + 1)
                let l = line(m) + "|" + game.standings.map(String.init).joined(separator: ".") + "|"
                    + "\(game.current),\(game.sixStreak),\(game.turnCount)"
                lines.append(l)
                for b in (l + "\n").utf8 {
                    hash ^= UInt64(b)
                    hash = hash &* 0x0000_0100_0000_01b3
                }
            }
            let what = "players \(t.players) rules \(t.rules) seed \(t.seed)"
            if let moves = t.moves {
                for (i, (mine, theirs)) in zip(lines, moves).enumerated() where mine != theirs {
                    XCTFail("\(what): roll \(i) is \"\(mine)\", JVM \"\(theirs)\"")
                    break
                }
            }
            XCTAssertEqual(lines.count, t.count, what)
            XCTAssertEqual(String(hash, radix: 16), t.hash, what)
            XCTAssertEqual(game.positions, t.positions, what)
            XCTAssertEqual(game.finishOrder, t.finishOrder, what)
            XCTAssertEqual(game.standings, t.standings, what)
            XCTAssertEqual(game.current, t.current, what)
            XCTAssertEqual(game.sixStreak, t.sixStreak, what)
            XCTAssertEqual(game.turnCount, t.turnCount, what)
            XCTAssertEqual(game.isOver, t.isOver, what)
            // The copy keeps everything (save / resume path).
            let copy = game.copy()
            XCTAssertEqual(copy.positions, game.positions, what)
            XCTAssertEqual(copy.standings, game.standings, what)
        }
    }

    // MARK: Themes and colours

    func testThemesMatchTheJVM() throws {
        let themes = try golden().themes
        XCTAssertEqual(themes.count, SnakesTheme.all.count)
        for (mine, t) in zip(SnakesTheme.all, themes) {
            let what = "theme \(t.id)"
            XCTAssertEqual(mine.id, t.id, what)
            XCTAssertEqual(mine.name, t.name, what)
            XCTAssertEqual(mine.emoji, t.emoji, what)
            XCTAssertEqual(mine.tagline, t.tagline, what)
            XCTAssertEqual(mine.background.map(argb), t.background, what)
            XCTAssertEqual(argb(mine.frame), t.frame, what)
            XCTAssertEqual(argb(mine.cellA), t.cellA, what)
            XCTAssertEqual(argb(mine.cellB), t.cellB, what)
            XCTAssertEqual(argb(mine.numberColor), t.numberColor, what)
            XCTAssertEqual(argb(mine.numberColorB), t.numberColorB, what)
            XCTAssertEqual(mine.isDark, t.isDark, what)
            XCTAssertEqual(mine.snakeColors.map { $0.map(argb) }, t.snakeColors, what)
            XCTAssertEqual(mine.snakePattern.rawValue, t.snakePattern, what)
            XCTAssertEqual(mine.ladder.rails.map(argb), t.rails, what)
            XCTAssertEqual(argb(mine.ladder.rung), t.rung, what)
            XCTAssertEqual(mine.ladder.stripe.map(argb), t.stripe, what)
            XCTAssertEqual(mine.ladder.glow.map(argb), t.glow, what)
            XCTAssertEqual(mine.ladder.knots, t.knots, what)
            XCTAssertEqual(argb(mine.accent), t.accent, what)
            XCTAssertEqual(mine.backdrop.rawValue, t.backdrop, what)
        }
    }

    func testColourMixesMatchCompose() throws {
        let mixes = try golden().mixes
        XCTAssertFalse(mixes.isEmpty)
        var exact = 0
        for m in mixes {
            let base = SnakesColor(argb: UInt32(m[0]))
            let other = SnakesColor(argb: UInt32(m[1]))
            let by = Double(Float(bitPattern: UInt32(truncatingIfNeeded: m[2])))
            let mine = argb(base.mix(other, by))
            let theirs = UInt32(m[3])
            if mine == theirs { exact += 1 }
            for shift in stride(from: 0, through: 24, by: 8) {
                let a = Int((mine >> UInt32(shift)) & 0xFF)
                let b = Int((theirs >> UInt32(shift)) & 0xFF)
                XCTAssertLessThanOrEqual(abs(a - b), 1, String(format: "mix %08X + %08X by %.3f = %08X, Compose %08X", UInt32(m[0]), UInt32(m[1]), by, mine, theirs))
            }
        }
        print("Snakes golden: \(exact)/\(mixes.count) colour mixes identical to Compose (the rest within ±1 per channel)")
    }
}
