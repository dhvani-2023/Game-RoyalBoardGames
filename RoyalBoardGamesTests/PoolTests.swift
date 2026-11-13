import XCTest
@testable import RoyalBoardGames

/// 1:1 port of the Android `PoolTests` (app/src/test/.../game/pool/PoolTests.kt).
final class PoolTests: XCTestCase {
    private let R = PoolTableGeometry.R

    // MARK: Helpers

    private func table(_ game: PoolVariant = .EIGHT, _ seats: Int = 2, _ options: PoolOptions = PoolOptions()) -> PoolTableState {
        PoolTableState.create(game, options, seats, 0, 1)
    }

    /// Applies a shot that hit [first] and pocketed [pot] (numbers), without physics.
    @discardableResult
    private func stroke(
        _ t: inout PoolTableState, _ first: Int?, _ pot: [Int], rail: Bool = true, pocket: Int = 0,
        call: Int? = nil, cushions: Set<Int> = [1, 2, 3, 4, 5]
    ) -> PoolStroke {
        let legal = t.legalFirst()
        var balls = t.balls
        let run = PoolPhysics.Run()
        run.firstHit = first
        run.railAfterContact = rail
        run.cushionBalls.formUnion(cushions)
        for n in pot {
            guard let i = balls.firstIndex(where: { $0.n == n && $0.live }) else { continue }
            balls[i].live = false
            run.potted.append(PoolPhysics.Potted(i, pocket, 0.0))
        }
        return t.apply(balls, run, PoolShot(angle: 0.0, power: 0.5, call: call), legal)
    }

    /// A broken 8-Ball table with these groups set.
    private func groups(_ g: PoolGroup = .SOLIDS) -> PoolTableState {
        var t = table()
        t.broken = true
        t.ballInHand = false
        t.kitchenOnly = false
        t.groups = [g, g.other]
        return t
    }

    /// Balls scattered over the cloth without touching, as after a break.
    private func scattered(_ seed: Int64, _ game: PoolVariant = .EIGHT) -> PoolTableState {
        var t = table(game)
        let rng = PoolRandom(seed)
        let geo = t.geometry
        var placed: [Vec2] = []
        for i in t.balls.indices {
            var p: Vec2
            repeat {
                p = Vec2((rng.unit() * 2 - 1) * (geo.a - 2 * R), (rng.unit() * 2 - 1) * (geo.b - 2 * R))
            } while placed.contains { ($0 - p).length < 2 * R + 0.5 }
            placed.append(p)
            t.balls[i].p = p
        }
        t.broken = true
        t.ballInHand = false
        t.kitchenOnly = false
        return t
    }

    private func clearGroup(_ t: inout PoolTableState, _ numbers: ClosedRange<Int>) {
        for n in numbers {
            if let i = t.balls.firstIndex(where: { $0.n == n }) { t.balls[i].live = false }
        }
    }

    // MARK: Geometry

    func testEightBallRack() {
        let t = PoolTableGeometry.bar
        let balls = PoolRack.eight(t, 3)
        XCTAssertEqual(16, balls.count)
        XCTAssertEqual(Set(0...15), Set(balls.map { $0.n }))
        let objects = balls.filter { $0.n != 0 }
        // The 8 is in the middle of the third row, the apex on the foot spot.
        let eight = objects.first { $0.n == 8 }!
        XCTAssertTrue(abs(eight.y) < 0.01)
        XCTAssertTrue(abs(eight.x - (t.footSpot.x + 2 * (3.0).squareRoot() * R)) < 0.1)
        XCTAssertTrue(objects.contains { ($0.p - t.footSpot).length < 0.01 })
        for i in balls.indices { for j in balls.indices where j > i { XCTAssertTrue((balls[i].p - balls[j].p).length >= 2 * R) } }
    }

    func testEightBallRackCornersHoldOneOfEach() {
        for seed in Int64(1)...20 {
            let balls = PoolRack.eight(PoolTableGeometry.bar, seed)
            let back = Array(balls.dropFirst(11))
            XCTAssertEqual(5, back.count)
            let corners = [back.first!.n, back.last!.n]
            XCTAssertTrue(corners.contains { $0 < 8 } && corners.contains { $0 > 8 })
        }
    }

    func testNineBallRack() {
        let t = PoolTableGeometry.bar
        let balls = PoolRack.nine(t, 3)
        XCTAssertEqual(10, balls.count)
        XCTAssertTrue((balls.first { $0.n == 1 }!.p - t.footSpot).length < 0.01)
        let nine = balls.first { $0.n == 9 }!
        XCTAssertTrue(abs(nine.y) < 0.01 && nine.x > t.footSpot.x)
    }

    func testPocketsAreSymmetric() {
        for t in [PoolTableGeometry.bar, PoolTableGeometry.pro] {
            XCTAssertEqual(6, t.pockets.count)
            for pk in t.pockets {
                XCTAssertTrue(t.pockets.contains { ($0.c - Vec2(-pk.c.x, pk.c.y)).length < 0.001 })
                XCTAssertTrue(t.pockets.contains { ($0.c - Vec2(pk.c.x, -pk.c.y)).length < 0.001 })
            }
        }
    }

    func testKitchenLimit() {
        let t = PoolTableGeometry.bar
        XCTAssertTrue(t.inKitchen(Vec2(t.headString - 1, 0.0)))
        XCTAssertFalse(t.inKitchen(Vec2(t.headString + 1, 0.0)))
        var state = table()
        XCTAssertTrue(state.kitchenOnly && state.ballInHand)
        XCTAssertFalse(state.free(Vec2(0.0, 0.0)))
        state.kitchenOnly = false
        XCTAssertTrue(state.free(Vec2(0.0, 0.0)))
    }

    func testRandomMatchesSplitMix64() {
        // Reference values of SplitMix64 for seed 0.
        let rng = PoolRandom(0)
        XCTAssertEqual(Int64(bitPattern: 0xE220_A839_7B1D_CDAF), rng.next())
        XCTAssertEqual(Int64(bitPattern: 0x6E78_9E6A_A1B9_65F4), rng.next())
        let u = PoolRandom(42)
        for _ in 0..<1000 { let x = u.unit(); XCTAssertTrue(x >= 0 && x < 1) }
        let b = PoolRandom(7)
        for _ in 0..<1000 { let x = b.nextBelow(13); XCTAssertTrue((0..<13).contains(x)) }
    }

    // MARK: Physics

    private func twoBalls(_ cue: Vec2, _ obj: Vec2) -> [PoolBall] { [PoolBall(0, cue), PoolBall(1, obj)] }

    func testSameShotSameResult() {
        var a = PoolRack.eight(PoolTableGeometry.bar, 5)
        var b = a.map { $0.copy() }
        PoolPhysics.strike(&a[0], 0.01, 1.0, Vec2(0.1, -0.2))
        PoolPhysics.strike(&b[0], 0.01, 1.0, Vec2(0.1, -0.2))
        let ra = PoolPhysics.run(&a, PoolTableGeometry.bar, false)
        let rb = PoolPhysics.run(&b, PoolTableGeometry.bar, false)
        XCTAssertEqual(a.map { $0.p }, b.map { $0.p })
        XCTAssertEqual(ra.potted.map { $0.ball }, rb.potted.map { $0.ball })
    }

    func testFollowCarriesForwardAndDrawComesBack() {
        // The reference test ran the follow shot to rest, but with the current constants the object
        // ball comes back off the foot cushion and knocks the cue ball back (the Swift engine does the
        // same, bit for bit). So the follow is checked before that second contact.
        var follow = twoBalls(Vec2(-30.0, 0.0), Vec2(0.0, 0.0))
        PoolPhysics.strike(&follow[0], 0.0, 0.45, Vec2(0.0, 0.4))
        let run = PoolPhysics.Run()
        var time = 0.0
        while time < 0.6 {
            _ = PoolPhysics.advance(&follow, PoolTableGeometry.bar, run, time)
            time += PoolPhysics.dt
        }
        XCTAssertEqual(1, run.events.filter { $0.kind == .Hit }.count)
        XCTAssertTrue(follow[0].x > -2 * R + 2)
        XCTAssertTrue(follow[0].vx > 0)

        var draw = twoBalls(Vec2(-30.0, 0.0), Vec2(0.0, 0.0))
        PoolPhysics.strike(&draw[0], 0.0, 0.45, Vec2(0.0, -0.4))
        _ = PoolPhysics.run(&draw, PoolTableGeometry.bar, false)
        XCTAssertTrue(draw[0].x < -2 * R - 5)
    }

    func testSlideReachesNaturalRoll() {
        var balls = [PoolBall(0, Vec2(-60.0, 0.0))]
        PoolPhysics.strike(&balls[0], 0.0, 0.5, Vec2.ZERO)
        let v0 = balls[0].v.length
        let run = PoolPhysics.Run()
        var time = 0.0
        while true {
            let b = balls[0]
            let slip = Vec2(b.vx - R * b.wy, b.vy + R * b.wx).length
            if slip <= 0.4 { break }
            _ = PoolPhysics.advance(&balls, PoolTableGeometry.bar, run, time)
            time += PoolPhysics.dt
        }
        XCTAssertTrue(abs(balls[0].v.length / v0 - 5.0 / 7.0) < 0.03)
    }

    func testHardShotNeverTunnels() {
        var balls = [PoolBall(0, Vec2(0.0, 0.0))]
        PoolPhysics.strike(&balls[0], 0.0, 1.0, Vec2.ZERO)
        let geo = PoolTableGeometry.bar
        let run = PoolPhysics.run(&balls, geo, true)
        XCTAssertTrue(run.potted.isEmpty)
        for frame in run.frames { XCTAssertTrue(abs(Double(frame[0])) <= geo.a - R + 0.05) }
    }

    func testEnergyNeverGrows() {
        var balls = twoBalls(Vec2(-40.0, 0.0), Vec2(0.0, 1.0))
        PoolPhysics.strike(&balls[0], 0.0, 0.7, Vec2(0.3, 0.3))
        // Moving plus spinning, per half unit mass: v² + (2/5)R²|w|².
        let b = balls[0]
        let start = b.v.dot(b.v) + 0.4 * R * R * (b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
        let run = PoolPhysics.run(&balls, PoolTableGeometry.bar, true)
        for f in 2..<run.frames.count {
            var total = 0.0
            for i in 0..<2 {
                let dx: Float = (run.frames[f][2 * i] - run.frames[f - 1][2 * i]) * 60
                let dy: Float = (run.frames[f][2 * i + 1] - run.frames[f - 1][2 * i + 1]) * 60
                total += Double(dx * dx + dy * dy)
            }
            XCTAssertTrue(total <= start * 1.02)
        }
    }

    func testRunningEnglishWidensTheRebound() {
        func rebound(_ english: Double) -> Double {
            var balls = [PoolBall(0, Vec2(-20.0, 0.0))]
            PoolPhysics.strike(&balls[0], Double.pi / 4, 0.35, Vec2(english, 0.0))
            let run = PoolPhysics.Run()
            var time = 0.0
            // Until it has come off the long cushion.
            while run.events.isEmpty && time < 3 {
                _ = PoolPhysics.advance(&balls, PoolTableGeometry.bar, run, time)
                time += PoolPhysics.dt
            }
            return atan2(-balls[0].vy, balls[0].vx)
        }
        // Here right english is running english: the ball comes off closer to the cushion.
        XCTAssertTrue(rebound(0.4) < rebound(-0.4))
    }

    func testRolledAlongTheCushionDropsInTheCorner() {
        let geo = PoolTableGeometry.bar
        var balls = [PoolBall(0, Vec2(20.0, geo.b - R - 0.3))]
        PoolPhysics.strike(&balls[0], 0.0, 0.45, Vec2.ZERO)
        let run = PoolPhysics.run(&balls, geo, false)
        XCTAssertEqual(2, run.potted.first?.pocket)
    }

    func testQuaternionRollKeepsUnitLength() {
        var q = PoolQuat.start(3)
        for _ in 0..<500 { q = PoolQuat.roll(q, 0.7, -0.3) }
        let n = (q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w).squareRoot()
        XCTAssertEqual(1.0, n, accuracy: 1e-9)
        // Rolling one circumference along x brings the ball back round.
        let start = PoolQuat.identity
        var r = start
        let steps = 400
        for _ in 0..<steps { r = PoolQuat.roll(r, 2 * Double.pi * R / Double(steps), 0.0) }
        let v = PoolQuat.rotate(r, Vec3(0.0, 0.0, -1.0))
        XCTAssertEqual(-1.0, v.z, accuracy: 1e-6)
    }

    // MARK: 8-Ball rules

    func testScratchIsAFoul() {
        var t = groups()
        let s = stroke(&t, 1, [0])
        XCTAssertTrue(s.foul && s.scratch)
        XCTAssertTrue(t.turn == 1 && t.ballInHand && !t.kitchenOnly)
        XCTAssertTrue(t.cue.live)
    }

    func testWrongBallAndNoCushionAreFouls() {
        var a = groups(.SOLIDS)
        XCTAssertEqual("Wrong ball first", stroke(&a, 9, []).why)
        var b = groups(.SOLIDS)
        XCTAssertEqual("Hit the 8 too early", stroke(&b, 8, []).why)
        var c = groups(.SOLIDS)
        let s = stroke(&c, 1, [], rail: false)
        XCTAssertTrue(s.foul && s.why == "No cushion after contact")
        var d = groups(.SOLIDS)
        XCTAssertEqual("No ball hit", stroke(&d, nil, []).why)
    }

    func testBreakRules() {
        var weak = table()
        XCTAssertEqual("Weak break", stroke(&weak, 1, [], cushions: [1, 2]).why)
        var good = table()
        let s = stroke(&good, 1, [3])
        XCTAssertTrue(!s.foul && s.continues && s.groupsSet == nil)
        XCTAssertEqual([nil, nil] as [PoolGroup?], good.groups)
        var eight = table()
        let e = stroke(&eight, 1, [8])
        XCTAssertTrue(e.respotted == 8 && !e.rackOver)
        XCTAssertNotNil(eight.ball(8))
        var scratch = table()
        stroke(&scratch, 1, [0])
        XCTAssertTrue(scratch.ballInHand && scratch.kitchenOnly)
    }

    func testFirstLegalPotSetsGroups() {
        var t = table()
        t.broken = true
        let s = stroke(&t, 11, [11])
        XCTAssertEqual(PoolGroup.STRIPES, s.groupsSet)
        XCTAssertEqual([PoolGroup.STRIPES, PoolGroup.SOLIDS] as [PoolGroup?], t.groups)
        XCTAssertTrue(s.continues && t.turn == 0)
    }

    func testEightBallWinsAndLosses() {
        // Early 8 loses.
        var early = groups()
        let e = stroke(&early, 8, [8])
        XCTAssertTrue(e.rackOver && !e.won && early.winner == 1)

        // Cleared, called right: win.
        var win = groups()
        clearGroup(&win, 1...7)
        let w = stroke(&win, 8, [8], pocket: 3, call: 3)
        XCTAssertTrue(w.won && win.winner == 0)

        // Wrong pocket loses.
        var wrong = groups()
        clearGroup(&wrong, 1...7)
        let x = stroke(&wrong, 8, [8], pocket: 2, call: 3)
        XCTAssertTrue(!x.won && wrong.winner == 1)

        // The 8 with a scratch loses.
        var foul = groups()
        clearGroup(&foul, 1...7)
        let f = stroke(&foul, 8, [8, 0], pocket: 3, call: 3)
        XCTAssertTrue(!f.won && foul.winner == 1)
    }

    func testTeamsAlternate() {
        var t = PoolTableState.create(.EIGHT, PoolOptions(), 4, 0, 1)
        XCTAssertTrue(t.teams && t.units == 2)
        XCTAssertTrue(t.unit(2) == 0 && t.unit(3) == 1)
        t.broken = true
        t.ballInHand = false
        var order: [Int] = []
        for _ in 0..<4 {
            order.append(t.turn)
            stroke(&t, t.legalFirst().first, [])
        }
        XCTAssertEqual([0, 1, 2, 3], order)
    }

    // MARK: 9-Ball rules

    func testNineBallLowestFirst() {
        var t = table(.NINE)
        t.broken = true
        t.ballInHand = false
        let s = stroke(&t, 3, [])
        XCTAssertTrue(s.foul && s.why == "Hit the 1 first")
    }

    func testNineOnACombinationWins() {
        var t = table(.NINE)
        t.broken = true
        let s = stroke(&t, 1, [9])
        XCTAssertTrue(s.won && t.winner == 0)
    }

    func testNineOnAFoulIsSpotted() {
        var t = table(.NINE)
        t.broken = true
        let s = stroke(&t, 4, [9])
        XCTAssertTrue(s.foul && s.respotted == 9 && !s.rackOver)
        XCTAssertNotNil(t.ball(9))
    }

    func testThreeFoulsLose() {
        var t = PoolTableState.create(.NINE, PoolOptions(threeFouls: true), 2, 0, 1)
        t.broken = true
        for _ in 0..<2 {
            stroke(&t, nil, []) // seat 0 fouls
            stroke(&t, t.lowest, [], rail: true) // seat 1 plays a legal miss
        }
        let s = stroke(&t, nil, [])
        XCTAssertTrue(s.rackOver && t.winner == 1)
    }

    func testRotationForThree() {
        let m = PoolMatch.create(PoolOptions(), 3, 0, 1)
        XCTAssertEqual(PoolVariant.NINE, m.game)
        var t = m.table
        t.broken = true
        t.ballInHand = false
        var order: [Int] = []
        for _ in 0..<3 {
            order.append(t.turn)
            stroke(&t, t.lowest, [])
        }
        XCTAssertEqual([0, 1, 2], order)
    }

    func testTimeOutGivesBallInHand() {
        var t = groups()
        let s = t.timeOut()
        XCTAssertTrue(s.foul && s.timedOut)
        XCTAssertTrue(t.turn == 1 && t.ballInHand && !t.kitchenOnly)
    }

    // MARK: Matches and saves

    func testRaceToThree() {
        var m = PoolMatch.create(PoolOptions(), 2, 0, 1)
        XCTAssertEqual(3, m.target)
        for rack in 1...3 {
            m.table.winner = 1
            let over = m.finishRack()
            XCTAssertEqual(rack == 3, over)
            if !over {
                m.nextRack()
                XCTAssertEqual(rack % 2, m.table.breaker)
            }
        }
        XCTAssertTrue(m.winner == 1 && m.wins == [0, 3])
    }

    func testSaveRoundTrips() throws {
        var m = PoolMatch.create(PoolOptions(), 2, 1, 9)
        m.table = scattered(4)
        m.table.groups = [.STRIPES, .SOLIDS]
        m.table.turn = 1
        let back = try JSONDecoder().decode(PoolMatch.self, from: try JSONEncoder().encode(m))
        XCTAssertEqual(m.table.balls, back.table.balls)
        XCTAssertTrue(back.table.turn == 1 && back.table.groups == [.STRIPES, .SOLIDS])
        XCTAssertEqual(m.options, back.options)
        XCTAssertEqual(m.seed, back.seed)
    }

    func testOldSavesDecodeWithDefaults() throws {
        let setup = try JSONDecoder().decode(PoolStore.Setup.self, from: Data(#"{"seats":3,"options":{"game":"NINE"},"future":1}"#.utf8))
        XCTAssertEqual(3, setup.seats)
        XCTAssertEqual(PoolVariant.NINE, setup.options.game)
        XCTAssertEqual(PoolMatchLength.RACE_TO_3, setup.options.length)
        XCTAssertEqual(3, setup.difficulties.count)
    }

    func testCloneIsIndependent() {
        let m = PoolMatch.create(PoolOptions(), 2, 0, 3)
        var c = m.clone()
        c.table.balls[0].x = 50.0
        c.table.stats[0].potted = 9
        c.wins[0] = 2
        XCTAssertTrue(m.table.balls[0].x != 50.0)
        XCTAssertEqual(0, m.table.stats[0].potted)
        XCTAssertEqual(0, m.wins[0])
    }

    func testEstimatedMinutesIsSensible() {
        let one = PoolStore.estimatedMinutes(2, 1, PoolOptions(length: .ONE))
        let race = PoolStore.estimatedMinutes(2, 1, PoolOptions(length: .RACE_TO_5))
        XCTAssertTrue(one >= 2 && race > one)
    }

    // MARK: Aim guide

    func testGuideFindsTheGhostBall() {
        var t = groups()
        for i in t.balls.indices where t.balls[i].n != 0 && t.balls[i].n != 1 { t.balls[i].live = false }
        t.balls[t.balls.firstIndex { $0.n == 1 }!].p = Vec2(20.0, 0.0)
        let g = PoolGuide.compute(t, Vec2(-20.0, 0.0), 0.0, Vec2.ZERO, .FULL, t.legalFirst())
        XCTAssertEqual(1, t.balls[g.target ?? 0].n)
        XCTAssertNotNil(g.target)
        XCTAssertTrue(g.legal)
        XCTAssertEqual(20.0 - 2 * R, g.ghost!.x, accuracy: 1e-6)
        XCTAssertNotNil(g.objectEnd)
        let off = PoolGuide.compute(t, Vec2(-20.0, 0.0), 0.0, Vec2.ZERO, .OFF, t.legalFirst())
        XCTAssertNil(off.end)
        XCTAssertNotNil(off.target)
    }

    // MARK: Computers

    func testBotShotsAreLegal() {
        for seed in Int64(1)...6 {
            var t = scattered(seed)
            if seed % 2 == 0 { t.ballInHand = true }
            let plan = PoolBot.plan(t, .NORMAL, seed)
            if plan.target >= 0 { XCTAssertTrue(t.legalFirst().contains(plan.target)) }
            if t.ballInHand, let place = plan.shot.place { XCTAssertTrue(t.free(place)) }
            XCTAssertTrue(plan.shot.power > 0 && plan.shot.power <= 1)
        }
    }

    func testBreakPlacementIsInTheKitchen() {
        let t = table()
        let plan = PoolBot.plan(t, .HARD, 2)
        XCTAssertTrue(plan.shot.place.map { t.free($0) } == true)
    }

    func testHardPotsMoreThanEasy() {
        func pots(_ level: PoolDifficulty) -> Int {
            var count = 0
            for seed in Int64(20)...27 {
                var t = scattered(seed)
                let before = t.unitNow
                let plan = PoolBot.plan(t, level, seed)
                let s = t.play(plan.shot)
                if !s.foul && s.continues && t.unitNow == before { count += 1 }
            }
            return count
        }
        XCTAssertTrue(pots(.HARD) > pots(.EASY))
    }
}
