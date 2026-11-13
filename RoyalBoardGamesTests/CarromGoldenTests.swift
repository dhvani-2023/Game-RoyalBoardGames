import XCTest
@testable import RoyalBoardGames

/// Bit-exact parity with Android: every value in Golden/carrom_golden.json was dumped from the Kotlin engine on the
/// JVM (dump source: Golden/source/CarromGoldenDump.kt) with Doubles as raw bits. The Swift engine must reproduce
/// all of it exactly: the rack, physics runs (positions, events, 60 fps frames), bot plans, aim guides, estimates and
/// whole computer-vs-computer matches in every mode.
final class CarromGoldenTests: XCTestCase {
    private static var cached: [String: Any]?

    private func golden() throws -> [String: Any] {
        if let g = CarromGoldenTests.cached { return g }
        var urls: [URL] = []
        let bundle = Bundle(for: CarromGoldenTests.self)
        if let u = bundle.url(forResource: "carrom_golden", withExtension: "json") { urls.append(u) }
        if let u = bundle.url(forResource: "carrom_golden", withExtension: "json", subdirectory: "Golden") { urls.append(u) }
        urls.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/carrom_golden.json"))
        for u in urls {
            if let data = try? Data(contentsOf: u), let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                CarromGoldenTests.cached = obj
                return obj
            }
        }
        XCTFail("carrom_golden.json not found")
        throw NSError(domain: "CarromGoldenTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "carrom_golden.json not found"])
    }

    // MARK: Fingerprints (identical to the Kotlin dump)

    private func hx(_ d: Double) -> String { String(d.bitPattern, radix: 16) }

    private func bits(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }

    private struct Fnv {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        mutating func add(_ v: UInt64) {
            for k in 0..<8 {
                h ^= (v >> UInt64(8 * k)) & 0xff
                h = h &* 0x100_0000_01b3
            }
        }
        mutating func d(_ x: Double) { add(x.bitPattern) }
        mutating func f(_ x: Float) { add(UInt64(bitPattern: Int64(Int32(bitPattern: x.bitPattern)))) }
        mutating func i(_ x: Int) { add(UInt64(bitPattern: Int64(x))) }
        var hex: String { String(h, radix: 16) }
    }

    private func discsHash(_ d: [CarromDisc]) -> String {
        var f = Fnv()
        for c in d { f.i(c.kind.ordinal); f.d(c.x); f.d(c.y); f.d(c.vx); f.d(c.vy); f.i(c.live ? 1 : 0) }
        return f.hex
    }

    private func tableHash(_ t: CarromTable) -> String {
        var f = Fnv()
        for c in t.coins { f.i(c.kind.ordinal); f.d(c.x); f.d(c.y); f.i(c.live ? 1 : 0) }
        f.i(t.turn); f.i(t.strokes); f.i(t.broken ? 1 : 0); f.i(t.queenWaiting ?? -1); f.i(t.queenCoveredBy ?? -1)
        for p in t.points { f.i(p) }
        for o in t.owed { f.i(o) }
        for s in t.stats { f.i(s.coins); f.i(s.points); f.i(s.queens); f.i(s.fouls); f.i(s.bestCombo); f.i(s.strokes) }
        f.i(t.winner ?? -1); f.i(t.boardPoints); f.i(t.target)
        for w in t.winnerScoreBefore { f.i(w) }
        return f.hex
    }

    private func kinds(_ k: [CarromKind]) -> String {
        k.map { switch $0 { case .WHITE: return "W"; case .BLACK: return "B"; case .QUEEN: return "Q"; case .STRIKER: return "S" } }.joined()
    }

    private func checkRun(_ sim: CarromSimulation, _ g: [String: Any], _ label: String) {
        let run = sim.run
        var ev = Fnv()
        for e in run.events {
            ev.i(e.kind.rawValue); ev.d(e.time); ev.d(e.strength); ev.i(e.disc); ev.i(e.other); ev.d(e.at.x); ev.d(e.at.y); ev.i(e.pocket)
        }
        var fr = Fnv()
        for frame in run.frames { for v in frame { fr.f(v) } }
        XCTAssertEqual(g["final"] as? String, discsHash(sim.discs), "\(label) final discs")
        let striker = g["striker"] as! [Any]
        XCTAssertEqual(striker[0] as? String, hx(sim.discs[sim.striker].x), "\(label) striker x")
        XCTAssertEqual(striker[1] as? String, hx(sim.discs[sim.striker].y), "\(label) striker y")
        let pocketed = (g["pocketed"] as! [[Any]]).map { "\($0[0]),\($0[1]),\($0[2])" }
        XCTAssertEqual(pocketed, run.pocketed.map { "\($0.disc),\($0.pocket),\(hx($0.time))" }, "\(label) pocketed")
        XCTAssertEqual(g["events"] as? Int, run.events.count, "\(label) event count")
        XCTAssertEqual(g["eventHash"] as? String, ev.hex, "\(label) events")
        XCTAssertEqual(g["firstContact"] as? Int, run.firstContact ?? -1, "\(label) first contact")
        XCTAssertEqual(g["duration"] as? String, hx(run.duration), "\(label) duration")
        XCTAssertEqual(g["frames"] as? Int, run.frames.count, "\(label) frame count")
        XCTAssertEqual(g["frameHash"] as? String, fr.hex, "\(label) frames")
    }

    private func checkStroke(_ s: CarromStroke, _ g: [String: Any], _ label: String) {
        XCTAssertEqual(g["seat"] as? Int, s.seat, "\(label) seat")
        XCTAssertEqual(g["pocketed"] as? String, kinds(s.pocketed), "\(label) pocketed")
        XCTAssertEqual(g["foul"] as? Bool, s.foul, "\(label) foul")
        XCTAssertEqual(g["continues"] as? Bool, s.continues, "\(label) continues")
        XCTAssertEqual(g["queenCovered"] as? Bool, s.queenCovered, "\(label) queenCovered")
        XCTAssertEqual(g["queenWaiting"] as? Bool, s.queenWaiting, "\(label) queenWaiting")
        XCTAssertEqual(g["queenReturned"] as? Bool, s.queenReturned, "\(label) queenReturned")
        XCTAssertEqual(g["returned"] as? String, kinds(s.returned), "\(label) returned")
        XCTAssertEqual(g["queenFirst"] as? Bool, s.queenFirst, "\(label) queenFirst")
        XCTAssertEqual(g["points"] as? Int, s.points, "\(label) points")
        XCTAssertEqual(g["boardOver"] as? Bool, s.boardOver, "\(label) boardOver")
        XCTAssertEqual(g["timedOut"] as? Bool, s.timedOut, "\(label) timedOut")
    }

    private func checkPlan(_ p: CarromPlan, _ g: [String: Any], _ label: String) {
        XCTAssertEqual(g["slide"] as? String, hx(p.shot.slide), "\(label) slide")
        XCTAssertEqual(g["angle"] as? String, hx(p.shot.angle), "\(label) angle")
        XCTAssertEqual(g["power"] as? String, hx(p.shot.power), "\(label) power")
        XCTAssertEqual(g["target"] as? Int, p.target, "\(label) target")
        XCTAssertEqual(g["pocket"] as? Int, p.pocket, "\(label) pocket")
        let ghost = g["ghost"] as! [Any]
        XCTAssertEqual(ghost[0] as? String, hx(p.ghost.x), "\(label) ghost x")
        XCTAssertEqual(ghost[1] as? String, hx(p.ghost.y), "\(label) ghost y")
        XCTAssertEqual(g["score"] as? String, hx(p.score), "\(label) score")
    }

    private func classic(tournament: Bool = false) -> CarromTable {
        let t = CarromTable.create(.CLASSIC, [0, 2], teams: false, tournament: tournament, breaker: 0)
        t.broken = true
        return t
    }

    /// The same scattered tables as CarromTest.
    private func scattered(_ seed: UInt64) -> CarromTable {
        var rng = CarromRandom(seed)
        let t = classic()
        var placed: [CarromVec] = []
        for i in t.coins.indices {
            let kind = t.coins[i].kind
            let keep = kind == .QUEEN || t.coins.prefix(i).filter({ $0.kind == kind }).count < 5
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

    // MARK: Board

    func testConstantsAndRack() throws {
        let g = try golden()
        let consts = g["constants"] as! [String: String]
        let values: [String: Double] = [
            "pocketR": CarromBoard.pocketR, "pocketC": CarromBoard.pocketC, "coinR": CarromBoard.coinR, "strikerR": CarromBoard.strikerR,
            "baseOuter": CarromBoard.baseOuter, "baseInner": CarromBoard.baseInner, "baseY": CarromBoard.baseY, "slideMax": CarromBoard.slideMax,
            "outerR": CarromBoard.outerR, "dt": CarromPhysics.dt,
        ]
        for (k, v) in values { XCTAssertEqual(consts[k], hx(v), k) }
        let rack = CarromBoard.rack(true)
        let gr = g["rack"] as! [[String]]
        XCTAssertEqual(gr.count, rack.count)
        for (i, d) in rack.enumerated() {
            XCTAssertEqual(gr[i][0], d.kind.rawValue)
            XCTAssertEqual(gr[i][1], hx(d.x), "rack \(i) x")
            XCTAssertEqual(gr[i][2], hx(d.y), "rack \(i) y")
        }
        XCTAssertEqual(g["rackNoQueen"] as? String, discsHash(CarromBoard.rack(false)))
    }

    func testSpotsAimsAndFreeSpots() throws {
        let g = try golden()
        let spots = g["spots"] as! [[String]]
        var k = 0
        for side in 0..<4 {
            for slide in [-1.0, -0.37, 0.0, 0.5, 1.0] {
                let p = CarromBoard.strikerSpot(side, slide)
                XCTAssertEqual(spots[k], [hx(p.x), hx(p.y), hx(CarromBoard.slide(p, side)), hx(CarromBoard.distanceToBaseLine(CarromVec(3.3, 20.1), side))], "spot \(side) \(slide)")
                k += 1
            }
        }
        let aims = g["clampAim"] as! [String]
        k = 0
        for side in 0..<4 {
            for a in [-3.0, -Double.pi / 2, 0.0, 1.0, 2.5, Double.pi, 4.0] {
                XCTAssertEqual(aims[k], hx(CarromBoard.clampAim(a, side)), "clampAim \(a) side \(side)")
                k += 1
            }
        }
        let rack = CarromBoard.rack(true)
        let fs = CarromBoard.freeSpot(avoiding: rack)
        let fs2 = CarromBoard.freeSpot(CarromVec(5.0, -3.0), avoiding: rack)
        XCTAssertEqual(g["freeSpot"] as! [String], [hx(fs.x), hx(fs.y), hx(fs2.x), hx(fs2.y)])
    }

    /// The engine's sin/cos/atan2/log/pow are a port of Java's StrictMath (fdlibm): same bits on 200k inputs.
    func testFdLibmMatchesStrictMath() throws {
        let g = try golden()
        let h = g["fdlibm"] as! [String: Any]
        var rng = CarromRandom(2026)
        var hSin = Fnv(), hCos = Fnv(), hAtan2 = Fnv(), hLog = Fnv(), hPow = Fnv(), hPowInv = Fnv()
        for _ in 0..<(h["n"] as! Int) {
            let x = (rng.unit() - 0.5) * 20
            let y = (rng.unit() - 0.5) * 20
            let p = rng.unit() * 400
            let b = rng.unit()
            hSin.d(CarromFdLibm.sin(x)); hCos.d(CarromFdLibm.cos(x)); hAtan2.d(CarromFdLibm.atan2(y, x)); hLog.d(CarromFdLibm.log(p))
            hPow.d(CarromFdLibm.pow(b, 1.8)); hPowInv.d(CarromFdLibm.pow(b, 1 / 1.8))
        }
        XCTAssertEqual(h["sin"] as? String, hSin.hex, "sin")
        XCTAssertEqual(h["cos"] as? String, hCos.hex, "cos")
        XCTAssertEqual(h["atan2"] as? String, hAtan2.hex, "atan2")
        XCTAssertEqual(h["log"] as? String, hLog.hex, "log")
        XCTAssertEqual(h["pow"] as? String, hPow.hex, "pow")
        XCTAssertEqual(h["powInv"] as? String, hPowInv.hex, "pow 1/1.8")
    }

    func testRandomAndHelpers() throws {
        let g = try golden()
        let r = g["random"] as! [String: [String]]
        var rng = CarromRandom(42)
        XCTAssertEqual(r["next"]!, (0..<4).map { _ in String(rng.next(), radix: 16) })
        XCTAssertEqual(r["unit"]!, (0..<4).map { _ in hx(rng.unit()) })
        XCTAssertEqual(r["normal"]!, (0..<6).map { _ in hx(rng.normal()) })
        var helpers: [String] = []
        for v in [0.0, 1.0, 10.0, 50.0, 123.4, 300.0] { helpers.append(hx(CarromPhysics.travel(v))) }
        for x in [1.0, 10.0, 55.5, 100.0] { helpers.append(hx(CarromPhysics.speedToTravel(x))) }
        helpers.append(hx(CarromPhysics.launch(100.0, 30.0)))
        for p in [0.0, 0.02, 0.3, 0.5, 0.93, 1.0] { helpers.append(hx(CarromPhysics.speedForPower(p))) }
        for s in [0.0, 10.0, 150.0, 299.0, 400.0] { helpers.append(hx(CarromPhysics.powerForSpeed(s))) }
        XCTAssertEqual(g["helpers"] as! [String], helpers)
    }

    // MARK: Physics

    func testPhysicsRuns() throws {
        let g = try golden()
        for (n, entry) in (g["runs"] as! [[String: Any]]).enumerated() {
            let name = entry["table"] as! String
            let shotBits = entry["shot"] as! [Any]
            let shot = CarromShot(bits(shotBits[0]), bits(shotBits[1]), bits(shotBits[2]))
            func make() -> CarromTable {
                if name == "classic" { return CarromTable.create(.CLASSIC, [0, 2], false, false, 0) }
                if name == "teams1" { return CarromTable.create(.FREESTYLE, [0, 1, 2, 3], true, false, 1) }
                return scattered(UInt64(name.dropFirst("scattered".count))!)
            }
            let t = make()
            let sim = t.simulate(shot, true)
            checkRun(sim, entry["run"] as! [String: Any], "run \(n) \(name)")
            let stroke = t.play(shot)
            checkStroke(stroke, entry["stroke"] as! [String: Any], "run \(n) \(name)")
            XCTAssertEqual(entry["hash"] as? String, tableHash(t), "run \(n) \(name) table")
        }
    }

    // MARK: Computers

    func testScatteredTablesAndCandidates() throws {
        let g = try golden()
        for entry in g["scattered"] as! [[String: Any]] {
            let seed = UInt64(entry["seed"] as! Int)
            XCTAssertEqual(entry["hash"] as? String, tableHash(scattered(seed)), "scattered \(seed)")
        }
        let c = g["candidates"] as! [String: Any]
        let cands = CarromBot.candidates(scattered(1))
        XCTAssertEqual(c["count"] as? Int, cands.count)
        for (i, p) in (c["top"] as! [[String: Any]]).enumerated() { checkPlan(cands[i], p, "candidate \(i)") }
    }

    func testBotPlans() throws {
        let g = try golden()
        let fresh = CarromTable.create(.CLASSIC, [0, 2], false, false, 0)
        for entry in g["plans"] as! [[String: Any]] {
            let table = entry["table"] as! Int
            let levelName = entry["level"] as! String
            let seed = UInt64(entry["seed"] as! Int)
            let label = "plan table \(table) \(levelName) seed \(seed)"
            if levelName == "SAFETY" {
                checkPlan(CarromBot.safety(scattered(2)), entry["plan"] as! [String: Any], label)
                continue
            }
            let level = CarromDifficulty(rawValue: levelName)!
            let t = table == 0 ? fresh : scattered(UInt64(table))
            let plan = CarromBot.plan(t, level, seed)
            checkPlan(plan, entry["plan"] as! [String: Any], label)
            if let gs = entry["stroke"] as? [String: Any] {
                let after = t.deepCopy()
                let s = after.play(plan.shot)
                checkStroke(s, gs, label)
                XCTAssertEqual(entry["hash"] as? String, tableHash(after), "\(label) table")
            }
        }
    }

    // MARK: Aim guide, table helpers, estimates

    func testGuides() throws {
        let g = try golden()
        let gt = CarromTable.create(.CLASSIC, [0, 2], false, false, 0)
        let gs = scattered(62)
        for (n, entry) in (g["guides"] as! [[String: Any]]).enumerated() {
            let table = (entry["table"] as! Int) == 0 ? gt : gs
            let style = CarromAimGuide(rawValue: entry["style"] as! String)!
            let guide = CarromGuide.compute(table, bits(entry["slide"]), bits(entry["angle"]), style)
            let e = entry["guide"] as! [String: Any]
            let path = (e["path"] as! [[String]]).map { $0.joined(separator: ",") }
            XCTAssertEqual(path, guide.path.map { "\(hx($0.x)),\(hx($0.y))" }, "guide \(n) path")
            let ghost = (e["ghost"] as? [String])?.joined(separator: ",")
            XCTAssertEqual(ghost, guide.ghost.map { "\(hx($0.x)),\(hx($0.y))" }, "guide \(n) ghost")
            XCTAssertEqual(e["coin"] as? Int, guide.coin ?? -1, "guide \(n) coin")
            let end = (e["coinEnd"] as? [String])?.joined(separator: ",")
            XCTAssertEqual(end, guide.coinEnd.map { "\(hx($0.x)),\(hx($0.y))" }, "guide \(n) coinEnd")
            XCTAssertEqual(e["pocket"] as? Int, guide.pocket ?? -1, "guide \(n) pocket")
        }
    }

    func testTableHelpersAndEstimates() throws {
        let g = try golden()
        let h = g["tableHelpers"] as! [String: Any]
        let ht = scattered(31)
        XCTAssertEqual(h["targets"] as! [Int], ht.targets())
        XCTAssertEqual(h["fits"] as! [Bool], (0...20).map { ht.strikerFits(-1 + Double($0) * 0.1) })
        XCTAssertEqual(h["free"] as! [String], [-1.0, -0.5, 0.0, 0.33, 1.0].map { hx(ht.freeSlide($0)) })
        var est: [Int] = []
        for seats in 2...4 {
            for people in 0...seats {
                for mode in CarromMode.allCases {
                    for length in CarromMatchLength.allCases {
                        for fast in [false, true] {
                            est.append(CarromStore.estimatedMinutes(seats, people, CarromOptions(mode: mode, length: length, fastBots: fast)))
                        }
                    }
                }
            }
        }
        XCTAssertEqual(g["estimates"] as! [Int], est)
    }

    // MARK: Whole matches

    func testComputerMatches() throws {
        let g = try golden()
        for game in g["games"] as! [[String: Any]] {
            let name = game["name"] as! String
            let seats = game["seats"] as! Int
            let options = CarromOptions(
                mode: CarromMode(rawValue: game["mode"] as! String)!,
                length: CarromMatchLength(rawValue: game["length"] as! String)!,
                tournament: game["tournament"] as! Bool,
                freestyleTeams: game["freestyleTeams"] as! Bool
            )
            let levels = (game["levels"] as! [String]).map { CarromDifficulty(rawValue: $0)! }
            let gi = game["gi"] as! Int
            let steps = game["steps"] as! [[String: Any]]
            let m = CarromMatch.create(options, seats, 0)
            var k = 0
            var n = 0
            while !m.isOver && k < 400 {
                let t = m.table
                if t.winner != nil {
                    m.finishBoard()
                    if m.isOver { break }
                    m.nextBoard()
                    guard n < steps.count else { XCTFail("\(name): more steps than Android"); return }
                    let s = steps[n]
                    XCTAssertEqual(s["nextBoard"] as? Int, m.board, "\(name) step \(n) board")
                    XCTAssertEqual(s["turn"] as? Int, m.table.turn, "\(name) step \(n) breaker")
                    XCTAssertEqual(s["hash"] as? String, tableHash(m.table), "\(name) step \(n) new table")
                    n += 1
                    continue
                }
                let level = levels[t.turn]
                let seed = UInt64(gi * 7919 + k * 31 + 1)
                let plan = CarromBot.plan(t, level, seed)
                let shot = CarromShot(t.freeSlide(plan.shot.slide), plan.shot.angle, plan.shot.power)
                let stroke = t.play(shot)
                guard n < steps.count else { XCTFail("\(name): more steps than Android"); return }
                let s = steps[n]
                let label = "\(name) step \(n)"
                checkPlan(plan, s["plan"] as! [String: Any], label)
                checkStroke(stroke, s["stroke"] as! [String: Any], label)
                let ok = (s["hash"] as? String) == tableHash(t)
                XCTAssertTrue(ok, "\(label) table diverged")
                if !ok { return }
                n += 1
                k += 1
            }
            XCTAssertEqual(steps.count, n, "\(name) step count")
            XCTAssertEqual(game["winner"] as? Int, m.winner ?? -1, "\(name) winner")
            XCTAssertEqual(game["board"] as? Int, m.board, "\(name) boards")
            XCTAssertEqual(game["scores"] as? [Int], m.scores, "\(name) scores")
            XCTAssertEqual(game["wins"] as? [Int], m.wins, "\(name) wins")
            let totals = (game["totals"] as! [[Int]])
            XCTAssertEqual(totals, m.totals.map { [$0.coins, $0.points, $0.queens, $0.fouls, $0.bestCombo, $0.strokes] }, "\(name) totals")
        }
    }
}
