import SwiftUI
import GameKit

/// Tic-Tac-Toe: a single game or a best-of match, pass-the-device or against the computer.
/// Like the reference, a match is short and isn't autosaved.
@MainActor
final class TicTacToeGame: BoardGameModule {
    static let shared = TicTacToeGame()

    let kind = GameKind.TIC_TAC_TOE

    func hasSavedGame() -> Bool { false }

    func clearSavedGame() {}

    func Content(resume: Bool, onExit: @escaping () -> Void) -> AnyView {
        AnyView(TicTacToeContent(onExit: onExit))
    }

    func Artwork() -> AnyView { AnyView(TicTacToeCardArt()) }
}

private struct TicTacToeContent: View {
    let onExit: () -> Void

    private enum Route: Equatable {
        case Setup
        case Play(config: TicTacToeConfig, serial: Int)

        /// Kotlin `contentKey`: every match is new content; Setup is −1.
        var key: Int {
            if case let .Play(_, serial) = self { return serial }
            return -1
        }
    }

    @State private var serial = 0
    @State private var route: Route = .Setup

    private func go(_ next: Route) {
        withAnimation(.tween(280)) { route = next }
    }

    var body: some View {
        ZStack {
            switch route {
            case .Setup:
                TicTacToeSetupScreen(onBack: onExit, onStart: { config in
                    serial += 1
                    go(.Play(config: config, serial: serial))
                })
                .transition(routeTransition)
            case let .Play(config, _):
                TicTacToeScreen(config: config, onPlayers: { go(.Setup) }, onHub: onExit)
                    .id(route.key)
                    .transition(routeTransition)
            }
        }
    }

    /// Compose `(fadeIn(tween(280)) + scaleIn(tween(280), initialScale = 0.96f)) togetherWith fadeOut(tween(200))`.
    private var routeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.tween(280)),
            removal: .opacity.animation(.tween(200))
        )
    }
}
