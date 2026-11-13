import XCTest
import GameKit
@testable import RoyalBoardGames

/// The table's session: piece identities follow every kind of move, clocks run and flag, autosaves replay.
/// Any real autosave in the host app's defaults is put back afterwards.
@MainActor
final class ChessSessionTests: XCTestCase {
    private var backup: ChessSaved?

    override func setUp() async throws {
        backup = Prefs.load(ChessGame.SAVE_KEY, as: ChessSaved.self)
    }

    override func tearDown() async throws {
        if let backup { Prefs.save(ChessGame.SAVE_KEY, backup) } else { Prefs.remove(ChessGame.SAVE_KEY) }
    }

    private func sq(_ name: String) -> Int { ChessSquare.parse(name)! }

    private func config(_ clock: ChessClockOption = .OFF) -> ChessConfig {
        ChessConfig(white: PartyPlayer(id: "w", name: "Raj", avatar: "🦊", colorIndex: 0),
                    black: PartyPlayer(id: "b", name: "Mia", avatar: "🐼", colorIndex: 1), clock: clock)
    }

    /// Every piece sits on its own square and matches the board.
    private func assertPiecesMirrorBoard(_ s: ChessSession, file: StaticString = #filePath, line: UInt = #line) {
        let occupied = s.position.board.enumerated().filter { $0.element != nil }.map(\.offset)
        XCTAssertEqual(occupied.sorted(), s.pieces.map(\.square).sorted(), file: file, line: line)
        for p in s.pieces { XCTAssertEqual(s.position.board[p.square], p.piece, file: file, line: line) }
    }

    func testTapMovesKeepIdentityAndCapturesBecomeGhosts() {
        let s = ChessSession(config())
        let pawn = s.pieces.first { $0.square == sq("e2") }!.id
        s.tap(sq("e2"))
        XCTAssertEqual(s.selected, sq("e2"))
        XCTAssertEqual(s.targets, [sq("e3"): false, sq("e4"): false])
        s.tap(sq("e4"))
        XCTAssertEqual(s.pieces.first { $0.id == pawn }?.square, sq("e4"))
        XCTAssertNil(s.selected)
        XCTAssertEqual(s.moveCount, 1)
        XCTAssertTrue(s.drop(sq("d7"), sq("d5")))
        XCTAssertTrue(s.drop(sq("e4"), sq("d5")))
        XCTAssertEqual(s.ghosts.map(\.piece), [ChessPiece(.PAWN, .BLACK)])
        XCTAssertEqual(s.captureCount, 1)
        XCTAssertEqual(s.pieces.count, 31)
        assertPiecesMirrorBoard(s)
        // Illegal drops are refused and counted.
        XCTAssertFalse(s.drop(sq("d8"), sq("d4")))
        XCTAssertEqual(s.illegalCount, 1)
        s.clearGhost(s.ghosts[0].id)
        XCTAssertTrue(s.ghosts.isEmpty)
    }

    func testEnPassantCastlingAndPromotionUpdatePieces() {
        let s = ChessSession(config())
        for m in ["e2e4", "a7a6", "e4e5", "d7d5", "e5d6"] {
            XCTAssertTrue(s.drop(sq(String(m.prefix(2))), sq(String(m.suffix(2)))), m)
        }
        XCTAssertNil(s.pieces.first { $0.square == sq("d5") }, "en passant removes the pawn beside")
        XCTAssertEqual(s.ghosts.first?.square, sq("d5"))
        assertPiecesMirrorBoard(s)
        for m in ["a6a5", "g1f3", "a5a4", "f1e2", "a4a3", "e1g1"] {
            XCTAssertTrue(s.drop(sq(String(m.prefix(2))), sq(String(m.suffix(2)))), m)
        }
        XCTAssertEqual(s.position.board[sq("f1")], ChessPiece(.ROOK, .WHITE))
        assertPiecesMirrorBoard(s)
        for m in ["a3b2", "d6c7", "b2a1"] {
            XCTAssertTrue(s.drop(sq(String(m.prefix(2))), sq(String(m.suffix(2)))), m)
        }
        // b2xa1 needs a promotion choice first.
        XCTAssertEqual(s.pendingPromotion, ChessSession.SquarePair(first: sq("b2"), second: sq("a1")))
        XCTAssertTrue(s.isPaused)
        s.promote(.KNIGHT)
        XCTAssertNil(s.pendingPromotion)
        XCTAssertEqual(s.position.board[sq("a1")], ChessPiece(.KNIGHT, .BLACK))
        assertPiecesMirrorBoard(s)
        XCTAssertEqual(s.match.sanMoves.last, "bxa1=N")
    }

    func testClockRunsAfterTheFirstMoveAndFlags() {
        let s = ChessSession(config(.BLITZ3))
        XCTAssertEqual(s.clocks, [.WHITE: 180, .BLACK: 180])
        s.tick(ChessSession.nanoTime() + 5_000_000_000)
        XCTAssertEqual(s.clocks[.WHITE], 180, "no clock before the first move")
        XCTAssertTrue(s.drop(sq("e2"), sq("e4")))
        XCTAssertEqual(s.clocks[.WHITE], 182, "3 + 2 increment")
        s.tick()
        s.tick(ChessSession.nanoTime() + 2_000_000_000)
        XCTAssertEqual(s.clocks[.BLACK]!, 178, accuracy: 0.05)
        s.tick(ChessSession.nanoTime() + 500_000_000_000)
        XCTAssertEqual(s.clocks[.BLACK], 0)
        XCTAssertEqual(s.match.result, ChessResult.Timeout(by: .WHITE))
        XCTAssertEqual(s.resultCount, 1)
        XCTAssertEqual(ChessSession.format(9.94), "0:09.9")
        XCTAssertEqual(ChessSession.format(141.3), "2:22")
        XCTAssertEqual(ChessSession.format(-1), "0:00.0")
    }

    func testRestoreReplaysTheSavedMatch() {
        var c = config(.RAPID5)
        c.passDevice = true
        let saved = ChessSaved(config: c, moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1"],
                               whiteClock: 250, blackClock: 260.5, flipped: true)
        let s = ChessSession(config())
        s.restore(saved)
        XCTAssertEqual(s.config, c)
        XCTAssertEqual(s.moveCount, 7)
        XCTAssertEqual(s.match.sanMoves, ["e4", "e5", "Nf3", "Nc6", "Bc4", "Nf6", "O-O"])
        XCTAssertEqual(s.clocks, [.WHITE: 250, .BLACK: 260.5])
        XCTAssertTrue(s.flipped)
        XCTAssertEqual(s.passTo, .BLACK, "pass-and-play resumes behind the hand-off screen")
        assertPiecesMirrorBoard(s)
        s.ready()
        XCTAssertNil(s.passTo)
        // The autosave writes the same moves back.
        s.save()
        XCTAssertEqual(Prefs.load(ChessGame.SAVE_KEY, as: ChessSaved.self)?.moves, saved.moves)
        s.resign(.BLACK)
        XCTAssertNil(Prefs.load(ChessGame.SAVE_KEY, as: ChessSaved.self), "finished matches are not kept")
    }

    func testBotDrawOfferAndHumanColour() {
        var c = config()
        c.blackIsBot = true
        let s = ChessSession(c)
        XCTAssertEqual(s.humanColor, .WHITE)
        XCTAssertFalse(s.flipped)
        XCTAssertFalse(s.botAcceptsDraw(), "level start position: the bot is not worse")
        s.rematch(true)
        XCTAssertTrue(s.config.whiteIsBot && !s.config.blackIsBot)
        XCTAssertEqual(s.humanColor, .BLACK)
        XCTAssertTrue(s.flipped, "the human plays from the bottom")
    }
}
