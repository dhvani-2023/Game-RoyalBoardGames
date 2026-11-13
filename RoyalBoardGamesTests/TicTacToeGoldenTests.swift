import XCTest
import GameKit
@testable import RoyalBoardGames

/// The Tic-Tac-Toe bot must match Android (JVM) exactly, random choices included: Golden/tictactoe_golden.json
/// was dumped by Golden/source/ChessTicTacToeGoldenDump.kt from an unmodified copy of TicTacToeEngine.kt.
final class TicTacToeGoldenTests: XCTestCase {
    private struct Game: Decodable {
        let x: String
        let o: String
        let starter: String
        let seed: Int
        let cells: [Int]
        let winner: String?
    }

    private struct Choice: Decodable {
        let cells: String
        let turn: String
        let easy: Int?
        let normal: Int?
        let hard: Int?
        let best: Int?
    }

    private struct Golden: Decodable {
        let games: [Game]
        let choices: [Choice]
    }

    private static var cached: Golden?

    private func golden() throws -> Golden {
        if let g = Self.cached { return g }
        let bundle = Bundle(for: TicTacToeGoldenTests.self)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/tictactoe_golden.json")
        let candidates = [
            bundle.url(forResource: "tictactoe_golden", withExtension: "json"),
            bundle.url(forResource: "tictactoe_golden", withExtension: "json", subdirectory: "Golden"),
            source,
        ].compactMap { $0 }
        let url = try XCTUnwrap(candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }), "tictactoe_golden.json not found")
        let g = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        Self.cached = g
        return g
    }

    private func level(_ name: String) throws -> BotLevel { try XCTUnwrap(BotLevel(rawValue: name)) }
    private func mark(_ label: String) -> TTTMark { label == "X" ? .X : .O }

    func testBotGamesMatchTheJVM() throws {
        let games = try golden().games
        XCTAssertEqual(216, games.count)
        for g in games {
            var board = TicTacToeBoard(mark(g.starter))
            let rng = KotlinRandom(intSeed: g.seed)
            var cells: [Int] = []
            while !board.isOver {
                let lvl = try level(board.turn == .X ? g.x : g.o)
                let cell = try XCTUnwrap(TicTacToeBot.choose(board, lvl, rng))
                XCTAssertTrue(board.play(cell))
                cells.append(cell)
            }
            XCTAssertEqual(g.cells, cells, "\(g.x) vs \(g.o), \(g.starter) starts, seed \(g.seed)")
            XCTAssertEqual(g.winner, board.win?.mark.label)
        }
    }

    func testChoicesMatchTheJVM() throws {
        let choices = try golden().choices
        XCTAssertEqual(300, choices.count)
        for (k, c) in choices.enumerated() {
            // Rebuild the position exactly as the dump did.
            let gen = KotlinRandom(intSeed: 1000 + k)
            var board = TicTacToeBoard(gen.nextBoolean() ? .X : .O)
            let plies = gen.nextInt(0, 8)
            for _ in 0..<plies where !board.isOver {
                board.play((0..<9).filter { board.canPlay($0) }.kotlinRandom(gen))
            }
            XCTAssertEqual(c.cells, board.cells.map { $0?.label ?? "." }.joined(), "position \(k)")
            XCTAssertEqual(c.turn, board.turn.label, "position \(k)")
            XCTAssertEqual(c.easy, TicTacToeBot.choose(board, .EASY, KotlinRandom(intSeed: k)), "easy \(k)")
            XCTAssertEqual(c.normal, TicTacToeBot.choose(board, .NORMAL, KotlinRandom(intSeed: k)), "normal \(k)")
            XCTAssertEqual(c.hard, TicTacToeBot.choose(board, .HARD, KotlinRandom(intSeed: k)), "hard \(k)")
            XCTAssertEqual(c.best, TicTacToeBot.best(board, KotlinRandom(intSeed: k)), "best \(k)")
        }
    }
}
