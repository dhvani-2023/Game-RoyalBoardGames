import SwiftUI

@MainActor
enum GameRegistry {
    /// Display order across Home and Games.
    static let all: [any BoardGameModule] = [
        PoolGame.shared, LudoGame.shared, CarromGame.shared, ChessGame.shared, SnakesGame.shared, TicTacToeGame.shared,
    ]

    static func module(_ kind: GameKind) -> any BoardGameModule { all.first { $0.kind == kind }! }
}
