import XCTest
import GameKit
@testable import RoyalBoardGames

// 1:1 port of app/src/test/java/com/ngstudio/royalboardgames/game/ludo/LudoTests.kt

final class LudoGeometryTests: XCTestCase {
    func testTrackIsAClosedLoopOfTouchingSquares() {
        for arms in [4, 6] {
            let g = LudoGeometry(arms)
            XCTAssertEqual(13 * arms, g.trackLength)
            let points = (0..<g.trackLength).map(g.trackPoint)
            // Every square is distinct.
            let keys = Set(points.map { "\(Kt.roundToInt($0.x * 100)),\(Kt.roundToInt($0.y * 100))" })
            XCTAssertEqual(g.trackLength, keys.count)
            // Consecutive squares are neighbours (one cell apart, or diagonal where two arms meet).
            for i in 0..<g.trackLength {
                let a = points[i]
                let b = points[(i + 1) % g.trackLength]
                let d = hypot(a.x - b.x, a.y - b.y)
                XCTAssertTrue(d > 0.9 && d < 1.75, "squares \(i) and \(i + 1) are \(d) apart")
            }
        }
    }

    func testClassicLayoutMatchesTheBoard() {
        let g = LudoGeometry(4)
        XCTAssertEqual(56, g.homeStep, "57 positions: start … 50 on the track, 5 home-lane squares, home")
        // Red (arm 0) starts on the left arm's top row, second from the edge: board cell (6, 1).
        let start = g.routePoint(0, 0)
        XCTAssertTrue(abs(start.x - (1.5 - 7.5)) < 0.001 && abs(start.y - (6.5 - 7.5)) < 0.001)
        // Its last track square is the left arm's tip (7, 0), then the home lane runs right.
        let tip = g.routePoint(0, g.lastTrackStep)
        XCTAssertTrue(abs(tip.x - (0.5 - 7.5)) < 0.001 && abs(tip.y) < 0.001)
        XCTAssertTrue(g.isStart(g.trackIndex(2, 0)!))
        XCTAssertTrue(g.isStar(g.trackIndex(0, 8)!), "a star sits 8 squares after each start")
    }

    func testSixArmBoardHasLongerRoutesAndTriangleYards() {
        let g = LudoGeometry(6)
        XCTAssertEqual(82, g.homeStep)
        XCTAssertEqual(3, g.yard(0).count)
        for arm in 0..<6 {
            let c = g.yard(arm)
            let sides = (0..<3).map { hypot(c[$0].x - c[($0 + 1) % 3].x, c[$0].y - c[($0 + 1) % 3].y) }
            XCTAssertTrue(sides.allSatisfy { abs($0 - 6) < 0.001 }, "equilateral, side 6")
        }
    }

    func testBoardTurnsALoneSeatToTheBottomLeft() {
        for arms in [4, 6] {
            let g = LudoGeometry(arms)
            for arm in 0..<arms {
                let t = LudoTransform(g, g.shift(toBottomLeft: arm), 100.0, 100.0)
                let p = t.screen(g.yardCenter(arm))
                XCTAssertTrue(p.x < 50 && p.y > 50, "\(arms) arms, arm \(arm) ends up bottom-left")
                // board() undoes screen().
                let back = t.board(p)
                let c = g.yardCenter(arm)
                XCTAssertTrue(abs(back.x - c.x) < 1e-9 && abs(back.y - c.y) < 1e-9)
            }
        }
    }

    func testDefaultSeatsSpreadOut() {
        XCTAssertEqual([0, 2], LudoGeometry.defaultArms(2, 4))
        XCTAssertEqual(5, LudoGeometry.defaultArms(5, 6).count)
        XCTAssertEqual(Array(0..<6), LudoGeometry.defaultArms(6, 6))
    }
}

final class LudoRulesTests: XCTestCase {
    private func engine(_ rules: LudoRules = LudoRules(), arms: Int = 4, seats: [Int] = [0, 1, 2, 3]) -> LudoEngine {
        LudoEngine(arms, seats, rules)
    }

    private func moves(_ outcome: LudoEngine.RollOutcome, file: StaticString = #filePath, line: UInt = #line) -> [LudoMove] {
        guard case .Moves(let m) = outcome else {
            XCTFail("expected moves, got \(outcome)", file: file, line: line)
            return []
        }
        return m
    }

    func testASixBringsATokenOut() {
        var e = engine()
        XCTAssertEqual(LudoEngine.RollOutcome.NoMoves(again: false), e.roll(3))
        XCTAssertEqual(1, e.current)
        let m = moves(e.roll(6))
        XCTAssertTrue(m.count == 1 && m[0].comesOut)
        let result = e.apply(m[0])
        XCTAssertTrue(result.extraRoll, "a six rolls again")
        XCTAssertTrue(e.current == 1 && e.steps[1].contains(0))
    }

    func testOneOrSixOptionAlsoBringsTokensOut() {
        var e = engine(LudoRules(oneOrSix: true))
        XCTAssertTrue(moves(e.roll(1)).first!.comesOut)
    }

    func testThreeSixesLoseTheTurn() {
        var e = engine()
        for _ in 0..<2 { e.apply(moves(e.roll(6))[0]) }
        XCTAssertEqual(LudoEngine.RollOutcome.ThreeSixes, e.roll(6))
        XCTAssertEqual(1, e.current)
    }

    func testCapturesSendTokensHomeAndGiveAnExtraRoll() {
        // Quick mode: tokens start on their start squares.
        var e = engine(LudoRules(quick: true), seats: [0, 1])
        // Seat 1 (arm 1) starts 13 squares after seat 0; walk seat 0 onto seat 1's step 2 square.
        let target = e.geometry.trackIndex(1, 2)!
        for roll in [6, 6] { e.apply(moves(e.roll(roll)).first { $0.token == 0 }!) }
        _ = moves(e.roll(1))
        // Seat 0 moved token 0 to 12 and rolled 1 (no bonus): now play it.
        let one = e.legalMoves(1).first { $0.token == 0 }!
        e.apply(one)
        XCTAssertEqual(1, e.current)
        // Seat 1 moves token 0 two squares onto the target, then seat 0 rolls a 2 to hit it.
        e.apply(moves(e.roll(2)).first { $0.token == 0 }!)
        XCTAssertEqual(target, e.trackIndex(1, 0))
        let hit = moves(e.roll(2)).first { $0.token == 0 }!
        XCTAssertEqual([LudoTokenRef(1, 0)], hit.captures)
        let result = e.apply(hit)
        XCTAssertTrue(result.extraRoll, "capture bonus")
        XCTAssertEqual(0, e.steps[1][0], "in Quick mode a captured token returns to its start")
        XCTAssertTrue(e.stats[0].captures == 1 && e.stats[1].captured == 1)
    }

    func testSafeSquaresProtectTokens() {
        let rules = LudoRules(quick: true)
        let e = engine(rules, seats: [0, 1])
        let star = e.geometry.trackIndex(0, 8)!
        XCTAssertTrue(e.isSafe(star))
        let start = e.geometry.trackIndex(1, 0)!
        XCTAssertTrue(e.isSafe(start))
        var noStars = rules
        noStars.safeStars = false
        XCTAssertFalse(LudoEngine(4, [0, 1], noStars).isSafe(star))
    }

    func testFinishingNeedsAnExactRollAndWins() {
        var e = engine(LudoRules(quick: true), seats: [0, 2])
        let home = e.geometry.homeStep
        // March both of seat 0's tokens home, skipping seat 2's turns with misses.
        var safety = 0
        while !e.isOver && safety < 500 {
            safety += 1
            if e.current == 1 {
                e.roll(1)
                if e.pendingRoll != nil, let m = e.legalMoves(1).first { e.apply(m) }
                continue
            }
            let token = e.steps[0][0] < home ? 0 : 1
            let left = home - e.steps[0][token]
            let roll = min(5, left)
            guard case .Moves(let ms) = e.roll(roll) else { continue }
            XCTAssertTrue(ms.allSatisfy { $0.to <= home }, "no overshooting")
            e.apply(ms.first { $0.token == token } ?? ms[0])
        }
        XCTAssertTrue(e.isOver)
        XCTAssertEqual(0, e.ranks.first)
        XCTAssertEqual(2, e.standings.count)
    }

    func testBlockadesStopOtherColours() {
        // Red (arm 0) stacks on track square 11; Blue (arm 3) comes round behind it.
        var e = engine(LudoRules(quick: true, blockades: true), seats: [0, 3])
        func play(_ roll: Int, _ token: Int) {
            let m = moves(e.roll(roll))
            e.apply(m.first { $0.token == token } ?? m[0])
        }
        play(3, 0)                              // Red token 0 → square 11
        play(6, 0); play(6, 0); play(1, 1)      // Blue token 0 → step 12 (square 7)
        play(3, 1)                              // Red token 1 → square 11: a blockade
        XCTAssertTrue(e.trackIndex(0, 0) == 11 && e.trackIndex(0, 1) == 11)
        XCTAssertEqual(1, e.current)
        let m = moves(e.roll(4))
        XCTAssertFalse(m.contains { $0.token == 0 }, "Blue can't land on the blockade")
    }
}

final class LudoBotTests: XCTestCase {
    /// Plays a whole game with bots; returns the winner.
    private func playGame(_ seed: Int64, _ difficulties: [LudoDifficulty], quick: Bool = true) -> Int? {
        var e = LudoEngine(4, [0, 1, 2, 3], LudoRules(quick: quick))
        let dice = SeededDice(seed)
        let random = SeededDice(seed + 99)
        var guardCount = 0
        while !e.isOver && guardCount < 4000 {
            guardCount += 1
            let outcome = e.roll(dice.roll())
            if case .Moves(let m) = outcome {
                let difficulty = difficulties[e.current]
                // "easy" here always picks at random.
                let move = (difficulty == .EASY && random.roll() <= 6) ? m.random(random) : LudoBot.choose(m, e, difficulty, random)!
                XCTAssertTrue(m.contains(move))
                e.apply(move)
            }
        }
        return e.ranks.first
    }

    func testBotsAlwaysPlayLegalMovesAndGamesFinish() {
        for seed in 1...6 {
            XCTAssertNotNil(playGame(Int64(seed), [.HARD, .NORMAL, .EASY, .NORMAL]))
        }
    }

    func testHardComputersBeatRandomPlayers() {
        // Seat 0 is Hard; the rest move at random.
        let games = 60
        let wins = (0..<games).filter { playGame(Int64($0) + 100, [.HARD, .EASY, .EASY, .EASY]) == 0 }.count
        XCTAssertTrue(Double(wins) / Double(games) > 0.45, "Hard won \(wins) of \(games) against three random players (chance is 25%)")
    }

    func testHardTakesACaptureWhenItCan() {
        var e = LudoEngine(4, [0, 1], LudoRules(quick: true))
        func play(_ roll: Int, _ token: Int) {
            guard case .Moves(let m) = e.roll(roll) else { return XCTFail("expected moves") }
            e.apply(m.first { $0.token == token } ?? m[0])
        }
        play(6, 0); play(6, 0); play(1, 0) // Red token 0 → step 13
        play(2, 0)                         // Green token 0 → its step 2
        guard case .Moves(let m) = e.roll(2) else { return XCTFail("expected moves") }
        let move = LudoBot.choose(m, e, .HARD, SeededDice(3))!
        XCTAssertTrue(!move.captures.isEmpty, "Hard takes the capture")
    }

    func testFairDiceAreUniform() {
        let dice = FairDice()
        var counts = [Int](repeating: 0, count: 7)
        for _ in 0..<12_000 { counts[dice.roll()] += 1 }
        XCTAssertEqual(0, counts[0])
        for face in 1...6 { XCTAssertTrue(abs(counts[face] - 2000) < 230, "face \(face) came up \(counts[face]) times") }
    }
}

final class LudoSaveTests: XCTestCase {
    /// The same JSON round trip `Prefs` uses (a JSON string per key).
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testEnginesRoundTripThroughJSON() throws {
        var e = LudoEngine(6, [0, 1, 2, 3, 4], LudoRules())
        if case .Moves(let m) = e.roll(6) { e.apply(m[0]) }
        let back = try roundTrip(e)
        XCTAssertEqual(e, back)
        XCTAssertEqual(e.geometry, back.geometry)
    }

    func testSetupDecodesOldDataWithDefaults() throws {
        let setup = try JSONDecoder().decode(LudoStore.Setup.self, from: Data(#"{"seats":5}"#.utf8))
        XCTAssertEqual(5, setup.seats)
        XCTAssertEqual(1, setup.peopleCount)
        XCTAssertEqual(0, setup.themeID)
        let rules = try JSONDecoder().decode(LudoRules.self, from: Data(#"{"quick":true}"#.utf8))
        XCTAssertTrue(rules.quick && rules.captureBonus && rules.safeStars)
    }

    func testTimeEstimatesFollowTheSimulation() {
        let classic4 = LudoStore.estimatedMinutes(4, 2, 4, LudoRules())
        let quick6 = LudoStore.estimatedMinutes(6, 2, 6, LudoRules(quick: true))
        let classic6 = LudoStore.estimatedMinutes(6, 2, 6, LudoRules())
        XCTAssertTrue((8...20).contains(classic4))
        XCTAssertTrue(quick6 < classic6)
    }

    func testCopiesAreIndependent() {
        let e = LudoEngine(4, [0, 2], LudoRules(quick: true))
        var c = e.copy()
        guard case .Moves(let m) = c.roll(3) else { return XCTFail("expected moves") }
        c.apply(m[0])
        XCTAssertEqual(0, e.steps[0][0])
        XCTAssertEqual(3, c.steps[0][0])
        XCTAssertEqual(0, e.stats[0].rolls)
    }

    /// Swift-only: a whole saved match (seats, rules, engine mid-choice) survives the store's JSON.
    func testSavedMatchRoundTrips() throws {
        let seats = [
            LudoSeat(PartyPlayer(name: "Raj", avatar: "🦊", colorIndex: 0), 0, isBot: false),
            LudoSeat(PartyPlayer(name: "CPU Leo", avatar: "🤖", colorIndex: 2), 2, isBot: true, difficulty: .HARD),
        ]
        let config = LudoConfig(seats: seats, arms: 4, themeID: 3, rules: LudoRules(quick: true, blockades: true), shift: 3, resume: true)
        var e = LudoEngine(config.arms, seats.map { $0.arm }, config.rules)
        _ = e.roll(5)
        XCTAssertNotNil(e.pendingRoll)
        let saved = LudoStore.SavedMatch(config, e, 42.5, 1_700_000_000_000)
        let back = try roundTrip(saved)
        XCTAssertEqual(saved, back)
        XCTAssertEqual(5, back.engine.pendingRoll)
        XCTAssertEqual(.HARD, back.config.seats[1].difficulty)
    }
}
