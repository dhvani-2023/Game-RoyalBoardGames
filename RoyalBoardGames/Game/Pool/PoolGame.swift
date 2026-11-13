import SwiftUI
import GameKit

/// 8-Ball and 9-Ball for 2–4 players with computers, spin, ball in hand and eight tables.
@MainActor
final class PoolGame: BoardGameModule {
    static let shared = PoolGame()

    let kind = GameKind.POOL

    func hasSavedGame() -> Bool { PoolStore.saved != nil }

    func savedGameSummary() -> String? {
        guard let saved = PoolStore.saved else { return nil }
        let names = saved.config.seats.map { $0.player.name }.joined(separator: " vs ")
        return "\(names) · \(saved.match.game.title)"
    }

    func clearSavedGame() {
        PoolStore.saved = nil
    }

    func Content(resume: Bool, onExit: @escaping () -> Void) -> AnyView {
        AnyView(PoolFlow(resume: resume, onExit: onExit))
    }

    func Artwork() -> AnyView {
        AnyView(PoolArtwork())
    }
}

/// Setup → play → results → rematch, inside the game (Kotlin `PoolGame.Content`).
private struct PoolFlow: View {
    let resume: Bool
    let onExit: () -> Void

    private enum Screen: Equatable {
        case Setup
        case Game(PoolConfig, Int)

        var key: Int {
            if case .Game(_, let id) = self { return id }
            return -1
        }
    }

    @State private var counter = 1
    @State private var screen: Screen

    init(resume: Bool, onExit: @escaping () -> Void) {
        self.resume = resume
        self.onExit = onExit
        let saved = resume ? PoolStore.saved : nil
        _screen = State(initialValue: saved.map { Screen.Game($0.config.copy(resume: true), 0) } ?? .Setup)
    }

    var body: some View {
        ZStack {
            switch screen {
            case .Setup:
                PoolSetupScreen(onBack: onExit, onStart: { config in
                    screen = .Game(config, counter)
                    counter += 1
                })
                .transition(.opacity)
            case .Game(let config, let id):
                PoolGameScreen(
                    config,
                    onExit: onExit,
                    onRematch: {
                        screen = .Game(config.copy(resume: false), counter)
                        counter += 1
                    },
                    onNewSetup: { screen = .Setup }
                )
                .id(id)
                .transition(.opacity)
            }
        }
        .animation(.tween(260), value: screen.key)
    }
}
