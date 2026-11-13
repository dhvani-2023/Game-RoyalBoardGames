import XCTest
import GameKit
@testable import RoyalBoardGames

/// Golden values dumped from the JVM by Golden/source/LudoGoldenDump.kt: SeededDice streams, board geometry,
/// bot threat values, 76 complete seeded bot games (every roll and move, bot scores bit for bit), the time
/// estimates and Compose colour mixes. Everything deterministic must match 100%.
final class LudoGoldenTests: XCTestCase {
    // MARK: Golden file

    struct Golden: Decodable {
        struct Dice: Decodable {
            let seed: Int64
            let next: [Int64]
            let rolls: [Int]
            let doubles: [Int64]
            let bounds: [Int]
            let ints: [Int]
            let picks: [Int]
        }

        struct Arm: Decodable {
            let direction: [Double]
            let lateral: [Double]
            let route: [[Double]]
            let trackIndex: [Int]
            let yard: [[Double]]
            let yardCenter: [Double]
            let yardSpots: [[Double]]
            let homeSpots: [[Double]]
            let triangle: [[Double]]
            let hexVertex: [Double]
            let cellCorners: [[[Double]]]
            let shift: Int
            let cell: Double
            let screenYard: [Double]
            let boardBack: [Double]
        }

        struct Geometry: Decodable {
            let arms: Int
            let trackLength: Int
            let lastTrackStep: Int
            let homeStep: Int
            let inner: Double
            let radius: Double
            let yardPlateRadius: Double
            let track: [[Double]]
            let cells: [[Int]]
            let centre: [[Double]]
            let perArm: [Arm]
        }

        struct DefaultArms: Decodable {
            let arms: Int
            let seats: Int
            let value: [Int]
        }

        struct Threats: Decodable {
            let steps: [[Int]]
            let count: [[Int64]]
            let exact: [[Int64]]
        }

        struct Rules: Decodable {
            let quick: Bool
            let allPlaces: Bool
            let oneOrSix: Bool
            let captureBonus: Bool
            let blockades: Bool
            let safeStars: Bool
        }

        struct Stats: Decodable, Equatable {
            let rolls: Int
            let sixes: Int
            let captures: Int
            let captured: Int
            let recent: [Int]

            init(rolls: Int, sixes: Int, captures: Int, captured: Int, recent: [Int]) {
                self.rolls = rolls
                self.sixes = sixes
                self.captures = captures
                self.captured = captured
                self.recent = recent
            }

            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                rolls = try c.decode(Int.self)
                sixes = try c.decode(Int.self)
                captures = try c.decode(Int.self)
                captured = try c.decode(Int.self)
                recent = try c.decode([Int].self)
            }
        }

        struct Game: Decodable {
            let name: String
            let seed: Int64
            let arms: Int
            let seatArms: [Int]
            let rules: Rules
            let difficulties: [String]
            let easyAlwaysRandom: Bool
            let `guard`: Int
            let isOver: Bool
            let turnCount: Int
            let current: Int
            let ranks: [Int]
            let standings: [Int]
            let steps: [[Int]]
            let stats: [Stats]
            let trace: String
            let scores: [[Int64]]?
        }

        let dice: [Dice]
        let geometry: [Geometry]
        let defaultArms: [DefaultArms]
        let threats: Threats
        let estimates: [[Int]]
        let colors: [[Double]]
        let games: [Game]
    }

    private static var cached: Golden?

    private func golden() throws -> Golden {
        if let g = Self.cached { return g }
        let bundle = Bundle(for: LudoGoldenTests.self)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/ludo_golden.json")
        let candidates = [
            bundle.url(forResource: "ludo_golden", withExtension: "json"),
            bundle.url(forResource: "ludo_golden", withExtension: "json", subdirectory: "Golden"),
            source,
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("ludo_golden.json not found")
        }
        let g = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        Self.cached = g
        return g
    }

    private func bits(_ d: Double) -> Int64 { Int64(bitPattern: d.bitPattern) }

    private func near(_ a: LPoint, _ b: [Double], _ what: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b[0], accuracy: 1e-9, what(), file: file, line: line)
        XCTAssertEqual(a.y, b[1], accuracy: 1e-9, what(), file: file, line: line)
    }

    // MARK: Dice

    func testSeededDiceMatchTheJVM() throws {
        for d in try golden().dice {
            let a = SeededDice(d.seed)
            XCTAssertEqual(d.next, (0..<8).map { _ in a.next() }, "next() seed \(d.seed)")
            let b = SeededDice(d.seed)
            XCTAssertEqual(d.rolls, (0..<24).map { _ in b.roll() }, "roll() seed \(d.seed)")
            let c = SeededDice(d.seed)
            XCTAssertEqual(d.doubles, (0..<6).map { _ in bits(c.nextDouble()) }, "nextDouble() seed \(d.seed)")
            let e = SeededDice(d.seed)
            XCTAssertEqual(d.ints, d.bounds.map { e.nextInt($0) }, "nextInt(bound) seed \(d.seed)")
            let f = SeededDice(d.seed)
            XCTAssertEqual(d.picks, (0..<10).map { _ in [10, 20, 30, 40].random(f) }, "random() seed \(d.seed)")
        }
    }

    // MARK: Geometry

    func testGeometryMatchesTheJVM() throws {
        let gold = try golden()
        for gg in gold.geometry {
            let g = LudoGeometry(gg.arms)
            XCTAssertEqual(gg.trackLength, g.trackLength)
            XCTAssertEqual(gg.lastTrackStep, g.lastTrackStep)
            XCTAssertEqual(gg.homeStep, g.homeStep)
            XCTAssertEqual(gg.inner, g.inner, accuracy: 1e-12)
            XCTAssertEqual(gg.radius, g.radius, accuracy: 1e-12)
            XCTAssertEqual(gg.yardPlateRadius, g.yardPlateRadius)
            for i in 0..<g.trackLength {
                near(g.trackPoint(i), gg.track[i], "track \(i)")
                let c = g.cell(ofTrack: i)
                XCTAssertEqual(gg.cells[i], [c.arm, c.v, c.u], "cell \(i)")
            }
            for (i, p) in g.centreOutline.enumerated() { near(p, gg.centre[i], "centre \(i)") }
            for arm in 0..<g.arms {
                let a = gg.perArm[arm]
                let tag = "\(g.arms) arms, arm \(arm)"
                let d = g.direction(arm), l = g.lateral(arm)
                XCTAssertEqual(d.dx, a.direction[0], accuracy: 1e-12, tag)
                XCTAssertEqual(d.dy, a.direction[1], accuracy: 1e-12, tag)
                XCTAssertEqual(l.dx, a.lateral[0], accuracy: 1e-12, tag)
                XCTAssertEqual(l.dy, a.lateral[1], accuracy: 1e-12, tag)
                for (k, step) in (-1...g.homeStep).enumerated() {
                    near(g.routePoint(arm, step), a.route[k], "\(tag) route \(step)")
                    XCTAssertEqual(g.trackIndex(arm, step) ?? -1, a.trackIndex[k], "\(tag) trackIndex \(step)")
                }
                for (k, p) in g.yard(arm).enumerated() { near(p, a.yard[k], "\(tag) yard \(k)") }
                near(g.yardCenter(arm), a.yardCenter, "\(tag) yardCenter")
                for token in 0..<4 { near(g.yardSpot(arm, token), a.yardSpots[token], "\(tag) yardSpot \(token)") }
                var k = 0
                for of in 1...4 {
                    for slot in 0..<of {
                        near(g.homeSpot(arm, slot, of), a.homeSpots[k], "\(tag) homeSpot \(slot)/\(of)")
                        k += 1
                    }
                }
                for (j, p) in g.homeTriangle(arm).enumerated() { near(p, a.triangle[j], "\(tag) triangle \(j)") }
                near(g.hexVertex(arm), a.hexVertex, "\(tag) hexVertex")
                var n = 0
                for v in 0..<6 {
                    for u in -1...1 {
                        for (j, p) in g.cellCorners(arm, v, u).enumerated() { near(p, a.cellCorners[n][j], "\(tag) corner \(v),\(u),\(j)") }
                        n += 1
                    }
                }
                XCTAssertEqual(a.shift, g.shift(toBottomLeft: arm), tag)
                let t = LudoTransform(g, g.shift(toBottomLeft: arm), 390.0, 520.0)
                XCTAssertEqual(a.cell, t.cell, accuracy: 1e-12, tag)
                near(t.screen(g.yardCenter(arm)), a.screenYard, "\(tag) screen")
                near(t.board(t.screen(g.yardCenter(arm))), a.boardBack, "\(tag) board")
            }
        }
        for d in gold.defaultArms {
            XCTAssertEqual(d.value, LudoGeometry.defaultArms(d.seats, d.arms), "defaultArms(\(d.seats), \(d.arms))")
        }
    }

    // MARK: Bot

    func testThreatsMatchTheJVMBitForBit() throws {
        let gold = try golden().threats
        var e = LudoEngine(4, [0, 1, 2, 3], LudoRules())
        e.steps = gold.steps
        for seat in 0..<4 {
            for index in 0..<e.geometry.trackLength {
                XCTAssertEqual(gold.count[seat][index], bits(LudoBot.threat(index, seat, e, exact: false)), "count seat \(seat) square \(index)")
                XCTAssertEqual(gold.exact[seat][index], bits(LudoBot.threat(index, seat, e, exact: true)), "exact seat \(seat) square \(index)")
            }
        }
    }

    func testTimeEstimatesMatchTheJVM() throws {
        for row in try golden().estimates {
            let (seats, people, arms, mask, minutes) = (row[0], row[1], row[2], row[3], row[4])
            let rules = LudoRules(quick: mask & 1 != 0, allPlaces: mask & 2 != 0, fastBots: mask & 4 != 0)
            XCTAssertEqual(minutes, LudoStore.estimatedMinutes(seats, people, arms, rules), "\(row)")
        }
    }

    /// Compose `lerp` works in Oklab; our `LudoColor.mix` must land on the same 8-bit colour (±1 for float rounding).
    func testColourMixesMatchCompose() throws {
        let others: [LudoColor] = [.White, .Black, ludoHex(0xE6E2F0)]
        for row in try golden().colors {
            let base = UInt32(row[0])
            let which = Int(row[1])
            let amount = Double(Float(row[2]))
            let argb = UInt32(bitPattern: Int32(row[3]))
            let mixed = which == 3 ? ludoHex(base).copy(alpha: Double(Float(0.4))).mix(.Black, amount) : ludoHex(base).mix(others[which], amount)
            let want = [Double((argb >> 24) & 0xFF), Double((argb >> 16) & 0xFF), Double((argb >> 8) & 0xFF), Double(argb & 0xFF)]
            let got = [mixed.a, mixed.r, mixed.g, mixed.b].map { ($0 * 255).rounded() }
            for i in 0..<4 { XCTAssertEqual(got[i], want[i], accuracy: 1.0, "mix \(String(base, radix: 16)) \(which) \(amount)") }
        }
    }

    // MARK: Whole games

    private func difficulty(_ name: String) -> LudoDifficulty {
        switch name {
        case "EASY": return .EASY
        case "HARD": return .HARD
        default: return .NORMAL
        }
    }

    /// LudoGoldenDump.game(): the JUnit `playGame` loop with a full trace.
    private func replay(_ spec: Golden.Game) -> (trace: String, engine: LudoEngine, guardCount: Int, scores: [[Int64]]) {
        let r = spec.rules
        let rules = LudoRules(quick: r.quick, allPlaces: r.allPlaces, oneOrSix: r.oneOrSix, captureBonus: r.captureBonus, blockades: r.blockades, safeStars: r.safeStars)
        let difficulties = spec.difficulties.map(difficulty)
        var e = LudoEngine(spec.arms, spec.seatArms, rules)
        let dice = SeededDice(spec.seed)
        let random = SeededDice(spec.seed + 99)
        var trace: [String] = []
        var scores: [[Int64]] = []
        var guardCount = 0
        while !e.isOver && guardCount < 4000 {
            guardCount += 1
            let seat = e.current
            let value = dice.roll()
            let outcome = e.roll(value)
            switch outcome {
            case .Moves(let m):
                let level = difficulties[e.current]
                if spec.scores != nil && m.count > 1 && scores.count < 400 {
                    for mv in m { scores.append([Int64(mv.token), Int64(mv.to), bits(LudoBot.score(mv, e, level))]) }
                }
                let move = (spec.easyAlwaysRandom && level == .EASY && random.roll() <= 6) ? m.random(random) : LudoBot.choose(m, e, level, random)!
                let res = e.apply(move)
                trace.append("\(seat):\(value):\(move.token)>\(move.to)\(move.captures.isEmpty ? "" : "x\(move.captures.count)")\(res.extraRoll ? "+" : "")")
            case .NoMoves(let again):
                trace.append("\(seat):\(value):\(again ? "A" : "N")")
            case .ThreeSixes:
                trace.append("\(seat):\(value):T")
            }
        }
        return (trace.joined(separator: ","), e, guardCount, scores)
    }

    func testSeededBotGamesMatchTheJVMMoveForMove() throws {
        let games = try golden().games
        XCTAssertEqual(76, games.count)
        for spec in games {
            let (trace, e, guardCount, scores) = replay(spec)
            if trace != spec.trace {
                let mine = trace.split(separator: ","), theirs = spec.trace.split(separator: ",")
                let at = zip(mine, theirs).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(mine.count, theirs.count)
                XCTFail("\(spec.name): trace differs at event \(at): \(at < mine.count ? String(mine[at]) : "end") vs \(at < theirs.count ? String(theirs[at]) : "end")")
                continue
            }
            XCTAssertEqual(spec.guard, guardCount, spec.name)
            XCTAssertEqual(spec.isOver, e.isOver, spec.name)
            XCTAssertEqual(spec.turnCount, e.turnCount, spec.name)
            XCTAssertEqual(spec.current, e.current, spec.name)
            XCTAssertEqual(spec.ranks, e.ranks, spec.name)
            XCTAssertEqual(spec.standings, e.standings, spec.name)
            XCTAssertEqual(spec.steps, e.steps, spec.name)
            XCTAssertEqual(spec.stats, e.stats.map { Golden.Stats(rolls: $0.rolls, sixes: $0.sixes, captures: $0.captures, captured: $0.captured, recent: $0.recent) }, spec.name)
            if let want = spec.scores { XCTAssertEqual(want, scores, "\(spec.name) bot scores") }
        }
    }

    /// The JUnit `hardComputersBeatRandomPlayers` games are the golden ones: same winners, same 38 of 60.
    func testHardVersusRandomWinnersMatchTheJVM() throws {
        let games = try golden().games.filter { $0.name.hasPrefix("hardVsRandom") }
        XCTAssertEqual(60, games.count)
        let wins = games.filter { replay($0).engine.ranks.first == 0 }.count
        XCTAssertEqual(games.filter { $0.ranks.first == 0 }.count, wins)
    }
}
