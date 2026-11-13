import SwiftUI
import GameKit

/// Before a Ludo match: how many seats, how many people, who sits where, the board and the rules.
struct LudoSetupScreen: View {
    let onBack: () -> Void
    let onStart: (LudoConfig) -> Void
    let onResume: (LudoConfig) -> Void

    @State private var setup: LudoStore.Setup = LudoStore.setup
    @State private var seats: [LudoSeat] = []
    @State private var editing: Int? = nil
    @State private var showRules = false
    @State private var saved: LudoStore.SavedMatch? = LudoStore.saved

    init(onBack: @escaping () -> Void, onStart: @escaping (LudoConfig) -> Void, onResume: @escaping (LudoConfig) -> Void) {
        self.onBack = onBack
        self.onStart = onStart
        self.onResume = onResume
    }

    private var arms: Int { (setup.seats >= 5 || (setup.sixArms && setup.seats >= 3)) ? 6 : 4 }
    private var geometry: LudoGeometry { LudoGeometry(arms) }
    private var theme: LudoTheme { LudoTheme.theme(setup.themeID) }

    /// Lays out the seats: people first (keeping their names), then computers.
    private func rebuild(_ next: LudoStore.Setup? = nil) {
        let next = next ?? setup
        let boardArms = (next.seats >= 5 || (next.sixArms && next.seats >= 3)) ? 6 : 4
        let people = min(next.peopleCount, next.seats)
        var known = seats.filter { !$0.isBot }.map { $0.player }
        if known.isEmpty { known += next.players }
        if known.isEmpty { known.append(PartyPlayer(name: AppSettings.displayName, avatar: AppSettings.data.avatar, colorIndex: 0)) }
        for extra in PartyStore.players(.LUDO) ?? [] where !known.contains(where: { $0.id == extra.id }) { known.append(extra) }
        while known.count < people {
            let used = Set(known.map { $0.avatar })
            let avatar = PartyStyle.avatars.first { !used.contains($0) } ?? "🙂"
            known.append(PartyPlayer(name: "Player \(known.count + 1)", avatar: avatar, colorIndex: known.count))
        }
        let defaults = LudoGeometry.defaultArms(next.seats, boardArms)
        var taken = Set<Int>()
        var result: [LudoSeat] = []
        for i in 0..<next.seats {
            let isBot = i >= people
            // Keep a seat's colour when it's still on this board.
            var arm = (i < seats.count && seats[i].isBot == isBot && seats[i].arm < boardArms) ? seats[i].arm : defaults[i]
            if taken.contains(arm) {
                arm = defaults.first { !taken.contains($0) } ?? (0..<boardArms).first { !taken.contains($0) } ?? 0
            }
            taken.insert(arm)
            if isBot {
                let b = i - people
                let player = PartyPlayer(name: LudoStore.botNames[b % LudoStore.botNames.count],
                                         avatar: LudoStore.botAvatars[b % LudoStore.botAvatars.count], colorIndex: arm)
                let difficulty = next.difficulties.isEmpty ? LudoDifficulty.NORMAL : next.difficulties[min(b, next.difficulties.count - 1)]
                result.append(LudoSeat(player, arm, isBot: true, difficulty: difficulty))
            } else {
                result.append(LudoSeat(known[i], arm, isBot: false))
            }
        }
        setup = next
        seats = result
    }

    private func setSeats(_ count: Int) {
        var next = setup
        next.seats = count
        next.peopleCount = min(setup.peopleCount, count)
        // Five and six seats default to Quick unless the mode was picked by hand.
        if !next.customMode { next.rules.quick = count >= 5 }
        LudoSound.play(.Tap)
        rebuild(next)
    }

    private func setPeople(_ count: Int) {
        LudoSound.play(.Tap)
        var next = setup
        next.peopleCount = count
        rebuild(next)
    }

    private func cycleColor(_ index: Int) {
        LudoSound.play(.Tap)
        let current = seats[index].arm
        let next = (current + 1) % arms
        seats = seats.enumerated().map { i, s in
            var s = s
            if i == index { s.arm = next } else if s.arm == next { s.arm = current }
            return s
        }
    }

    private func cycleDifficulty(_ index: Int) {
        LudoSound.play(.Tap)
        let all = LudoDifficulty.entries
        let next = all[((all.firstIndex(of: seats[index].difficulty) ?? 0) + 1) % all.count]
        seats[index].difficulty = next
        let b = index - min(setup.peopleCount, setup.seats)
        if b >= 0 && b < setup.difficulties.count {
            setup.difficulties[b] = next
        }
    }

    private func start() {
        let people = seats.filter { !$0.isBot }
        var stored = setup
        stored.players = people.map { $0.player }
        stored.arms = people.map { $0.arm }
        setup = stored
        LudoStore.setup = stored
        PartyStore.remember(people.map { $0.player }, .LUDO)
        LudoStore.saved = nil
        LudoSound.play(.Turn)
        // A lone person sits at the bottom-left, next to their dice.
        let shift = people.count == 1 ? geometry.shift(toBottomLeft: people[0].arm) : 0
        let ordered = seats.enumerated().sorted { $0.element.arm != $1.element.arm ? $0.element.arm < $1.element.arm : $0.offset < $1.offset }.map(\.element)
        onStart(LudoConfig(seats: ordered, arms: arms, themeID: setup.themeID, rules: setup.rules, shift: shift))
    }

    var body: some View {
        ZStack {
            RoyalBackground(glow: GameAccent.ludo[0], secondGlow: GameAccent.ludo[1]) {
                VStack(spacing: 0) {
                    RoyalTopBar("Ludo", onBack, subtitle: "\(GameKind.LUDO.playersLabel) · Offline · Same device")
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            LudoSetupHeader(setup: setup, arms: arms, geometry: geometry, theme: theme, seats: seats)
                                .springIn(0)
                            if let saved {
                                LudoResumeCard(saved: saved) { onResume(saved.config) }
                                    .springIn(60)
                            }
                            LudoSetupSection(title: "Seats at the table") {
                                RoyalSegmented(Array(2...6), setup.seats, setSeats, { "\($0)" })
                            }
                            .springIn(120)
                            LudoSetupSection(title: "People playing") {
                                RoyalSegmented(Array(1...setup.seats), min(setup.peopleCount, setup.seats), setPeople, { "\($0)" })
                            }
                            .springIn(180)
                            if setup.seats == 3 || setup.seats == 4 {
                                RoyalPanel(padding: 12) {
                                    LudoToggleRow(icon: Icons.Rounded.Hexagon, color: ludoHex(0x8E5BE8).color, title: "Six-arm board", subtitle: "Roomier, longer games",
                                              value: setup.sixArms) { v in
                                        var next = setup
                                        next.sixArms = v
                                        rebuild(next)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            RoyalPanel(padding: 6) {
                                ForEach(Array(seats.enumerated()), id: \.offset) { index, seat in
                                    if index > 0 {
                                        Rectangle().fill(Royal.Stroke).frame(height: 1).padding(.horizontal, 10)
                                    }
                                    LudoSeatRow(
                                        seat: seat, color: theme.color(seat.arm, arms), colorName: LudoTheme.colorName(seat.arm, arms),
                                        onColor: { cycleColor(index) },
                                        onDifficulty: { cycleDifficulty(index) },
                                        onEdit: { editing = index }
                                    )
                                }
                            }
                            .springIn(240)
                            LudoSetupSection(title: "Board design") {
                                VStack(spacing: 10) {
                                    ForEach(0..<2, id: \.self) { row in
                                        HStack(spacing: 10) {
                                            ForEach(LudoTheme.all[(row * 3)..<(row * 3 + 3)], id: \.id) { item in
                                                LudoThemeTile(item: item, geometry: geometry, arms: arms, selected: item.id == setup.themeID) {
                                                    LudoSound.play(.Tap)
                                                    setup.themeID = item.id
                                                }
                                                .frame(maxWidth: .infinity)
                                            }
                                        }
                                    }
                                }
                            }
                            .springIn(300)
                            LudoSetupSection(title: "Rules") {
                                LudoRulesPanel(setup: $setup, arms: arms, onMore: { showRules = true })
                            }
                            .springIn(360)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                        .animation(.compose(dampingRatio: 0.8, stiffness: 400), value: seats.count)
                        .animation(.compose(dampingRatio: 1, stiffness: 400), value: setup.seats == 3 || setup.seats == 4)
                    }
                    CandyButton("Start game", start, icon: Icons.Rounded.PlayArrow, enabled: !seats.isEmpty)
                        .frame(maxWidth: 600)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(LinearGradient(colors: [.clear, Royal.Night.copy(alpha: 0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
                }
            }

            LudoRulesSheet(visible: showRules, rules: setup.rules, onChange: { setup.rules = $0 }, onDismiss: { showRules = false })

            PlayerEditDialog(
                editing.flatMap { $0 < seats.count ? seats[$0].player : nil },
                onDismiss: { editing = nil },
                onSave: { p in
                    if let i = editing, i < seats.count { seats[i].player = p.copy(name: String(p.name.prefix(14))) }
                    editing = nil
                },
                showColors: false
            )
        }
        .onAppear { if seats.isEmpty { rebuild() } }
    }
}

private struct LudoSetupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title, color: Royal.Smoke)
            content
        }
    }
}

private struct LudoSetupHeader: View {
    let setup: LudoStore.Setup
    let arms: Int
    let geometry: LudoGeometry
    let theme: LudoTheme
    let seats: [LudoSeat]

    var body: some View {
        let people = min(setup.peopleCount, setup.seats)
        let bots = setup.seats - people
        let who = people == 1 ? "You" : "\(people) people"
        let summary = bots == 0 ? "\(who), pass and play." : "\(who) and \(bots) computer\(bots == 1 ? "" : "s")."
        let shape = RoundedCornerShape(24)
        HStack(spacing: 14) {
            LudoBoardPlate(geometry: geometry, theme: theme, shift: 0, armsInPlay: Set(seats.map { $0.arm }))
                .padding(6)
                .frame(width: 130, height: 130)
                .background(LinearGradient(colors: theme.backdrop.map(\.color), startPoint: .top, endPoint: .bottom))
                .clipShape(shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [Royal.GoldLight.copy(alpha: 0.8), Royal.GoldDark.copy(alpha: 0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                .background(shape.fill(theme.backdrop[0].color).composeShadow(14, color: theme.backdrop[0].color))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(setup.seats) PLAYERS · \(arms)-ARM BOARD", style: bodyStyle(11, .Black, Royal.Gold).copy(letterSpacing: 1.2))
                Text("Set the table", style: displayStyle(26))
                Text(summary, style: bodyStyle(13, .SemiBold, Royal.Smoke)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    Icon(Icons.Rounded.AirplanemodeActive, tint: Royal.Smoke, size: 13)
                    Spacer().frame(width: 4)
                    Text("Works offline · same device", style: bodyStyle(11, .Black, Royal.Smoke))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LudoResumeCard: View {
    let saved: LudoStore.SavedMatch
    let onResume: () -> Void

    var body: some View {
        let seat = saved.config.seats[min(saved.engine.current, saved.config.seats.count - 1)]
        RoyalPanel(padding: 12) {
            HStack(spacing: 0) {
                Icon(Icons.Rounded.PlayCircle, tint: Royal.Gold, size: 34)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Game in progress", style: displayStyle(18))
                    Text("\(saved.config.seats.count) players · \(seat.player.name) to play", style: bodyStyle(12, .Bold, Royal.Smoke))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CandyButton("Resume", onResume, height: 42, fontSize: 17)
                    .frame(width: 118)
            }
        }
    }
}

private struct LudoSeatRow: View {
    let seat: LudoSeat
    let color: LudoColor
    let colorName: String
    let onColor: () -> Void
    let onDifficulty: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let row = HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.mix(.White, 0.15).color, color.mix(.Black, 0.2).color], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Color.White, lineWidth: 2.5)
                Text(seat.player.avatar).font(.system(size: 20))
            }
            .frame(width: 40, height: 40)
            .background(Circle().fill(color.color).composeShadow(6, color: color.color))
            .frame(width: 48, height: 48)
            .pressable(sound: .Tap, pressedScale: 0.88, onClick: onColor)
            .accessibilityLabel("\(colorName) seat. Change colour")
            VStack(alignment: .leading, spacing: 0) {
                Text(seat.player.name, style: bodyStyle(16, .ExtraBold, Royal.Ivory)).lineLimit(1).truncationMode(.tail)
                Text(colorName, style: bodyStyle(11, .Bold, color.mix(.White, 0.25).color))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if seat.isBot {
                Text(seat.difficulty.title, style: bodyStyle(13, .Black, Royal.Gold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Royal.Glass))
                    .overlay(Capsule().strokeBorder(Royal.Stroke, lineWidth: 1))
                    .pressable(sound: .Toggle, haptic: .Tick, pressedScale: 0.92, onClick: onDifficulty)
                    .accessibilityLabel("Computer level \(seat.difficulty.title). Change")
                LudoTag(icon: Icons.Rounded.Memory, text: "CPU", color: Royal.Smoke)
            } else {
                Icon(Icons.Rounded.Edit, tint: Royal.Smoke, size: 16)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Royal.Glass))
                    .pressable(sound: .Tap, pressedScale: 0.88, onClick: onEdit)
                    .accessibilityLabel("Edit \(seat.player.name)")
                LudoTag(icon: Icons.Rounded.Person, text: "Person", color: Royal.Emerald)
            }
        }
        .frame(minHeight: 60)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)

        if seat.isBot {
            row
        } else {
            row.pressable(pressedScale: 0.98, onClick: onEdit)
        }
    }
}

private struct LudoTag: View {
    let icon: ImageVector
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, tint: color, size: 13)
            Spacer().frame(width: 3)
            Text(text, style: bodyStyle(11, .Black, color))
        }
    }
}

private struct LudoThemeTile: View {
    let item: LudoTheme
    let geometry: LudoGeometry
    let arms: Int
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedCornerShape(16)
        VStack(spacing: 5) {
            LudoBoardPlate(geometry: geometry, theme: item, shift: 0, armsInPlay: Set(0..<arms))
                .padding(6)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: item.backdrop.map(\.color), startPoint: .top, endPoint: .bottom))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Royal.goldBrush, lineWidth: selected ? 3 : 0).animation(.compose(dampingRatio: 0.6, stiffness: 1500), value: selected))
                .background(shape.fill(item.backdrop[0].color).composeShadow(selected ? 12 : 4, color: selected ? Royal.Gold : .black))
            Text(item.name, style: bodyStyle(11, .Black, selected ? Royal.Ivory : Royal.Smoke)).lineLimit(1)
        }
        .pressable(sound: .Toggle, pressedScale: 0.95, onClick: onClick)
        .accessibilityLabel("\(item.name) board\(selected ? ", selected" : "")")
    }
}

private struct LudoToggleRow: View {
    let icon: ImageVector
    let color: Color
    let title: String
    let subtitle: String?
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, tint: .White, size: 19)
                .frame(width: 34, height: 34)
                .background(RoundedCornerShape(10).fill(color))
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(title, style: bodyStyle(15, .ExtraBold))
                if let subtitle { Text(subtitle, style: bodyStyle(12, .SemiBold, Royal.Smoke)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoyalSwitch(value, onChange, label: title)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}

private struct LudoRulesPanel: View {
    @Binding var setup: LudoStore.Setup
    let arms: Int
    let onMore: () -> Void

    var body: some View {
        RoyalPanel(padding: 14) {
            RoyalSegmented([false, true], setup.rules.quick, { v in
                setup.rules.quick = v
                setup.customMode = true
            }, { $0 ? "Quick" : "Classic" })
            Spacer().frame(height: 8)
            Text(setup.rules.quick ? "Two tokens each, already out of the yard. Fast and lively." : "Four tokens each, starting in the yard. The full classic game.",
                 style: bodyStyle(13, .SemiBold, Royal.Smoke))
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 12)
            RoyalSegmented([false, true], setup.rules.allPlaces, { setup.rules.allPlaces = $0 }, { $0 ? "All places" : "First winner" })
            Spacer().frame(height: 12)
            HStack(spacing: 0) {
                Icon(Icons.Rounded.Schedule, tint: Royal.Gold, size: 18)
                Spacer().frame(width: 6)
                Text("About \(LudoStore.estimatedMinutes(setup.seats, setup.peopleCount, arms, setup.rules)) min", style: bodyStyle(14, .Black, Royal.Ivory))
                    .frame(maxWidth: .infinity, alignment: .leading)
                OutlineButton("More rules", onMore, icon: Icons.Rounded.Tune, height: 42)
            }
        }
    }
}

/// The finer rule options.
private struct LudoRulesSheet: View {
    let visible: Bool
    let rules: LudoRules
    let onChange: (LudoRules) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            if visible {
                LudoRulesCard(rules: rules, onChange: onChange, onDismiss: onDismiss)
                    .transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.16), value: visible)
    }

    private struct LudoRulesCard: View {
        let rules: LudoRules
        let onChange: (LudoRules) -> Void
        let onDismiss: () -> Void

        @State private var scale: CGFloat = 0.85

        private func set(_ change: (inout LudoRules) -> Void) {
            var r = rules
            change(&r)
            onChange(r)
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                WoodPanel(padding: 18) {
                    ViewThatFits(in: .vertical) {
                        content
                        ScrollView(showsIndicators: false) { content }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {}
                .frame(maxWidth: 440)
                .padding(22)
                .scaleEffect(scale)
                .onAppear { withAnimation(.compose(dampingRatio: 0.6, stiffness: 500)) { scale = 1 } }
            }
        }

        private var content: some View {
            VStack(spacing: 0) {
                Text("Rules", style: displayStyle(26, Royal.Gold, .Center)).frame(maxWidth: .infinity)
                Spacer().frame(height: 10)
                LudoToggleRow(icon: Icons.Rounded.LooksOne, color: ludoHex(0xF0453A).color, title: "Come out on a 1 too", subtitle: nil, value: rules.oneOrSix) { v in set { $0.oneOrSix = v } }
                LudoToggleRow(icon: Icons.Rounded.Bolt, color: ludoHex(0xFF8A1F).color, title: "Extra roll after a capture", subtitle: nil, value: rules.captureBonus) { v in set { $0.captureBonus = v } }
                LudoToggleRow(icon: Icons.Rounded.Star, color: ludoHex(0xFFC21C).color, title: "Safe star squares", subtitle: nil, value: rules.safeStars) { v in set { $0.safeStars = v } }
                LudoToggleRow(icon: Icons.Rounded.Shield, color: ludoHex(0x2DB45A).color, title: "Blockades", subtitle: "Two of your tokens block a square", value: rules.blockades) { v in set { $0.blockades = v } }
                LudoToggleRow(icon: Icons.Rounded.TouchApp, color: ludoHex(0x2E8BEF).color, title: "Auto-move a single choice", subtitle: nil, value: rules.autoMove) { v in set { $0.autoMove = v } }
                LudoToggleRow(icon: Icons.Rounded.FastForward, color: ludoHex(0x8E5BE8).color, title: "Fast computers", subtitle: nil, value: rules.fastBots) { v in set { $0.fastBots = v } }
                Spacer().frame(height: 14)
                CandyButton("Done", onDismiss, height: 50, fontSize: 20)
            }
        }
    }
}
