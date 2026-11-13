import XCTest
import GameKit
@testable import RoyalBoardGames

// 1:1 port of app/src/test/.../game/tictactoe/TicTacToeTests.kt (TicTacToeTests, TicTacToeBotTests).

final class TicTacToeTests: XCTestCase {
    func testEveryLineWins() {
        for line in TicTacToeBoard.lines {
            var board = TicTacToeBoard()
            var others = (0..<9).filter { !line.contains($0) }.makeIterator()
            // X takes the line; O plays elsewhere without completing a line first.
            for (i, cell) in line.enumerated() {
                XCTAssertTrue(board.play(cell))
                if i < 2, let other = others.next() { XCTAssertTrue(board.play(other)) }
            }
            XCTAssertEqual(TTTMark.X, board.win?.mark)
            XCTAssertEqual(line, board.win?.line)
        }
    }

    func testAlternatesAndBlocksOccupiedCells() {
        var board = TicTacToeBoard()
        XCTAssertEqual(TTTMark.X, board.turn)
        XCTAssertTrue(board.play(4))
        XCTAssertEqual(TTTMark.O, board.turn)
        XCTAssertFalse(board.play(4), "occupied")
        XCTAssertEqual(TTTMark.O, board.turn, "a rejected move doesn't pass the turn")
        XCTAssertFalse(board.play(9), "off the board")
    }

    func testDraw() {
        var board = TicTacToeBoard()
        // X O X / X O O / O X X
        for cell in [0, 1, 2, 4, 3, 5, 7, 6, 8] { XCTAssertTrue(board.play(cell)) }
        XCTAssertNil(board.win)
        XCTAssertTrue(board.isDraw)
    }

    func testNoMovesAfterWin() {
        var board = TicTacToeBoard()
        for cell in [0, 3, 1, 4, 2] { board.play(cell) }
        XCTAssertEqual(TTTMark.X, board.win?.mark)
        XCTAssertFalse(board.play(8))
    }

    func testBestOfThreeMatch() {
        var match = TicTacToeMatch(3)
        XCTAssertEqual(2, match.winsNeeded)
        for cell in [0, 3, 1, 4, 2] { match.play(cell) } // X wins round 1
        XCTAssertTrue(match.xWins == 1 && !match.isMatchOver)
        match.nextRound()
        XCTAssertTrue(match.round == 2 && match.board.turn == .O, "starter alternates")
        for cell in [0, 3, 1, 4, 2] { match.play(cell) } // O wins round 2
        XCTAssertEqual(1, match.oWins)
        match.nextRound()
        XCTAssertEqual(TTTMark.X, match.board.turn)
        for cell in [0, 1, 2, 4, 3, 5, 7, 6, 8] { match.play(cell) } // draw
        XCTAssertTrue(match.draws == 1 && !match.isMatchOver)
        match.nextRound()
        for cell in [0, 3, 1, 4, 2] { match.play(cell) } // O starts, O wins
        XCTAssertEqual(TTTMark.O, match.matchWinner)
        XCTAssertFalse(match.play(8), "no moves once the match is won")
    }

    func testRestartRoundUndoesItsScore() {
        var match = TicTacToeMatch(5)
        for cell in [0, 3, 1, 4, 2] { match.play(cell) }
        XCTAssertEqual(1, match.xWins)
        match.restartRound()
        XCTAssertTrue(match.xWins == 0 && match.board.moveCount == 0)
    }

    func testSingleGame() {
        var match = TicTacToeMatch(1)
        for cell in [0, 3, 1, 4, 2] { match.play(cell) }
        XCTAssertEqual(TTTMark.X, match.matchWinner)
        match.restartMatch()
        XCTAssertTrue(match.xWins == 0 && match.round == 1 && match.matchWinner == nil)
    }

    func testCopiesAreIndependent() {
        let match = TicTacToeMatch(3)
        var next = match.copy()
        next.play(4)
        XCTAssertEqual(0, match.board.moveCount)
        XCTAssertEqual(1, next.board.moveCount)
        XCTAssertFalse(match == next)
        XCTAssertEqual(match, TicTacToeMatch(3))
    }

    func testPlayerNamesFallBack() {
        let blank = PartyPlayer(name: "   ", avatar: "🦊", colorIndex: 0)
        XCTAssertEqual("Player 3", blank.displayName(2))
        let long = PartyPlayer(name: "A very long player name indeed", avatar: "🦊", colorIndex: 0)
        XCTAssertEqual(16, long.displayName(0).count)
    }
}

final class TicTacToeBotTests: XCTestCase {
    func testEveryLevelWinsAndBlocksOrPlaysLegally() {
        // X: 0, 1; O: 3, 4. X to move: 2 wins.
        var board = TicTacToeBoard()
        for cell in [0, 3, 1, 4] { board.play(cell) }
        XCTAssertEqual(2, TicTacToeBot.choose(board, .HARD, KotlinRandom(intSeed: 1)))
        XCTAssertEqual(2, TicTacToeBot.choose(board, .NORMAL, KotlinRandom(intSeed: 1)))
        for seed in 0..<20 {
            let cell = TicTacToeBot.choose(board, .EASY, KotlinRandom(intSeed: seed))
            XCTAssertNotNil(cell)
            XCTAssertTrue(board.canPlay(cell!))
        }
    }

    func testHardBlocksALine() {
        // X: 0, 1 then O to move: must block 2.
        var board = TicTacToeBoard()
        for cell in [0, 4, 1] { board.play(cell) }
        XCTAssertEqual(2, TicTacToeBot.choose(board, .HARD, KotlinRandom(intSeed: 7)))
    }

    func testHardNeverLosesToRandomPlay() {
        let rng = KotlinRandom(intSeed: 42)
        for game in 0..<200 {
            var board = TicTacToeBoard(game % 2 == 0 ? .X : .O)
            // The bot plays O.
            while !board.isOver {
                let cell = board.turn == .O
                    ? TicTacToeBot.choose(board, .HARD, rng)!
                    : (0..<9).filter { board.canPlay($0) }.kotlinRandom(rng)
                XCTAssertTrue(board.play(cell))
            }
            XCTAssertTrue(board.win?.mark != .X, "game \(game): the bot lost")
        }
    }

    func testHardAgainstHardIsAlwaysADraw() {
        for seed in 0..<10 {
            let rng = KotlinRandom(intSeed: seed)
            var board = TicTacToeBoard()
            while !board.isOver { board.play(TicTacToeBot.choose(board, .HARD, rng)!) }
            XCTAssertTrue(board.isDraw)
        }
    }

    func testNoMoveOnAFinishedBoard() {
        var board = TicTacToeBoard()
        for cell in [0, 3, 1, 4, 2] { board.play(cell) }
        XCTAssertNil(TicTacToeBot.choose(board, .HARD))
    }
}
