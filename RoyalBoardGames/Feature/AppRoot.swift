import SwiftUI
import GameKit

/// Full-screen destinations pushed over the tab shell.
enum Destination: Hashable {
    case Shell
    case Game(kind: GameKind, resume: Bool, serial: Int)
    case Legal(doc: LegalDoc, serial: Int)

    var isShell: Bool { if case .Shell = self { return true } else { return false } }
    var isGame: Bool { if case .Game = self { return true } else { return false } }
}

/// How the stack is changing; picks the enter/exit transitions (Compose `AnimatedContent` transitionSpec).
enum StackMotion {
    case gamePush, gamePop, slidePush, slidePop

    var animation: Animation {
        switch self {
        case .gamePush: .tween(350)
        case .gamePop: .tween(300)
        case .slidePush, .slidePop: .tween(320)
        }
    }
}

/// App-wide navigation: a tiny stack the screens push onto.
@MainActor
@Observable
final class AppNavigator {
    private(set) var stack: [Destination] = [.Shell]
    var top: Destination { stack.last! }
    /// The transition for the change in progress (set one run-loop turn before the stack changes).
    private(set) var motion: StackMotion = .gamePush
    /// The tab shell's own state, kept while games and pages sit on top (Compose `rememberSaveable`).
    let shell = HomeShellState()
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var pending = false

    func openGame(_ kind: GameKind, resume: Bool = false) {
        UiSound.play(.Whoosh)
        serial += 1
        push(.Game(kind: kind, resume: resume, serial: serial))
    }

    func openLegal(_ doc: LegalDoc) {
        UiSound.play(.Swoosh)
        serial += 1
        push(.Legal(doc: doc, serial: serial))
    }

    func back() {
        guard stack.count > 1, !pending else { return }
        let leaving = top
        let entering = stack[stack.count - 2]
        change(leaving.isGame || entering.isGame ? .gamePop : .slidePop) { $0.removeLast() }
    }

    private func push(_ d: Destination) {
        guard !pending else { return }
        change(d.isGame || top.isGame ? .gamePush : .slidePush) { $0.append(d) }
    }

    private func change(_ m: StackMotion, _ edit: @escaping (inout [Destination]) -> Void) {
        pending = true
        motion = m
        // Let the outgoing screen pick up its exit transition first, then change the stack.
        DispatchQueue.main.async {
            withAnimation(m.animation) { edit(&self.stack) }
            self.pending = false
        }
    }
}

private enum Phase { case Splash, Onboarding, Main }

struct AppRoot: View {
    @State private var phase: Phase = .Splash
    @State private var navigator = AppNavigator()

    var body: some View {
        ZStack {
            Royal.Night.ignoresSafeArea()
            switch phase {
            case .Splash:
                SplashScreen(onFinished: {
                    withAnimation { phase = AppSettings.data.onboardingDone ? .Main : .Onboarding }
                })
                .transition(phaseTransition)
            case .Onboarding:
                OnboardingScreen(onDone: {
                    AppSettings.update { $0.copy(onboardingDone: true) }
                    withAnimation { phase = .Main }
                })
                .transition(phaseTransition)
            case .Main:
                MainStack(navigator: navigator)
                    .transition(phaseTransition)
            }
        }
        .onAppear { PartyStore.ensureLoaded() }
    }

    private var phaseTransition: AnyTransition {
        .asymmetric(insertion: .opacity.animation(.tween(500)), removal: .opacity.animation(.tween(400)))
    }
}

private struct MainStack: View {
    let navigator: AppNavigator

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let top = navigator.top
            ZStack {
                screen(top)
                    .id(top)
                    .transition(transition(for: navigator.motion, width: w))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func screen(_ d: Destination) -> some View {
        switch d {
        case .Shell:
            HomeShell(navigator: navigator)
        case let .Game(kind, resume, _):
            GameRegistry.module(kind).Content(resume: resume, onExit: { navigator.back() })
        case let .Legal(doc, _):
            LegalScreen(doc: doc, onBack: { navigator.back() })
        }
    }

    private func transition(for m: StackMotion, width w: CGFloat) -> AnyTransition {
        switch m {
        case .gamePush:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.08)),
                removal: .opacity.combined(with: .scale(scale: 0.94)))
        case .gamePop:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94)),
                removal: .opacity.combined(with: .scale(scale: 1.06)))
        case .slidePush:
            return .asymmetric(
                insertion: .modifier(active: SlideFade(x: w, opacity: 0), identity: SlideFade(x: 0, opacity: 1)),
                removal: .modifier(active: SlideFade(x: -w / 3, opacity: 0), identity: SlideFade(x: 0, opacity: 1)))
        case .slidePop:
            return .asymmetric(
                insertion: .modifier(active: SlideFade(x: -w / 3, opacity: 0), identity: SlideFade(x: 0, opacity: 1)),
                removal: .modifier(active: SlideFade(x: w, opacity: 0), identity: SlideFade(x: 0, opacity: 1)))
        }
    }
}

/// Horizontal slide + fade (Compose `slideInHorizontally + fadeIn`).
struct SlideFade: ViewModifier {
    let x: CGFloat
    var y: CGFloat = 0
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: x, y: y).opacity(opacity)
    }
}
