import SwiftUI
import GameKit

final class SnakesGame: BoardGameModule {
    static let shared = SnakesGame()
    static let SAVE_KEY = "party.snakes.saved.v1"

    let kind = GameKind.SNAKES

    func hasSavedGame() -> Bool { Prefs.has(SnakesGame.SAVE_KEY) && Prefs.load(SnakesGame.SAVE_KEY, as: SnakesSaved.self) != nil }

    func savedGameSummary() -> String? {
        Prefs.load(SnakesGame.SAVE_KEY, as: SnakesSaved.self).map { s in
            "\(s.config.players.map(\.name).joined(separator: " vs ")) · \(SnakesTheme.theme(s.config.themeID).name)"
        }
    }

    func clearSavedGame() { Prefs.remove(SnakesGame.SAVE_KEY) }

    func Content(resume: Bool, onExit: @escaping () -> Void) -> AnyView {
        AnyView(SnakesFlow(resume: resume, onExit: onExit))
    }

    /// Ported from SnakesArtwork in PartyArtwork.swift: tilted Classic Garden board, a bobbing die and two tokens.
    func Artwork() -> AnyView { AnyView(SnakesArtwork()) }
}

/// Setup → play, with the Kotlin `AnimatedContent` crossfade between the two.
private struct SnakesFlow: View {
    let onExit: () -> Void

    private enum Stage {
        case Setup
        case Play(config: SnakesConfig, saved: SnakesSaved?)
    }

    @State private var stage: Stage
    /// Each new stage is new content (Kotlin `Stage.Play` is a plain class, so every instance differs).
    @State private var stageID = 0

    init(resume: Bool, onExit: @escaping () -> Void) {
        self.onExit = onExit
        let saved = resume ? Prefs.load(SnakesGame.SAVE_KEY, as: SnakesSaved.self) : nil
        if let saved {
            _stage = State(initialValue: .Play(config: saved.config, saved: saved))
        } else {
            _stage = State(initialValue: .Setup)
        }
    }

    private func go(_ next: Stage) {
        stage = next
        stageID += 1
    }

    var body: some View {
        ZStack {
            Group {
                switch stage {
                case .Setup:
                    SnakesSetupScreen(onBack: onExit, onStart: { config in
                        SnakesGame.shared.clearSavedGame()
                        go(.Play(config: config, saved: nil))
                    })
                case let .Play(config, saved):
                    SnakesGameScreen(config, saved, onPlayers: { go(.Setup) }, onHome: onExit)
                }
            }
            .id(stageID)
            .transition(.asymmetric(
                // (fadeIn(tween(260)) + scaleIn(initialScale = 0.96f)) togetherWith fadeOut(tween(200))
                insertion: AnyTransition.opacity.animation(.tween(260))
                    .combined(with: AnyTransition.scale(scale: 0.96).animation(.compose(dampingRatio: 1, stiffness: 400))),
                removal: AnyTransition.opacity.animation(.tween(200))
            ))
        }
        .animation(.tween(260), value: stageID)
    }
}

/// Tilted Classic Garden board, a bobbing die and two tokens. Fills the frame it is given.
private struct SnakesArtwork: View {
    @State private var start = Date()

    var body: some View {
        let reduce = LocalReduceMotion.current
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: nil, paused: reduce)) { tl in
                // infiniteRepeatable(tween(1400), RepeatMode.Reverse): FastOutSlowIn there and back.
                let phase = (tl.date.timeIntervalSince(start) / 1.4).truncatingRemainder(dividingBy: 2)
                let u = phase < 1 ? phase : 2 - phase
                let bob = reduce ? 0 : CGFloat(Easing.FastOutSlowIn.transform(u))
                ZStack {
                    SnakesBoardArt(SnakesTheme.theme(0), size / 10, showsNumbers: false)
                        .equatable()
                        .clipShape(RoundedCornerShape(size * 0.08))
                        .background(RoundedCornerShape(size * 0.08).fill(Color.black).composeShadow(12 * (size / 130)))
                        .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0), perspective: 0.27)
                        .rotation3DEffect(.degrees(-7), axis: (x: 0, y: 1, z: 0), perspective: 0.27)
                    DiceView(5, false, SnakesColor(0x2B2A33))
                        .frame(width: size * 0.36, height: size * 0.36)
                        .rotationEffect(.degrees(Double(-4 - 10 * bob)))
                        .offset(y: -(size * 0.046) * bob)
                        .offset(x: size * 0.4, y: size * 0.32)
                    ForEach(0..<2, id: \.self) { i in
                        let c = SnakesColor(argb: PartyStyle.tokenArgb[i])
                        ZStack {
                            Circle().fill(LinearGradient(colors: [c.mix(.White, 0.15).color, c.color], startPoint: .top, endPoint: .bottom))
                            Circle().strokeBorder(Color.white, lineWidth: 2)
                            Text(verbatim: PartyStyle.avatars[i]).font(.system(size: size * 0.1))
                        }
                        .frame(width: size * 0.2, height: size * 0.2)
                        .background(Circle().fill(c.color).composeShadow(3))
                        .offset(y: i == 0 ? -(size * 0.038) * bob : 0)
                        .offset(x: -size * 0.18 + size * 0.22 * CGFloat(i), y: -size * 0.12)
                    }
                }
                .frame(width: size, height: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
