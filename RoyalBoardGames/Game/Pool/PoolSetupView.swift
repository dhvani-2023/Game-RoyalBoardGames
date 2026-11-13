import SwiftUI
import GameKit

/// Before a Pool match: the game, players, people, the turn order, the table, the cue and the rules.
struct PoolSetupScreen: View {
    let onBack: () -> Void
    let onStart: (PoolConfig) -> Void

    @State private var setup = PoolStore.setup
    @State private var seats: [PoolSeat] = []
    @State private var editing: Int? = nil
    @State private var saved = PoolStore.saved

    init(onBack: @escaping () -> Void, onStart: @escaping (PoolConfig) -> Void) {
        self.onBack = onBack
        self.onStart = onStart
    }

    private var game: PoolVariant { setup.seats == 3 ? .NINE : setup.options.game }

    var body: some View {
        let game = game
        let theme = PoolTableTheme.theme(setup.tableID)
        let teams = game == .EIGHT && setup.seats == 4
        ZStack {
            RoyalBackground(glow: theme.cloth[1].color, secondGlow: Royal.Amethyst) {
                VStack(spacing: 0) {
                    RoyalTopBar("Pool", onBack, subtitle: "8-Ball · 9-Ball")
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            PoolSetupHeader(setup: setup, game: game, theme: theme).springIn(0)
                            if let saved {
                                PoolResumeCard(saved: saved) { onStart(saved.config) }.springIn(40)
                            }
                            PoolSetupSection("Game") {
                                HStack(spacing: 10) {
                                    ForEach(PoolVariant.allCases, id: \.self) { item in
                                        PoolGameCard(item: item, selected: item == game, disabled: setup.seats == 3 && item == .EIGHT) {
                                            setup.options.game = item
                                        }
                                    }
                                }
                            }
                            .springIn(80)
                            PoolSetupSection("Players") {
                                RoyalSegmented([2, 3, 4], setup.seats, { count in
                                    var s = setup
                                    s.seats = count
                                    s.peopleCount = min(setup.peopleCount, count)
                                    setup = s
                                    rebuild(s)
                                }, { "\($0)" })
                                Text(playersText(teams), style: bodyStyle(12, .SemiBold, Royal.Smoke))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .springIn(120)
                            PoolSetupSection("People playing") {
                                RoyalSegmented(Array(1...setup.seats), min(setup.peopleCount, setup.seats), { count in
                                    var s = setup
                                    s.peopleCount = count
                                    setup = s
                                    rebuild(s)
                                }, { "\($0)" })
                            }
                            .springIn(160)
                            RoyalPanel(padding: 6) {
                                ForEach(Array(seats.enumerated()), id: \.offset) { index, seat in
                                    if index > 0 { Rectangle().fill(Royal.Stroke).frame(height: 1).frame(maxWidth: .infinity) }
                                    PoolSeatRow(
                                        index: index, seat: seat, teams: teams,
                                        onColour: { changeColour(index) },
                                        onMove: { move(index) },
                                        onLevel: { changeLevel(index) },
                                        onEdit: { editing = index }
                                    )
                                }
                            }
                            .springIn(200)
                            PoolSetupSection("Table") {
                                VStack(spacing: 8) {
                                    ForEach(0..<2, id: \.self) { row in
                                        HStack(spacing: 8) {
                                            ForEach(PoolTableTheme.all[(row * 4)..<min(PoolTableTheme.all.count, row * 4 + 4)], id: \.id) { item in
                                                PoolTableTile(item: item, selected: item.id == setup.tableID) {
                                                    setup.tableID = item.id
                                                    if !setup.customCue { setup.cueID = item.cue }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .springIn(240)
                            PoolSetupSection("Cue") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(PoolCueStyle.all, id: \.id) { style in
                                            PoolCueTile(style: style, selected: style.id == setup.cueID) {
                                                setup.cueID = style.id
                                                setup.customCue = true
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .springIn(280)
                            PoolSetupSection("Rules") {
                                PoolRulesPanel(setup: setup, game: game) { setup = $0 }
                            }
                            .springIn(320)
                        }
                        .frame(maxWidth: 640)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                    }
                    HStack(spacing: 10) {
                        // Extras: a practice table for the first person, keeping any saved match.
                        if ExtrasFeatures.practiceTable { ExtrasPracticeButton(practice) }
                        CandyButton("Start game", start, icon: Icons.Rounded.PlayArrow)
                    }
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
            }
            PlayerEditDialog(
                editing.flatMap { $0 < seats.count ? seats[$0].player : nil },
                onDismiss: { editing = nil },
                onSave: { p in
                    if let i = editing, i < seats.count {
                        seats[i] = seats[i].copy(player: p.copy(name: String(p.name.prefix(14))))
                    }
                    editing = nil
                },
                showColors: false
            )
        }
        .onAppear { if seats.isEmpty { rebuild(setup) } }
    }

    private func playersText(_ teams: Bool) -> String {
        switch setup.seats {
        case 3: return "Three players play 9-Ball in rotation, everyone for themselves."
        case 4: return teams ? "Four players play as two teams: partners take turns, A1, B1, A2, B2." : "Four players in rotation, everyone for themselves."
        default: return "One against one."
        }
    }

    /// Lays out the seats: people first (keeping their names), then computers.
    private func rebuild(_ s: PoolStore.Setup) {
        let people = min(s.peopleCount, s.seats)
        var known = seats.filter { !$0.isBot }.map { $0.player }
        if known.isEmpty { known += s.players }
        if known.isEmpty {
            let name = AppSettings.data.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            known.append(PartyPlayer(name: name.isEmpty ? "Player 1" : name, avatar: AppSettings.data.avatar, colorIndex: 0))
        }
        for extra in PartyStore.players(.POOL) ?? [] where !known.contains(where: { $0.id == extra.id }) { known.append(extra) }
        while known.count < people {
            let used = Set(known.map { $0.avatar })
            let avatar = PartyStyle.avatars.first { !used.contains($0) } ?? "🙂"
            known.append(PartyPlayer(name: "Player \(known.count + 1)", avatar: avatar, colorIndex: known.count))
        }
        var usedColours = Set<Int>()
        var result: [PoolSeat] = []
        for i in 0..<s.seats {
            if i < people {
                var player = known[i]
                if usedColours.contains(player.colorIndex) {
                    player = player.copy(colorIndex: (0..<6).first { !usedColours.contains($0) } ?? i)
                }
                usedColours.insert(player.colorIndex)
                result.append(PoolSeat(player, isBot: false))
            } else {
                let b = i - people
                let colour = (0..<6).first { !usedColours.contains($0) } ?? i
                usedColours.insert(colour)
                let player = PartyPlayer(name: PoolStore.botNames[b % PoolStore.botNames.count],
                                         avatar: PoolStore.botAvatars[b % PoolStore.botAvatars.count], colorIndex: colour)
                result.append(PoolSeat(player, isBot: true, difficulty: s.difficulties[min(b, s.difficulties.count - 1)]))
            }
        }
        seats = result
    }

    private func changeColour(_ index: Int) {
        PoolSound.play(PoolSound.tap)
        let current = seats[index].player.colorIndex
        let next = (current + 1) % PartyStyle.tokenColors.count
        seats = seats.enumerated().map { i, s in
            if i == index { return s.copy(player: s.player.copy(colorIndex: next)) }
            if s.player.colorIndex == next { return s.copy(player: s.player.copy(colorIndex: current)) }
            return s
        }
    }

    private func move(_ index: Int) {
        if seats.count > 1 {
            PoolSound.play(PoolSound.tap)
            let other = (index + 1) % seats.count
            var list = seats
            list.swapAt(index, other)
            seats = list
        }
    }

    private func changeLevel(_ index: Int) {
        PoolSound.play(PoolSound.tap)
        let all = PoolDifficulty.allCases
        let next = all[(all.firstIndex(of: seats[index].difficulty)! + 1) % all.count]
        seats[index] = seats[index].copy(difficulty: next)
        let b = seats.prefix(index).filter { $0.isBot }.count
        if b < setup.difficulties.count { setup.difficulties[b] = next }
    }

    private func practice() {
        guard let seat = seats.first(where: { !$0.isBot }) ?? seats.first else { return }
        PoolSound.play(PoolSound.turn)
        onStart(PoolPractice.config(seat, setup.options, game, setup.tableID, setup.cueID))
    }

    private func start() {
        let people = seats.filter { !$0.isBot }
        var s = setup
        s.players = people.map { $0.player }
        setup = s
        PoolStore.setup = s
        PartyStore.remember(people.map { $0.player }, .POOL)
        PoolStore.saved = nil
        PoolSound.play(PoolSound.turn)
        var options = s.options
        options.game = game
        onStart(PoolConfig(seats, options, s.tableID, s.cueID))
    }
}

private struct PoolSetupSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title, color: Royal.Smoke)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PoolSetupHeader: View {
    let setup: PoolStore.Setup
    let game: PoolVariant
    let theme: PoolTableTheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .circular)
        HStack(spacing: 14) {
            PoolTablePreview(theme, game, setup.options.tableSize)
                .padding(8)
                .frame(width: 136, height: 136)
                .background(shape.fill(LinearGradient(colors: theme.backdrop.map { $0.color }, startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1.2))
                .clipShape(shape)
                .background(shape.fill(Color.black).composeShadow(12))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(setup.seats) PLAYERS · \(game.title.uppercased())", style: bodyStyle(11, .Black, Royal.Gold).copy(letterSpacing: 1.4))
                Text("Rack 'em up", style: displayStyle(28))
                let people = min(setup.peopleCount, setup.seats)
                let bots = setup.seats - people
                let who = people == 1 ? "You" : "\(people) people"
                Text(bots == 0 ? "\(who), pass and play." : "\(who) and \(bots) computer\(bots == 1 ? "" : "s").", style: bodyStyle(13, .SemiBold, Royal.Smoke))
                HStack(spacing: 4) {
                    Icon(Icons.Rounded.AirplanemodeActive, tint: Royal.Smoke, size: 13)
                    Text("Works offline · same device", style: bodyStyle(11, .ExtraBold, Royal.Smoke))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PoolResumeCard: View {
    let saved: PoolStore.SavedMatch
    let onResume: () -> Void

    var body: some View {
        let seat = saved.config.seats[min(saved.match.table.turn, saved.config.seats.count - 1)]
        RoyalPanel(padding: 12) {
            HStack(spacing: 12) {
                PoolMiniBall(saved.match.game == .EIGHT ? 8 : 9, 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Game in progress", style: bodyStyle(16, .ExtraBold))
                    Text("\(saved.match.game.title) · \(seat.player.name) to shoot", style: bodyStyle(12, .SemiBold, Royal.Smoke))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CandyButton("Resume", onResume, icon: Icons.AutoMirrored.Rounded.ArrowForward, height: 42, fontSize: 17)
                    .frame(width: 124)
            }
        }
    }
}

private struct PoolGameCard: View {
    let item: PoolVariant
    let selected: Bool
    let disabled: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: -4) {
                ForEach(item == .EIGHT ? [1, 8, 12] : [1, 9, 4], id: \.self) { PoolMiniBall($0, 24) }
            }
            Text(item.title, style: displayStyle(18))
            Text(item.blurb, style: bodyStyle(11, .SemiBold, Royal.Smoke)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background {
            if selected {
                shape.fill(LinearGradient(colors: [Royal.Gold.copy(alpha: 0.22), Royal.Panel], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(Royal.panelBrush)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(selected ? Royal.Gold : Royal.Stroke, lineWidth: selected ? 2.5 : 1).animation(.tween(300), value: selected))
        .pressable(enabled: !disabled, sound: nil, pressedScale: 0.96) {
            PoolSound.play(PoolSound.tap)
            onClick()
        }
        .opacity(disabled ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title): \(item.blurb)")
    }
}

private struct PoolSeatRow: View {
    let index: Int
    let seat: PoolSeat
    let teams: Bool
    let onColour: () -> Void
    let onMove: () -> Void
    let onLevel: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let c = seat.player.color
        let place = ["1st", "2nd", "3rd", "4th"][min(index, 3)]
        let order = teams ? "Shoots \(place) · \(PoolStore.teamNames[index % 2])" : "Shoots \(place)"
        HStack(spacing: 10) {
            ZStack {
                ZStack {
                    Circle().fill(LinearGradient(colors: [lerp(c, Color.White, Float(0.15)), lerp(c, Color.Black, Float(0.25))], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(Color.white, lineWidth: 2.5)
                    Text(verbatim: seat.player.avatar).font(.system(size: 19))
                }
                .frame(width: 40, height: 40)
                .background(Circle().fill(c).composeShadow(6, color: c))
            }
            .frame(width: 48, height: 48)
            .pressable(sound: nil, pressedScale: 0.9, onClick: onColour)
            .accessibilityLabel("\(seat.player.name)'s colour. Change")
            VStack(alignment: .leading, spacing: 0) {
                Text(seat.player.name, style: bodyStyle(16, .Bold)).lineLimit(1).truncationMode(.tail)
                Text(order, style: bodyStyle(11, .Bold, Royal.Smoke))
                    .padding(.vertical, 4)
                    .pressable(sound: nil, pressedScale: 0.95, onClick: onMove)
                    .accessibilityLabel("\(order). Move later in the order")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if seat.isBot {
                Text(seat.difficulty.title, style: bodyStyle(12, .ExtraBold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(Royal.Glass))
                    .overlay(Capsule().strokeBorder(Royal.Stroke, lineWidth: 1))
                    .clipShape(Capsule())
                    .pressable(sound: nil, pressedScale: 0.92, onClick: onLevel)
                    .accessibilityLabel("Computer level \(seat.difficulty.title). Change")
                PoolTag(icon: Icons.Rounded.Memory, text: "CPU", color: Royal.Smoke)
            } else {
                Icon(Icons.Rounded.Edit, tint: Royal.Smoke, size: 16)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Royal.Glass))
                    .clipShape(Circle())
                    .pressable(sound: nil, pressedScale: 0.9) {
                        PoolSound.play(PoolSound.tap)
                        onEdit()
                    }
                    .accessibilityLabel("Edit \(seat.player.name)")
                PoolTag(icon: Icons.Rounded.Person, text: "Person", color: Royal.Emerald)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private struct PoolTag: View {
    let icon: ImageVector
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Icon(icon, tint: color, size: 13)
            Text(text, style: bodyStyle(11, .ExtraBold, color))
        }
    }
}

private struct PoolTableTile: View {
    let item: PoolTableTheme
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        VStack(spacing: 4) {
            PoolTablePlate(item, .BAR, true)
                .aspectRatio(CGFloat((99.0 + 28) / (198.0 + 28)), contentMode: .fit)
                .padding(5)
                .frame(maxWidth: .infinity)
                .frame(height: 114)
                .background(shape.fill(LinearGradient(colors: item.backdrop.map { $0.color }, startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(selected ? Royal.Gold : Royal.Stroke, lineWidth: selected ? 3 : 1))
                .clipShape(shape)
            Text(item.name, style: bodyStyle(10, .ExtraBold, selected ? Royal.Ivory : Royal.Smoke)).lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .pressable(sound: nil, pressedScale: 0.95) {
            PoolSound.play(PoolSound.tap)
            onClick()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name) table")
    }
}

private struct PoolCueTile: View {
    let style: PoolCueStyle
    let selected: Bool
    let onClick: () -> Void
    @Environment(\.displayScale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        let style = style
        let scale = scale
        VStack(spacing: 6) {
            Canvas { ctx, s in
                PoolCueSprites.drawCue(ctx, CGPoint(x: 6, y: s.height / 2), CGPoint(x: -1, y: 0), s.width - 12, 7, style, scale: scale)
            }
            .frame(width: 150, height: 24)
            Text(style.name, style: bodyStyle(11, .ExtraBold, selected ? Royal.Ivory : Royal.Smoke)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(shape.fill(Royal.panelBrush))
        .overlay(shape.strokeBorder(selected ? Royal.Gold : Royal.Stroke, lineWidth: selected ? 2.5 : 1))
        .clipShape(shape)
        .pressable(sound: nil, pressedScale: 0.95) {
            PoolSound.play(PoolSound.chalk)
            onClick()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.name) cue")
    }
}

private struct PoolRulesPanel: View {
    let setup: PoolStore.Setup
    let game: PoolVariant
    let onChange: (PoolStore.Setup) -> Void

    private func set(_ options: PoolOptions) {
        var s = setup
        s.options = options
        onChange(s)
    }

    var body: some View {
        let o = setup.options
        RoyalPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                PoolRuleLabel("Match")
                RoyalSegmented(PoolMatchLength.allCases, o.length, { var x = o; x.length = $0; set(x) }, { $0.title })
                PoolRuleLabel("Table size")
                RoyalSegmented(PoolTableSize.allCases, o.tableSize, { var x = o; x.tableSize = $0; set(x) }, { $0.title })
                if game == .EIGHT {
                    PoolRuleLabel("Call the 8-ball pocket")
                    RoyalSegmented([true, false], o.callEight, { var x = o; x.callEight = $0; set(x) }, { $0 ? "On" : "Off" })
                }
                PoolRuleLabel("Ball in hand after a break scratch")
                RoyalSegmented([true, false], o.kitchenAfterScratch, { var x = o; x.kitchenAfterScratch = $0; set(x) }, { $0 ? "Behind the line" : "Anywhere" })
                PoolRuleLabel("Aim guide")
                RoyalSegmented(PoolAimGuide.allCases, o.aimGuide, { var x = o; x.aimGuide = $0; set(x) }, { $0.title })
                Text(guideText(o.aimGuide), style: bodyStyle(12, .SemiBold, Royal.Smoke)).fixedSize(horizontal: false, vertical: true)
                PoolRuleLabel("Shot clock")
                RoyalSegmented([0, 30, 60], o.shotClock, { var x = o; x.shotClock = $0; set(x) }, { $0 == 0 ? "Off" : "\($0) s" })
                VStack(spacing: 0) {
                    PoolSwitchRow(icon: Icons.Rounded.EmojiEvents, color: poolHex(0xE8952F).color, title: "Winner breaks",
                                  subtitle: "Off: the break alternates each rack", value: o.winnerBreaks) { v in var x = o; x.winnerBreaks = v; set(x) }
                    if game == .NINE {
                        Rectangle().fill(Royal.Stroke).frame(height: 1)
                        PoolSwitchRow(icon: Icons.Rounded.Warning, color: poolHex(0xE0115F).color, title: "Three fouls lose the rack",
                                      subtitle: nil, value: o.threeFouls) { v in var x = o; x.threeFouls = v; set(x) }
                    }
                    Rectangle().fill(Royal.Stroke).frame(height: 1)
                    PoolSwitchRow(icon: Icons.Rounded.Speed, color: poolHex(0x8E5BE8).color, title: "Fast computers",
                                  subtitle: nil, value: o.fastBots) { v in var x = o; x.fastBots = v; set(x) }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(Color.black.opacity(0.2)))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .circular))
                HStack(spacing: 6) {
                    Icon(Icons.Rounded.Schedule, tint: Royal.Gold, size: 16)
                    Text("About \(PoolStore.estimatedMinutes(setup.seats, setup.peopleCount, o)) min", style: bodyStyle(13, .ExtraBold))
                }
            }
        }
    }

    private func guideText(_ g: PoolAimGuide) -> String {
        switch g {
        case .FULL: return "Ghost ball, the object ball's line and the cue ball's path."
        case .SHORT: return "Just the line to the ghost ball."
        case .OFF: return "No guide: the cue shows the line."
        }
    }
}

private struct PoolRuleLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text, style: bodyStyle(12, .ExtraBold, Royal.Smoke)) }
}

private struct PoolSwitchRow: View {
    let icon: ImageVector
    let color: Color
    let title: String
    let subtitle: String?
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, tint: Color.white, size: 17)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .circular).fill(color))
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(title, style: bodyStyle(15, .Bold))
                if let subtitle { Text(subtitle, style: bodyStyle(11, .SemiBold, Royal.Smoke)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoyalSwitch(value, onChange, label: title)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56)
    }
}

/// A table on end with the rack and cue ball, for setup and the hub.
struct PoolTablePreview: View {
    let theme: PoolTableTheme
    var game: PoolVariant = .EIGHT
    var size: PoolTableSize = .BAR
    @Environment(\.displayScale) private var scale

    init(_ theme: PoolTableTheme, _ game: PoolVariant = .EIGHT, _ size: PoolTableSize = .BAR) {
        self.theme = theme
        self.game = game
        self.size = size
    }

    var body: some View {
        let t = PoolTableGeometry.of(size)
        let ratio = CGFloat((t.width + 2 * PoolTableMap.RAIL) / (t.length + 2 * PoolTableMap.RAIL))
        let balls = game == .EIGHT ? PoolRack.eight(t, 7) : PoolRack.nine(t, 7)
        let scale = scale
        // One composited layer for the table and the racked balls (the balls are many small paths).
        ZStack {
            PoolTablePlate(theme, size, true)
            Canvas { ctx, s in
                let m = PoolTableMap(s, true, t)
                for ball in balls {
                    PoolArt.drawBall(ctx, m.pt(ball.p), m.len(PoolTableGeometry.R), ball.n, PoolQuat.start(ball.n), true, false, 0, scale: scale)
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// The hub card's illustration: a tilted table, a cue lined up and the 8.
struct PoolArtwork: View {
    @State private var start = Date()
    @Environment(\.displayScale) private var scale

    var body: some View {
        let reduce = LocalReduceMotion.current
        let scale = scale
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                PoolTablePreview(PoolTableTheme.theme(0))
                    .background(RoundedRectangle(cornerRadius: size * 0.024, style: .circular).fill(Color.black).composeShadow(10))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .rotation3DEffect(.degrees(22), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .offset(y: size * 0.04)
                TimelineView(.animation(minimumInterval: nil, paused: reduce)) { tl in
                    let bob = reduce ? 0 : PoolArtwork.bob(tl.date.timeIntervalSince(start))
                    Canvas { ctx, s in
                        PoolCueSprites.drawCue(ctx, CGPoint(x: s.width * 0.58, y: s.height * 0.7), CGPoint(x: -0.6, y: -0.8),
                                               s.width * 0.8, s.width * 0.035, PoolCueStyle.style(4), scale: scale)
                    }
                    .frame(width: size, height: size)
                    .offset(y: -4 * CGFloat(bob))
                }
                .frame(width: size, height: size)
                PoolMiniBall(8, size * 0.24)
                    .background(Circle().fill(Color.black).composeShadow(6))
                    .offset(x: size * 0.3, y: -size * 0.28)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    /// Compose `infiniteRepeatable(tween(1300, FastOutSlowInEasing), RepeatMode.Reverse)` from 0 to 1.
    private static func bob(_ t: Double) -> Double {
        let cycle = t.truncatingRemainder(dividingBy: 2.6)
        let x = cycle < 1.3 ? cycle / 1.3 : 2 - cycle / 1.3
        return Easing.FastOutSlowIn.transform(x)
    }
}
