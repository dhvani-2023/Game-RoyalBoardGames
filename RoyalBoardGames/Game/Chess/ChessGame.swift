import SwiftUI
import GameKit

/// Chess module for the app shell: setup → table → result → rematch, with an autosave that resumes from Home.
@MainActor
final class ChessGame: BoardGameModule {
    static let shared = ChessGame()
    nonisolated static let SAVE_KEY = "party.chess.saved.v1"

    let kind = GameKind.CHESS

    func hasSavedGame() -> Bool { Prefs.has(Self.SAVE_KEY) && Prefs.load(Self.SAVE_KEY, as: ChessSaved.self) != nil }

    func savedGameSummary() -> String? {
        guard let s = Prefs.load(Self.SAVE_KEY, as: ChessSaved.self) else { return nil }
        return "\(s.config.white.name) vs \(s.config.black.name) · \(s.config.clock.title)"
    }

    func clearSavedGame() { Prefs.remove(Self.SAVE_KEY) }

    func Content(resume: Bool, onExit: @escaping () -> Void) -> AnyView {
        AnyView(ChessGameContent(resume: resume, onExit: onExit))
    }

    /// "Royal Duel": perspective board, facing kings and a leaping knight (see ChessCardArt).
    func Artwork() -> AnyView { AnyView(ChessCardArt()) }
}

private struct ChessGameContent: View {
    let resume: Bool
    let onExit: () -> Void

    private enum Stage: Equatable {
        case Setup
        case Play(config: ChessConfig, saved: ChessSaved?, serial: Int)
    }

    @State private var stage: Stage
    @State private var serial = 0

    init(resume: Bool, onExit: @escaping () -> Void) {
        self.resume = resume
        self.onExit = onExit
        let saved = resume ? Prefs.load(ChessGame.SAVE_KEY, as: ChessSaved.self) : nil
        _stage = State(initialValue: saved.map { .Play(config: $0.config, saved: $0, serial: 0) } ?? .Setup)
    }

    private func go(_ next: Stage) {
        withAnimation(.tween(260)) { stage = next }
    }

    var body: some View {
        ZStack {
            switch stage {
            case .Setup:
                ChessSetupScreen(onBack: onExit, onStart: { config in
                    ChessGame.shared.clearSavedGame()
                    serial += 1
                    go(.Play(config: config, saved: nil, serial: serial))
                })
                .transition(stageTransition)
            case let .Play(config, saved, serial):
                ChessGameScreen(startConfig: config, saved: saved, onPlayers: { go(.Setup) }, onHome: onExit)
                    .id(serial)
                    .transition(stageTransition)
            }
        }
    }

    /// Compose `(fadeIn(tween(260)) + scaleIn(initialScale = 0.96f)) togetherWith fadeOut(tween(200))`.
    private var stageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.tween(260)).combined(with: .scale(scale: 0.96).animation(.compose(dampingRatio: 1, stiffness: 400))),
            removal: .opacity.animation(.tween(200))
        )
    }
}
