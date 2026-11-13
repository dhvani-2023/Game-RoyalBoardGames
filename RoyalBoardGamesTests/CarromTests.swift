import XCTest
@testable import RoyalBoardGames

/// Ported 1:1 from the Android JUnit suite (app/src/test/.../carrom/CarromTest.kt).
final class CarromTests: XCTestCase {
    // MARK: Helpers

    /// Applies a stroke that pocketed exactly these kinds (and the striker if [foul]), without physics.
    @discardableResult
    private func stroke(_ table: CarromTable, _ pocket: [CarromKind], foul: Bool = false) -> CarromStroke {
        var discs = table.coins.cloned()
        discs.append(CarromDisc(.STRIKER, table.strikerSpot(0.0)))
        let si = discs.count - 1
        let run = CarromPhysics.Run()
        for kind in pocket {
            guard let i = discs.indices.first(where: { discs[$0].live && discs[$0].kind == kind }) else { continue }
            discs[i].live = false
            run.pocketed.append(CarromPhysics.Pocketed(i, 0, 0.0))
        }
        if foul {
            discs[si].live = false
            run.pocketed.append(CarromPhysics.Pocketed(si, 1, 0.1))
        }
        return table.apply(discs, run, si)
    }

    private func classic(tournament: Bool = false) -> CarromTable {
        let t = CarromTable.create(.CLASSIC, [0, 2], teams: false, tournament: tournament, breaker: 0)
        t.broken = true
        return t
    }

    private let W = CarromKind.WHITE
    private let B = CarromKind.BLACK
    private let Q = CarromKind.QUEEN

    // MARK: Geometry

    func testRackIsRegulation() {
        let rack = CarromBoard.rack(true)
        XCTAssertEqual(19, rack.count)
        XCTAssertEqual(9, rack.filter { $0.kind == W }.count)
        XCTAssertEqual(9, rack.filter { $0.kind == B }.count)
        XCTAssertEqual(1, rack.filter { $0.kind == Q }.count)
        XCTAssertEqual(CarromVec.ZERO, rack[0].p, "the queen sits in the centre circle")
        for i in rack.indices {
            XCTAssertTrue(rack[i].p.length + CarromBoard.coinR <= CarromBoard.outerR + 1e-9, "inside the outer circle")
            var nearest = Double.infinity
            for j in rack.indices where j != i { nearest = min(nearest, (rack[i].p - rack[j].p).length) }
            XCTAssertTrue(nearest >= 2 * CarromBoard.coinR - 1e-9, "no overlaps")
            XCTAssertTrue(nearest <= 2 * CarromBoard.coinR + 1e-6, "every coin touches a neighbour")
        }
        XCTAssertEqual(18, CarromBoard.rack(false).count)
    }

    func testPocketsAndBaseLines() {
        XCTAssertTrue(abs(CarromBoard.pocketC - (CarromBoard.half - CarromBoard.pocketR)) < 1e-9)
        XCTAssertEqual(4, CarromBoard.pockets.count)
        let bottom = CarromBoard.strikerSpot(0, 0.0)
        XCTAssertTrue(abs(bottom.x) < 1e-9 && abs(bottom.y - CarromBoard.baseY) < 1e-9)
        let right = CarromBoard.strikerSpot(1, 0.0)
        XCTAssertTrue(abs(right.x - CarromBoard.baseY) < 1e-9 && abs(right.y) < 1e-9)
        let top = CarromBoard.strikerSpot(2, 0.0)
        XCTAssertTrue(abs(top.y + CarromBoard.baseY) < 1e-9)
        XCTAssertTrue(abs(CarromBoard.strikerSpot(0, 1.0).x - CarromBoard.slideMax) < 1e-9)
        XCTAssertTrue(abs(CarromBoard.slide(CarromBoard.strikerSpot(3, 0.4), 3) - 0.4) < 1e-9)
        // The striker touches both base lines.
        XCTAssertTrue(CarromBoard.strikerR * 2 >= CarromBoard.baseOuter - CarromBoard.baseInner)
    }

    func testAimStaysForward() {
        for side in 0..<4 {
            let f = CarromBoard.forward(side)
            let back = atan2(-f.y, -f.x)
            let clamped = CarromBoard.clampAim(back, side)
            let d = CarromVec(cos(clamped), sin(clamped))
            XCTAssertTrue(d.dot(f) > -0.1, "never straight back at your own frame")
            let ahead = atan2(f.y, f.x) + 0.3
            XCTAssertTrue(abs(CarromBoard.clampAim(ahead, side) - ahead) < 1e-9)
        }
    }

    // MARK: Physics

    func testFullPowerRunsThreeAndAHalfLengths() {
        var discs = [CarromDisc(.STRIKER, CarromBoard.strikerSpot(0, 0.0))]
        discs[0].v = CarromVec(0.0, -CarromPhysics.maxSpeed)
        let run = CarromPhysics.Run()
        var path = 0.0
        var last = discs[0].p
        var t = 0.0
        while CarromPhysics.advance(&discs, run, 0, t) {
            path += (discs[0].p - last).length
            last = discs[0].p
            t += CarromPhysics.dt
        }
        let firstRun = CarromBoard.baseY + CarromBoard.half - CarromBoard.strikerR
        XCTAssertTrue(abs(path / firstRun - 3.5) < 0.25, "ICF board test: \(path / firstRun) lengths")
    }

    func testEnergyNeverGrows() {
        let t = CarromTable.create(.CLASSIC, [0, 2], false, false, 0)
        var discs = t.coins.cloned()
        discs.append(CarromDisc(.STRIKER, t.strikerSpot(0.0)))
        discs[discs.count - 1].v = CarromVec(0.0, -CarromPhysics.maxSpeed)
        func energy(_ d: [CarromDisc]) -> Double { d.filter { $0.live }.reduce(0.0) { $0 + 0.5 * $1.m * $1.v.dot($1.v) } }
        let run = CarromPhysics.Run()
        var previous = energy(discs)
        var time = 0.0
        var steps = 0
        while CarromPhysics.advance(&discs, run, discs.count - 1, time) && steps < 3000 {
            let e = energy(discs)
            XCTAssertTrue(e <= previous + 1e-6)
            previous = e
            time += CarromPhysics.dt
            steps += 1
        }
        XCTAssertNotNil(run.firstContact, "the break reaches the pack")
    }

    func testHeadOnHitConservesMomentum() {
        var discs = [
            CarromDisc(.STRIKER, CarromVec(0.0, 10.0)),
            CarromDisc(.WHITE, CarromVec(0.0, 10 - CarromBoard.strikerR - CarromBoard.coinR - 0.1)),
        ]
        discs[0].v = CarromVec(0.0, -200.0)
        let before = discs.reduce(CarromVec.ZERO) { $0 + $1.v * $1.m }
        let run = CarromPhysics.Run()
        CarromPhysics.advance(&discs, run, 0, 0.0)
        CarromPhysics.advance(&discs, run, 0, CarromPhysics.dt)
        let after = discs.reduce(CarromVec.ZERO) { $0 + $1.v * $1.m }
        // Friction takes a little over two substeps; the collision itself conserves momentum.
        XCTAssertTrue(abs(after.y - before.y) < 0.02 * abs(before.y))
        XCTAssertTrue(discs[1].v.y < -100, "the coin takes most of the striker's speed")
    }

    func testSameShotSameResult() {
        let t = CarromTable.create(.CLASSIC, [0, 2], false, false, 0)
        let shot = CarromShot(0.12, -1.5, 0.97)
        let a = t.simulate(shot, false)
        let b = t.simulate(shot, false)
        XCTAssertEqual(a.discs, b.discs)
        XCTAssertEqual(a.run.duration, b.run.duration, accuracy: 0.0)
    }

    func testNothingTunnelsAtTopSpeed() {
        var discs = [CarromDisc(.STRIKER, CarromVec(0.0, 25.0)), CarromDisc(.WHITE, CarromVec(0.0, 0.0))]
        discs[0].v = CarromVec(0.0, -CarromPhysics.maxSpeed)
        let run = CarromPhysics.run(&discs, 0, false)
        XCTAssertEqual(1, run.firstContact)
        XCTAssertTrue(discs[1].p.y < -5 || !discs[1].live, "the coin was struck, not passed through")
    }

    func testCoinAlongTheFrameDropsInTheCorner() {
        let lane = CarromBoard.half - CarromBoard.coinR
        var discs = [CarromDisc(.BLACK, CarromVec(0.0, lane))]
        discs[0].v = CarromVec(160.0, 0.0)
        let run = CarromPhysics.run(&discs, nil, false)
        XCTAssertFalse(discs[0].live)
        XCTAssertEqual(2, run.pocketed.first?.pocket)
    }

    func testRecordedFramesCoverTheRun() {
        let t = CarromTable.create(.CLASSIC, [0, 2], false, false, 0)
        let sim = t.simulate(CarromShot(0.0, -Double.pi / 2, 1.0), true)
        XCTAssertTrue(sim.run.frames.count >= Int(sim.run.duration * 60))
        XCTAssertTrue(sim.run.frames.allSatisfy { $0.count == sim.discs.count * 2 })
    }

    // MARK: Rules: Classic

    func testOwnCoinKeepsTheTurnOtherColourEndsIt() {
        let t = classic()
        let a = stroke(t, [W])
        XCTAssertTrue(a.continues && t.turn == 0)
        let b = stroke(t, [B])
        XCTAssertTrue(!b.continues && t.turn == 1, "their coin counts for them and ends your turn")
        XCTAssertEqual(1, t.pocketed(B))
    }

    func testQueenTooEarlyGoesBack() {
        let t = classic()
        let s = stroke(t, [Q])
        XCTAssertTrue(s.queenReturned && t.queenOnBoard)
        XCTAssertFalse(s.continues)
    }

    func testQueenCoveredSameStroke() {
        let t = classic()
        stroke(t, [W])
        let s = stroke(t, [Q, W])
        XCTAssertTrue(s.queenCovered && t.queenCoveredBy == 0 && s.continues)
    }

    func testQueenCoveredNextStroke() {
        let t = classic()
        stroke(t, [W])
        let s = stroke(t, [Q])
        XCTAssertTrue(s.queenWaiting && s.continues && t.queenWaiting == 0)
        let c = stroke(t, [W])
        XCTAssertTrue(c.queenCovered && t.queenCoveredBy == 0 && t.queenWaiting == nil)
    }

    func testFailedCoverReturnsTheQueen() {
        let t = classic()
        stroke(t, [W])
        stroke(t, [Q])
        let s = stroke(t, [])
        XCTAssertTrue(s.queenReturned && t.queenOnBoard && t.queenCoveredBy == nil)
        XCTAssertEqual(1, t.turn)
    }

    func testTournamentFullBoardQueenNeedsAnotherCover() {
        let t = classic(tournament: true)
        let s = stroke(t, [Q, W])
        XCTAssertTrue(s.queenWaiting && !s.queenCovered, "ICF 97: on a full board the queen with one coin still needs a cover")
        let f = classic(tournament: false)
        XCTAssertTrue(stroke(f, [Q, W]).queenCovered)
    }

    func testFoulReturnsCoinsAndADue() {
        let t = classic()
        stroke(t, [W, W])
        XCTAssertEqual(2, t.pocketed(W))
        let s = stroke(t, [W], foul: true)
        XCTAssertTrue(s.foul && !s.continues)
        // The coin pocketed on the foul comes back, plus one more as the due.
        XCTAssertEqual(1, t.pocketed(W))
        XCTAssertEqual(1, t.turn)
    }

    func testDueOwedUntilACoinIsPocketed() {
        let t = classic()
        stroke(t, [], foul: true)
        XCTAssertEqual(1, t.owed[0])
        stroke(t, []) // black misses
        stroke(t, [W])
        XCTAssertEqual(0, t.owed[0], "the due is paid as soon as a coin is available")
        XCTAssertEqual(0, t.pocketed(W))
    }

    func testQueenFirstFriendlyBringsTheCoinBack() {
        let t = classic()
        for _ in 0..<8 { stroke(t, [W]) }
        let s = stroke(t, [W])
        XCTAssertTrue(s.queenFirst && !s.continues && t.left(W) == 1 && t.winner == nil)
    }

    func testQueenFirstTournamentLosesTheBoard() {
        let t = classic(tournament: true)
        for _ in 0..<8 { stroke(t, [W]) }
        let s = stroke(t, [W])
        XCTAssertTrue(s.queenFirst && s.boardOver && t.winner == 1 && t.boardPoints == 3)
    }

    func testBoardPointsAreCoinsLeftPlusQueen() {
        let t = classic()
        stroke(t, [W])
        stroke(t, [Q, W])
        for _ in 0..<7 { stroke(t, [W]) }
        XCTAssertEqual(0, t.winner)
        XCTAssertEqual(9 + 3, t.boardPoints, "nine black left plus three for the queen")
    }

    // MARK: Rules: other modes and turns

    func testPocketPoolHasNoQueenAndClearingWins() {
        let t = CarromTable.create(.POOL, [0, 2], false, false, 0)
        XCTAssertTrue(!t.queenOnBoard && t.coins.count == 18)
        for _ in 0..<9 { stroke(t, [W]) }
        XCTAssertTrue(t.winner == 0 && t.boardPoints == 9)
    }

    func testFreestyleScoring() {
        let t = CarromTable.create(.FREESTYLE, [0, 2], false, false, 0)
        let a = stroke(t, [W, B])
        XCTAssertTrue(a.points == 30 && a.continues && t.points[0] == 30)
        let q = stroke(t, [Q])
        XCTAssertTrue(q.queenWaiting && q.continues)
        let c = stroke(t, [B])
        XCTAssertTrue(c.queenCovered && t.points[0] == 30 + 50 + 10)
        let f = stroke(t, [], foul: true)
        XCTAssertTrue(f.points == -10 && t.points[0] == 80 && t.turn == 1)
        XCTAssertEqual(160, t.target)
        XCTAssertEqual(120, CarromTable.create(.FREESTYLE, [0, 1, 3], false, false, 0).target)
        XCTAssertEqual(100, CarromTable.create(.FREESTYLE, [0, 1, 2, 3], false, false, 0).target)
    }

    func testTurnsPassToTheRightAndPartnersShareATeam() {
        let t = CarromTable.create(.FREESTYLE, [0, 1, 3], false, false, 0)
        var order: [Int] = []
        for _ in 0..<4 { order.append(t.side); stroke(t, []) }
        XCTAssertEqual([0, 1, 3, 0], order)
        let teams = CarromTable.create(.CLASSIC, [0, 1, 2, 3], true, false, 0)
        XCTAssertEqual(teams.unit(0), teams.unit(2))
        XCTAssertEqual(teams.unit(1), teams.unit(3))
        XCTAssertTrue(teams.unit(0) != teams.unit(1))
    }

    func testMatchLengths() {
        var options = CarromOptions(length: .BEST_OF_THREE)
        let m = CarromMatch.create(options, 2, 0)
        for _ in 0..<9 { stroke(m.table, [W]) }
        XCTAssertNil(m.table.winner, "queen still to cover")
        let copy = m.table.deepCopy()
        for i in copy.coins.indices where copy.coins[i].kind == Q { copy.coins[i].live = false }
        copy.queenCoveredBy = 0
        m.table = copy
        stroke(m.table, [W])
        XCTAssertEqual(0, m.table.winner)
        XCTAssertTrue(!m.finishBoard() && m.wins[0] == 1)
        m.nextBoard()
        XCTAssertTrue(m.board == 2 && m.table.turn == 1, "the break moves round the table")
        options.length = .RACE25
        let race = CarromMatch.create(options, 2, 0)
        race.scores = [24, 0]
        race.table.winner = 0
        race.table.boardPoints = 2
        XCTAssertTrue(race.finishBoard() && race.winner == 0)
    }

    // MARK: Computers

    private func scattered(_ seed: UInt64) -> CarromTable {
        var rng = CarromRandom(seed)
        let t = classic()
        var placed: [CarromVec] = []
        for i in t.coins.indices {
            let kind = t.coins[i].kind
            let keep = kind == Q || t.coins.prefix(i).filter({ $0.kind == kind }).count < 5
            if !keep { t.coins[i].live = false; continue }
            while true {
                let p = CarromVec(rng.unit() * 64 - 32, rng.unit() * 52 - 32)
                if placed.allSatisfy({ ($0 - p).length > 2 * CarromBoard.coinR + 0.3 }) && CarromBoard.pockets.allSatisfy({ ($0 - p).length > 5 }) {
                    t.coins[i].p = p
                    placed.append(p)
                    break
                }
            }
        }
        return t
    }

    func testBotShotsAreLegal() {
        for seed in UInt64(1)...6 {
            let t = scattered(seed)
            let plan = CarromBot.plan(t, .NORMAL, seed)
            XCTAssertTrue(t.strikerFits(t.freeSlide(plan.shot.slide)))
            let d = CarromVec(cos(plan.shot.angle), sin(plan.shot.angle))
            XCTAssertTrue(d.dot(CarromBoard.forward(t.side)) > -0.1)
            XCTAssertTrue(plan.shot.power > 0 && plan.shot.power <= 1.0001)
        }
    }

    func testHardPocketsMoreThanEasy() {
        var easy = 0
        var hard = 0
        for seed in UInt64(1)...10 {
            let t = scattered(seed * 31)
            let a = t.deepCopy()
            let b = t.deepCopy()
            if a.play(CarromBot.plan(t, .EASY, seed).shot).pocketed.contains(W) { easy += 1 }
            if b.play(CarromBot.plan(t, .HARD, seed).shot).pocketed.contains(W) { hard += 1 }
        }
        XCTAssertTrue(hard > easy, "Hard \(hard) vs Easy \(easy) of 10")
        XCTAssertTrue(hard >= 6, "Hard \(hard) of 10")
    }

    func testBreakShotIsLegal() {
        let t = CarromTable.create(.CLASSIC, [0, 2], false, false, 0)
        for level in CarromDifficulty.allCases {
            let plan = CarromBot.plan(t, level, 7)
            XCTAssertTrue(plan.shot.power > 0.5)
        }
    }

    // MARK: Saves and estimates

    func testSavedMatchRoundTrips() throws {
        let m = CarromMatch.create(CarromOptions(), 4, 1)
        m.table.play(CarromShot(0.0, CarromBoard.clampAim(Double.pi, m.table.side), 1.0))
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(CarromMatch.self, from: data)
        XCTAssertEqual(m.table.coins, back.table.coins)
        XCTAssertTrue(back.table.turn == m.table.turn && back.teams && back.mode == .CLASSIC)
    }

    func testOldSavesDecodeWithDefaults() throws {
        let options = try JSONDecoder().decode(CarromOptions.self, from: Data(#"{"mode":"POOL"}"#.utf8))
        XCTAssertEqual(CarromMode.POOL, options.mode)
        XCTAssertTrue(options.turnBoard)
        let setup = try JSONDecoder().decode(CarromStore.Setup.self, from: Data(#"{"seats":4}"#.utf8))
        XCTAssertEqual(4, setup.seats)
        XCTAssertEqual(3, setup.difficulties.count)
    }

    func testEstimatesScaleWithTheMatch() {
        var options = CarromOptions()
        let one = CarromStore.estimatedMinutes(2, 2, options)
        options.length = .BEST_OF_THREE
        let three = CarromStore.estimatedMinutes(2, 2, options)
        XCTAssertTrue((3...8).contains(one))
        XCTAssertTrue(three > one)
    }

    func testGuideFindsTheCoinAhead() {
        let t = CarromTable.create(.CLASSIC, [0, 2], false, false, 0)
        let g = CarromGuide.compute(t, 0.0, -Double.pi / 2, .FULL)
        XCTAssertNotNil(g.ghost)
        XCTAssertNotNil(g.coin)
        XCTAssertTrue(CarromGuide.compute(t, 0.0, -Double.pi / 2, .OFF).path.isEmpty)
    }
}
