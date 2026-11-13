import SwiftUI
import UIKit
import GameKit

/// Kotlin `springFor(response, damping)`: stiffness = (2π / response)², the SwiftUI response/damping spring.
private func springFor(_ response: Double, _ damping: Double) -> Animation {
    .compose(dampingRatio: damping, stiffness: pow(2 * Double.pi / response, 2))
}

private let MoveSpring = springFor(0.32, 0.82)
private let FlipSpring = springFor(0.6, 0.85)
private let DragResetSpring = springFor(0.3, 0.8)

/// The chess table: board, players, clocks, notation, actions and every overlay.
struct ChessGameScreen: View {
    let startConfig: ChessConfig
    let saved: ChessSaved?
    let onPlayers: () -> Void
    let onHome: () -> Void

    @State private var session: ChessSession
    @State private var showResult = false
    @State private var prompt: RoyalPrompt? = nil
    @State private var choice: ChessChoice? = nil
    @State private var showHistory = false
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    init(startConfig: ChessConfig, saved: ChessSaved?, onPlayers: @escaping () -> Void, onHome: @escaping () -> Void) {
        self.startConfig = startConfig
        self.saved = saved
        self.onPlayers = onPlayers
        self.onHome = onHome
        let s = ChessSession(startConfig)
        if let saved { s.restore(saved) }
        _session = State(initialValue: s)
    }

    private var inProgress: Bool { session.moveCount > 0 && !session.match.isOver }

    private func requestExit() {
        if inProgress {
            prompt = RoyalPrompt(
                title: "Leave this game?",
                message: "Your match is saved. Continue it any time from Home.",
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
        prompt = RoyalPrompt(
            title: "Restart the game?",
            message: "All pieces go back to their starting squares.",
            confirmTitle: "Restart",
            icon: Icons.Rounded.Refresh,
            onConfirm: { session.reset(); showResult = false }
        )
    }

    private func askResign() {
        if let human = session.humanColor {
            prompt = RoyalPrompt(
                title: "Resign this game?",
                message: "\(session.player(human.opposite).name) wins if you resign.",
                confirmTitle: "Resign",
                icon: Icons.Rounded.Flag,
                destructive: true,
                onConfirm: { session.resign(human) }
            )
        } else {
            choice = ChessChoice(
                title: "Who is resigning?",
                message: nil,
                options: [
                    ("\(session.player(.WHITE).name) resigns (White)", { session.resign(.WHITE) }),
                    ("\(session.player(.BLACK).name) resigns (Black)", { session.resign(.BLACK) }),
                ]
            )
        }
    }

    private func offerDraw() {
        if let human = session.humanColor {
            let bot = session.player(human.opposite)
            prompt = RoyalPrompt(
                title: "Offer a draw?",
                message: "\(bot.name) will accept only if the position is going badly for it.",
                confirmTitle: "Offer draw",
                icon: Icons.Rounded.PanTool,
                onConfirm: {
                    if session.botAcceptsDraw() {
                        session.agreeDraw()
                    } else {
                        UiSound.play(.Back)
                        session.showNotice("\(bot.name) declines the draw")
                    }
                }
            )
        } else {
            prompt = RoyalPrompt(
                title: "\(session.player(session.sideToMove).name) offers a draw",
                message: "\(session.player(session.sideToMove.opposite).name), do you accept?",
                confirmTitle: "Accept draw",
                cancelTitle: "Decline",
                icon: Icons.Rounded.PanTool,
                onConfirm: { session.agreeDraw() }
            )
        }
    }

    private func askClaim() {
        prompt = RoyalPrompt(
            title: "Claim a draw?",
            message: session.match.canClaimThreefold ? "This position has appeared three times." : "50 moves have passed without a capture or pawn move.",
            confirmTitle: "Claim draw",
            icon: Icons.Rounded.Balance,
            onConfirm: { session.claimDraw() }
        )
    }

    var body: some View {
        let accent = GameAccent.chess
        RoyalBackground(glow: accent[1], secondGlow: accent[0]) {
            ZStack {
                GeometryReader { geo in
                    table(geo)
                }

                // Promotion.
                ZStack {
                    if session.pendingPromotion != nil {
                        PromotionPicker(session: session)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.tween(200), value: session.pendingPromotion)

                // Pass the device.
                ZStack {
                    if let to = session.passTo {
                        PassDeviceOverlay(
                            session.player(to),
                            "You're playing \(to.title). The board stays hidden until you're ready."
                        ) { session.ready() }
                            .transition(.opacity)
                    }
                }
                .animation(.tween(250), value: session.passTo)

                if showHistory {
                    HistorySheet(session: session) { showHistory = false }
                }

                if showResult {
                    ResultOverlay(
                        session: session,
                        onRematch: { showResult = false; session.rematch(true) },
                        onPlayers: onPlayers,
                        onHome: onHome
                    )
                }

                QuickSettingsOverlay(
                    showSettings, { showSettings = false },
                    extra: ExtrasFeatures.chessTools
                        ? QuickSettingsAction(title: "Copy PGN", icon: Icons.Rounded.Description) { showSettings = false; session.copyPGN() }
                        : nil
                )
                ChoiceDialog(choice: choice) { choice = nil }
                RoyalDialogHost(prompt) { prompt = nil }
            }
        }
        .task { session.start() }
        // Clock.
        .task(id: session.usesClock) {
            guard session.usesClock else { return }
            while !Task.isCancelled {
                session.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        // Result.
        .task(id: session.resultCount) {
            if session.resultCount == 0 || !session.match.isOver { return }
            record(session)
            try? await Task.sleep(for: .milliseconds(900))
            if Task.isCancelled { return }
            showResult = true
        }
        // Haptics.
        .modifier(HapticOn(counter: session.moveCount, kind: .Medium))
        .modifier(HapticOn(counter: session.checkCount, kind: .Warning))
        .modifier(HapticOn(counter: session.illegalCount, kind: .Error))
        .modifier(HapticOn(counter: session.resultCount, kind: .Success))
        .onDisappear {
            session.save()
            session.dispose()
        }
        .onChange(of: scenePhase) { _, phase in
            session.suspended = phase != .active
            if phase != .active { session.save() }
        }
    }

    @ViewBuilder
    private func table(_ geo: GeometryProxy) -> some View {
        let accent = GameAccent.chess
        let bottomColor: ChessColor = session.flipped ? .BLACK : .WHITE
        let insets = windowInsets()
        // Compose measures the whole edge-to-edge window here.
        let w = geo.size.width
        let h = geo.size.height + insets.top + insets.bottom
        let wide = w > h * 1.05
        let levels = ["Easy", "Normal", "Hard"]
        let level = levels.indices.contains(session.config.botLevel) ? levels[session.config.botLevel] : "Normal"
        VStack(spacing: 0) {
            RoyalTopBar(
                "Chess",
                { requestExit() },
                subtitle: session.config.hasBot ? "\(session.config.clock.title) · vs Computer (\(level))" : "\(session.config.clock.title) · Offline"
            ) {
                RoundIconButton(Icons.Rounded.SwapVert, { session.flipped.toggle() }, size: 42, contentDescription: "Flip board")
                RoundIconButton(Icons.Rounded.Refresh, { askRestart() }, size: 42, contentDescription: "Restart game")
                RoundIconButton(Icons.Rounded.Settings, { showSettings = true }, size: 42, contentDescription: "Settings")
            }
            if wide {
                HStack(alignment: .center, spacing: 20) {
                    ChessBoard(session: session, side: min(h - 90, w * 0.58))
                    VStack(spacing: 12) {
                        PlayerPanel(session: session, color: bottomColor.opposite)
                        StatusLine(session: session)
                        if ExtrasFeatures.chessTools {
                            // Extras: a scrollable move list in place of the strip.
                            ExtrasChessMoveList(session: session, accent: accent[0]).frame(minHeight: 90, maxHeight: 220)
                        } else {
                            HistoryStrip(session: session, accent: accent[0])
                        }
                        ActionBar(session: session, onDraw: offerDraw, onResign: askResign, onClaim: askClaim) { showHistory = true }
                        PlayerPanel(session: session, color: bottomColor)
                    }
                    .frame(maxWidth: 420)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Fits small phones too: the board never pushes the action bar off screen.
                let fit = geo.size.height - 372
                VStack(spacing: 10) {
                    PlayerPanel(session: session, color: bottomColor.opposite)
                    ChessBoard(session: session, side: max(240, min(w - 20, h - 330, fit)))
                    PlayerPanel(session: session, color: bottomColor)
                    StatusLine(session: session)
                    HistoryStrip(session: session, accent: accent[0])
                    Spacer(minLength: 0)
                    ActionBar(session: session, onDraw: offerDraw, onResign: askResign, onClaim: askClaim) { showHistory = true }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The key window's safe-area insets (Compose's BoxWithConstraints sees the edge-to-edge window).
@MainActor
private func windowInsets() -> UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first?.keyWindow?.safeAreaInsets ?? scenes.first?.windows.first?.safeAreaInsets ?? .zero
}

/// Plays `kind` whenever `counter` changes to a positive value other than the one it started with.
private struct HapticOn: ViewModifier {
    let counter: Int
    let kind: Haptics.Kind
    @State private var first: Int? = nil

    func body(content: Content) -> some View {
        content
            .onAppear { if first == nil { first = counter } }
            .onChange(of: counter) { _, value in
                if value != first && value > 0 { Haptics.play(kind) }
            }
    }
}

@MainActor
private func record(_ session: ChessSession) {
    guard let result = session.match.result else { return }
    let winner = result.winner.map { session.player($0) }
    let moves = (session.match.sanMoves.count + 1) / 2
    PartyStore.record(
        .CHESS,
        [session.config.white, session.config.black],
        winner,
        "\(result.winner == nil ? result.reason : result.title.replacingOccurrences(of: "!", with: "")) · \(moves) move\(moves == 1 ? "" : "s")"
    )
}

// MARK: - Panels

private struct PlayerPanel: View {
    let session: ChessSession
    let color: ChessColor

    var body: some View {
        let player = session.player(color)
        let active = session.sideToMove == color && !session.match.isOver
        let inCheck = active && session.position.isInCheck(color)
        let captured = session.match.captured(color)
        let balance = session.match.materialBalance * (color == .WHITE ? 1 : -1)
        let shape = RoundedCornerShape(20)
        let ink = Color(argb: 0xFF24232B)
        HStack(spacing: 0) {
            AvatarBadge(player, size: 40, isActive: active)
            Spacer().frame(width: 10)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(player.name, style: bodyStyle(16, .ExtraBold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(color.title.uppercased(), style: bodyStyle(9, .Black, color == .WHITE ? ink : Color.white).copy(letterSpacing: 0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color == .WHITE ? Color.white : ink))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        .fixedSize()
                        .layoutPriority(1)
                    if inCheck {
                        Text("CHECK", style: bodyStyle(9, .Black, Color.white).copy(letterSpacing: 0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Royal.Ruby))
                            .fixedSize()
                            .layoutPriority(1)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if active && session.isBot(color) && session.botThinking {
                        ThinkingDots(color: player.color).layoutPriority(1)
                    }
                }
                .animation(.compose(dampingRatio: 1, stiffness: 400), value: inCheck)
                Spacer().frame(height: 3)
                HStack(spacing: -4) {
                    ForEach(Array(captured.enumerated()), id: \.offset) { _, kind in
                        ChessPieceView(ChessPiece(kind, color.opposite), 17)
                    }
                    if balance > 0 {
                        Text("+\(balance)", style: bodyStyle(11, .Black, Royal.Smoke))
                            .padding(.leading, 12)
                    }
                }
                .frame(height: 17)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let seconds = session.clocks[color] {
                let low = seconds < 20
                let bg: Color = active && low ? Royal.Ruby : (active ? player.color.copy(alpha: 0.25) : Royal.PanelHigh)
                Text(ChessSession.format(seconds), style: displayStyle(20, active ? (low ? Color.white : Royal.Ivory) : Royal.Smoke))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(RoundedCornerShape(12).fill(bg))
                    .clipShape(RoundedCornerShape(12))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(ZStack {
            Royal.panelBrush
            if active { player.color.copy(alpha: 0.10) }
        })
        .clipShape(shape)
        .overlay(shape.strokeBorder(active ? player.color : Royal.Stroke, lineWidth: 2))
        .background(shape.fill(Royal.Panel).composeShadow(active ? 12 : 6, color: active ? player.color : .black))
        .animation(.compose(dampingRatio: 0.8, stiffness: 1500), value: active)
    }
}

private struct ThinkingDots: View {
    let color: Color
    @State private var start = Date()

    var body: some View {
        let dot = lerp(color, Color.White, Float(0.3))
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 0.9) / 0.9
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = ((t * 3 - Double(i)).truncatingRemainder(dividingBy: 3) + 3).truncatingRemainder(dividingBy: 3)
                    let a = phase < 1 ? 0.4 + 0.6 * (1 - abs(phase - 0.5) * 2) : 0.4
                    Circle().fill(dot).frame(width: 5, height: 5).opacity(a)
                }
            }
        }
    }
}

private struct StatusLine: View {
    let session: ChessSession

    var body: some View {
        let over = session.match.isOver
        let check = session.position.isInCheck(session.sideToMove) && !over
        HStack(spacing: 8) {
            Circle()
                .fill(session.sideToMove == .WHITE ? Color.white : Color(argb: 0xFF24232B))
                .overlay(Circle().strokeBorder(Royal.Ivory.copy(alpha: 0.3), lineWidth: 1))
                .frame(width: 14, height: 14)
            Text(over ? (session.match.result?.title ?? "") : "\(session.sideToMove.title)'s turn", style: bodyStyle(15, .ExtraBold))
                .lineLimit(1)
                .fixedSize()
            Text("·", style: bodyStyle(15, .Bold, Royal.Smoke))
            Text(session.statusText, style: bodyStyle(13, .Bold, check ? Royal.Ruby : Royal.Smoke))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryStrip: View {
    let session: ChessSession
    let accent: Color

    var body: some View {
        let pairs = session.movePairs
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 6) {
                    if pairs.isEmpty {
                        Text("Moves appear here", style: bodyStyle(13, .SemiBold, Royal.Smoke))
                            .padding(.horizontal, 10)
                    }
                    ForEach(pairs) { pair in
                        let last = pair.number == pairs.count
                        HStack(spacing: 5) {
                            Text("\(pair.number).").foregroundStyle(Royal.Smoke)
                            Text(pair.white).foregroundStyle(Royal.Ivory)
                            if let black = pair.black { Text(black).foregroundStyle(Royal.Ivory) }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(last ? accent.copy(alpha: 0.28) : Royal.Panel))
                        .overlay(Capsule().strokeBorder(last ? accent.copy(alpha: 0.6) : Royal.Stroke, lineWidth: 1))
                        .id(pair.number)
                    }
                }
                .frame(height: 34)
            }
            .frame(height: 34)
            .onAppear {
                if let last = pairs.last { proxy.scrollTo(last.number, anchor: .leading) }
            }
            .onChange(of: session.moveCount) { _, _ in
                if let last = session.movePairs.last {
                    withAnimation(.compose(dampingRatio: 1, stiffness: 400)) { proxy.scrollTo(last.number, anchor: .leading) }
                }
            }
        }
    }
}

private struct ActionBar: View {
    let session: ChessSession
    let onDraw: () -> Void
    let onResign: () -> Void
    let onClaim: () -> Void
    let onMoves: () -> Void

    var body: some View {
        let canClaim = session.match.canClaimThreefold || session.match.canClaimFiftyMoves
        HStack(spacing: 8) {
            ActionButton(title: "Draw", icon: Icons.Rounded.PanTool, enabled: !session.match.isOver && session.moveCount > 0, onClick: onDraw)
            ActionButton(title: "Resign", icon: Icons.Rounded.Flag, enabled: !session.match.isOver, onClick: onResign)
            if canClaim { ActionButton(title: "Claim", icon: Icons.Rounded.Balance, enabled: true, onClick: onClaim, highlight: true) }
            // Extras: take back and hint against the computer.
            if ExtrasFeatures.chessTools && session.humanColor != nil {
                ActionButton(title: "Undo", icon: Icons.AutoMirrored.Rounded.Undo, enabled: session.canUndo, onClick: { session.undo() })
                ActionButton(title: session.hintBusy ? "Thinking" : "Hint", icon: ExtrasChessIcons.Hint, enabled: session.canHint || session.hint != nil,
                             onClick: { session.requestHint() }, highlight: session.hint != nil)
            }
            ActionButton(title: "Moves", icon: Icons.Rounded.FormatListNumbered, enabled: true, onClick: onMoves)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActionButton: View {
    let title: String
    let icon: ImageVector
    let enabled: Bool
    let onClick: () -> Void
    var highlight: Bool = false

    var body: some View {
        let shape = RoundedCornerShape(18)
        VStack(spacing: 0) {
            Icon(icon, tint: highlight ? Royal.WoodDark : Royal.Gold, size: 18)
            Spacer().frame(height: 3)
            Text(title, style: bodyStyle(12, .ExtraBold, highlight ? Royal.WoodDark : Royal.Ivory)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            if highlight { shape.fill(Royal.goldBrush) } else { shape.fill(Royal.panelBrush) }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1))
        .background(shape.fill(Royal.Panel).composeShadow(6))
        .opacity(enabled ? 1 : 0.4)
        .pressable(enabled: enabled, onClick: onClick)
        .accessibilityLabel(title)
    }
}

// MARK: - Promotion

private struct PromotionPicker: View {
    let session: ChessSession

    var body: some View {
        let color = session.sideToMove
        GeometryReader { geo in
            // Four 70 pt tiles where they fit; narrower phones shrink them instead of clipping the row.
            let tile = min(70, (geo.size.width - 48 - 14 - 40 - 36) / 4)
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { session.cancelPromotion() }
                WoodPanel(padding: 20) {
                    VStack(spacing: 16) {
                        Text("Promote your pawn", style: displayStyle(22, Royal.Gold))
                        HStack(spacing: 12) {
                            ForEach(Array([PieceKind.QUEEN, .ROOK, .BISHOP, .KNIGHT].enumerated()), id: \.offset) { i, kind in
                                let shape = RoundedCornerShape(18)
                                ChessPieceView(ChessPiece(kind, color), tile * 58 / 70)
                                    .frame(width: tile, height: tile)
                                    .background(shape.fill(LinearGradient(colors: [Royal.PanelHigh, Royal.Panel], startPoint: .top, endPoint: .bottom)))
                                    .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1.5))
                                    .clipShape(shape)
                                    .pressable(sound: .Place, pressedScale: 0.9) { session.promote(kind) }
                                    .accessibilityLabel(kind.rawValue.prefix(1).uppercased() + kind.rawValue.dropFirst())
                                    .springIn(i * 50)
                            }
                        }
                        Text("Cancel", style: bodyStyle(15, .Bold, Royal.Smoke))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Capsule())
                            .pressable(sound: .Back) { session.cancelPromotion() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
                .onTapGesture {}
                .padding(24)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - History & results

private struct HistorySheet: View {
    let session: ChessSession
    let onDone: () -> Void

    var body: some View {
        let pairs = session.movePairs
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDone() }
            RoyalPanel {
                HStack(spacing: 8) {
                    Text("Moves", style: displayStyle(24, Royal.Gold)).frame(maxWidth: .infinity, alignment: .leading)
                    // Extras: the game as PGN.
                    if ExtrasFeatures.chessTools && !pairs.isEmpty {
                        OutlineButton("Copy PGN", { session.copyPGN(); onDone() }, icon: Icons.Rounded.Description, height: 40)
                    }
                    OutlineButton("Done", onDone, height: 40)
                }
                Spacer().frame(height: 10)
                if pairs.isEmpty {
                    Text("No moves yet", style: bodyStyle(15, .SemiBold, Royal.Smoke))
                }
                ViewThatFits(in: .vertical) {
                    rows(pairs)
                    ScrollView(.vertical, showsIndicators: true) { rows(pairs) }
                }
            }
            .frame(maxHeight: 520)
            .contentShape(Rectangle())
            .onTapGesture {}
            .springIn()
            .padding(10)
        }
    }

    private func rows(_ pairs: [ChessSession.MovePair]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(pairs) { pair in
                HStack(spacing: 0) {
                    Text("\(pair.number).").foregroundStyle(Royal.Smoke).frame(width: 48, alignment: .leading)
                    Text(pair.white).foregroundStyle(Royal.Ivory).frame(maxWidth: .infinity, alignment: .leading)
                    Text(pair.black ?? "").foregroundStyle(Royal.Ivory).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 16, design: .monospaced))
                .padding(.vertical, 6)
            }
        }
    }
}

private struct ResultOverlay: View {
    let session: ChessSession
    let onRematch: () -> Void
    let onPlayers: () -> Void
    let onHome: () -> Void

    var body: some View {
        let result = session.match.result
        let winnerColor = result?.winner
        let winner = winnerColor.map { session.player($0) }
        let white = session.player(.WHITE)
        let black = session.player(.BLACK)
        let standings: [PartyStanding] = winnerColor.map { wc in
            [PartyStanding(session.player(wc), "\(wc.title) · 1"), PartyStanding(session.player(wc.opposite), "\(wc.opposite.title) · 0")]
        } ?? [PartyStanding(white, "White · ½"), PartyStanding(black, "Black · ½")]
        PartyResultOverlay(
            title: winner.map { "\($0.name) wins!" } ?? "Draw",
            subtitle: result?.reason ?? "",
            winner: winner,
            standings: standings,
            accent: GameAccent.chess,
            primaryTitle: "Rematch · swap colours",
            onPrimary: onRematch,
            onHub: onHome,
            secondaryTitle: "Players",
            onSecondary: onPlayers,
            winnerIsBot: winnerColor.map { session.isBot($0) } ?? false
        )
    }
}

// MARK: - Choice dialog (the reference's three-button LabPrompt)

final class ChessChoice: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let options: [(String, () -> Void)]

    init(title: String, message: String?, options: [(String, () -> Void)]) {
        self.title = title
        self.message = message
        self.options = options
    }
}

private struct ChoiceDialog: View {
    let choice: ChessChoice?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            if let c = choice {
                ChoiceCard(choice: c, onDismiss: onDismiss).transition(.opacity)
            }
        }
        .animation(.tween(160), value: choice?.id)
    }
}

private struct ChoiceCard: View {
    let choice: ChessChoice
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 0.8

    var body: some View {
        let c = choice
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
            WoodPanel(padding: 22) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Royal.Ruby, Royal.RubyDark], startPoint: .top, endPoint: .bottom))
                        Icon(Icons.Rounded.Flag, tint: .white, size: 34)
                    }
                    .frame(width: 64, height: 64)
                    Spacer().frame(height: 14)
                    Text(c.title, style: displayStyle(26, Royal.Ivory, .Center)).multilineTextAlignment(.center)
                    if let message = c.message {
                        Spacer().frame(height: 8)
                        Text(message, style: bodyStyle(15, .SemiBold, Royal.Smoke, .Center)).multilineTextAlignment(.center)
                    }
                    Spacer().frame(height: 18)
                    ForEach(Array(c.options.enumerated()), id: \.offset) { _, option in
                        CandyButton(
                            option.0, { onDismiss(); option.1() },
                            colors: [Color(argb: 0xFFFF7A84), Royal.Ruby, Royal.RubyDark], textColor: .white, height: 50, fontSize: 17
                        )
                        Spacer().frame(height: 10)
                    }
                    OutlineButton("Cancel", onDismiss, tint: Royal.Smoke, fill: true)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture {}
            .frame(maxWidth: 420)
            .padding(28)
            .scaleEffect(scale)
            .onAppear { withAnimation(.compose(dampingRatio: 0.6, stiffness: 500)) { scale = 1 } }
        }
    }
}

// MARK: - Board

private struct Drag: Equatable {
    let from: Int
    let offset: CGSize
}

/// One touch on the board: where it started, the square under it, and whether it has turned into a drag.
private struct Touch: Equatable {
    let start: CGPoint
    let from: Int?
    var moved: Bool
}

struct ChessBoard: View {
    let session: ChessSession
    let side: CGFloat

    @State private var drag: Drag? = nil
    @State private var touch: Touch? = nil
    @GestureState private var pressing = false

    var body: some View {
        let boardSide = max(240, (side / 8).rounded(.down) * 8)
        let square = boardSide / 8
        let style = ChessBoardStyle.style(session.config.boardStyle)
        let flipped = session.flipped
        let corner = square * 0.22
        let shape = RoundedCornerShape(corner)
        let last = session.match.lastMove
        let center = { (sq: Int) -> CGPoint in Self.center(sq, flipped, square) }

        ZStack(alignment: .topLeading) {
            // Squares, highlights and coordinates.
            BoardSquares(
                light: style.lightArgb, dark: style.darkArgb, flipped: flipped, square: square,
                lastFrom: last?.from ?? -1, lastTo: last?.to ?? -1, selected: session.selected ?? -1, check: session.checkedKing ?? -1
            )
            .equatable()
            .frame(width: boardSide, height: boardSide)

            // Legal targets.
            TargetDots(targets: session.targets, version: session.targetsVersion, flipped: flipped, square: square)
                .equatable()
                .frame(width: boardSide, height: boardSide)

            // Extras: the hinted move.
            if let hint = session.hint {
                ExtrasChessHintOverlay(move: hint, flipped: flipped, square: square)
                    .id("\(hint.from)-\(hint.to)")
                    .frame(width: boardSide, height: boardSide)
                    .zIndex(5)
            }

            // Captured pieces fading out.
            ForEach(session.ghosts) { ghost in
                GhostNode(piece: ghost.piece, center: center(ghost.square), square: square) {
                    session.clearGhost(ghost.id)
                }
            }

            // Pieces.
            ForEach(session.pieces) { item in
                let dragging = drag?.from == item.square
                PieceNode(
                    item: item,
                    center: center(item.square),
                    dragging: dragging,
                    dragOffset: dragging ? (drag?.offset ?? .zero) : .zero,
                    flipped: flipped,
                    square: square
                )
                .zIndex(dragging ? 10 : 1)
            }

            // Notices such as a declined draw.
            NoticeBadge(session: session)
                .frame(width: boardSide, height: boardSide)
                .zIndex(20)
        }
        .frame(width: boardSide, height: boardSide)
        .clipShape(shape)
        .overlay(shape.strokeBorder(lerp(style.dark, Color.Black, Float(0.3)), lineWidth: 2))
        .background(shape.fill(style.dark).composeShadow(18))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($pressing) { _, state, _ in state = true }
                .onChanged { v in changed(v, square, flipped) }
                .onEnded { v in ended(v, square, flipped) }
        )
        .onChange(of: pressing) { _, isPressing in
            if !isPressing && drag != nil { drag = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chess board. \(session.statusText)")
    }

    static func center(_ sq: Int, _ flipped: Bool, _ square: CGFloat) -> CGPoint {
        let file = ChessSquare.file(sq)
        let rank = ChessSquare.rank(sq)
        let col = flipped ? 7 - file : file
        let row = flipped ? rank : 7 - rank
        return CGPoint(x: (CGFloat(col) + 0.5) * square, y: (CGFloat(row) + 0.5) * square)
    }

    private func squareAt(_ p: CGPoint, _ square: CGFloat, _ flipped: Bool) -> Int? {
        let col = Int((p.x / square).rounded(.down))
        let row = Int((p.y / square).rounded(.down))
        if col < 0 || col > 7 || row < 0 || row > 7 { return nil }
        let file = flipped ? 7 - col : col
        let rank = flipped ? row : 7 - row
        return rank * 8 + file
    }

    private func changed(_ v: DragGesture.Value, _ square: CGFloat, _ flipped: Bool) {
        if touch == nil || touch?.start != v.startLocation {
            touch = Touch(start: v.startLocation, from: squareAt(v.startLocation, square, flipped), moved: false)
        }
        guard var t = touch else { return }
        let dist = hypot(v.location.x - t.start.x, v.location.y - t.start.y)
        if dist > square * 0.2 {
            if !t.moved, let from = t.from { session.pick(from) }
            t.moved = true
            touch = t
            if let from = t.from, session.canDrag(from) {
                drag = Drag(from: from, offset: CGSize(width: v.location.x - t.start.x, height: v.location.y - t.start.y))
            }
        }
    }

    private func ended(_ v: DragGesture.Value, _ square: CGFloat, _ flipped: Bool) {
        drag = nil
        guard let t = touch, t.start == v.startLocation else { return }
        touch = nil
        guard let from = t.from else { return }
        if t.moved {
            if session.canDrag(from), let to = squareAt(v.location, square, flipped) { session.drop(from, to) }
        } else {
            session.tap(from)
        }
    }
}

/// Squares, last-move / selection / check highlights and coordinates, drawn square by square like Android.
/// Equatable on plain values, so it redraws only when one of them changes (not while a piece is dragged).
private struct BoardSquares: View, Equatable {
    let light: UInt32
    let dark: UInt32
    let flipped: Bool
    let square: CGFloat
    let lastFrom: Int
    let lastTo: Int
    let selected: Int
    let check: Int

    var body: some View {
        Canvas { ctx, _ in
            let lightColor = Color(argb: light)
            let darkColor = Color(argb: dark)
            let lastColor = Color(argb: 0xFFF6D94A).opacity(0.45)
            let selectedColor = Color(argb: 0xFF4FC3F7).opacity(0.45)
            let checkRed = Color(argb: 0xFFFF3B3B)
            let labelFont = RoyalFonts.body(max(8, square * 0.18), .Bold)
            let files = Array("abcdefgh")
            for sq in 0..<64 {
                let file = ChessSquare.file(sq)
                let rank = ChessSquare.rank(sq)
                let col = flipped ? 7 - file : file
                let row = flipped ? rank : 7 - rank
                let topLeft = CGPoint(x: CGFloat(col) * square, y: CGFloat(row) * square)
                let rect = Path(CGRect(origin: topLeft, size: CGSize(width: square + 0.5, height: square + 0.5)))
                let isLight = ChessSquare.isLight(sq)
                ctx.fill(rect, with: .color(isLight ? lightColor : darkColor))
                if sq == lastFrom || sq == lastTo { ctx.fill(rect, with: .color(lastColor)) }
                if sq == selected { ctx.fill(rect, with: .color(selectedColor)) }
                if sq == check {
                    let c = CGPoint(x: topLeft.x + square / 2, y: topLeft.y + square / 2)
                    ctx.fill(rect, with: .radialGradient(Gradient(colors: [checkRed.opacity(0.95), checkRed.opacity(0)]),
                                                         center: c, startRadius: 0, endRadius: square * 0.75))
                }
                let labelColor = isLight ? darkColor : lightColor
                if col == 0 {
                    ctx.draw(Text(verbatim: "\(rank + 1)").font(labelFont).foregroundColor(labelColor),
                             at: CGPoint(x: topLeft.x + square * 0.06, y: topLeft.y + square * 0.02), anchor: .topLeading)
                }
                if row == 7 {
                    ctx.draw(Text(verbatim: String(files[file])).font(labelFont).foregroundColor(labelColor),
                             at: CGPoint(x: topLeft.x + square - square * 0.06, y: topLeft.y + square - square * 0.01), anchor: .bottomTrailing)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Legal-move dots and capture rings. They pop in (spring 0.8 / 630) every time the targets change.
private struct TargetDots: View, Equatable {
    let targets: [Int: Bool]
    let version: Int
    let flipped: Bool
    let square: CGFloat

    static func == (a: TargetDots, b: TargetDots) -> Bool {
        a.version == b.version && a.flipped == b.flipped && a.square == b.square
    }

    var body: some View {
        KeyframeAnimator(initialValue: 1.0, trigger: version) { a in
            Canvas { ctx, _ in
                let s = 0.4 + 0.6 * a
                let alpha = min(1, max(0, a))
                for (target, isCapture) in targets {
                    let c = ChessBoard.center(target, flipped, square)
                    if isCapture {
                        let r = square * 0.92 / 2 * s
                        let lw = square * 0.09
                        let rr = r - lw / 2
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                                   with: .color(Color.black.opacity(0.28 * alpha)), lineWidth: lw)
                    } else {
                        let r = square * 0.15 * s
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Color.black.opacity(0.22 * alpha)))
                    }
                }
            }
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                MoveKeyframe(0.0)
                SpringKeyframe(1.0, spring: Spring(mass: 1, stiffness: 630, damping: 2 * 0.8 * 630.0.squareRoot()))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GhostNode: View {
    let piece: ChessPiece
    let center: CGPoint
    let square: CGFloat
    let onDone: () -> Void
    @State private var fade: CGFloat = 1

    var body: some View {
        ChessPieceView(piece, square * 0.9)
            .scaleEffect(0.3 + 0.7 * fade)
            .opacity(Double(fade))
            .position(center)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.tween(260)) { fade = 0 } completion: { onDone() }
            }
    }
}

private struct PieceNode: View {
    let item: ChessSession.BoardPiece
    let center: CGPoint
    let dragging: Bool
    let dragOffset: CGSize
    let flipped: Bool
    let square: CGFloat

    @State private var lastFlipped: Bool? = nil
    @State private var wasDragging = false
    @State private var appear: CGFloat = 0.3

    var body: some View {
        let pos = dragging ? CGPoint(x: center.x + dragOffset.width, y: center.y + dragOffset.height) : center
        let spec: Animation? = dragging ? nil : ((lastFlipped ?? flipped) != flipped ? FlipSpring : (wasDragging ? DragResetSpring : MoveSpring))
        ChessPieceView(item.piece, square * 0.9)
            .scaleEffect(dragging ? 1.18 : 1)
            .animation(.compose(dampingRatio: 0.8, stiffness: 439), value: dragging)
            .scaleEffect(appear)
            .opacity(Double(min(1, max(0, (appear - 0.3) / 0.7))))
            .position(pos)
            .animation(spec, value: pos)
            .allowsHitTesting(false)
            .onChange(of: pos) { _, _ in
                if dragging {
                    wasDragging = true
                } else {
                    lastFlipped = flipped
                    wasDragging = false
                }
            }
            .onAppear {
                if lastFlipped == nil { lastFlipped = flipped }
                withAnimation(.compose(dampingRatio: 0.8, stiffness: 385)) { appear = 1 }
            }
    }
}

private struct NoticeBadge: View {
    let session: ChessSession

    var body: some View {
        ZStack {
            if let notice = session.notice {
                Text(notice, style: bodyStyle(15, .ExtraBold, Color.white))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(LinearGradient(colors: [GameAccent.chess[0], GameAccent.chess[1]], startPoint: .leading, endPoint: .trailing)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5))
                    .background(Capsule().fill(GameAccent.chess[1]).composeShadow(12))
                    .id(session.noticeId)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.7)), removal: .opacity))
            }
        }
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: session.noticeId)
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: session.notice)
        .allowsHitTesting(false)
        .task(id: session.noticeId) {
            if session.notice == nil { return }
            let id = session.noticeId
            try? await Task.sleep(for: .milliseconds(1800))
            if Task.isCancelled { return }
            session.clearNotice(id)
        }
    }
}
