import Foundation

/// Switches for the iOS-only extras (upgrades over Android). Each can be turned off on its own; the games
/// then look and play exactly like the Android port.
enum ExtrasFeatures {
    /// Pool and Carrom: a Replay button after every shot plays it again at 0.4× with a REPLAY badge.
    static var instantReplay = true
    /// Pool and Carrom: a Practice button in the setup opens a one-player table with no turns, fouls or score.
    static var practiceTable = true
    /// Chess: move list panel, Undo and Hint against the computer, Copy PGN.
    static var chessTools = true
}
