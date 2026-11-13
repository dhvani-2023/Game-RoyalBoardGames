import SwiftUI
import GameKit

private let SETTINGS_KEY = "party.snakes.settings.v1"

private func botPersona(_ player: PartyPlayer, _ seat: Int) -> PartyPlayer {
    player.copy(
        name: "CPU \(PartyStyle.botNames[seat % PartyStyle.botNames.count])",
        avatar: PartyStyle.botAvatars[seat % PartyStyle.botAvatars.count]
    )
}

/// Players, board theme and rules before a match (the Snakes half of the reference PartySetupView), reskinned.
struct SnakesSetupScreen: View {
    let onBack: () -> Void
    let onStart: (SnakesConfig) -> Void

    @State private var settings: SnakesSetupSettings
    @State private var players: [PartyPlayer]
    @State private var bots: [Bool]
    @State private var editing: PartyPlayer? = nil
    @State private var showThemes = false

    init(onBack: @escaping () -> Void, onStart: @escaping (SnakesConfig) -> Void) {
        self.onBack = onBack
        self.onStart = onStart
        let initial = Prefs.load(SETTINGS_KEY, as: SnakesSetupSettings.self) ?? SnakesSetupSettings()
        _settings = State(initialValue: initial)
        let count = initial.playerCount.coerceIn(2, 6)
        var list = PartyStore.players(.SNAKES) ?? []
        if list.count < count {
            let have = list
            list = list + PartyStyle.defaultPlayers(6).filter { c in !have.contains { $0.colorIndex == c.colorIndex } }
        }
        let seats = Array(list.prefix(count))
        _players = State(initialValue: seats)
        var b = (0..<6).map { initial.bots.indices.contains($0) ? initial.bots[$0] : false }
        if b.prefix(seats.count).allSatisfy({ $0 }) { b = [false] + Array(b.dropFirst()) }
        _bots = State(initialValue: b)
    }

    private func setPlayerCount(_ count: Int) {
        let target = count.coerceIn(GameKind.SNAKES.minPlayers, GameKind.SNAKES.maxPlayers)
        var list = players
        if target < list.count {
            for _ in 0..<(list.count - target) { list.removeLast() }
        } else {
            while list.count < target {
                let used = Set(list.map(\.colorIndex))
                let usedAvatars = Set(list.map(\.avatar))
                let color = (0..<PartyStyle.tokenColors.count).first { !used.contains($0) } ?? list.count
                let avatar = PartyStyle.avatars.first { !usedAvatars.contains($0) } ?? "🙂"
                list.append(PartyPlayer(name: "Player \(list.count + 1)", avatar: avatar, colorIndex: color))
            }
        }
        players = list
        if bots.prefix(target).allSatisfy({ $0 }) { bots = [false] + Array(bots.dropFirst()) }
        UiSound.play(.Tap)
    }

    /// Tapping cycles to the next colour; if someone else has it, they swap.
    private func cycleColor(_ index: Int) {
        let next = (players[index].colorIndex + 1) % PartyStyle.tokenColors.count
        var list = players
        if let other = list.firstIndex(where: { $0.colorIndex == next }) {
            list[other] = list[other].copy(colorIndex: list[index].colorIndex)
        }
        list[index] = list[index].copy(colorIndex: next)
        players = list
        UiSound.play(.Tap)
    }

    private func toggleBot(_ index: Int) {
        var next = bots
        next[index].toggle()
        if next.prefix(players.count).allSatisfy({ $0 }) {
            Haptics.play(.Warning)
            return
        }
        bots = next
    }

    private func start() {
        let ready = players.enumerated().map { i, p in p.copy(name: p.displayName(i)) }
        PartyStore.remember(ready, .SNAKES)
        let seatBots = Array(bots.prefix(ready.count))
        let final = ready.enumerated().map { i, p in seatBots[i] ? botPersona(p, i) : p }
        settings = settings.copy(playerCount: ready.count, bots: bots)
        Prefs.save(SETTINGS_KEY, settings)
        UiSound.play(.Turn)
        onStart(SnakesConfig(players: final, themeID: settings.themeID, rules: settings.rules, bots: seatBots))
    }

    var body: some View {
        let accent = GameAccent.snakes
        RoyalBackground(glow: accent[1], secondGlow: accent[0]) {
            ZStack {
                VStack(spacing: 0) {
                    RoyalTopBar(GameKind.SNAKES.title, onBack, subtitle: "\(GameKind.SNAKES.playersLabel) · Offline · Same device")
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            hero(accent)
                                .springIn()
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Players")
                                CountPicker(count: players.count, onChange: setPlayerCount)
                                RoyalPanel(padding: 6) {
                                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                                        let isBot = bots[index]
                                        PlayerRow(
                                            player: isBot ? botPersona(player, index) : player,
                                            isBot: isBot,
                                            onEdit: { if !isBot { editing = player } },
                                            onToggleBot: { toggleBot(index) },
                                            onColor: { cycleColor(index) }
                                        )
                                        if index < players.count - 1 {
                                            Rectangle().fill(Royal.Stroke).frame(height: 1).frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                            .springIn(60)
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Board & rules")
                                ThemeCard(theme: SnakesTheme.theme(settings.themeID)) { showThemes = true }
                                OptionToggle(icon: Icons.Rounded.Looks6, title: "Roll a 6 to start", subtitle: "Tokens wait at the start until they roll a six",
                                             checked: settings.rules.requireSixToStart) { v in
                                    settings = settings.copy(rules: settings.rules.copy(requireSixToStart: v))
                                }
                                OptionToggle(icon: Icons.Rounded.SportsScore, title: "Exact roll to finish", subtitle: "Rolls that would pass 100 don't move",
                                             checked: settings.rules.exactRollToFinish) { v in
                                    settings = settings.copy(rules: settings.rules.copy(exactRollToFinish: v))
                                }
                                OptionToggle(icon: Icons.Rounded.Replay, title: "Extra turn on 6", subtitle: "Roll again after a six — three in a row ends the turn",
                                             checked: settings.rules.extraTurnOnSix) { v in
                                    settings = settings.copy(rules: settings.rules.copy(extraTurnOnSix: v))
                                }
                            }
                            .springIn(120)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                    CandyButton(
                        "Start game", start,
                        colors: [Color(argb: 0xFF7DF0B8), accent[0], accent[1]],
                        textColor: .white,
                        icon: Icons.Rounded.PlayArrow
                    )
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [Color.clear, Royal.Night.copy(alpha: 0.9)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                    )
                }

                if showThemes {
                    SnakesThemePicker(selection: settings.themeID, onSelect: { settings = settings.copy(themeID: $0) }) { showThemes = false }
                        .transition(.asymmetric(
                            insertion: AnyTransition.opacity.animation(.tween(180))
                                .combined(with: AnyTransition.modifier(active: SlideFraction(fraction: 1.0 / 6), identity: SlideFraction(fraction: 0))
                                    .animation(.compose(dampingRatio: 1, stiffness: 400))),
                            removal: AnyTransition.opacity.animation(.tween(160))
                                .combined(with: AnyTransition.modifier(active: SlideFraction(fraction: 1.0 / 6), identity: SlideFraction(fraction: 0))
                                    .animation(.compose(dampingRatio: 1, stiffness: 400)))
                        ))
                        .zIndex(10)
                }

                PlayerEditDialog(
                    editing,
                    onDismiss: { editing = nil },
                    onSave: { updated in
                        players = players.map { $0.id == updated.id ? updated : $0 }
                        editing = nil
                    },
                    showColors: true,
                    takenColors: Set(players.filter { $0.id != editing?.id }.map(\.colorIndex))
                )
                .zIndex(20)
            }
            .animation(.compose(dampingRatio: 1, stiffness: 400), value: showThemes)
        }
    }

    private func hero(_ accent: [Color]) -> some View {
        HStack(spacing: 0) {
            let shape = RoundedCornerShape(28)
            SnakesGame.shared.Artwork()
                .frame(width: 96, height: 96)
                .frame(width: 112, height: 112)
                .background(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1.5))
                .background(shape.fill(accent[0]).composeShadow(14, color: accent[0]))
            Spacer().frame(width: 16)
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up the table", style: displayStyle(24))
                Text(GameKind.SNAKES.tagline, style: bodyStyle(13, .SemiBold, Royal.Smoke))
                    .fixedSize(horizontal: false, vertical: true)
                RoyalChip("Works offline", icon: Icons.Rounded.WifiOff, color: Royal.Gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Offset by a fraction of the view's own height (Compose `slideInVertically { it / 6 }`).
private struct SlideFraction: ViewModifier {
    let fraction: CGFloat

    func body(content: Content) -> some View {
        let f = fraction
        content.visualEffect { c, proxy in c.offset(y: proxy.size.height * f) }
    }
}

private struct CountPicker: View {
    let count: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GameKind.SNAKES.minPlayers...GameKind.SNAKES.maxPlayers, id: \.self) { n in
                let on = n == count
                let text = on ? Color.white : Royal.Ivory
                let shape = RoundedCornerShape(16)
                VStack(spacing: 0) {
                    Text("\(n)", style: displayStyle(20, text))
                    Text("players", style: bodyStyle(9, .Bold, text))
                }
                .animation(.compose(dampingRatio: 1, stiffness: 1500), value: on)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    if on {
                        LinearGradient(colors: GameAccent.snakes, startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Royal.panelBrush
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(on ? Color.white.opacity(0.5) : Royal.Stroke, lineWidth: 1))
                .background(shape.fill(on ? GameAccent.snakes[0] : Royal.Panel).composeShadow(on ? 10 : 4, color: on ? GameAccent.snakes[0] : .black))
                .pressable(sound: nil, pressedScale: 0.92) { onChange(n) }
                .accessibilityLabel("\(n) players")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlayerRow: View {
    let player: PartyPlayer
    let isBot: Bool
    let onEdit: () -> Void
    let onToggleBot: () -> Void
    let onColor: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Kotlin makes the whole row the edit target; here the avatar and name are (SwiftUI buttons don't nest).
            HStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarBadge(player, size: 48)
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
                    Text(PartyStyle.colorNames[player.colorIndex % PartyStyle.colorNames.count].uppercased(),
                         style: bodyStyle(10, .Black, player.color).copy(letterSpacing: 1))
                    Text(player.name, style: bodyStyle(17, .ExtraBold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .pressable(enabled: !isBot, pressedScale: 0.97, onClick: onEdit)
            // Person / CPU switch.
            HStack(spacing: 0) {
                Icon(isBot ? Icons.Rounded.SmartToy : Icons.Rounded.Person, tint: isBot ? Royal.Emerald : Royal.Smoke, size: 15)
                Spacer().frame(width: 4)
                Text(isBot ? "CPU" : "Person", style: bodyStyle(12, .ExtraBold, isBot ? Royal.Emerald : Royal.Smoke))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Capsule().fill(isBot ? Royal.Emerald.copy(alpha: 0.18) : Royal.Glass))
            .overlay(Capsule().strokeBorder(isBot ? Royal.Emerald.copy(alpha: 0.6) : Royal.Stroke, lineWidth: 1))
            .clipShape(Capsule())
            .pressable(sound: .Toggle, haptic: .Tick, onClick: onToggleBot)
            .accessibilityLabel(isBot ? "Computer player, tap for a person" : "Person, tap for a computer player")
            Spacer().frame(width: 4)
            let c = SnakesColor.player(player)
            Circle()
                .fill(LinearGradient(colors: [c.mix(.White, 0.2).color, c.color], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                .frame(width: 30, height: 30)
                .background(Circle().fill(c.color).composeShadow(4, color: c.color))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .pressable(sound: nil, pressedScale: 0.85, onClick: onColor)
                .accessibilityLabel("Change colour")
        }
        .padding(10)
        .frame(maxWidth: .infinity)
    }
}

private struct ThemeCard: View {
    let theme: SnakesTheme
    let onClick: () -> Void

    var body: some View {
        RoyalPanel(padding: 12) {
            HStack(spacing: 0) {
                SnakesBoardArt(theme, 7.2, showsNumbers: false)
                    .equatable()
                    .padding(8)
                    .background(theme.backgroundGradient)
                    .clipShape(RoundedCornerShape(14))
                Spacer().frame(width: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text("BOARD THEME", style: bodyStyle(10, .Black, Royal.Smoke).copy(letterSpacing: 1))
                    Text("\(theme.emoji) \(theme.name)", style: bodyStyle(17, .ExtraBold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("10 boards to choose from", style: bodyStyle(12, .SemiBold, Royal.Smoke))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, tint: Royal.Gold)
            }
        }
        .pressable(pressedScale: 0.97, onClick: onClick)
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
                Icon(icon, tint: Royal.Gold, size: 20)
                    .frame(width: 38, height: 38)
                    .background(RoundedCornerShape(12).fill(Royal.Gold.copy(alpha: 0.14)))
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title, style: bodyStyle(15, .ExtraBold))
                    Text(subtitle, style: bodyStyle(12, .SemiBold, Royal.Smoke))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 8)
                RoyalSwitch(checked, onChange, label: title)
            }
        }
    }
}

/// Gallery of the ten Snakes & Ladders boards.
struct SnakesThemePicker: View {
    let selection: Int
    let onSelect: (Int) -> Void
    let onDone: () -> Void

    init(selection: Int, onSelect: @escaping (Int) -> Void, onDone: @escaping () -> Void) {
        self.selection = selection
        self.onSelect = onSelect
        self.onDone = onDone
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Royal.nightBrush)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Board themes", style: displayStyle(24, Royal.Gold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    OutlineButton("Done", onDone, height: 42)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(SnakesTheme.all) { theme in
                            ThemeTile(theme: theme, selected: theme.id == selection) {
                                onSelect(theme.id)
                                UiSound.play(.Tap)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct ThemeTile: View {
    let theme: SnakesTheme
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedCornerShape(24)
        let accent = theme.accent.color
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let cell = (geo.size.width - 16) / 10
                SnakesBoardArt(theme, cell, showsNumbers: cell > 13)
                    .equatable()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(theme.backgroundGradient)
            .clipShape(RoundedCornerShape(18))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(theme.emoji) \(theme.name)", style: bodyStyle(14, .ExtraBold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(theme.tagline, style: bodyStyle(11, .SemiBold, Royal.Smoke))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Royal.panelBrush)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(selected ? accent : Royal.Stroke, lineWidth: selected ? 3 : 1)
                .animation(.compose(dampingRatio: 0.75, stiffness: 1500), value: selected)
        )
        .overlay(alignment: .topTrailing) {
            ZStack {
                if selected {
                    ZStack {
                        Circle().fill(Color.white)
                        Icon(Icons.Rounded.CheckCircle, "Selected", tint: accent, size: 28)
                    }
                    .frame(width: 28, height: 28)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(10)
            .animation(.compose(dampingRatio: 1, stiffness: 400), value: selected)
        }
        .background(shape.fill(Royal.Panel).composeShadow(selected ? 14 : 8, color: selected ? accent : .black))
        .pressable(sound: nil, pressedScale: 0.96, onClick: onClick)
    }
}
