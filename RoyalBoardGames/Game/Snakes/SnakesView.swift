import SwiftUI
import GameKit

/// Compose `spring(dampingRatio = damping, stiffness = (2π / response)²)`.
private func snakesSpringOf(_ response: Double, _ damping: Double) -> Animation {
    .compose(dampingRatio: damping, stiffness: pow(2 * Double.pi / response, 2))
}

/// Kotlin `rememberCoroutineScope()`: jobs launched from the screen, cancelled when it goes away.
@MainActor
private final class SnakesScope {
    private var jobs: [Int: Task<Void, Never>] = [:]
    private var serial = 0

    func launch(_ body: @escaping @MainActor () async -> Void) {
        serial += 1
        let id = serial
        jobs[id] = Task { @MainActor [weak self] in
            await body()
            self?.jobs[id] = nil
        }
    }

    func cancel() {
        for job in jobs.values { job.cancel() }
        jobs.removeAll()
    }
}

struct SnakesGameScreen: View {
    let config: SnakesConfig
    let saved: SnakesSaved?
    let onPlayers: () -> Void
    let onHome: () -> Void

    @State private var session: SnakesSession
    @State private var scope = SnakesScope()
    @State private var showResult = false
    @State private var prompt: RoyalPrompt? = nil
    @State private var showSettings = false
    @State private var recorded = false

    init(_ config: SnakesConfig, _ saved: SnakesSaved?, onPlayers: @escaping () -> Void, onHome: @escaping () -> Void) {
        self.config = config
        self.saved = saved
        self.onPlayers = onPlayers
        self.onHome = onHome
        let s = SnakesSession(config)
        s.reduceMotion = LocalReduceMotion.current
        if let saved { s.restore(saved) }
        _session = State(initialValue: s)
    }

    private var reduce: Bool { LocalReduceMotion.current }

    private func roll() {
        let session = session
        scope.launch { await session.roll() }
    }

    private func requestExit() {
        if session.inProgress {
            let session = session
            let onPlayers = onPlayers
            prompt = RoyalPrompt(
                title: "Leave this game?",
                message: "Everyone's spot on the board is saved. Continue any time from Home.",
                confirmTitle: "Leave",
                icon: Icons.AutoMirrored.Rounded.Logout,
                destructive: true,
                onConfirm: { session.save(); onPlayers() }
            )
        } else {
            onPlayers()
        }
    }

    private func askRestart() {
        let session = session
        prompt = RoyalPrompt(
            title: "Restart the game?",
            message: "All tokens go back to the start.",
            confirmTitle: "Restart",
            icon: Icons.Rounded.Refresh,
            onConfirm: { session.restart(); recorded = false; showResult = false }
        )
    }

    /// The keys of Kotlin's bot `LaunchedEffect`.
    private struct BotKey: Hashable {
        let activePlayer: Int
        let isBusy: Bool
        let isFinished: Bool
        let turnID: Int
        let showResult: Bool
    }

    var body: some View {
        let theme = session.theme
        ZStack(alignment: .topLeading) {
            SnakesBackdropView(theme)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let wide = w > h * 1.05
                VStack(spacing: 0) {
                    RoyalTopBar(theme.name, { requestExit() }, subtitle: "\(session.players.count) players · Offline") {
                        RoundIconButton(Icons.Rounded.Refresh, { if !session.isBusy { askRestart() } }, size: 42, contentDescription: "Restart match")
                        RoundIconButton(Icons.Rounded.Settings, { showSettings = true }, size: 42, contentDescription: "Settings")
                    }
                    .background(
                        LinearGradient(colors: [Royal.Night.copy(alpha: 0.8), Royal.Night.copy(alpha: 0.35), Color.clear], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                    )
                    if wide {
                        HStack(alignment: .top, spacing: 20) {
                            BoardArea(session: session, rawCell: min((h - 90) / 11.2, w * 0.58 / 10), fill: false)
                            VStack(spacing: 14) {
                                Banner(session: session)
                                Standings(session: session)
                                Spacer(minLength: 0)
                                Controls(session: session, onRoll: roll)
                            }
                            .frame(maxWidth: 400)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        VStack(spacing: 12) {
                            Banner(session: session)
                            BoardArea(session: session, rawCell: min((w - 24) / 10, (h - 360) / 11.1))
                            Standings(session: session)
                            Spacer(minLength: 0)
                            Controls(session: session, onRoll: roll)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }

            if showResult {
                let order = session.game.standings
                let winner = order.first.map { session.players[$0] }
                PartyResultOverlay(
                    title: "\(winner?.name ?? "Someone") wins!",
                    subtitle: "First to reach 100 on \(theme.name)",
                    winner: winner,
                    standings: order.map { index in
                        let place = session.game.finishOrder.firstIndex(of: index).map { $0 + 1 }
                        return PartyStanding(session.players[index], place.map { session.ordinal($0) } ?? "Square \(session.game.positions[index])")
                    },
                    accent: [theme.accent.color, theme.frame.color],
                    primaryTitle: "Play Again",
                    onPrimary: { showResult = false; recorded = false; session.restart() },
                    onHub: onHome,
                    secondaryTitle: "Players",
                    onSecondary: onPlayers,
                    winnerIsBot: order.first.map { session.isBot($0) } ?? false
                )
                .zIndex(40)
            }
            QuickSettingsOverlay(showSettings) { showSettings = false }
                .zIndex(50)
            RoyalDialogHost(prompt) { prompt = nil }
                .zIndex(60)
        }
        .onDisappear {
            scope.cancel()
            session.save()
        }
        .task(id: session.isFinished) {
            if !session.isFinished { return }
            if !recorded {
                if let first = session.game.finishOrder.first {
                    recorded = true
                    PartyStore.record(.SNAKES, session.players, session.players[first], "Won in \(session.game.turnCount) rolls · \(theme.name)")
                }
            }
            try? await Task.sleep(nanoseconds: (reduce ? 200 : 700) * 1_000_000)
            if Task.isCancelled { return }
            showResult = true
        }
        // Computer players roll on their own (new on Android).
        .task(id: BotKey(activePlayer: session.activePlayer, isBusy: session.isBusy, isFinished: session.isFinished,
                         turnID: session.turnID, showResult: showResult)) {
            if session.isBusy || session.isFinished || showResult || !session.isBot(session.activePlayer) { return }
            try? await Task.sleep(nanoseconds: (reduce ? 350 : 900) * 1_000_000)
            if Task.isCancelled { return }
            if !session.isBusy && prompt == nil { roll() }
        }
        // Haptics.
        .onChange(of: session.rollCount) { _, n in if n > 0 { Haptics.play(.Medium) } }
        .onChange(of: session.hops.reduce(0, +)) { _, n in if n > 0 { Haptics.play(.Tick) } }
        .onChange(of: session.finishedCelebration) { _, n in if n > 0 { Haptics.play(.Success) } }
    }
}

// MARK: - Banner

private struct Banner: View {
    let session: SnakesSession

    var body: some View {
        TurnBanner(session.currentPlayer, session.headline, session.message, session.turnID)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Board

private struct BoardArea: View {
    let session: SnakesSession
    let rawCell: CGFloat
    var fill: Bool = true

    var body: some View {
        let cell = max(18, rawCell.rounded(.down))
        let theme = session.theme
        let frame = max(3, cell * 0.24)
        let padColor = theme.isDark ? SnakesColor.White.copy(alpha: 0.75).color : theme.numberColor.copy(alpha: 0.7).color
        ZStack(alignment: .topLeading) {
            SnakesBoardArt(theme, cell)
                .equatable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(session.players.indices.map { i in
                    let sq = session.game.positions[i]
                    return "\(session.players[i].name) \(sq == 0 ? "at start" : "on \(sq)")"
                }.joined(separator: ", "))
                .background(
                    RoundedRectangle(cornerRadius: cell * 0.35 + frame, style: .circular)
                        .fill(theme.frame.color)
                        // shadow(18.dp, spotColor = Black × (0.5 dark / 0.18 light), ambientColor = Black), on `composeShadow`'s scale.
                        .shadow(color: Color.black.opacity(theme.isDark ? 0.27 : 0.13), radius: 18 * 0.55, x: 0, y: 18 * 0.35)
                )

            // Start pad below square 1.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Icon(Icons.Rounded.SportsScore, tint: padColor, size: max(11, cell * 0.3))
                Spacer().frame(width: 4)
                Text("START", style: bodyStyle(max(9, cell * 0.24), .Black, padColor))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: cell * (CGFloat(session.players.count) * 0.62 + 2.1), height: cell * 0.8)
            .background((theme.isDark ? SnakesColor.White : theme.frame).copy(alpha: 0.14).color)
            .clipShape(Capsule())
            .offset(y: cell * 10.15)
            .accessibilityHidden(true)

            ForEach(Array(session.players.indices), id: \.self) { index in
                TokenSlot(session: session, index: index, cell: cell)
                    .accessibilityHidden(true)
            }

            SpotlightLayer(session: session)
                .frame(width: cell * 10)
                .offset(y: cell * 0.4)
                .zIndex(20)

            if session.finishedCelebration > 0 {
                Confetti(count: 90, durationMs: 3000)
                    .frame(width: cell * 10, height: cell * 10)
                    .id(session.finishedCelebration)
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        .frame(width: cell * 10, height: cell * 11, alignment: .topLeading)
        .frame(maxWidth: fill ? .infinity : nil, alignment: .top)
    }
}

/// One token, animated to its latest point with the move's spring or tween.
private struct TokenSlot: View {
    let session: SnakesSession
    let index: Int
    let cell: CGFloat

    var body: some View {
        let target = session.tokenPoints[index]
        let kind = session.tokenAnims[index]
        let spec: Animation = switch kind {
        case .HOP: snakesSpringOf(0.24, 0.72)
        case .LADDER: .linear(duration: 0.06)
        case .SNAKE: .linear(duration: 0.03)
        case .RELAYOUT: snakesSpringOf(0.35, 0.8)
        }
        let scale = CGFloat(session.tokenScale(index))
        let size = cell * 0.66
        let half = size / 2
        let active = index == session.activePlayer && !session.isFinished
        TokenView(
            player: session.players[index], size: size, isCurrent: active, hop: session.hops[index],
            finished: session.game.hasFinished(index), isBot: session.isBot(index)
        )
        .animation(.compose(dampingRatio: 0.8, stiffness: 322)) { $0.scaleEffect(scale) }
        .animation(spec) { $0.offset(x: CGFloat(target.x) * cell - half, y: CGFloat(target.y) * cell - half) }
        .zIndex(session.movingPlayer == index ? 10 : (active ? 5 : 1))
    }
}

private struct SpotlightLayer: View {
    let session: SnakesSession

    var body: some View {
        ZStack {
            if let s = session.spotlight {
                SpotlightToast(spotlight: s)
                    .id(s.id)
                    .transition(.asymmetric(
                        // scaleIn(0.7, spring(0.75, 247)) + fadeIn() / scaleOut(0.7) + fadeOut(tween(300)).
                        insertion: AnyTransition.scale(scale: 0.7).animation(.compose(dampingRatio: 0.75, stiffness: 247))
                            .combined(with: AnyTransition.opacity.animation(.compose(dampingRatio: 1, stiffness: 400))),
                        removal: AnyTransition.scale(scale: 0.7).animation(.compose(dampingRatio: 1, stiffness: 400))
                            .combined(with: AnyTransition.opacity.animation(.tween(300)))
                    ))
                    .task(id: s.id) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        if Task.isCancelled { return }
                        session.clearSpotlight(s.id)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.composeDefaultSpring, value: session.spotlight?.id)
    }
}

// MARK: - Standings

private struct Standings: View {
    let session: SnakesSession

    var body: some View {
        let order = session.game.standings
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(order, id: \.self) { index in
                    StandingChip(session: session, index: index)
                }
            }
            .animation(.compose(dampingRatio: 1, stiffness: 400), value: order)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StandingChip: View {
    let session: SnakesSession
    let index: Int

    var body: some View {
        let player = session.players[index]
        let square = session.game.positions[index]
        let place = session.game.finishOrder.firstIndex(of: index)
        let isCurrent = index == session.activePlayer && !session.isFinished
        HStack(spacing: 0) {
            AvatarBadge(player, size: 30)
            Spacer().frame(width: 8)
            VStack(alignment: .leading, spacing: 0) {
                SnakesWidthIn(max: 120) {
                    Text(player.name, style: bodyStyle(13, .ExtraBold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(place.map { "🏆 \(session.ordinal($0 + 1))" } ?? (square == 0 ? "At start" : "Square \(square)"),
                     style: bodyStyle(11, .Bold, Royal.Smoke))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Royal.panelBrush)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(isCurrent ? player.color : Royal.Stroke, lineWidth: 2.5))
        .background(Capsule().fill(Royal.Panel).composeShadow(isCurrent ? 8 : 4, color: isCurrent ? player.color : .black))
        .animation(.compose(dampingRatio: 0.8, stiffness: 195)) { $0.scaleEffect(isCurrent ? 1 : 0.96) }
        .padding(.vertical, 6)
    }
}

/// Compose `Modifier.widthIn(max = …)` inside an unbounded row: the child gets at most `max`, so long text truncates.
private struct SnakesWidthIn: Layout {
    let max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified)
        let width = Swift.min(ideal.width, max, proposal.width ?? .infinity)
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

// MARK: - Controls

private struct Controls: View {
    let session: SnakesSession
    let onRoll: () -> Void

    var body: some View {
        let player = session.currentPlayer
        let pc = SnakesColor.player(player)
        let botTurn = session.isBot(session.activePlayer)
        let enabled = !session.isBusy && !session.isFinished && !botTurn
        let shape = RoundedCornerShape(28)
        HStack(spacing: 14) {
            DiceView(session.diceValue, session.isRolling, pc.mix(.Black, 0.35))
                .frame(width: 72, height: 72)
                .pressable(enabled: enabled, sound: nil, pressedScale: 0.9) { onRoll() }
                .accessibilityLabel("Dice showing \(session.diceValue)")
            VStack(alignment: .leading, spacing: 8) {
                LastMoveRow(session: session)
                let label = session.isBusy ? "Moving…" : (botTurn && !session.isFinished ? "\(player.name) rolls…" : "Roll Dice")
                CandyButton(
                    label, { if enabled { onRoll() } },
                    colors: [pc.mix(.White, 0.25).color, pc.color, pc.mix(.Black, 0.22).color],
                    textColor: .white,
                    icon: session.isBusy ? Icons.Rounded.HourglassTop : (botTurn ? Icons.Rounded.SmartToy : Icons.Rounded.Casino),
                    enabled: enabled || session.isBusy || botTurn,
                    height: 52, fontSize: 20,
                    sound: .Pop
                )
                .frame(maxWidth: .infinity)
                .opacity(session.isBusy ? 0.7 : 1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Royal.panelBrush)
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [player.color.copy(alpha: 0.7), Royal.Stroke], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
        .background(shape.fill(Royal.Panel).composeShadow(16))
    }
}

private struct LastMoveRow: View {
    let session: SnakesSession

    var body: some View {
        ZStack(alignment: .leading) {
            if let move = session.lastMove {
                let mover = session.players[move.player]
                HStack(spacing: 6) {
                    Text(verbatim: mover.avatar).font(.system(size: 13))
                    Text("\(mover.name) · rolled \(move.roll)", style: bodyStyle(12, .Bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                    if move.to != move.from {
                        Text("\(move.from == 0 ? "Start" : "\(move.from)") → \(move.to)", style: bodyStyle(12, .Bold, Royal.Smoke))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .transition(.opacity)
            }
        }
        // AnimatedVisibility(fadeIn(), fadeOut()): Compose's default fade spring.
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: session.lastMove == nil)
    }
}

// MARK: - Pieces

private struct TokenView: View {
    let player: PartyPlayer
    let size: CGFloat
    let isCurrent: Bool
    let hop: Int
    let finished: Bool
    let isBot: Bool

    private static let fastOutSlowIn = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1))

    var body: some View {
        let c = SnakesColor.player(player)
        ZStack {
            // Ground shadow.
            Ellipse()
                .fill(Color.black.opacity(0.25))
                .frame(width: size * 0.8, height: size * 0.22)
                .blur(radius: 1)
                .offset(y: size * 0.46)
            ZStack {
                if isCurrent { PulseRing(player.color).frame(width: size, height: size) }
                TokenFace(color: c, size: size)
                    .equatable()
                    .background(Circle().fill(c.color).composeShadow(3))
                Text(verbatim: player.avatar).font(.system(size: size * 0.5))
                if finished {
                    Text(verbatim: "👑").font(.system(size: size * 0.38)).offset(y: -size * 0.56)
                } else if isBot {
                    ZStack {
                        Circle().fill(Royal.Night)
                        Circle().strokeBorder(Color.white, lineWidth: 1)
                        Icon(Icons.Rounded.SmartToy, tint: Royal.Gold, size: size * 0.24)
                    }
                    .frame(width: size * 0.36, height: size * 0.36)
                    .offset(x: size * 0.08 + (size - size * 0.36) / 2, y: size * 0.08 + (size - size * 0.36) / 2)
                }
            }
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: 0.0, trigger: hop) { content, lift in
                content
                    .scaleEffect(1 + lift * 0.08)
                    .offset(y: -lift * size * 0.45)
            } keyframes: { _ in
                LinearKeyframe(1.0, duration: 0.1, timingCurve: Self.fastOutSlowIn)
                LinearKeyframe(0.0, duration: 0.14, timingCurve: Self.fastOutSlowIn)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The token disc: seat-colour radial gradient with a white rim.
private struct TokenFace: View, Equatable {
    let color: SnakesColor
    let size: CGFloat

    var body: some View {
        let c = color
        Canvas { ctx, sz in
            let r = min(sz.width, sz.height) / 2
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [c.mix(.White, 0.35).color, c.color, c.mix(.Black, 0.25).color]),
                    center: CGPoint(x: sz.width * 0.35, y: sz.height * 0.3), startRadius: 0, endRadius: sz.width * 0.7
                )
            )
            let bw = max(1.5, sz.width * 0.08)
            let rr = r - bw / 2
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)), with: .color(.white), lineWidth: bw)
        }
        .frame(width: size, height: size)
    }
}

private let SNAKES_PIPS: [Int: [(Double, Double)]] = [
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
]

/// White die with coloured pips that tumbles while rolling (ported from DiceView). Fills the (square) frame it is given.
struct DiceView: View {
    let value: Int
    let isRolling: Bool
    let pipColor: SnakesColor

    init(_ value: Int, _ isRolling: Bool, _ pipColor: SnakesColor) {
        self.value = value
        self.isRolling = isRolling
        self.pipColor = pipColor
    }

    private static let spring = Animation.compose(dampingRatio: 0.5, stiffness: pow(2 * Double.pi / 0.18, 2))

    var body: some View {
        let rot = isRolling ? Double((value * 53) % 50 - 25) : 0
        let rot3 = isRolling ? Double((value * 31) % 40 - 20) : 0
        let scale: CGFloat = isRolling ? 0.9 : 1
        let dy: CGFloat = isRolling ? CGFloat((value * 17) % 8 - 4) : 0
        let elevation: CGFloat = isRolling ? 4 : 10
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let shape = RoundedCornerShape(s * 0.24)
            DiceFace(value: value, pipColor: pipColor, side: s)
                .equatable()
                .frame(width: s, height: s)
                .background(LinearGradient(colors: [Color.white, SnakesColor(0xEDEAF4).color], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                .animation(Self.spring) { content in
                    content
                        .background(shape.fill(Color.white).shadow(color: Color.black.opacity(0.3), radius: elevation * 0.55, x: 0, y: elevation * 0.35))
                        .scaleEffect(scale)
                        .rotation3DEffect(.degrees(rot3 * 0.7), axis: (x: 1, y: 0, z: 0), perspective: 0.2)
                        .rotation3DEffect(.degrees(rot3 * 0.7), axis: (x: 0, y: 1, z: 0), perspective: 0.2)
                        .rotationEffect(.degrees(rot))
                        .offset(y: dy)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private struct DiceFace: View, Equatable {
    let value: Int
    let pipColor: SnakesColor
    let side: CGFloat

    var body: some View {
        let pip = pipColor
        let value = value
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            for (x, y) in SNAKES_PIPS[value] ?? [] {
                let c = CGPoint(x: x * side, y: y * side)
                let r = side * 0.09
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [pip.mix(.White, 0.15).color, pip.color]),
                        center: CGPoint(x: c.x - r, y: c.y - r), startRadius: 0, endRadius: side * 0.1 * 1.6
                    )
                )
            }
        }
    }
}

private struct SpotlightToast: View {
    let spotlight: SnakesSession.Spotlight

    var body: some View {
        let emoji: String = switch spotlight.kind {
        case .LADDER: "🪜"
        case .SNAKE: "🐍"
        case .FINISH: "🏆"
        case .SIX: "🎲"
        }
        let c = SnakesColor.player(spotlight.player)
        HStack(spacing: 0) {
            Text(verbatim: emoji).font(.system(size: 24))
            Spacer().frame(width: 10)
            Text(spotlight.text, style: bodyStyle(15, .ExtraBold, .white))
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(LinearGradient(colors: [c.color, c.mix(.Black, 0.3).color], startPoint: .leading, endPoint: .trailing))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5))
        .background(Capsule().fill(c.color).composeShadow(12))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }
}
