import SwiftUI
import GameKit

/// Ludo for 2–6 seats on a four-arm or six-arm board, with computers, six designs and autosave.
@MainActor
final class LudoGame: BoardGameModule {
    static let shared = LudoGame()

    let kind = GameKind.LUDO

    func hasSavedGame() -> Bool { LudoStore.saved != nil }

    func savedGameSummary() -> String? {
        guard let saved = LudoStore.saved else { return nil }
        let seats = saved.config.seats
        let toPlay = seats[min(saved.engine.current, seats.count - 1)].player.name
        let who = seats.count == 2 ? "\(seats[0].player.name) vs \(seats[1].player.name)" : "\(seats.count) players"
        return "\(who) · \(toPlay) to roll"
    }

    func clearSavedGame() {
        LudoStore.saved = nil
    }

    func Content(resume: Bool, onExit: @escaping () -> Void) -> AnyView {
        AnyView(LudoFlow(resume: resume, onExit: onExit))
    }

    func Artwork() -> AnyView {
        AnyView(LudoArtwork())
    }
}

/// Setup → play → results → rematch, inside the game (Kotlin `LudoGame.Content`).
private struct LudoFlow: View {
    let resume: Bool
    let onExit: () -> Void

    private enum Route: Equatable {
        case Setup
        case Play(LudoConfig, Int)

        /// Kotlin `contentKey`: a new match (serial) gets a fresh screen.
        var key: Int {
            if case .Play(_, let serial) = self { return serial }
            return -1
        }
    }

    @State private var serial = 0
    @State private var route: Route
    /// A match opened straight from the hub goes back to the hub when quit.
    @State private var fromSetup: Bool

    init(resume: Bool, onExit: @escaping () -> Void) {
        self.resume = resume
        self.onExit = onExit
        let start = resume ? LudoStore.saved?.config.copy(resume: true) : nil
        _fromSetup = State(initialValue: start == nil)
        _route = State(initialValue: start.map { Route.Play($0, 0) } ?? .Setup)
    }

    private func play(_ config: LudoConfig) {
        serial += 1
        route = .Play(config, serial)
    }

    var body: some View {
        ZStack {
            switch route {
            case .Setup:
                LudoSetupScreen(
                    onBack: onExit,
                    onStart: { fromSetup = true; play($0) },
                    onResume: { fromSetup = true; play($0.copy(resume: true)) }
                )
                .id(route.key)
                .transition(transition)
            case .Play(let config, _):
                LudoScreen(
                    config: config,
                    onQuit: { if fromSetup { route = .Setup } else { onExit() } },
                    onReplace: play,
                    onNewSetup: { fromSetup = true; route = .Setup },
                    onHub: onExit
                )
                .id(route.key)
                .transition(transition)
            }
        }
        // fadeIn(tween(280)) + scaleIn(tween(280), initialScale = 0.96f) togetherWith fadeOut(tween(200))
        .animation(.tween(280), value: route.key)
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.96)).animation(.tween(280)),
            removal: AnyTransition.opacity.animation(.tween(200))
        )
    }
}
