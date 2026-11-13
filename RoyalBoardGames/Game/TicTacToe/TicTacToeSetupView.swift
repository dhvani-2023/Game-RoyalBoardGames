import SwiftUI
import GameKit

/// Players and options before a Tic-Tac-Toe match (the reference's party setup, Tic-Tac-Toe part).
struct TicTacToeSetupScreen: View {
    let onBack: () -> Void
    let onStart: (TicTacToeConfig) -> Void

    @State private var setup: TicTacToeStore.Setup
    @State private var players: [PartyPlayer]
    @State private var editing: Int? = nil

    init(onBack: @escaping () -> Void, onStart: @escaping (TicTacToeConfig) -> Void) {
        self.onBack = onBack
        self.onStart = onStart
        _setup = State(initialValue: TicTacToeStore.setup)
        _players = State(initialValue: loadPlayers())
    }

    private var level: BotLevel {
        BotLevel.entries.indices.contains(setup.botLevel) ? BotLevel.entries[setup.botLevel] : BotLevel.default
    }

    /// The two rows, X first: people, or a person and the computer.
    private func seat(_ i: Int) -> PartyPlayer {
        if !setup.vsBot { return players[i] }
        if i == setup.botSeat { return TicTacToeStore.botPlayer(setup.botColor) }
        return players[0]
    }

    private func isBotSeat(_ i: Int) -> Bool { setup.vsBot && i == setup.botSeat }

    private func swap() {
        UiSound.play(.Tap)
        if setup.vsBot { setup = setup.copy(botSeat: 1 - setup.botSeat) } else { players = players.reversed() }
    }

    /// Tapping cycles to the next colour; if the other seat has it, they swap.
    private func cycleColor(_ i: Int) {
        UiSound.play(.Tap)
        let mine = seat(i).colorIndex
        let theirs = seat(1 - i).colorIndex
        let next = (mine + 1) % PartyStyle.tokenColors.count
        func setColor(_ row: Int, _ color: Int) {
            if isBotSeat(row) {
                setup = setup.copy(botColor: color)
            } else {
                let k = setup.vsBot ? 0 : row
                players = players.enumerated().map { j, p in j == k ? p.copy(colorIndex: color) : p }
            }
        }
        if next == theirs { setColor(1 - i, mine) }
        setColor(i, next)
    }

    private func start() {
        let ready = players.enumerated().map { i, p in p.copy(name: p.displayName(i)) }
        players = ready
        PartyStore.remember(ready, .TIC_TAC_TOE)
        TicTacToeStore.setup = setup
        UiSound.play(.Turn)
        let x = setup.vsBot && setup.botSeat == 0 ? TicTacToeStore.botPlayer(setup.botColor) : ready[0]
        let o = setup.vsBot && setup.botSeat == 1 ? TicTacToeStore.botPlayer(setup.botColor) : (setup.vsBot ? ready[0] : ready[1])
        onStart(
            TicTacToeConfig(
                playerX: x,
                playerO: o,
                bestOf: setup.bestOf,
                passDevice: setup.passDevice && !setup.vsBot,
                botMark: setup.vsBot ? (setup.botSeat == 0 ? .X : .O) : nil,
                botLevel: level
            )
        )
    }

    var body: some View {
        let accent = GameAccent.ticTacToe
        RoyalBackground(glow: accent[0], secondGlow: accent[1]) {
            ZStack {
                VStack(spacing: 0) {
                    RoyalTopBar(GameKind.TIC_TAC_TOE.title, onBack, subtitle: "\(GameKind.TIC_TAC_TOE.playersLabel) · Offline · Same device")
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            TttSetupHeader().springIn(0)
                            playersSection.springIn(80)
                            optionsSection.springIn(160)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                    }
                    ZStack {
                        CandyButton("Start \(setup.bestOf > 1 ? "match" : "game")", start, icon: Icons.Rounded.PlayArrow)
                            .frame(maxWidth: 600)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.clear, Royal.Night.copy(alpha: 0.85)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                    )
                }

                let editIndex = editing
                PlayerEditDialog(
                    editIndex.flatMap { players.indices.contains($0) ? players[$0] : nil },
                    onDismiss: { editing = nil },
                    onSave: { p in
                        if let i = editing { players = players.enumerated().map { j, old in j == i ? p : old } }
                        editing = nil
                    },
                    showColors: true,
                    takenColors: editIndex.map { i in [setup.vsBot ? setup.botColor : players[1 - i].colorIndex] } ?? []
                )
            }
        }
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                SectionLabel("Players", color: Royal.Smoke).frame(maxWidth: .infinity, alignment: .leading)
                OutlineButton("Swap X / O", swap, icon: Icons.Rounded.SwapVert, height: 38)
            }
            RoyalSegmented([false, true], setup.vsBot, { setup = setup.copy(vsBot: $0) }, { $0 ? "vs Computer" : "vs Friend" })
            ForEach(0..<2, id: \.self) { i in
                TttPlayerRow(
                    player: seat(i),
                    mark: i == 0 ? .X : .O,
                    isBot: isBotSeat(i),
                    level: level,
                    onEdit: { editing = setup.vsBot ? 0 : i },
                    onColor: { cycleColor(i) },
                    onLevel: {
                        let next = BotLevel.entries[(level.ordinal + 1) % BotLevel.entries.count]
                        setup = setup.copy(botLevel: next.ordinal)
                    }
                )
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Options", color: Royal.Smoke)
            RoyalPanel(padding: 14) {
                OptionTitle(icon: Icons.Rounded.EmojiEvents, title: "Match length")
                Spacer().frame(height: 10)
                RoyalSegmented([1, 3, 5], setup.bestOf, { setup = setup.copy(bestOf: $0) }, { $0 == 1 ? "Single game" : "Best of \($0)" })
            }
            if setup.vsBot {
                RoyalPanel(padding: 14) {
                    OptionTitle(icon: Icons.Rounded.Memory, title: "Computer level")
                    Spacer().frame(height: 10)
                    RoyalSegmented(BotLevel.entries, level, { setup = setup.copy(botLevel: $0.ordinal) }, { $0.title })
                }
                .transition(.opacity)
            } else {
                RoyalPanel(padding: 14) {
                    HStack(spacing: 0) {
                        ZStack {
                            RoundedCornerShape(10).fill(GameAccent.ticTacToe[1])
                            Icon(Icons.Rounded.VisibilityOff, tint: .white, size: 19)
                        }
                        .frame(width: 34, height: 34)
                        Spacer().frame(width: 12)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Pass the device screen", style: bodyStyle(15, .ExtraBold))
                            Text("Show a hand-off screen between turns", style: bodyStyle(12, .SemiBold, Royal.Smoke))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        RoyalSwitch(setup.passDevice, { setup = setup.copy(passDevice: $0) }, label: "Pass the device screen")
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: setup.vsBot)
    }
}

/// Last players, topped up with defaults, with two different colours (as in the reference).
@MainActor
private func loadPlayers() -> [PartyPlayer] {
    var list = PartyStore.players(.TIC_TAC_TOE) ?? []
    if list.count < 2 {
        let current = list
        list += PartyStyle.defaultPlayers(6).filter { candidate in !current.contains { $0.colorIndex == candidate.colorIndex } }
    }
    var two = Array(list.prefix(2))
    if two[0].colorIndex == two[1].colorIndex {
        two[1] = two[1].copy(colorIndex: (two[0].colorIndex + 1) % PartyStyle.tokenColors.count)
    }
    return two
}

private struct TttSetupHeader: View {
    var body: some View {
        let accent = GameAccent.ticTacToe
        let shape = RoundedCornerShape(28)
        HStack(alignment: .center, spacing: 16) {
            TicTacToeCardArt()
                .frame(width: 104, height: 104)
                .frame(width: 112, height: 112)
                .background(shape.fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing)))
                .clipShape(shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                .background(shape.fill(accent[1]).composeShadow(14, color: accent[0]))
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up the table", style: displayStyle(24))
                Text(GameKind.TIC_TAC_TOE.tagline, style: bodyStyle(13, .SemiBold, Royal.Smoke))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    Icon(Icons.Rounded.AirplanemodeActive, tint: Royal.Gold, size: 13)
                    Spacer().frame(width: 5)
                    Text("Offline · Same device", style: bodyStyle(11, .Black, Royal.Ivory))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OptionTitle: View {
    let icon: ImageVector
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, tint: Royal.Gold, size: 20)
            Spacer().frame(width: 8)
            Text(title, style: bodyStyle(15, .ExtraBold))
        }
    }
}

private struct TttPlayerRow: View {
    let player: PartyPlayer
    let mark: TTTMark
    let isBot: Bool
    let level: BotLevel
    let onEdit: () -> Void
    let onColor: () -> Void
    let onLevel: () -> Void

    var body: some View {
        let shape = RoundedCornerShape(22)
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarBadge(player, size: 50)
                    .frame(width: 54, height: 54)
                if !isBot {
                    ZStack {
                        Circle().fill(Royal.Ivory)
                        Icon(Icons.Rounded.Edit, tint: Royal.Night, size: 12)
                    }
                    .frame(width: 20, height: 20)
                    .offset(x: 2, y: 2)
                }
            }
            .frame(width: 54, height: 54)
            .pressable(enabled: !isBot, sound: .Tap, pressedScale: 0.9, onClick: onEdit)
            .accessibilityLabel(isBot ? player.name : "Change avatar for \(player.name)")
            VStack(alignment: .leading, spacing: 0) {
                Text("\(mark.label)\(isBot ? " · COMPUTER" : "")", style: bodyStyle(10, .Black, Royal.Smoke).copy(letterSpacing: 1))
                Text(player.name, style: bodyStyle(18, .Black)).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .pressable(enabled: !isBot, pressedScale: 0.98, onClick: onEdit)
            if isBot {
                Text(level.title, style: bodyStyle(13, .Black, Royal.Gold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Royal.Glass))
                    .overlay(Capsule().strokeBorder(Royal.Stroke, lineWidth: 1))
                    .contentShape(Capsule())
                    .pressable(sound: .Toggle, haptic: .Tick, pressedScale: 0.92, onClick: onLevel)
                    .accessibilityLabel("Computer level \(level.title). Change")
            }
            MarkGlyph(mark, player.color, 4.5).frame(width: 26, height: 26)
            Circle()
                .fill(player.color.sheen())
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                .frame(width: 30, height: 30)
                .background(Circle().fill(player.color).composeShadow(4, color: player.color))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .pressable(sound: nil, pressedScale: 0.85, onClick: onColor)
                .accessibilityLabel("Change colour")
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Royal.panelBrush)
        .clipShape(shape)
        .overlay(shape.strokeBorder(player.color.copy(alpha: 0.55), lineWidth: 1.5))
        .animation(.compose(dampingRatio: 1, stiffness: 1500), value: player.colorIndex)
        .background(shape.fill(Royal.Panel).composeShadow(8))
    }
}
