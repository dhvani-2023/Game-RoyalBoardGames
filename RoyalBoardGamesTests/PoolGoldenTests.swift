import XCTest
@testable import RoyalBoardGames

/// Bit-for-bit parity with the Android (JVM) engine: racks, orientations, geometry, physics traces with
/// their rules outcomes and rolled orientations, computer plans, the aim guide, free spots and match seeds.
/// The dump is `Golden/pool_golden.json`, written by `Golden/source/PoolGoldenDump.kt`.
final class PoolGoldenTests: XCTestCase {
    private let R = PoolTableGeometry.R

    private static let golden: [String: Any] = {
        var urls: [URL] = []
        if let u = Bundle(for: PoolGoldenTests.self).url(forResource: "pool_golden", withExtension: "json") { urls.append(u) }
        urls.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/pool_golden.json"))
        for u in urls {
            if let d = try? Data(contentsOf: u), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return j }
        }
        return [:]
    }()

    private var g: [String: Any] { PoolGoldenTests.golden }

    // MARK: Canonical forms (JSON values and Swift values rendered the same way)

    private func canon(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "null" }
        if let s = v as? String { return "\"\(s)\"" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let a = v as? [Any] { return "[" + a.map { canon($0) }.joined(separator: ",") + "]" }
        if let d = v as? [String: Any] { return "{" + d.keys.sorted().map { "\($0):" + canon(d[$0]) }.joined(separator: ",") + "}" }
        return "?"
    }

    private func hx(_ d: Double) -> String { String(d.bitPattern, radix: 16) }
    private func S(_ s: String) -> String { "\"\(s)\"" }
    private func D(_ d: Double) -> String { S(hx(d)) }
    private func I(_ i: Int) -> String { String(i) }
    private func B(_ b: Bool) -> String { b ? "true" : "false" }
    private func N(_ i: Int?) -> String { i.map { String($0) } ?? "null" }
    private func A(_ items: [String]) -> String { "[" + items.joined(separator: ",") + "]" }
    private func V(_ v: Vec2?) -> String { v.map { A([D($0.x), D($0.y)]) } ?? "null" }
    private func ints(_ l: [Int]) -> String { A(l.map(I)) }

    private func ballsCanon(_ balls: [PoolBall]) -> String {
        A(balls.map { A([I($0.n), D($0.x), D($0.y), D($0.vx), D($0.vy), D($0.wx), D($0.wy), D($0.wz), B($0.live)]) })
    }

    private func shotCanon(_ s: PoolShot) -> String {
        "{angle:\(D(s.angle)),call:\(N(s.call)),place:\(V(s.place)),power:\(D(s.power)),spin:\(V(s.spin))}"
    }

    private func bits(_ any: Any?) -> Double { Double(bitPattern: UInt64(any as! String, radix: 16)!) }

    private func shotFrom(_ any: Any?) -> PoolShot {
        let o = any as! [String: Any]
        let spin = o["spin"] as! [Any]
        let place = o["place"] as? [Any]
        return PoolShot(
            angle: bits(o["angle"]), power: bits(o["power"]), spin: Vec2(bits(spin[0]), bits(spin[1])),
            place: place.map { Vec2(bits($0[0]), bits($0[1])) }, call: o["call"] as? Int
        )
    }

    private struct H {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        mutating func add(_ v: Int64) { h = (h ^ UInt64(bitPattern: v)) &* 0x100_0000_01b3 }
        mutating func d(_ x: Double) { add(Int64(bitPattern: x.bitPattern)) }
        mutating func f(_ x: Float) { add(Int64(Int32(bitPattern: x.bitPattern))) }
        mutating func i(_ x: Int) { add(Int64(x)) }
        var hex: String { String(h, radix: 16) }
    }

    private func scattered(_ seed: Int64, _ game: PoolVariant = .EIGHT, _ size: PoolTableSize = .BAR) -> PoolTableState {
        var t = PoolTableState.create(game, PoolOptions(tableSize: size), 2, 0, 1)
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

    private func check(_ what: String, _ expected: Any?, _ actual: String, _ failures: inout [String]) {
        let e = canon(expected)
        if e != actual { failures.append("\(what):\n  android \(e.prefix(300))\n  ios     \(actual.prefix(300))") }
    }

    private func report(_ failures: [String], file: StaticString = #filePath, line: UInt = #line) {
        if !failures.isEmpty {
            XCTFail("\(failures.count) mismatches:\n" + failures.prefix(12).joined(separator: "\n"), file: file, line: line)
        }
    }

    func testGoldenLoaded() {
        XCTAssertFalse(g.isEmpty, "pool_golden.json not found")
    }

    // MARK: Random, orientations, geometry, racks

    // MARK: StrictMath (fdlibm), the JVM functions the engine relies on

    func testStrictMath() {
        var failures: [String] = []
        let rows = g["strictMath"] as? [[Any]] ?? []
        XCTAssertEqual(3000, rows.count)
        for (k, row) in rows.enumerated() {
            let x = bits(row[0]), y = bits(row[1]), p = bits(row[2])
            let mine = [PoolStrictMath.sin(x), PoolStrictMath.cos(x), PoolStrictMath.atan2(y, x), PoolStrictMath.acos(p * 2 - 1),
                        PoolStrictMath.log(p + 1e-12), PoolStrictMath.pow(p, 1.6), PoolStrictMath.pow(p * 3, 1 / 1.6)]
            let names = ["sin", "cos", "atan2", "acos", "log", "pow", "pow2"]
            for (i, v) in mine.enumerated() where hx(v) != (row[3 + i] as! String) {
                failures.append("\(names[i]) #\(k) x=\(x) y=\(y) p=\(p): android \(row[3 + i]) ios \(hx(v))")
            }
        }
        report(failures)
    }

    func testRandom() {
        var failures: [String] = []
        for case let o as [String: Any] in g["random"] as? [Any] ?? [] {
            let seed = (o["seed"] as! NSNumber).int64Value
            let r = PoolRandom(seed)
            let next = (0..<6).map { _ in S(String(UInt64(bitPattern: r.next()), radix: 16)) }
            check("next \(seed)", o["next"], A(next), &failures)
            check("unit \(seed)", o["unit"], A((0..<4).map { _ in D(r.unit()) }), &failures)
            check("normal \(seed)", o["normal"], A((0..<4).map { _ in D(r.normal()) }), &failures)
            check("below \(seed)", o["below"], ints((0..<8).map { _ in r.nextBelow(13) }), &failures)
            check("shuffled \(seed)", o["shuffled"], ints(r.shuffled(Array(0...14))), &failures)
        }
        report(failures)
    }

    func testQuaternions() {
        var failures: [String] = []
        let starts = (0...15).map { n -> String in let q = PoolQuat.start(n); return A([D(q.x), D(q.y), D(q.z), D(q.w)]) }
        check("quatStart", g["quatStart"], A(starts), &failures)
        var h = H()
        var q = PoolQuat.start(3)
        for _ in 0..<500 { q = PoolQuat.roll(q, 0.7, -0.3); h.d(q.x); h.d(q.y); h.d(q.z); h.d(q.w) }
        check("rollHash", g["rollHash"], S(h.hex), &failures)
        report(failures)
    }

    func testGeometry() {
        var failures: [String] = []
        let list = g["geometry"] as? [[String: Any]] ?? []
        XCTAssertEqual(2, list.count)
        for (o, geo) in zip(list, [PoolTableGeometry.bar, PoolTableGeometry.pro]) {
            check("size", o["size"], S(geo.size.rawValue), &failures)
            check("cornerMouth", o["cornerMouth"], D(geo.cornerMouth), &failures)
            check("sideMouth", o["sideMouth"], D(geo.sideMouth), &failures)
            check("cushions", o["cushions"], A(geo.cushions.map { A([D($0.px), D($0.py), D($0.qx), D($0.qy), B($0.jaw)]) }), &failures)
            check("pockets", o["pockets"], A(geo.pockets.map { A([D($0.c.x), D($0.c.y), D($0.r), B($0.corner)]) }), &failures)
            check("aims", o["aims"], A(geo.aimPoints.map { V($0) }), &failures)
        }
        report(failures)
    }

    func testRacks() {
        var failures: [String] = []
        let racks = g["racks"] as? [[String: Any]] ?? []
        XCTAssertEqual(160, racks.count)
        for o in racks {
            let size = PoolTableSize(rawValue: o["size"] as! String)!
            let game = PoolVariant(rawValue: o["game"] as! String)!
            let seed = (o["seed"] as! NSNumber).int64Value
            let geo = PoolTableGeometry.of(size)
            let balls = game == .EIGHT ? PoolRack.eight(geo, seed) : PoolRack.nine(geo, seed)
            var h = H()
            for b in balls { h.i(b.n); h.d(b.x); h.d(b.y) }
            check("rack \(size) \(game) \(seed) numbers", o["numbers"], ints(balls.map { $0.n }), &failures)
            check("rack \(size) \(game) \(seed) hash", o["hash"], S(h.hex), &failures)
            if o["positions"] != nil { check("rack \(size) \(game) \(seed) positions", o["positions"], A(balls.map { V($0.p) }), &failures) }
        }
        report(failures)
    }

    // MARK: Physics traces, rules outcomes and rolled orientations

    private func goldenCases() -> [(String, PoolTableState, PoolShot)] {
        var list: [(String, PoolTableState, PoolShot)] = []
        for game in PoolVariant.allCases {
            for size in PoolTableSize.allCases {
                for seed in Int64(1)...3 {
                    let t = PoolTableState.create(game, PoolOptions(tableSize: size), 2, 0, seed)
                    let geo = t.geometry
                    let cue = t.cue.p
                    let straight = PoolStrictMath.atan2(geo.footSpot.y - cue.y, geo.footSpot.x - cue.x)
                    list.append(("break-\(game)-\(size)-\(seed)-straight", t, PoolShot(straight, 1.0)))
                    list.append(("break-\(game)-\(size)-\(seed)-spin", t, PoolShot(straight + 0.004, 0.62, Vec2(0.2, -0.3))))
                    list.append(("break-\(game)-\(size)-\(seed)-bot", t, PoolBot.plan(t, .HARD, seed * 31).shot))
                    list.append(("break-\(game)-\(size)-\(seed)-easy", t, PoolBot.plan(t, .EASY, seed * 17 + 5).shot))
                }
            }
        }
        for seed in Int64(1)...10 {
            var t = scattered(seed, seed % 3 == 0 ? .NINE : .EIGHT, seed % 4 == 0 ? .PRO : .BAR)
            if seed % 2 == 0 { t.ballInHand = true }
            for (ordinal, level) in PoolDifficulty.allCases.enumerated() {
                list.append(("scatter-\(seed)-\(level)", t, PoolBot.plan(t, level, seed * 7 + Int64(ordinal)).shot))
            }
            let s = Double(seed)
            list.append(("scatter-\(seed)-manual", t, PoolShot(s * 0.61, 0.15 + s * 0.08, Vec2(-0.25 + s * 0.05, 0.4 - s * 0.07))))
        }
        return list
    }

    private func tableCanonCheck(_ name: String, _ o: [String: Any], _ t: PoolTableState, _ failures: inout [String]) {
        check("\(name) after.game", o["game"], S(t.game.rawValue), &failures)
        check("\(name) after.size", o["size"], S(t.size.rawValue), &failures)
        check("\(name) after.seats", o["seats"], I(t.seats), &failures)
        check("\(name) after.turn", o["turn"], I(t.turn), &failures)
        check("\(name) after.broken", o["broken"], B(t.broken), &failures)
        check("\(name) after.ballInHand", o["ballInHand"], B(t.ballInHand), &failures)
        check("\(name) after.kitchenOnly", o["kitchenOnly"], B(t.kitchenOnly), &failures)
        check("\(name) after.groups", o["groups"], A(t.groups.map { $0.map { S($0.rawValue) } ?? "null" }), &failures)
        check("\(name) after.winner", o["winner"], N(t.winner), &failures)
        check("\(name) after.foulStreak", o["foulStreak"], ints(t.foulStreak), &failures)
        check("\(name) after.shots", o["shots"], I(t.shots), &failures)
        check("\(name) after.streak", o["streak"], I(t.streak), &failures)
        check("\(name) after.breakVisit", o["breakVisit"], B(t.breakVisit), &failures)
        check("\(name) after.stats", o["stats"], A(t.stats.map { ints([$0.potted, $0.fouls, $0.bestRun, $0.breakAndRuns, $0.shots]) }), &failures)
        check("\(name) after.balls", o["balls"], ballsCanon(t.balls), &failures)
    }

    func testPhysicsCases() {
        var failures: [String] = []
        let cases = g["cases"] as? [[String: Any]] ?? []
        let mine = goldenCases()
        XCTAssertEqual(cases.count, mine.count)
        for (o, (name, table, myShot)) in zip(cases, mine) {
            check("name", o["name"], S(name), &failures)
            check("\(name) shot", o["shot"], shotCanon(myShot), &failures)
            // Simulate the Android shot, so the physics is checked even if a plan differs.
            let shot = shotFrom(o["shot"])
            let prepared = PoolSession.prepare(table, shot, table.balls.map { PoolQuat.start($0.n) })
            let balls = prepared.balls
            let run = prepared.run
            var ev = H()
            for e in run.events {
                let kind: Int
                switch e.kind {
                case .Hit: kind = 0
                case .Cushion: kind = 1
                case .Jaw: kind = 2
                case .Pocket: kind = 3
                }
                ev.i(kind); ev.d(e.time); ev.d(e.strength); ev.i(e.ball); ev.i(e.other); ev.d(e.at.x); ev.d(e.at.y); ev.i(e.pocket)
            }
            var fr = H()
            for f in run.frames { for v in f { fr.f(v) } }
            var tq = H()
            for row in prepared.turns { for v in row { tq.f(v) } }
            check("\(name) balls", o["balls"], ballsCanon(balls), &failures)
            check("\(name) potted", o["potted"], A(run.potted.map { A([I($0.ball), I($0.pocket), D($0.time)]) }), &failures)
            check("\(name) firstHit", o["firstHit"], N(run.firstHit), &failures)
            check("\(name) rail", o["rail"], B(run.railAfterContact), &failures)
            check("\(name) cushionBalls", o["cushionBalls"], ints(run.cushionBalls.sorted()), &failures)
            check("\(name) duration", o["duration"], D(run.duration), &failures)
            check("\(name) events", o["events"], I(run.events.count), &failures)
            check("\(name) eventsHash", o["eventsHash"], S(ev.hex), &failures)
            check("\(name) frames", o["frames"], I(run.frames.count), &failures)
            check("\(name) framesHash", o["framesHash"], S(fr.hex), &failures)
            check("\(name) turnsHash", o["turnsHash"], S(tq.hex), &failures)
            check("\(name) finalQuats", o["finalQuats"], A(prepared.rested.map { A([D($0.x), D($0.y), D($0.z), D($0.w)]) }), &failures)
            var after = table.clone()
            let legal = after.legalFirst()
            let s = after.apply(balls, run, shot, legal)
            let st = o["stroke"] as? [String: Any] ?? [:]
            check("\(name) stroke.seat", st["seat"], I(s.seat), &failures)
            check("\(name) stroke.potted", st["potted"], ints(s.potted), &failures)
            check("\(name) stroke.foul", st["foul"], B(s.foul), &failures)
            check("\(name) stroke.why", st["why"], S(s.why), &failures)
            check("\(name) stroke.continues", st["continues"], B(s.continues), &failures)
            check("\(name) stroke.rackOver", st["rackOver"], B(s.rackOver), &failures)
            check("\(name) stroke.won", st["won"], B(s.won), &failures)
            check("\(name) stroke.groupsSet", st["groupsSet"], s.groupsSet.map { S($0.rawValue) } ?? "null", &failures)
            check("\(name) stroke.respotted", st["respotted"], N(s.respotted), &failures)
            check("\(name) stroke.scratch", st["scratch"], B(s.scratch), &failures)
            tableCanonCheck(name, o["after"] as? [String: Any] ?? [:], after, &failures)
        }
        report(failures)
    }

    // MARK: Computers, guide, spots, matches

    func testPlans() {
        var failures: [String] = []
        let plans = g["plans"] as? [[String: Any]] ?? []
        var k = 0
        for seed in Int64(1)...8 {
            var t = scattered(seed + 100, seed % 3 == 0 ? .NINE : .EIGHT)
            if seed % 2 == 0 { t.ballInHand = true }
            let cand = PoolBot.candidates(t)
            var ch = H()
            for c in cand { ch.d(c.score); ch.d(c.shot.angle); ch.d(c.shot.power); ch.i(c.target); ch.i(c.pocket) }
            for (ordinal, level) in PoolDifficulty.allCases.enumerated() {
                guard k < plans.count else { break }
                let o = plans[k]
                k += 1
                let p = PoolBot.plan(t, level, seed * 13 + Int64(ordinal))
                let name = "plan \(seed) \(level)"
                check("\(name) candidates", o["candidates"], I(cand.count), &failures)
                check("\(name) candidatesHash", o["candidatesHash"], S(ch.hex), &failures)
                check("\(name) shot", o["shot"], shotCanon(p.shot), &failures)
                check("\(name) target", o["target"], I(p.target), &failures)
                check("\(name) pocket", o["pocket"], I(p.pocket), &failures)
                check("\(name) ghost", o["ghost"], V(p.ghost), &failures)
                check("\(name) score", o["score"], D(p.score), &failures)
                check("\(name) leave", o["leave"], I(PoolBot.leave(t)), &failures)
            }
        }
        XCTAssertEqual(plans.count, k)
        report(failures)
    }

    func testGuides() {
        var failures: [String] = []
        let guides = g["guides"] as? [[String: Any]] ?? []
        var k = 0
        for seed in Int64(1)...4 {
            let t = scattered(seed + 200)
            let legal = t.legalFirst()
            for step in 0..<9 {
                for style in PoolAimGuide.allCases {
                    guard k < guides.count else { break }
                    let o = guides[k]
                    k += 1
                    let r = PoolGuide.compute(t, t.cue.p, Double(step) * 0.7, Vec2(0.0, 0.3), style, legal)
                    let name = "guide \(seed) \(step) \(style)"
                    check("\(name) end", o["end"], V(r.end), &failures)
                    check("\(name) ghost", o["ghost"], V(r.ghost), &failures)
                    check("\(name) target", o["target"], N(r.target), &failures)
                    check("\(name) legal", o["legal"], B(r.legal), &failures)
                    check("\(name) objectEnd", o["objectEnd"], V(r.objectEnd), &failures)
                    check("\(name) cueEnd", o["cueEnd"], V(r.cueEnd), &failures)
                    check("\(name) pocket", o["pocket"], N(r.pocket), &failures)
                }
            }
        }
        XCTAssertEqual(guides.count, k)
        report(failures)
    }

    func testFreeSpots() {
        var failures: [String] = []
        let spots = g["freeSpots"] as? [[String: Any]] ?? []
        var k = 0
        for seed in Int64(1)...3 {
            var t = scattered(seed + 300)
            t.ballInHand = true
            for step in 0..<6 {
                guard k < spots.count else { break }
                let p = t.balls[step + 1].p + Vec2(0.3 * Double(step), -0.2 * Double(step))
                t.kitchenOnly = step % 2 == 0
                check("spot \(seed) \(step)", spots[k]["spot"], V(t.freeSpot(p)), &failures)
                k += 1
            }
        }
        XCTAssertEqual(spots.count, k)
        report(failures)
    }

    func testMatchSeedsAndMinutes() {
        var failures: [String] = []
        var m = PoolMatch.create(PoolOptions(), 2, 0, 987_654_321)
        var seeds: [String] = []
        for i in 0..<6 {
            m.table.winner = i % 2
            _ = m.finishRack()
            m.nextRack()
            seeds.append(S(String(m.seed)))
        }
        check("matchSeeds", g["matchSeeds"], A(seeds), &failures)
        var mins: [Int] = []
        for seats in 2...4 {
            for people in 1...seats {
                for len in PoolMatchLength.allCases {
                    for fast in [false, true] {
                        mins.append(PoolStore.estimatedMinutes(seats, people, PoolOptions(length: len, fastBots: fast)))
                    }
                }
            }
        }
        check("minutes", g["minutes"], ints(mins), &failures)
        report(failures)
    }
}
