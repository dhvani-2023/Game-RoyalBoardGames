import SwiftUI
import GameKit

/// Carrom: Classic, Pocket Pool and Freestyle for 2–4 players on eight boards, with bots and autosave.
@MainActor
final class CarromGame: BoardGameModule {
    static let shared = CarromGame()

    let kind = GameKind.CARROM

    func hasSavedGame() -> Bool { CarromStore.saved != nil }

    func savedGameSummary() -> String? {
        guard let saved = CarromStore.saved else { return nil }
        let names = saved.match.teams ? CarromStore.teamNames : saved.config.seats.map { $0.player.name }
        let who = names.count <= 2 ? names.joined(separator: " vs ") : "\(names[0]) + \(names.count - 1) more"
        let turn = saved.match.table.turn
        let seat = saved.config.seats.indices.contains(turn) ? saved.config.seats[turn] : nil
        return "\(who) · \(saved.match.mode.title)" + (seat.map { " · \($0.player.name) to shoot" } ?? "")
    }

    func clearSavedGame() {
        CarromStore.saved = nil
    }

    func Content(resume: Bool, onExit: @escaping () -> Void) -> AnyView {
        AnyView(CarromFlow(resume: resume, onExit: onExit))
    }

    func Artwork() -> AnyView {
        AnyView(CarromArtwork())
    }
}

/// Setup → play → results → rematch, inside the game (Kotlin `CarromGame.Content`).
private struct CarromFlow: View {
    let resume: Bool
    let onExit: () -> Void

    private enum Screen {
        case Setup
        /// [generation] makes a rematch with the same config start a fresh session.
        case Game(CarromSession, fromSetup: Bool, generation: Int)

        var key: String {
            if case .Game(_, _, let generation) = self { return "game-\(generation)" }
            return "setup"
        }
    }

    @State private var generation = 0
    @State private var screen: Screen

    init(resume: Bool, onExit: @escaping () -> Void) {
        self.resume = resume
        self.onExit = onExit
        let saved = resume ? CarromStore.saved : nil
        _screen = State(initialValue: saved.map { .Game(CarromSession($0.config.copy(resume: true)), fromSetup: false, generation: 0) } ?? .Setup)
    }

    var body: some View {
        ZStack {
            switch screen {
            case .Setup:
                CarromSetupScreen(
                    onBack: onExit,
                    onStart: { config in
                        generation += 1
                        screen = .Game(CarromSession(config), fromSetup: true, generation: generation)
                    },
                    onResume: { config in
                        generation += 1
                        screen = .Game(CarromSession(config.copy(resume: true)), fromSetup: true, generation: generation)
                    }
                )
                .id(screen.key)
                .transition(transition)
            case .Game(let session, let fromSetup, _):
                CarromGameScreen(
                    session: session,
                    onRematch: {
                        generation += 1
                        screen = .Game(CarromSession(session.config.copy(resume: false)), fromSetup: fromSetup, generation: generation)
                    },
                    onNewSetup: { screen = .Setup },
                    onHub: onExit,
                    onQuit: { if fromSetup { screen = .Setup } else { onExit() } }
                )
                .id(screen.key)
                .transition(transition)
            }
        }
        // (fadeIn(tween(260)) + scaleIn(initialScale = 0.97f, tween(260))) togetherWith fadeOut(tween(200))
        .animation(.tween(260), value: screen.key)
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.97)).animation(.tween(260)),
            removal: AnyTransition.opacity.animation(.tween(200))
        )
    }
}
