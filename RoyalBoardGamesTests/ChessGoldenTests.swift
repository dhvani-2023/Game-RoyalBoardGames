import XCTest
import GameKit
@testable import RoyalBoardGames

/// Chess must match the Android (JVM) engine and bot exactly: Golden/chess_golden.json was dumped by
/// Golden/source/ChessTicTacToeGoldenDump.kt from unmodified copies of ChessEngine.kt and ChessBot.kt.
final class ChessGoldenTests: XCTestCase {
    private struct Game: Decodable {
        let white: Int
        let black: Int
        let seed: Int
        let maxPlies: Int
        let start: String
        let moves: [String]
        let san: [String]
        let fen: String
        let reason: String?
        let winner: String?
        let next: String?
    }

    private struct Best: Decodable {
        let fen: String
        let level: Int
        let seed: Int
        let move: String?
    }

    private struct Position: Decodable {
        let fen: String
        let white: Int
        let black: Int
        let legal: [String]
        let san: [String]
        let insufficient: Bool
        let whiteCanMate: Bool
        let blackCanMate: Bool
        let repetitionKey: String
    }

    private struct Perft: Decodable {
        let fen: String
        let depth: Int
        let nodes: Int
    }

    private struct Golden: Decodable {
        let games: [Game]
        let bestMoves: [Best]
        let positions: [Position]
        let perft: [Perft]
    }

    private static var cached: Golden?

    private func golden() throws -> Golden {
        if let g = Self.cached { return g }
        let bundle = Bundle(for: ChessGoldenTests.self)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/chess_golden.json")
        let candidates = [
            bundle.url(forResource: "chess_golden", withExtension: "json"),
            bundle.url(forResource: "chess_golden", withExtension: "json", subdirectory: "Golden"),
            source,
        ].compactMap { $0 }
        let url = try XCTUnwrap(candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }), "chess_golden.json not found")
        let g = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        Self.cached = g
        return g
    }

    func testBotGamesMatchTheJVM() throws {
        for g in try golden().games {
            var match = ChessMatch(try XCTUnwrap(ChessPosition.fromFen(g.start)))
            let random = KotlinRandom(intSeed: g.seed)
            var uci: [String] = []
            while !match.isOver && uci.count < g.maxPlies {
                let level = match.position.sideToMove == .WHITE ? g.white : g.black
                let move = try XCTUnwrap(ChessBot.bestMove(match.position, level, random))
                XCTAssertNotNil(match.play(move.from, move.to, move.promotion))
                uci.append(move.uci)
            }
            let label = "game \(g.white) vs \(g.black) seed \(g.seed)"
            XCTAssertEqual(g.moves, uci, label)
            XCTAssertEqual(g.san, match.sanMoves, label)
            XCTAssertEqual(g.fen, match.position.fen, label)
            XCTAssertEqual(g.reason, match.result?.reason, label)
            XCTAssertEqual(g.winner, match.result?.winner?.rawValue, label)
            let next = match.isOver ? nil : ChessBot.bestMove(match.position, 0, KotlinRandom(intSeed: g.seed + 100))?.uci
            XCTAssertEqual(g.next, next, label)
        }
    }

    func testBestMovesMatchTheJVM() throws {
        for b in try golden().bestMoves {
            let p = try XCTUnwrap(ChessPosition.fromFen(b.fen))
            XCTAssertEqual(b.move, ChessBot.bestMove(p, b.level, KotlinRandom(intSeed: b.seed))?.uci, "\(b.fen) level \(b.level) seed \(b.seed)")
        }
    }

    func testPositionsMatchTheJVM() throws {
        for g in try golden().positions {
            let p = try XCTUnwrap(ChessPosition.fromFen(g.fen))
            XCTAssertEqual(g.white, ChessBot.evaluate(p, .WHITE), g.fen)
            XCTAssertEqual(g.black, ChessBot.evaluate(p, .BLACK), g.fen)
            let legal = p.legalMoves()
            XCTAssertEqual(g.legal, legal.map(\.uci), "move order \(g.fen)")
            XCTAssertEqual(g.san, legal.map { p.san($0) }, g.fen)
            XCTAssertEqual(g.insufficient, p.hasInsufficientMaterial, g.fen)
            XCTAssertEqual(g.whiteCanMate, p.canMate(.WHITE), g.fen)
            XCTAssertEqual(g.blackCanMate, p.canMate(.BLACK), g.fen)
            XCTAssertEqual(g.repetitionKey, p.repetitionKey, g.fen)
            XCTAssertEqual(g.fen, p.fen)
        }
    }

    func testDeepPerftMatchesTheJVM() throws {
        for g in try golden().perft {
            XCTAssertEqual(g.nodes, try XCTUnwrap(ChessPosition.fromFen(g.fen)).perft(g.depth), "\(g.fen) depth \(g.depth)")
        }
    }

    // MARK: Autosave

    func testSavedGameReplaysAndRoundTrips() throws {
        let white = PartyPlayer(id: "w", name: "Raj", avatar: "🦊", colorIndex: 0)
        let black = PartyPlayer(id: "b", name: "CPU Leo", avatar: "🤖", colorIndex: 1)
        let config = ChessConfig(white: white, black: black, clock: .BLITZ3, blackIsBot: true, botLevel: 2)
        var match = ChessMatch()
        for m in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1", "f8c5"] {
            XCTAssertNotNil(match.play(ChessSquare.parse(String(m.prefix(2)))!, ChessSquare.parse(String(m.suffix(2)))!))
        }
        let saved = ChessSaved(config: config, moves: match.moves.map(\.uci), whiteClock: 150.5, blackClock: nil, flipped: true)
        let data = try JSONEncoder().encode(saved)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"clock\":\"BLITZ3\""), json)
        XCTAssertTrue(json.contains("\"blackClock\":null"), json)
        let back = try JSONDecoder().decode(ChessSaved.self, from: data)
        XCTAssertEqual(saved, back)
        // Android's JSON (kotlinx, encodeDefaults) decodes too, with unknown keys ignored.
        let android = """
        {"config":{"white":{"id":"w","name":"Raj","avatar":"🦊","colorIndex":0},"black":{"id":"b","name":"CPU Leo","avatar":"🤖","colorIndex":1},\
        "clock":"BLITZ3","passDevice":false,"autoRotate":false,"boardStyle":0,"whiteIsBot":false,"blackIsBot":true,"botLevel":2,"extra":1},\
        "moves":["e2e4","e7e5","g1f3","b8c6","f1c4","g8f6","e1g1","f8c5"],"whiteClock":150.5,"blackClock":null,"flipped":true}
        """
        XCTAssertEqual(saved, try JSONDecoder().decode(ChessSaved.self, from: Data(android.utf8)))
    }
}
