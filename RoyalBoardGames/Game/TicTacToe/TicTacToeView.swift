import SwiftUI
import UIKit
import GameKit

/// A Tic-Tac-Toe match: score board, status, the board, pass-the-device hand-offs and results.
struct TicTacToeScreen: View {
    let config: TicTacToeConfig
    let onPlayers: () -> Void
    let onHub: () -> Void

    @State private var match: TicTacToeMatch
    @State private var busy = false
    @State private var passTo: PartyPlayer? = nil
    @State private var showResult = false
    @State private var prompt: RoyalPrompt? = nil
    @State private var showSettings = false
    /// Bumped on every restart so stale bot moves and mark animations are dropped.
    @State private var generation = 0

    init(config: TicTacToeConfig, onPlayers: @escaping () -> Void, onHub: @escaping () -> Void) {
        self.config = config
        self.onPlayers = onPlayers
        self.onHub = onHub
        _match = State(initialValue: TicTacToeMatch(config.bestOf))
    }

    private var reduceMotion: Bool { LocalReduceMotion.current }

    private func player(_ mark: TTTMark) -> PartyPlayer { config.player(mark) }

    private var botTurn: Bool {
        config.botMark != nil && match.board.turn == config.botMark && !match.board.isOver && !match.isMatchOver
    }

    private func recordMatch() {
        guard let winnerMark = match.matchWinner else { return }
        let winner = player(winnerMark)
        let loser = player(winnerMark.other)
        PartyStore.record(
            .TIC_TAC_TOE,
            [config.playerX, config.playerO],
            winner,
            config.bestOf > 1 ? "Won \(match.wins(winnerMark))–\(match.wins(winnerMark.other)) vs \(loser.name)" : "Beat \(loser.name)"
        )
    }

    private func place(_ index: Int) {
        if busy || passTo != nil { return }
        let mover = match.board.turn
        var next = match.copy()
        if !next.play(index) { return }
        busy = true
        match = next
        Haptics.play(.Medium)
        UiSound.play(.Place)
        let gen = generation
        let reduce = reduceMotion
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduce ? 120 : 320))
            if gen != generation { return }
            if match.board.isOver {
                Haptics.play(.Success)
                UiSound.play(match.board.win != nil ? .Win : .Draw)
                if match.isMatchOver {
                    recordMatch()
                    try? await Task.sleep(for: .milliseconds(reduce ? 300 : 1100))
                    if gen != generation { return }
                    showResult = true
                }
            } else if config.passDevice && config.botMark == nil {
                passTo = player(mover.other)
            }
            busy = false
        }
    }

    private func nextRound() {
        var next = match.copy()
        next.nextRound()
        match = next
        UiSound.play(.Turn)
        if config.passDevice && config.botMark == nil { passTo = player(match.board.turn) }
    }

    private func restartMatch() {
        generation += 1
        match = TicTacToeMatch(config.bestOf)
        showResult = false
        passTo = nil
        busy = false
    }

    private func restartRound() {
        var next = match.copy()
        next.restartRound()
        match = next
        generation += 1
        busy = false
    }

    private func requestExit() {
        let live = match
        if !live.isMatchOver && (live.board.moveCount > 0 || live.round > 1) {
            prompt = RoyalPrompt(
                title: "Leave this match?",
                message: "The current score will be lost.",
                confirmTitle: "Leave",
                cancelTitle: "Keep playing",
                icon: Icons.AutoMirrored.Rounded.Logout,
                destructive: true,
                onConfirm: onPlayers
            )
        } else {
            onPlayers()
        }
    }

    /// Kotlin `LaunchedEffect(botTurn, match, busy, generation)`.
    private struct BotKey: Equatable {
        let botTurn: Bool
        let match: TicTacToeMatch
        let busy: Bool
        let generation: Int
    }

    var body: some View {
        let accent = GameAccent.ticTacToe
        RoyalBackground(glow: accent[0], secondGlow: accent[1]) {
            ZStack {
                GeometryReader { geo in
                    table(geo)
                }

                ZStack {
                    if let p = passTo {
                        PassDeviceOverlay(p, "You're \(p.id == config.playerX.id ? "X" : "O"). Tap when you're holding the device.") { passTo = nil }
                            .transition(.opacity)
                    }
                }
                .animation(.tween(250), value: passTo?.id)

                ZStack {
                    if showResult {
                        resultOverlay
                            .transition(.asymmetric(insertion: .opacity.animation(.tween(300)), removal: .opacity.animation(.tween(200))))
                    }
                }

                QuickSettingsOverlay(showSettings) { showSettings = false }
                RoyalDialogHost(prompt) { prompt = nil }
            }
        }
        // The computer takes its turn after a short think.
        .task(id: BotKey(botTurn: botTurn, match: match, busy: busy, generation: generation)) {
            if !botTurn || busy { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 560))
            if Task.isCancelled { return }
            let board = match.board.copy()
            let level = config.botLevel
            let choice = await Task.detached(priority: .userInitiated) { TicTacToeBot.choose(board, level) }.value
            if Task.isCancelled { return }
            guard let choice else { return }
            place(choice)
        }
    }

    @ViewBuilder
    private func table(_ geo: GeometryProxy) -> some View {
        let insets = windowInsets()
        // Compose measures the whole edge-to-edge window here.
        let maxW = geo.size.width
        let maxH = geo.size.height + insets.top + insets.bottom
        let wide = maxW > maxH * 1.05
        let boardInteractive = !busy && passTo == nil && !botTurn
        VStack(spacing: 0) {
            RoyalTopBar(
                "Tic-Tac-Toe",
                { requestExit() },
                subtitle: (config.bestOf > 1 ? "Best of \(config.bestOf)" : "Single game") +
                    (config.botMark != nil ? " · vs Computer (\(config.botLevel.title))" : " · Offline")
            ) {
                RoundIconButton(Icons.Rounded.Replay, {
                    prompt = RoyalPrompt(
                        title: "Restart the match?",
                        message: "Scores go back to 0–0.",
                        confirmTitle: "Restart",
                        cancelTitle: "Keep playing",
                        icon: Icons.Rounded.Replay,
                        onConfirm: { restartMatch() }
                    )
                }, contentDescription: "Restart match")
                RoundIconButton(Icons.Rounded.Settings, { showSettings = true }, contentDescription: "Settings")
            }
            if wide {
                HStack(alignment: .center, spacing: 24) {
                    TttBoard(match: match, config: config, size: min(maxH - 140, maxW * 0.5), interactive: boardInteractive, generation: generation, onPlace: place)
                    VStack(spacing: 16) {
                        ScorePanel(match: match, config: config)
                        StatusArea(match: match, config: config, onNext: nextRound)
                        RestartRoundButton(match: match, onRestart: restartRound)
                    }
                    .frame(maxWidth: 420)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Fits small phones too: the board never pushes the restart button off screen.
                let fit = geo.size.height - 390
                VStack(spacing: 16) {
                    ScorePanel(match: match, config: config)
                    StatusArea(match: match, config: config, onNext: nextRound)
                    Spacer(minLength: 0)
                    TttBoard(match: match, config: config, size: min(maxW - 40, maxH - 360, 440, fit), interactive: boardInteractive, generation: generation, onPlace: place)
                    Spacer(minLength: 0)
                    RestartRoundButton(match: match, onRestart: restartRound)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var resultOverlay: some View {
        let winnerMark = match.matchWinner ?? .X
        let winner = player(winnerMark)
        return PartyResultOverlay(
            title: "\(winner.name) wins!",
            subtitle: config.bestOf > 1
                ? "Match won \(match.wins(winnerMark))–\(match.wins(winnerMark.other)) · \(match.draws) draw\(match.draws == 1 ? "" : "s")"
                : "Three in a row",
            winner: winner,
            standings: [
                PartyStanding(winner, "\(match.wins(winnerMark)) wins"),
                PartyStanding(player(winnerMark.other), "\(match.wins(winnerMark.other)) wins"),
            ],
            accent: GameAccent.ticTacToe,
            primaryTitle: "Play Again",
            onPrimary: { restartMatch() },
            onHub: onHub,
            secondaryTitle: "Players",
            onSecondary: onPlayers,
            winnerIsBot: config.isBot(winnerMark)
        )
    }
}

/// The key window's safe-area insets (Compose's BoxWithConstraints sees the edge-to-edge window).
@MainActor
private func windowInsets() -> UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first?.keyWindow?.safeAreaInsets ?? scenes.first?.windows.first?.safeAreaInsets ?? .zero
}

// MARK: - Score

private struct ScorePanel: View {
    let match: TicTacToeMatch
    let config: TicTacToeConfig

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ScoreCard(match: match, config: config, mark: .X)
            VStack(spacing: 2) {
                Text("ROUND", style: bodyStyle(10, .Black, Royal.Smoke).copy(letterSpacing: 1))
                ZStack {
                    Text("\(match.round)", style: displayStyle(26, Royal.Gold))
                        .id(match.round)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 1.4).combined(with: .opacity)
                        ))
                }
                .animation(.compose(dampingRatio: 1, stiffness: 400), value: match.round)
                Text(match.draws == 1 ? "1 draw" : "\(match.draws) draws", style: bodyStyle(11, .Bold, Royal.Smoke))
            }
            .frame(width: 64)
            ScoreCard(match: match, config: config, mark: .O)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScoreCard: View {
    let match: TicTacToeMatch
    let config: TicTacToeConfig
    let mark: TTTMark

    var body: some View {
        let p = config.player(mark)
        let active = match.board.turn == mark && !match.board.isOver
        let shape = RoundedCornerShape(22)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarBadge(p, size: 36, isActive: active)
                MarkGlyph(mark, p.color, 3.5).frame(width: 18, height: 18)
                Spacer(minLength: 0)
                AnimatedCountText(match.wins(mark), style: displayStyle(28, Royal.Ivory))
            }
            HStack(spacing: 4) {
                Text(p.name, style: bodyStyle(14, .Black)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if config.bestOf > 1 {
                    HStack(spacing: 3) {
                        ForEach(0..<match.winsNeeded, id: \.self) { i in
                            PipDot(color: p.color, dot: i < match.wins(mark) ? 1 : 0)
                                .animation(.compose(dampingRatio: 0.5, stiffness: 1500), value: i < match.wins(mark))
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(ZStack {
            Royal.panelBrush
            if active { p.color.copy(alpha: 0.12) }
        })
        .clipShape(shape)
        .overlay(shape.strokeBorder(active ? p.color : Royal.Stroke, lineWidth: active ? 2.5 : 1))
        .background(shape.fill(Royal.Panel).composeShadow(active ? 14 : 6, color: active ? p.color : .black))
        .scaleEffect(active ? 1.02 : 0.97)
        .animation(.compose(dampingRatio: 0.75, stiffness: 400), value: active)
        .opacity(active || match.board.isOver ? 1 : 0.8)
        .animation(.tween(250), value: active || match.board.isOver)
    }
}

/// A match-point pip: bulges while it fills (Kotlin `scale = 1 + 0.4·dot·(1−dot)·4`).
private struct PipDot: View, Animatable {
    let color: Color
    var dot: Double

    var animatableData: Double {
        get { dot }
        set { dot = newValue }
    }

    var body: some View {
        Circle()
            .fill(lerp(Color.white.opacity(0.15), color, dot))
            .frame(width: 7, height: 7)
            .scaleEffect(1 + 0.4 * dot * (1 - dot) * 4)
    }
}

// MARK: - Status

private enum Status: Equatable {
    case RoundWon(mark: TTTMark, round: Int)
    case RoundDraw(round: Int)
    case Turn(mark: TTTMark, key: Int)
    case Empty

    /// Kotlin `contentKey`: every turn shares one key (the banner slides by itself).
    var contentKey: String {
        switch self {
        case let .RoundWon(mark, round): return "won-\(mark.label)-\(round)"
        case let .RoundDraw(round): return "draw-\(round)"
        case .Turn: return "turn"
        case .Empty: return "empty"
        }
    }
}

private struct StatusArea: View {
    let match: TicTacToeMatch
    let config: TicTacToeConfig
    let onNext: () -> Void

    var body: some View {
        let board = match.board
        let status: Status = {
            if let win = board.win, !match.isMatchOver { return .RoundWon(mark: win.mark, round: match.round) }
            if board.isDraw && !match.isMatchOver { return .RoundDraw(round: match.round) }
            if !board.isOver { return .Turn(mark: board.turn, key: match.round) }
            return .Empty
        }()
        ZStack {
            content(status)
                .id(status.contentKey)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).animation(.compose(dampingRatio: 1, stiffness: 400)),
                    removal: .opacity.animation(.tween(120))
                ))
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: status.contentKey)
    }

    @ViewBuilder
    private func content(_ s: Status) -> some View {
        switch s {
        case let .RoundWon(mark, round):
            RoundCard(title: "\(config.player(mark).name) wins round \(round)!", player: config.player(mark),
                      nextStarter: config.player(match.roundStarter.other).name, onNext: onNext)
        case let .RoundDraw(round):
            RoundCard(title: "Round \(round) is a draw", player: nil, nextStarter: config.player(match.roundStarter.other).name, onNext: onNext)
        case .Turn:
            let board = match.board
            let current = config.player(board.turn)
            let bot = config.isBot(board.turn)
            TurnBanner(
                current,
                bot ? "\(current.name) is thinking…" : "It's \(current.name)'s turn",
                "Place your \(board.turn.label)\(config.bestOf > 1 ? " · Round \(match.round)" : "")",
                board.moveCount + match.round * 10
            )
        case .Empty:
            Color.clear.frame(maxWidth: .infinity, minHeight: 78)
        }
    }
}

private struct RoundCard: View {
    let title: String
    let player: PartyPlayer?
    let nextStarter: String
    let onNext: () -> Void

    var body: some View {
        let accent = GameAccent.ticTacToe
        let shape = RoundedCornerShape(24)
        HStack(spacing: 12) {
            if let player {
                AvatarBadge(player, size: 46)
            } else {
                ZStack {
                    Circle().fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Icon(Icons.Rounded.DragHandle, tint: .white, size: 28)
                }
                .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title, style: displayStyle(18)).lineLimit(2)
                Text("\(nextStarter) starts the next round", style: bodyStyle(12, .SemiBold, Royal.Smoke))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CandyButton(
                "Next", onNext,
                colors: [lerp(accent[0], Color.White, Float(0.25)), accent[0], accent[1]],
                textColor: .white, height: 44, fontSize: 18, sound: .Pop
            )
            .frame(width: 92)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Royal.panelBrush)
        .clipShape(shape)
        .overlay(shape.strokeBorder((player?.color ?? Royal.Gold).copy(alpha: 0.6), lineWidth: 1.5))
        .background(shape.fill(Royal.Panel).composeShadow(14, color: player?.color ?? accent[0]))
    }
}

private struct RestartRoundButton: View {
    let match: TicTacToeMatch
    let onRestart: () -> Void

    var body: some View {
        let enabled = match.board.moveCount > 0 && !match.isMatchOver
        OutlineButton("Restart round", {
            if enabled {
                UiSound.play(.Tap)
                onRestart()
            }
        }, icon: Icons.AutoMirrored.Rounded.Undo, height: 48)
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Board

private let positions = ["top left", "top middle", "top right", "middle left", "centre", "middle right", "bottom left", "bottom middle", "bottom right"]

private struct TttBoard: View {
    let match: TicTacToeMatch
    let config: TicTacToeConfig
    let size: CGFloat
    let interactive: Bool
    let generation: Int
    let onPlace: (Int) -> Void

    var body: some View {
        let side = max(size, 200)
        let gap = side * 0.035
        let cell = (side - gap * 4) / 3
        let board = match.board
        let win = board.win
        let shape = RoundedCornerShape(side * 0.09)
        func origin(_ index: Int) -> CGPoint {
            CGPoint(x: gap + (cell + gap) * CGFloat(index % 3), y: gap + (cell + gap) * CGFloat(index / 3))
        }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<9, id: \.self) { index in
                let mark = board.cells[index]
                let label = "\(positions[index]), \(mark?.label ?? "empty")"
                TttCell(match: match, config: config, index: index, size: cell, generation: generation)
                    .frame(width: cell, height: cell)
                    .contentShape(Rectangle())
                    .pressable(enabled: interactive && board.canPlay(index), sound: nil, haptic: nil, pressedScale: 0.94) { onPlace(index) }
                    .accessibilityLabel(label)
                    .offset(x: origin(index).x, y: origin(index).y)
            }
            if let win {
                let a = origin(win.line[0]), b = origin(win.line[2])
                WinningLine(
                    CGPoint(x: a.x + cell / 2, y: a.y + cell / 2),
                    CGPoint(x: b.x + cell / 2, y: b.y + cell / 2),
                    config.player(win.mark).color,
                    cell * 0.12
                )
                .frame(width: side, height: side)
                .id("line-\(match.round)-\(generation)")
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .background(Royal.PanelHigh.copy(alpha: 0.7))
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Royal.GoldLight.copy(alpha: 0.6), Royal.GoldDark.copy(alpha: 0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
        .background(shape.fill(Royal.Panel).composeShadow(24))
    }
}

private struct TttCell: View {
    let match: TicTacToeMatch
    let config: TicTacToeConfig
    let index: Int
    let size: CGFloat
    let generation: Int

    var body: some View {
        let board = match.board
        let mark = board.cells[index]
        let win = board.win
        let isWinning = win?.line.contains(index) == true
        let dimmed = board.isOver && !isWinning
        let shape = RoundedCornerShape(size * 0.22)
        ZStack {
            shape.fill(LinearGradient(colors: [Royal.PanelHigh, Royal.Panel], startPoint: .top, endPoint: .bottom))
            if isWinning, let win {
                shape.fill(config.player(win.mark).color.copy(alpha: 0.18))
            }
            if let mark {
                PlacedMark(mark: mark, color: config.player(mark).color, winning: isWinning, dimmed: dimmed)
                    .padding(size * 0.22)
                    .id("\(match.round)-\(index)-\(generation)")
            } else if !board.isOver {
                MarkGlyph(board.turn, config.player(board.turn).color.copy(alpha: 0.08), 3)
                    .padding(size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .background(shape.fill(Royal.Panel).composeShadow(6, color: Color.black))
    }
}

/// A mark that pops in (spring 0.7 / 500), grows a little on the winning line and dims on the others.
private struct PlacedMark: View {
    let mark: TTTMark
    let color: Color
    let winning: Bool
    let dimmed: Bool
    @State private var pop: CGFloat = 0.5

    var body: some View {
        AnimatedMark(mark, color)
            .scaleEffect(pop)
            .opacity(Double(min(1, max(0, (pop - 0.5) * 2))))
            .scaleEffect(winning ? 1.06 : 1)
            .animation(.compose(dampingRatio: 0.7, stiffness: 300), value: winning)
            .opacity(dimmed ? 0.3 : 1)
            .animation(.tween(250), value: dimmed)
            .onAppear { withAnimation(.compose(dampingRatio: 0.7, stiffness: 500)) { pop = 1 } }
    }
}
