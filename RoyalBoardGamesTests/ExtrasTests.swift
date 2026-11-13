import XCTest
import GameKit
@testable import RoyalBoardGames

/// The iOS extras: Pool and Carrom practice rules, chess undo against the computer and PGN export.
final class PoolPracticeTests: XCTestCase {
    private func practiceTable(_ game: PoolVariant = .EIGHT) -> PoolTableState {
        var t = PoolTableState.create(game, PoolOptions(game: game, callEight: false), 1, 0, 7)
        t.practice = true
        return t
    }

    /// Applies a shot that hit [first] and pocketed [pot] (numbers), without physics.
    @discardableResult
    private func stroke(_ t: inout PoolTableState, _ first: Int?, _ pot: [Int], rail: Bool = true) -> PoolStroke {
        let legal = t.legalFirst()
        var balls = t.balls
        let run = PoolPhysics.Run()
        run.firstHit = first
        run.railAfterContact = rail
        for n in pot {
            guard let i = balls.firstIndex(where: { $0.n == n && $0.live }) else { continue }
            balls[i].live = false
            run.potted.append(PoolPhysics.Potted(i, 0, 0.0))
        }
        return t.apply(balls, run, PoolShot(0.0, 0.5), legal)
    }

    func testAnyBallMayBeHitFirstIncludingTheEight() {
        let t = practiceTable()
        XCTAssertEqual(t.legalFirst().sorted(), Array(1...15))
        XCTAssertEqual(practiceTable(.NINE).legalFirst().sorted(), Array(1...9))
    }

    func testNoFoulsTurnsOrRackEndings() {
        var t = practiceTable()
        // A weak "break" that hits nothing: a foul at a real table, nothing here.
        var s = stroke(&t, nil, [])
        XCTAssertFalse(s.foul)
        XCTAssertTrue(s.continues)
        XCTAssertFalse(t.ballInHand)
        // The 8 early and a ball without a cushion: still no foul, no winner, same shooter.
        s = stroke(&t, 8, [8, 3], rail: false)
        XCTAssertFalse(s.foul)
        XCTAssertFalse(s.rackOver)
        XCTAssertNil(t.winner)
        XCTAssertEqual(t.turn, 0)
        XCTAssertEqual(s.potted, [8, 3])
        XCTAssertNil(t.ball(8))
        XCTAssertNil(t.groups[0])
        XCTAssertEqual(t.shots, 2)
        XCTAssertEqual(t.stats[0].fouls, 0)
        XCTAssertEqual(PoolPractice.left(t), 13)
    }

    func testScratchBringsTheCueBallBackInHandAnywhere() {
        var t = practiceTable()
        let s = stroke(&t, 5, [0])
        XCTAssertTrue(s.scratch)
        XCTAssertFalse(s.foul)
        XCTAssertTrue(t.cue.live)
        XCTAssertTrue(t.ballInHand)
        XCTAssertFalse(t.kitchenOnly)
        XCTAssertTrue(t.free(t.cue.p))
        XCTAssertEqual(t.stats[0].fouls, 0)
        XCTAssertEqual(t.foulStreak[0], 0)
    }

    func testNineGoingDownDoesNotWin() {
        var t = practiceTable(.NINE)
        let s = stroke(&t, 4, [9])
        XCTAssertFalse(s.won)
        XCTAssertFalse(s.rackOver)
        XCTAssertNil(t.winner)
        XCTAssertNil(t.ball(9))
    }

    func testClearingAndReRacking() {
        var m = PoolMatch.create(PoolOptions(game: .EIGHT), 1, 0, 11)
        m.table.practice = true
        stroke(&m.table, 1, Array(1...15))
        XCTAssertEqual(PoolPractice.left(m.table), 0)
        XCTAssertNil(m.table.winner)
        let fresh = PoolPractice.rerack(m)
        XCTAssertTrue(fresh.table.practice)
        XCTAssertEqual(PoolPractice.left(fresh.table), 15)
        XCTAssertEqual(fresh.table.shots, 0)
        XCTAssertFalse(fresh.table.broken)
        XCTAssertTrue(fresh.table.ballInHand)
        XCTAssertEqual(fresh.rack, m.rack + 1)
        XCTAssertNotEqual(fresh.seed, m.seed)
        XCTAssertNil(fresh.winner)
    }

    func testPracticeConfigIsOnePersonWithoutClockOrCalls() throws {
        let player = PartyPlayer(id: "p", name: "Raj", avatar: "🦊", colorIndex: 2)
        let options = PoolOptions(game: .NINE, length: .RACE_TO_5, callEight: true, threeFouls: true, shotClock: 30)
        let c = PoolPractice.config(PoolSeat(player, isBot: true), options, .NINE, 3, 4)
        XCTAssertTrue(c.practice)
        XCTAssertEqual(c.seats.count, 1)
        XCTAssertFalse(c.seats[0].isBot)
        XCTAssertEqual(c.options.game, .NINE)
        XCTAssertEqual(c.options.shotClock, 0)
        XCTAssertFalse(c.options.callEight)
        XCTAssertFalse(c.options.threeFouls)
        XCTAssertEqual(c.options.length, .ONE)
        XCTAssertEqual(c.tableID, 3)
        XCTAssertEqual(c.cueID, 4)
        XCTAssertTrue(c.copy(resume: true).practice)
        let back = try JSONDecoder().decode(PoolConfig.self, from: JSONEncoder().encode(c))
        XCTAssertTrue(back.practice)
        // Older saves without the field still decode as a normal match.
        let old = try JSONDecoder().decode(PoolConfig.self, from: Data("{\"seats\":[]}".utf8))
        XCTAssertFalse(old.practice)
    }

    @MainActor
    func testPracticeSessionNeverTouchesTheSavedMatch() {
        let backup = PoolStore.saved
        defer { PoolStore.saved = backup }
        PoolStore.saved = nil
        let player = PartyPlayer(id: "p", name: "Raj", avatar: "🦊", colorIndex: 0)
        let s = PoolSession(config: PoolPractice.config(PoolSeat(player), PoolOptions(), .EIGHT, 0, 0))
        XCTAssertTrue(s.table.practice)
        s.save()
        XCTAssertNil(PoolStore.saved)
        XCTAssertFalse(s.canReplay)
        s.dispose()
    }
}

final class CarromPracticeTests: XCTestCase {
    private func practiceTable(_ mode: CarromMode = .CLASSIC) -> CarromTable {
        let m = CarromMatch.create(CarromOptions(mode: mode), 1, 0)
        return CarromPractice.rack(m)
    }

    @discardableResult
    private func stroke(_ table: CarromTable, _ pocket: [CarromKind], striker: Bool = false) -> CarromStroke {
        var discs = table.coins.cloned()
        discs.append(CarromDisc(.STRIKER, table.strikerSpot(0.0)))
        let si = discs.count - 1
        let run = CarromPhysics.Run()
        for kind in pocket {
            guard let i = discs.indices.first(where: { discs[$0].live && discs[$0].kind == kind }) else { continue }
            discs[i].live = false
            run.pocketed.append(CarromPhysics.Pocketed(i, 0, 0.0))
        }
        if striker {
            discs[si].live = false
            run.pocketed.append(CarromPhysics.Pocketed(si, 1, 0.1))
        }
        return table.apply(discs, run, si)
    }

    func testEveryCoinIsATargetIncludingTheQueen() {
        let t = practiceTable()
        XCTAssertTrue(t.practice)
        XCTAssertEqual(t.targets().count, t.coins.count)
        XCTAssertTrue(t.targets().contains { t.coins[$0].kind == .QUEEN })
        XCTAssertFalse(practiceTable(.POOL).coins.contains { $0.kind == .QUEEN })
    }

    func testStrikerInThePocketIsNoFoulAndNothingComesBack() {
        let t = practiceTable()
        stroke(t, [.WHITE, .BLACK])
        let s = stroke(t, [.QUEEN], striker: true)
        XCTAssertFalse(s.foul)
        XCTAssertTrue(s.continues)
        XCTAssertEqual(s.pocketed, [.QUEEN])
        XCTAssertTrue(s.returned.isEmpty)
        XCTAssertEqual(t.pocketed(.WHITE), 1)
        XCTAssertEqual(t.pocketed(.BLACK), 1)
        XCTAssertFalse(t.queenOnBoard)
        XCTAssertNil(t.queenWaiting)
        XCTAssertEqual(t.turn, 0)
        XCTAssertEqual(t.owed, [0, 0])
        XCTAssertEqual(t.points, [0, 0])
        XCTAssertEqual(t.strokes, 2)
    }

    func testClearingTheBoardNeverEndsIt() {
        let t = practiceTable(.FREESTYLE)
        let all = t.coins.map(\.kind)
        let s = stroke(t, all)
        XCTAssertEqual(CarromPractice.left(t), 0)
        XCTAssertNil(t.winner)
        XCTAssertFalse(s.boardOver)
        XCTAssertEqual(s.points, 0)
        XCTAssertEqual(t.points, [0, 0])
    }

    func testCopiesStayPracticeAndRackIsFresh() {
        let m = CarromMatch.create(CarromOptions(mode: .CLASSIC), 1, 0)
        m.table = CarromPractice.rack(m)
        stroke(m.table, [.WHITE, .WHITE])
        XCTAssertTrue(m.table.deepCopy().practice)
        XCTAssertTrue(m.deepCopy().table.practice)
        let fresh = CarromPractice.rack(m)
        XCTAssertEqual(CarromPractice.left(fresh), CarromBoard.rack(true).count)
        XCTAssertEqual(fresh.strokes, 0)
        XCTAssertFalse(fresh.broken)
        XCTAssertTrue(fresh.practice)
    }

    func testPracticeConfigIsOnePersonAtTheBottom() throws {
        let player = PartyPlayer(id: "p", name: "Raj", avatar: "🦊", colorIndex: 2)
        let options = CarromOptions(mode: .POOL, length: .RACE25, tournament: true, shotClock: 20, turnBoard: true)
        let c = CarromPractice.config(CarromSeat(player, 2, isBot: true), options, 1, 2, 3)
        XCTAssertTrue(c.practice)
        XCTAssertEqual(c.seats.count, 1)
        XCTAssertEqual(c.seats[0].side, 0)
        XCTAssertFalse(c.seats[0].isBot)
        XCTAssertEqual(c.options.mode, .POOL)
        XCTAssertEqual(c.options.clockSeconds, 0)
        XCTAssertFalse(c.options.tournament)
        XCTAssertEqual(c.options.length, .ONE)
        XCTAssertTrue(c.copy(resume: true).practice)
        let back = try JSONDecoder().decode(CarromConfig.self, from: JSONEncoder().encode(c))
        XCTAssertTrue(back.practice)
    }

    @MainActor
    func testPracticeSessionNeverTouchesTheSavedMatch() {
        let backup = CarromStore.saved
        defer { CarromStore.saved = backup }
        CarromStore.saved = nil
        let player = PartyPlayer(id: "p", name: "Raj", avatar: "🦊", colorIndex: 0)
        let s = CarromSession(CarromPractice.config(CarromSeat(player), CarromOptions(), 0, 0, 0))
        XCTAssertTrue(s.table.practice)
        XCTAssertEqual(s.currentSeat.player.name, "Raj")
        s.save()
        XCTAssertNil(CarromStore.saved)
        s.dispose()
    }
}

final class ChessExtrasTests: XCTestCase {
    private func sq(_ name: String) -> Int { ChessSquare.parse(name)! }

    private func play(_ moves: [String]) -> ChessMatch {
        var m = ChessMatch()
        for uci in moves {
            let from = sq(String(uci.prefix(2)))
            let to = sq(String(uci.dropFirst(2).prefix(2)))
            XCTAssertNotNil(m.play(from, to), uci)
        }
        return m
    }

    // MARK: Undo

    func testUndoPliesAgainstTheComputer() {
        XCTAssertEqual(ChessUndo.plies(ChessMatch(), .WHITE), 0)
        // The person (White) moved and the computer is thinking: just their move.
        XCTAssertEqual(ChessUndo.plies(play(["e2e4"]), .WHITE), 1)
        // The computer replied: both.
        XCTAssertEqual(ChessUndo.plies(play(["e2e4", "e7e5"]), .WHITE), 2)
        // The person is Black and only the computer has moved: nothing to take back.
        XCTAssertEqual(ChessUndo.plies(play(["e2e4"]), .BLACK), 0)
        XCTAssertEqual(ChessUndo.plies(play(["e2e4", "e7e5"]), .BLACK), 1)
        XCTAssertEqual(ChessUndo.plies(play(["e2e4", "e7e5", "g1f3"]), .BLACK), 2)
        // A finished game stays finished.
        XCTAssertEqual(ChessUndo.plies(play(["f2f3", "e7e5", "g2g4", "d8h4"]), .WHITE), 0)
    }

    func testRewoundReplaysExactly() {
        let m = play(["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"])
        let back = ChessUndo.rewound(m, 2)
        XCTAssertEqual(back.sanMoves, ["e4", "e5", "Nf3"])
        XCTAssertEqual(back.position, play(["e2e4", "e7e5", "g1f3"]).position)
        XCTAssertEqual(ChessUndo.rewound(m, 5).position, ChessPosition.start)
        XCTAssertEqual(ChessUndo.rewound(m, 9).moves.count, 0)
        XCTAssertNil(back.result)
    }

    func testRewoundKeepsRepetitionCounts() {
        // Knights out and back twice: the start position has appeared three times.
        let shuffle = ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"]
        let m = play(shuffle + ["e2e4"])
        XCTAssertFalse(m.canClaimThreefold)
        XCTAssertTrue(ChessUndo.rewound(m, 1).canClaimThreefold)
    }

    @MainActor
    func testSessionUndoTakesBackTheMoveAndTheReply() async throws {
        let backup = Prefs.load(ChessGame.SAVE_KEY, as: ChessSaved.self)
        defer { if let backup { Prefs.save(ChessGame.SAVE_KEY, backup) } else { Prefs.remove(ChessGame.SAVE_KEY) } }
        let config = ChessConfig(white: PartyPlayer(id: "w", name: "Raj", avatar: "🦊", colorIndex: 0),
                                 black: PartyPlayer(id: "b", name: "CPU Leo", avatar: "🤖", colorIndex: 1),
                                 blackIsBot: true, botLevel: 0)
        let s = ChessSession(config)
        XCTAssertFalse(s.canUndo)
        s.start()
        s.tap(sq("e2"))
        s.tap(sq("e4"))
        XCTAssertEqual(s.moveCount, 1)
        // Wait for the computer's reply.
        for _ in 0..<100 where s.moveCount < 2 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(s.moveCount, 2)
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertEqual(s.moveCount, 0)
        XCTAssertEqual(s.position, ChessPosition.start)
        XCTAssertEqual(s.sideToMove, .WHITE)
        XCTAssertFalse(s.botThinking)
        XCTAssertNil(s.hint)
        XCTAssertEqual(s.pieces.count, 32)
        for p in s.pieces { XCTAssertEqual(s.position.board[p.square], p.piece) }
        XCTAssertFalse(s.canUndo)
        // While the computer thinks, undo takes back only the person's move and cancels the reply.
        s.tap(sq("d2"))
        s.tap(sq("d4"))
        XCTAssertTrue(s.botThinking)
        s.undo()
        XCTAssertEqual(s.moveCount, 0)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(s.moveCount, 0)
        XCTAssertEqual(s.sideToMove, .WHITE)
        s.dispose()
    }

    @MainActor
    func testNoUndoBetweenTwoPeople() {
        let backup = Prefs.load(ChessGame.SAVE_KEY, as: ChessSaved.self)
        defer { if let backup { Prefs.save(ChessGame.SAVE_KEY, backup) } else { Prefs.remove(ChessGame.SAVE_KEY) } }
        let config = ChessConfig(white: PartyPlayer(id: "w", name: "Raj", avatar: "🦊", colorIndex: 0),
                                 black: PartyPlayer(id: "b", name: "Mia", avatar: "🐼", colorIndex: 1))
        let s = ChessSession(config)
        s.tap(sq("e2"))
        s.tap(sq("e4"))
        XCTAssertFalse(s.canUndo)
        s.undo()
        XCTAssertEqual(s.moveCount, 1)
        s.dispose()
    }

    // MARK: PGN

    private var day: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 8; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testFoolsMateExport() {
        let m = play(["f2f3", "e7e5", "g2g4", "d8h4"])
        XCTAssertEqual(ChessPGN.movetext(m), "1. f3 e5 2. g4 Qh4# 0-1")
        let pgn = ChessPGN.export(m, white: "Raj", black: "CPU Leo", date: day)
        XCTAssertEqual(pgn, """
        [Event "Casual game"]
        [Site "Board Games: Royal Club"]
        [Date "2026.11.08"]
        [Round "-"]
        [White "Raj"]
        [Black "CPU Leo"]
        [Result "0-1"]

        1. f3 e5 2. g4 Qh4# 0-1

        """)
    }

    func testResultsAndUnfinishedGames() {
        XCTAssertEqual(ChessPGN.movetext(ChessMatch()), "*")
        XCTAssertEqual(ChessPGN.movetext(play(["e2e4"])), "1. e4 *")
        var draw = play(["e2e4", "e7e5"])
        draw.agreeDraw()
        XCTAssertEqual(ChessPGN.movetext(draw), "1. e4 e5 1/2-1/2")
        var resigned = play(["e2e4"])
        resigned.resign(.BLACK)
        XCTAssertEqual(ChessPGN.result(resigned.result), "1-0")
        XCTAssertTrue(ChessPGN.export(resigned, white: "A", black: "B", date: day).contains("[Result \"1-0\"]"))
    }

    func testTagValuesAreEscaped() {
        let pgn = ChessPGN.export(ChessMatch(), white: "Raj \"The Rook\"", black: "C:\\bot", date: day)
        XCTAssertTrue(pgn.contains("[White \"Raj \\\"The Rook\\\"\"]"))
        XCTAssertTrue(pgn.contains("[Black \"C:\\\\bot\"]"))
    }

    func testLongGamesWrapAtEightyColumns() {
        let shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]
        let m = play(["e2e4", "e7e5"] + shuffle + shuffle + shuffle + ["d2d4", "d7d5", "c2c4", "c7c6", "b1c3", "b8d7", "c1g5", "f8b4"])
        let text = ChessPGN.movetext(m)
        let lines = text.split(separator: "\n")
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines { XCTAssertLessThanOrEqual(line.count, 80) }
        // Joining the lines gives back the single-line move text.
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        XCTAssertEqual(tokens.last, "*")
        XCTAssertEqual(tokens.filter { $0.hasSuffix(".") }.count, (m.sanMoves.count + 1) / 2)
        XCTAssertEqual(tokens.count, m.sanMoves.count + (m.sanMoves.count + 1) / 2 + 1)
    }
}
