import XCTest
import GameKit
@testable import RoyalBoardGames

// 1:1 port of app/src/test/.../game/chess/ChessEngineTest.kt (ChessPerftTest, ChessRuleTest, ChessBotTest).

/// Plays moves like "e2e4", "a7a8q"; fails on any illegal move.
private func play(_ match: inout ChessMatch, _ moves: [String], file: StaticString = #filePath, line: UInt = #line) {
    for text in moves {
        let from = ChessSquare.parse(String(text.prefix(2)))!
        let to = ChessSquare.parse(String(text.dropFirst(2).prefix(2)))!
        let promotions: [Character: PieceKind] = ["q": .QUEEN, "r": .ROOK, "b": .BISHOP, "n": .KNIGHT]
        let promotion: PieceKind? = text.count == 5 ? promotions[text.last!] : nil
        XCTAssertNotNil(match.play(from, to, promotion), "illegal move \(text)", file: file, line: line)
    }
}

private func square(_ name: String) -> Int { ChessSquare.parse(name)! }
private func pos(_ fen: String) -> ChessPosition { ChessPosition.fromFen(fen)! }

final class ChessPerftTests: XCTestCase {
    // Reference node counts from the Chess Programming Wiki perft suites.
    func testStart() {
        for (depth, nodes) in [(1, 20), (2, 400), (3, 8_902)] { XCTAssertEqual(nodes, ChessPosition.start.perft(depth)) }
    }

    func testKiwipete() {
        let p = pos("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        for (depth, nodes) in [(1, 48), (2, 2_039)] { XCTAssertEqual(nodes, p.perft(depth)) }
    }

    func testPosition3() {
        let p = pos("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        for (depth, nodes) in [(1, 14), (2, 191), (3, 2_812)] { XCTAssertEqual(nodes, p.perft(depth)) }
    }

    func testPosition4() {
        let p = pos("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
        for (depth, nodes) in [(1, 6), (2, 264)] { XCTAssertEqual(nodes, p.perft(depth)) }
    }

    func testPosition5() {
        let p = pos("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
        for (depth, nodes) in [(1, 44), (2, 1_486)] { XCTAssertEqual(nodes, p.perft(depth)) }
    }

    func testFenRoundTrip() {
        for fen in [ChessPosition.START_FEN, "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1"] {
            XCTAssertEqual(fen, ChessPosition.fromFen(fen)?.fen)
        }
    }
}

final class ChessRuleTests: XCTestCase {
    func testRejectsIllegalMoves() {
        var match = ChessMatch()
        XCTAssertNil(match.play(square("e7"), square("e5")), "black can't move first")
        XCTAssertNil(match.play(square("e2"), square("e5")), "pawns can't jump three")
        XCTAssertNil(match.play(square("g1"), square("g3")), "knights move in an L")
        XCTAssertNil(match.play(square("e1"), square("e2")), "can't capture own piece")
        var pinned = ChessMatch(pos("4k3/4r3/8/8/8/8/4N3/4K3 w - - 0 1"))
        XCTAssertNil(pinned.play(square("e2"), square("c3")))
        var king = ChessMatch(pos("4k3/8/8/8/8/8/5r2/4K3 w - - 0 1"))
        XCTAssertNil(king.play(square("e1"), square("e2")))
        XCTAssertNotNil(king.play(square("e1"), square("d1")))
    }

    func testFoolsMateIsCheckmate() {
        var match = ChessMatch()
        play(&match, ["f2f3", "e7e5", "g2g4", "d8h4"])
        XCTAssertEqual(ChessResult.Checkmate(by: .BLACK), match.result)
        XCTAssertEqual("Qh4#", match.sanMoves.last)
        XCTAssertNil(match.play(square("a2"), square("a3")), "no moves after mate")
    }

    func testStalemateIsAutomaticDraw() {
        let match = ChessMatch(pos("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        XCTAssertEqual(ChessResult.Stalemate, match.result)
        XCTAssertNil(match.result?.winner)
    }

    func testCastlingBothSides() {
        var match = ChessMatch(pos("r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"))
        play(&match, ["e1g1"])
        XCTAssertEqual("O-O", match.sanMoves.last)
        XCTAssertEqual(ChessPiece(.ROOK, .WHITE), match.position.board[square("f1")])
        XCTAssertNil(match.position.board[square("h1")])
        play(&match, ["e8c8"])
        XCTAssertEqual("O-O-O", match.sanMoves.last)
        XCTAssertEqual(ChessPiece(.ROOK, .BLACK), match.position.board[square("d8")])
    }

    func testCastlingRules() {
        var attacked = ChessMatch(pos("r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1"))
        XCTAssertNil(attacked.play(square("e1"), square("g1")))
        XCTAssertNotNil(attacked.play(square("e1"), square("c1")))
        var inCheck = ChessMatch(pos("r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1"))
        XCTAssertNil(inCheck.play(square("e1"), square("g1")))
        var moved = ChessMatch(pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        play(&moved, ["e1e2", "a8a7", "e2e1", "a7a8"])
        XCTAssertNil(moved.play(square("e1"), square("g1")))
    }

    func testEnPassant() {
        var match = ChessMatch(pos("4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1"))
        play(&match, ["d7d5"])
        XCTAssertEqual(square("d6"), match.position.enPassant)
        play(&match, ["e5d6"])
        XCTAssertEqual("exd6", match.sanMoves.last)
        XCTAssertNil(match.position.board[square("d5")], "captured pawn removed")
        XCTAssertEqual(true, match.lastMove?.isEnPassant)
    }

    func testEnPassantOnlyImmediately() {
        var match = ChessMatch(pos("4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1"))
        play(&match, ["d7d5", "e1f1", "e8f8"])
        XCTAssertNil(match.play(square("e5"), square("d6")))
    }

    func testPromotionNeedsAChoice() {
        var match = ChessMatch(pos("8/P7/8/8/8/8/8/k6K w - - 0 1"))
        XCTAssertTrue(match.needsPromotion(square("a7"), square("a8")))
        XCTAssertNil(match.play(square("a7"), square("a8")), "promotion piece required")
        XCTAssertNotNil(match.play(square("a7"), square("a8"), .KNIGHT))
        XCTAssertEqual(ChessPiece(.KNIGHT, .WHITE), match.position.board[square("a8")])
        XCTAssertEqual("a8=N", match.sanMoves.last)
    }

    func testPromotionWithCheck() {
        var match = ChessMatch(pos("8/P7/8/8/8/8/8/k6K w - - 0 1"))
        play(&match, ["a7a8q"])
        XCTAssertEqual("a8=Q+", match.sanMoves.last)
    }

    func testSanDisambiguation() {
        var match = ChessMatch(pos("4k3/8/8/8/8/8/8/R4RK1 w - - 0 1"))
        play(&match, ["a1d1"])
        XCTAssertEqual("Rad1", match.sanMoves.last)
    }

    func testInsufficientMaterial() {
        XCTAssertEqual(ChessResult.InsufficientMaterial, ChessMatch(pos("4k3/8/8/8/8/8/8/4K3 w - - 0 1")).result)
        XCTAssertEqual(ChessResult.InsufficientMaterial, ChessMatch(pos("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1")).result)
        XCTAssertEqual(ChessResult.InsufficientMaterial, ChessMatch(pos("4k3/8/8/8/8/8/8/1N2K3 w - - 0 1")).result)
        XCTAssertEqual(ChessResult.InsufficientMaterial, ChessMatch(pos("2b1k3/8/8/8/8/8/8/4KB2 w - - 0 1")).result)
        XCTAssertNil(ChessMatch(pos("2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1")).result)
        XCTAssertNil(ChessMatch(pos("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")).result)
    }

    func testThreefoldIsClaimableFivefoldIsAutomatic() {
        var match = ChessMatch()
        let shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]
        play(&match, shuffle + shuffle)
        XCTAssertTrue(match.canClaimThreefold)
        XCTAssertFalse(match.isOver)
        var claimed = match.copy()
        claimed.claimDraw()
        XCTAssertEqual(ChessResult.ThreefoldRepetition, claimed.result)
        play(&match, shuffle + shuffle)
        XCTAssertEqual(ChessResult.FivefoldRepetition, match.result)
    }

    func testFiftyAndSeventyFiveMoveRules() {
        var fifty = ChessMatch(pos("4k3/8/8/8/8/8/4P3/R3K3 w - - 99 80"))
        play(&fifty, ["a1a2"])
        XCTAssertTrue(fifty.canClaimFiftyMoves)
        fifty.claimDraw()
        XCTAssertEqual(ChessResult.FiftyMoves, fifty.result)

        var seventyFive = ChessMatch(pos("4k3/8/8/8/8/8/4P3/R3K3 w - - 149 100"))
        play(&seventyFive, ["a1a2"])
        XCTAssertEqual(ChessResult.SeventyFiveMoves, seventyFive.result)

        var reset = ChessMatch(pos("4k3/8/8/8/8/8/4P3/R3K3 w - - 99 80"))
        play(&reset, ["e2e4"])
        XCTAssertFalse(reset.canClaimFiftyMoves, "pawn move resets the count")
    }

    func testResignationAgreementAndTimeouts() {
        var resign = ChessMatch()
        resign.resign(.WHITE)
        XCTAssertEqual(ChessResult.Resignation(by: .BLACK), resign.result)

        var agree = ChessMatch()
        agree.agreeDraw()
        XCTAssertEqual(ChessResult.Agreement, agree.result)

        var flag = ChessMatch(pos("4k3/8/8/8/8/8/8/q3K3 w - - 0 1"))
        flag.flag(.WHITE)
        XCTAssertEqual(ChessResult.Timeout(by: .BLACK), flag.result)

        var noMate = ChessMatch(pos("4k3/8/8/8/8/8/8/q3K3 b - - 0 1"))
        noMate.flag(.BLACK)
        XCTAssertEqual(ChessResult.TimeoutVsInsufficientMaterial, noMate.result, "a lone king can't win on time")
    }

    func testCapturedPiecesAndMaterial() {
        var match = ChessMatch()
        play(&match, ["e2e4", "d7d5", "e4d5", "d8d5"])
        XCTAssertEqual([PieceKind.PAWN], match.captured(.WHITE))
        XCTAssertEqual([PieceKind.PAWN], match.captured(.BLACK))
        XCTAssertEqual(0, match.materialBalance)
    }

    func testUciRoundTrip() {
        var match = ChessMatch(pos("8/P7/8/8/8/8/8/k6K w - - 0 1"))
        play(&match, ["a7a8q"])
        XCTAssertEqual("a7a8q", match.lastMove?.uci)
    }
}

final class ChessBotTests: XCTestCase {
    func testFindsMateInOne() {
        // White to move: Qh7 is not mate, Ra8 is (back-rank).
        let p = pos("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
        for level in 1...2 {
            let move = ChessBot.bestMove(p, level, KotlinRandom(intSeed: 1))!
            let after = p.applying(move)
            XCTAssertTrue(after.legalMoves().isEmpty && after.isInCheck(.BLACK), "level \(level) should mate")
        }
    }

    func testTakesAHangingQueen() {
        let p = pos("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1")
        let move = ChessBot.bestMove(p, 2, KotlinRandom(intSeed: 3))!
        XCTAssertEqual(square("d5"), move.to)
    }

    func testAlwaysLegal() {
        var match = ChessMatch()
        let random = KotlinRandom(intSeed: 7)
        for _ in 0..<30 {
            if match.isOver { return }
            let move = ChessBot.bestMove(match.position, 0, random)!
            XCTAssertTrue(match.position.isLegal(move))
            XCTAssertNotNil(match.play(move.from, move.to, move.promotion))
        }
    }
}
