import SwiftUI
import GameKit

private let SETTINGS_KEY = "party.chess.settings.v1"

private func botPersona(_ colorIndex: Int) -> PartyPlayer {
    PartyPlayer(name: "CPU \(PartyStyle.botNames[0])", avatar: PartyStyle.botAvatars[0], colorIndex: colorIndex)
}

/// Players and options before a match (the chess half of the reference PartySetupView), reskinned.
struct ChessSetupScreen: View {
    let onBack: () -> Void
    let onStart: (ChessConfig) -> Void

    @State private var settings: ChessSetupSettings
    @State private var players: [PartyPlayer]
    /// In computer mode the bot takes one seat; the friend it replaced waits here.
    @State private var botIndex: Int?
    @State private var stashedFriend: PartyPlayer?
    @State private var editing: PartyPlayer? = nil

    init(onBack: @escaping () -> Void, onStart: @escaping (ChessConfig) -> Void) {
        self.onBack = onBack
        self.onStart = onStart
        let initial = Prefs.load(SETTINGS_KEY, as: ChessSetupSettings.self) ?? ChessSetupSettings(botLevel: BotLevel.default.ordinal)
        var list = PartyStore.players(.CHESS) ?? []
        if list.count < 2 {
            let current = list
            list += PartyStyle.defaultPlayers(6).filter { c in !current.contains { $0.colorIndex == c.colorIndex } }
        }
        list = Array(list.prefix(2))
        _settings = State(initialValue: initial)
        if initial.vsComputer {
            _players = State(initialValue: [list[0], botPersona(list[1].colorIndex)])
            _botIndex = State(initialValue: 1)
            _stashedFriend = State(initialValue: list[1])
        } else {
            _players = State(initialValue: list)
            _botIndex = State(initialValue: nil)
            _stashedFriend = State(initialValue: nil)
        }
    }

    private func setComputer(_ on: Bool) {
        if on && botIndex == nil {
            stashedFriend = players[1]
            players = [players[0], botPersona(players[1].colorIndex)]
            botIndex = 1
        } else if !on, let i = botIndex {
            var list = players
            list[i] = stashedFriend ?? PartyStyle.defaultPlayers(2)[1]
            players = list
            botIndex = nil
        }
        settings = settings.copy(vsComputer: on)
    }

    private func start() {
        let ready = players.enumerated().map { i, p in p.copy(name: p.displayName(i)) }
        var toRemember = ready
        if let i = botIndex, let friend = stashedFriend { toRemember[i] = friend }
        PartyStore.remember(toRemember, .CHESS)
        Prefs.save(SETTINGS_KEY, settings)
        UiSound.play(.Turn)
        onStart(
            ChessConfig(
                white: ready[0], black: ready[1], clock: settings.clock,
                passDevice: settings.passDevice, autoRotate: settings.autoRotate, boardStyle: settings.boardStyle,
                whiteIsBot: botIndex == 0, blackIsBot: botIndex == 1, botLevel: settings.botLevel
            )
        )
    }

    var body: some View {
        let accent = GameAccent.chess
        RoyalBackground(glow: accent[1], secondGlow: accent[0]) {
            ZStack {
                VStack(spacing: 0) {
                    RoyalTopBar("Chess", onBack, subtitle: "2 players · Offline · Same device")
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            header.springIn(0)
                            opponent.springIn(60)
                            playersSection.springIn(120)
                            options.springIn(180)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                    ZStack {
                        CandyButton(
                            "Start game", start,
                            colors: [Color(argb: 0xFFB4A8FF), accent[0], accent[1]], textColor: .white, icon: Icons.Rounded.PlayArrow
                        )
                        .frame(maxWidth: 600)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.clear, Royal.Night.copy(alpha: 0.9)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
                PlayerEditDialog(
                    editing,
                    onDismiss: { editing = nil },
                    onSave: { updated in
                        players = players.map { $0.id == updated.id ? updated : $0 }
                        editing = nil
                    },
                    showColors: false
                )
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        let accent = GameAccent.chess
        let tile = RoundedCornerShape(28)
        return HStack(spacing: 0) {
            ChessCardArt()
                .frame(width: 104, height: 104)
                .frame(width: 112, height: 112)
                .background(tile.fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing)))
                .clipShape(tile)
                .overlay(tile.strokeBorder(Royal.Stroke, lineWidth: 1.5))
                .background(tile.fill(accent[1]).composeShadow(14, color: accent[0]))
            Spacer().frame(width: 16)
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up the table", style: displayStyle(24))
                Text(GameKind.CHESS.tagline, style: bodyStyle(13, .SemiBold, Royal.Smoke))
                    .fixedSize(horizontal: false, vertical: true)
                RoyalChip("Works offline", icon: Icons.Rounded.WifiOff, color: Royal.Gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var opponent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Opponent")
            RoyalSegmented([false, true], settings.vsComputer, { setComputer($0) }, { $0 ? "Computer" : "Friend" })
            if settings.vsComputer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        Icon(Icons.Rounded.SmartToy, tint: Royal.Gold, size: 18)
                        Spacer().frame(width: 6)
                        Text("Computer strength", style: bodyStyle(13, .Bold, Royal.Smoke))
                    }
                    RoyalSegmented(
                        BotLevel.entries,
                        BotLevel.entries[min(2, max(0, settings.botLevel))],
                        { settings = settings.copy(botLevel: $0.ordinal) },
                        { $0.title }
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: settings.vsComputer)
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                SectionLabel("Players").frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    Icon(Icons.Rounded.SwapVert, tint: Royal.Gold, size: 16)
                    Spacer().frame(width: 6)
                    Text("Swap colours", style: bodyStyle(13, .ExtraBold))
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(Royal.Glass))
                .overlay(Capsule().strokeBorder(Royal.Stroke, lineWidth: 1))
                .contentShape(Capsule())
                .pressable(sound: .Tap) {
                    players = [players[1], players[0]]
                    botIndex = botIndex.map { 1 - $0 }
                }
            }
            RoyalPanel(padding: 6) {
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    let isBot = botIndex == index
                    ChessPlayerRow(player: player, color: index == 0 ? .WHITE : .BLACK, isBot: isBot) {
                        if !isBot { editing = player }
                    }
                    if index == 0 { Rectangle().fill(Royal.Stroke).frame(height: 1).frame(maxWidth: .infinity) }
                }
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Options")
            OptionCard(icon: Icons.Rounded.Timer, title: "Chess clock") {
                RoyalFlowRow(spacing: 6, lineSpacing: 6) {
                    ForEach(ChessClockOption.entries, id: \.self) { option in
                        let on = option == settings.clock
                        Text(option.title, style: bodyStyle(13, .ExtraBold, on ? Royal.WoodDark : Royal.Ivory))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background {
                                if on { Capsule().fill(Royal.goldBrush) } else { Capsule().fill(Royal.PanelHigh) }
                            }
                            .clipShape(Capsule())
                            .pressable(sound: .Toggle, haptic: .Tick, pressedScale: 0.93) { settings = settings.copy(clock: option) }
                    }
                }
            }
            OptionCard(icon: Icons.Rounded.GridOn, title: "Board") {
                HStack(spacing: 12) {
                    ForEach(Array(ChessBoardStyle.all.enumerated()), id: \.offset) { index, style in
                        BoardStyleSwatch(style: style, on: settings.boardStyle == index) {
                            settings = settings.copy(boardStyle: index)
                        }
                    }
                }
            }
            if !settings.vsComputer {
                VStack(spacing: 10) {
                    OptionToggle(
                        icon: Icons.Rounded.VisibilityOff, title: "Pass the device screen",
                        subtitle: "Hide the board between moves until the next player is ready",
                        checked: settings.passDevice
                    ) { settings = settings.copy(passDevice: $0) }
                    OptionToggle(
                        icon: Icons.Rounded.ScreenRotation, title: "Auto-rotate board",
                        subtitle: "Turn the board to face whoever is moving",
                        checked: settings.autoRotate
                    ) { settings = settings.copy(autoRotate: $0) }
                }
                .transition(.opacity)
            }
        }
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: settings.vsComputer)
    }
}

private struct BoardStyleSwatch: View {
    let style: ChessBoardStyle
    let on: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedCornerShape(10)
        VStack(spacing: 0) {
            Canvas { ctx, size in
                let h = size.width / 2
                ctx.fill(Path(CGRect(x: 0, y: 0, width: h, height: h)), with: .color(style.light))
                ctx.fill(Path(CGRect(x: h, y: 0, width: h, height: h)), with: .color(style.dark))
                ctx.fill(Path(CGRect(x: 0, y: h, width: h, height: h)), with: .color(style.dark))
                ctx.fill(Path(CGRect(x: h, y: h, width: h, height: h)), with: .color(style.light))
            }
            .frame(width: 48, height: 48)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Royal.Gold.opacity(on ? 1 : 0), lineWidth: 3))
            .scaleEffect(on ? 1 : 0.92)
            .animation(.compose(dampingRatio: 0.75, stiffness: 439), value: on)
            Spacer().frame(height: 4)
            Text(style.name, style: bodyStyle(10, .Bold, on ? Royal.Gold : Royal.Smoke))
        }
        .pressable(sound: .Toggle, pressedScale: 0.9, onClick: onClick)
        .accessibilityLabel("\(style.name) board")
    }
}

private struct ChessPlayerRow: View {
    let player: PartyPlayer
    let color: ChessColor
    let isBot: Bool
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                AvatarBadge(player, size: 50)
                if !isBot {
                    ZStack {
                        Circle().fill(Royal.Gold)
                        Icon(Icons.Rounded.Edit, "Edit \(player.name)", tint: Royal.WoodDark, size: 12)
                    }
                    .frame(width: 20, height: 20)
                }
            }
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(color.title.uppercased(), style: bodyStyle(10, .Black, Royal.Smoke).copy(letterSpacing: 1))
                Text(player.name, style: bodyStyle(18, .ExtraBold)).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isBot {
                RoyalChip("CPU", icon: Icons.Rounded.SmartToy, color: Royal.Emerald)
                Spacer().frame(width: 8)
            }
            ChessPieceView(ChessPiece(.KING, color), 34)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedCornerShape(16))
        .pressable(enabled: !isBot, pressedScale: 0.97, onClick: onClick)
    }
}

private struct OptionCard<Content: View>: View {
    let icon: ImageVector
    let title: String
    let content: Content

    init(icon: ImageVector, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        RoyalPanel(padding: 14) {
            HStack(spacing: 0) {
                Icon(icon, tint: Royal.Gold, size: 20)
                Spacer().frame(width: 8)
                Text(title, style: bodyStyle(15, .ExtraBold))
            }
            Spacer().frame(height: 12)
            content
        }
    }
}

private struct OptionToggle: View {
    let icon: ImageVector
    let title: String
    let subtitle: String
    let checked: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        RoyalPanel(padding: 12) {
            HStack(spacing: 0) {
                ZStack {
                    RoundedCornerShape(12).fill(Royal.Gold.copy(alpha: 0.14))
                    Icon(icon, tint: Royal.Gold, size: 20)
                }
                .frame(width: 38, height: 38)
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title, style: bodyStyle(15, .ExtraBold))
                    Text(subtitle, style: bodyStyle(12, .SemiBold, Royal.Smoke)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 8)
                RoyalSwitch(checked, onChange, label: title)
            }
        }
    }
}
