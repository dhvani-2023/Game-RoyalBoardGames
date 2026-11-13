import SwiftUI
import GameKit

private func toCarrom(_ level: BotLevel) -> CarromDifficulty {
    switch level {
    case .EASY: return .EASY
    case .NORMAL: return .NORMAL
    case .HARD: return .HARD
    }
}

extension View {
    /// A tap inside the Carrom screens: Carrom's own tap sound plus a light tick.
    func carromTap(enabled: Bool = true, scale: CGFloat = 0.95, onClick: @escaping () -> Void) -> some View {
        pressable(enabled: enabled, sound: nil, haptic: .Tick, pressedScale: scale) {
            CarromSound.play(.Tap)
            onClick()
        }
    }
}

/// Before a Carrom match: mode, seats, people, who sits where, the board, coins and striker, and the rules.
struct CarromSetupScreen: View {
    let onBack: () -> Void
    let onStart: (CarromConfig) -> Void
    let onResume: (CarromConfig) -> Void

    @State private var setup: CarromStore.Setup
    @State private var seats: [CarromSeat]
    @State private var editing: Int? = nil
    @State private var saved: CarromStore.SavedMatch?

    init(onBack: @escaping () -> Void, onStart: @escaping (CarromConfig) -> Void, onResume: @escaping (CarromConfig) -> Void) {
        self.onBack = onBack
        self.onStart = onStart
        self.onResume = onResume
        var s = CarromStore.setup
        if !CarromStore.hasSetup() { s.difficulties = [CarromDifficulty](repeating: toCarrom(BotLevel.default), count: 3) }
        _setup = State(initialValue: s)
        _seats = State(initialValue: buildSeats(s, []))
        _saved = State(initialValue: CarromStore.saved)
    }

    private var mode: CarromMode { setup.seats == 3 ? .FREESTYLE : setup.options.mode }
    private var teams: Bool { setup.seats == 4 && (mode != .FREESTYLE || setup.options.freestyleTeams) }

    private func rebuild() {
        seats = buildSeats(setup, seats)
    }

    private func setSeats(_ count: Int) {
        setup.seats = count
        setup.peopleCount = Swift.min(setup.peopleCount, count)
        CarromSound.play(.Tap)
        rebuild()
    }

    private func setPeople(_ count: Int) {
        setup.peopleCount = count
        CarromSound.play(.Tap)
        rebuild()
    }

    private func cycleColor(_ index: Int) {
        let current = seats[index].player.colorIndex
        let next = (current + 1) % PartyStyle.tokenColors.count
        seats = seats.enumerated().map { i, seat in
            var s = seat
            if i == index {
                s.player = seat.player.copy(colorIndex: next)
            } else if seat.player.colorIndex == next {
                s.player = seat.player.copy(colorIndex: current)
            }
            return s
        }
    }

    /// Swaps this seat's side with the next seat's, round the table.
    private func cycleSide(_ index: Int) {
        if seats.count <= 1 { return }
        let other = (index + 1) % seats.count
        let a = seats[index].side
        let b = seats[other].side
        seats[index].side = b
        seats[other].side = a
    }

    private func cycleDifficulty(_ index: Int) {
        let all = CarromDifficulty.allCases
        let next = all[(all.firstIndex(of: seats[index].difficulty)! + 1) % all.count]
        seats[index].difficulty = next
        let b = seats.prefix(index).filter { $0.isBot }.count
        if b < setup.difficulties.count { setup.difficulties[b] = next }
    }

    private func practice() {
        guard let seat = seats.first(where: { !$0.isBot }) ?? seats.first else { return }
        CarromSound.play(.Turn)
        var options = setup.options
        options.mode = mode
        onStart(CarromPractice.config(seat, options, setup.boardID, setup.coinsID, setup.strikerID))
    }

    private func start() {
        let people = seats.filter { !$0.isBot }
        setup.players = people.map { $0.player }
        CarromStore.setup = setup
        PartyStore.remember(people.map { $0.player }, GameKind.CARROM)
        CarromStore.saved = nil
        CarromSound.play(.Turn)
        var options = setup.options
        options.mode = mode
        onStart(CarromConfig(seats.sorted { $0.side < $1.side }, options, setup.boardID, setup.coinsID, setup.strikerID))
    }

    var body: some View {
        let theme = CarromBoardTheme.theme(setup.boardID)
        let coins = CarromCoinSet.set(setup.coinsID)
        let striker = CarromStrikerStyle.style(setup.strikerID)
        let mode = self.mode
        let teams = self.teams
        ZStack {
            RoyalBackground(glow: theme.backdrop[0].color, secondGlow: Royal.Amethyst) {
                VStack(spacing: 0) {
                    RoyalTopBar("Carrom", onBack, subtitle: "Set the table")
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            Spacer().frame(height: 2)
                            SetupHeader(setup: setup, mode: mode, theme: theme, coins: coins, striker: striker).springIn(0)
                            if let saved { ResumeCard(saved: saved) { onResume(saved.config) }.springIn(40) }
                            CarromSetupSection("Mode") {
                                HStack(alignment: .top, spacing: 8) {
                                    ForEach(CarromMode.allCases, id: \.self) { item in
                                        ModeCard(item: item, selected: item == mode, disabled: setup.seats == 3 && item != .FREESTYLE, coins: coins) {
                                            setup.options.mode = item
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .springIn(80)
                            CarromSetupSection("Seats") {
                                RoyalSegmented([2, 3, 4], setup.seats, setSeats, { "\($0)" })
                                Text(seatsText(setup.seats, teams), style: bodyStyle(12, .SemiBold, Royal.Smoke))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .springIn(120)
                            CarromSetupSection("People playing") {
                                RoyalSegmented(Array(1...setup.seats), Swift.min(setup.peopleCount, setup.seats), setPeople, { "\($0)" })
                            }
                            .springIn(160)
                            RoyalPanel(padding: 4) {
                                ForEach(Array(seats.enumerated()), id: \.element.id) { index, seat in
                                    if index > 0 {
                                        Rectangle().fill(Royal.Stroke).frame(height: 1).padding(.horizontal, 12)
                                    }
                                    SeatRow(
                                        seat: seat, side: sideText(seat, teams, mode, setup.seats),
                                        onColor: { CarromSound.play(.Tap); cycleColor(index) },
                                        onSide: { CarromSound.play(.Tap); cycleSide(index) },
                                        onDifficulty: { CarromSound.play(.Tap); cycleDifficulty(index) },
                                        onEdit: { editing = index }
                                    )
                                }
                            }
                            .animation(.compose(dampingRatio: 1, stiffness: 1500), value: seats.count)
                            .springIn(200)
                            CarromSetupSection("Board") { BoardGrid(setup: $setup) }.springIn(240)
                            CarromSetupSection("Coins") { CoinPicker(setup: $setup) }.springIn(280)
                            CarromSetupSection("Striker") { StrikerPicker(setup: $setup) }.springIn(320)
                            CarromSetupSection("Rules") { RulesPanel(setup: $setup, mode: mode) }.springIn(360)
                            Spacer().frame(height: 12)
                        }
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                    }
                    ZStack {
                        HStack(spacing: 10) {
                            // Extras: a practice board for the first person, keeping any saved match.
                            if ExtrasFeatures.practiceTable { ExtrasPracticeButton(practice) }
                            CandyButton("Start game", start, icon: Icons.Rounded.PlayArrow)
                        }
                            .frame(maxWidth: 640)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.clear, Royal.Night.copy(alpha: 0.9)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
                }
            }
            let editIndex = editing
            PlayerEditDialog(
                editIndex.flatMap { seats.indices.contains($0) ? seats[$0].player : nil },
                onDismiss: { editing = nil },
                onSave: { player in
                    if let i = editing, seats.indices.contains(i) { seats[i].player = player.copy(name: String(player.name.prefix(14))) }
                    editing = nil
                },
                showColors: true,
                takenColors: Set(seats.enumerated().filter { $0.offset != editIndex }.map { $0.element.player.colorIndex })
            )
        }
    }
}

private func seatsText(_ seats: Int, _ teams: Bool) -> String {
    switch seats {
    case 3: return "Three seats play Freestyle, everyone for themselves."
    case 4: return teams ? "Four seats play as two teams: partners sit opposite." : "Four seats, everyone for themselves."
    default: return "One against one, sitting opposite."
    }
}

/// Lays out the seats: people first (keeping their names), then computers, round the board.
@MainActor
private func buildSeats(_ s: CarromStore.Setup, _ current: [CarromSeat]) -> [CarromSeat] {
    let people = Swift.min(s.peopleCount, s.seats)
    var known = current.filter { !$0.isBot }.map { $0.player }
    if known.isEmpty { known += s.players }
    if known.isEmpty {
        let trimmed = AppSettings.data.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        known.append(PartyPlayer(name: String((trimmed.isEmpty ? "Player 1" : trimmed).prefix(16)), avatar: AppSettings.data.avatar, colorIndex: 0))
    }
    for extra in PartyStore.players(GameKind.CARROM) ?? [] where !known.contains(where: { $0.id == extra.id }) { known.append(extra) }
    while known.count < people {
        let used = Set(known.map { $0.avatar })
        let avatar = PartyStyle.avatars.first { !used.contains($0) } ?? "🙂"
        known.append(PartyPlayer(name: "Player \(known.count + 1)", avatar: avatar, colorIndex: known.count))
    }
    let sides = CarromSeat.sides(s.seats)
    var usedColours = Set<Int>()
    var result: [CarromSeat] = []
    for i in 0..<s.seats {
        if i < people {
            var player = known[i]
            if usedColours.contains(player.colorIndex) {
                player = player.copy(colorIndex: (0..<6).first { !usedColours.contains($0) } ?? i)
            }
            usedColours.insert(player.colorIndex)
            result.append(CarromSeat(player, sides[i], isBot: false))
        } else {
            let b = i - people
            let colour = (0..<6).first { !usedColours.contains($0) } ?? i
            usedColours.insert(colour)
            let player = PartyPlayer(
                name: CarromStore.botNames[b % CarromStore.botNames.count],
                avatar: CarromStore.botAvatars[b % CarromStore.botAvatars.count],
                colorIndex: colour
            )
            result.append(CarromSeat(player, sides[i], isBot: true, difficulty: s.difficulties[Swift.min(b, s.difficulties.count - 1)]))
        }
    }
    return result
}

private func sideText(_ seat: CarromSeat, _ teams: Bool, _ mode: CarromMode, _ seatCount: Int) -> String {
    let side = ["Bottom", "Right", "Top", "Left"][seat.side]
    if teams { return "\(side) · \(CarromStore.teamNames[seat.side % 2])" }
    if mode != .FREESTYLE && seatCount == 2 { return "\(side) · \(seat.side == 0 ? "white" : "black")" }
    return side
}

private struct CarromSetupSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compose `Brush.radialGradient(colors)`: centred, radius half the smaller side.
private struct CarromRadialFill: View {
    let colors: [CarromColor]

    var body: some View {
        GeometryReader { geo in
            RadialGradient(colors: colors.map(\.color), center: .center, startRadius: 0, endRadius: Swift.min(geo.size.width, geo.size.height) / 2)
        }
    }
}

private struct SetupHeader: View {
    let setup: CarromStore.Setup
    let mode: CarromMode
    let theme: CarromBoardTheme
    let coins: CarromCoinSet
    let striker: CarromStrikerStyle

    var body: some View {
        let people = Swift.min(setup.peopleCount, setup.seats)
        let bots = setup.seats - people
        let who = people == 1 ? "You" : "\(people) people"
        let summary = bots == 0 ? "\(who), pass and play." : "\(who) and \(bots) computer\(bots == 1 ? "" : "s")."
        HStack(spacing: 14) {
            CarromBoardPreview(theme: theme, coins: coins, striker: striker)
                .padding(6)
                .frame(width: 130, height: 130)
                .background(CarromRadialFill(colors: theme.backdrop))
                .clipShape(RoundedCornerShape(24))
                .background(RoundedCornerShape(24).fill(Royal.Night).composeShadow(12))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(setup.seats) PLAYERS · \(mode.title.uppercased())", style: bodyStyle(11, .Black, Royal.Gold).copy(letterSpacing: 1.2))
                Text("Set the table", style: displayStyle(26))
                Text(summary, style: bodyStyle(13, .SemiBold, Royal.Smoke))
                HStack(spacing: 0) {
                    Icon(Icons.Rounded.AirplanemodeActive, nil, tint: Royal.Smoke, size: 13)
                    Spacer().frame(width: 4)
                    Text("Works offline · same device", style: bodyStyle(11, .ExtraBold, Royal.Smoke))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ResumeCard: View {
    let saved: CarromStore.SavedMatch
    let onResume: () -> Void

    var body: some View {
        let seat = saved.config.seats[Swift.min(saved.match.table.turn, saved.config.seats.count - 1)]
        RoyalPanel(padding: 12) {
            HStack(spacing: 0) {
                Icon(Icons.Rounded.PlayCircle, nil, tint: Royal.Gold, size: 30)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Game in progress", style: bodyStyle(16, .ExtraBold))
                    Text("\(saved.match.mode.title) · \(seat.player.name) to shoot", style: bodyStyle(12, .SemiBold, Royal.Smoke))
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

private struct ModeCard: View {
    let item: CarromMode
    let selected: Bool
    let disabled: Bool
    let coins: CarromCoinSet
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedCornerShape(16)
        let icons: [CarromKind]
        switch item {
        case .CLASSIC: icons = [.WHITE, .BLACK, .QUEEN]
        case .POOL: icons = [.WHITE, .BLACK]
        case .FREESTYLE: icons = [.WHITE, .QUEEN]
        }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: -4) { ForEach(icons, id: \.self) { CarromCoinIcon(kind: $0, set: coins, size: 22) } }
            Text(item.title, style: bodyStyle(14, .Black, Royal.Ivory)).lineLimit(1).truncationMode(.tail)
            Text(item.blurb, style: bodyStyle(10.5, .SemiBold, Royal.Smoke)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(selected ? Royal.Gold.copy(alpha: 0.16) : Royal.Glass)
        .clipShape(shape)
        .overlay(shape.strokeBorder(selected ? Royal.Gold : Royal.Stroke, lineWidth: selected ? 2.5 : 1))
        .opacity(disabled ? 0.4 : 1)
        .carromTap(enabled: !disabled, scale: 0.96, onClick: onClick)
        .accessibilityLabel("\(item.title): \(item.blurb)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SeatRow: View {
    let seat: CarromSeat
    let side: String
    let onColor: () -> Void
    let onSide: () -> Void
    let onDifficulty: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let c = CarromColor.player(seat.player)
        HStack(spacing: 10) {
            ZStack {
                ZStack {
                    Circle().fill(LinearGradient(colors: [c.mix(.white, 0.18).color, c.color], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(Color.White, lineWidth: 2.5)
                    Text(seat.player.avatar).font(.system(size: 19))
                }
                .frame(width: 40, height: 40)
                .background(Circle().fill(c.color).composeShadow(5, color: c.color))
            }
            .frame(width: 48, height: 48)
            .carromTap(scale: 0.9, onClick: onColor)
            .accessibilityLabel("\(seat.player.name)'s colour. Change")
            VStack(alignment: .leading, spacing: 0) {
                Text(seat.player.name, style: bodyStyle(16, .Bold)).lineLimit(1).truncationMode(.tail)
                Text(side, style: bodyStyle(11, .Bold, Royal.Smoke))
                    .padding(.vertical, 4)
                    .frame(minHeight: 24)
                    .carromTap(scale: 0.97, onClick: onSide)
                    .accessibilityLabel("\(side). Swap seats")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if seat.isBot {
                Text(seat.difficulty.title, style: bodyStyle(12, .ExtraBold, Royal.Ivory))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 34)
                    .background(Capsule().fill(Royal.Glass))
                    .overlay(Capsule().strokeBorder(Royal.Stroke, lineWidth: 1))
                    .clipShape(Capsule())
                    .carromTap(scale: 0.92, onClick: onDifficulty)
                    .accessibilityLabel("Computer level \(seat.difficulty.title). Change")
                CarromTag(icon: Icons.Rounded.Memory, text: "CPU", tint: Royal.Smoke)
            } else {
                ZStack {
                    Circle().fill(Royal.Glass)
                    Icon(Icons.Rounded.Edit, nil, tint: Royal.Smoke, size: 16)
                }
                .frame(width: 40, height: 40)
                .carromTap(scale: 0.9, onClick: onEdit)
                .accessibilityLabel("Edit \(seat.player.name)")
                CarromTag(icon: Icons.Rounded.Person, text: "Person", tint: Royal.Emerald)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private struct CarromTag: View {
    let icon: ImageVector
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, nil, tint: tint, size: 13)
            Spacer().frame(width: 3)
            Text(text, style: bodyStyle(11, .ExtraBold, tint))
        }
    }
}

private struct BoardGrid: View {
    @Binding var setup: CarromStore.Setup

    var body: some View {
        let rows = stride(from: 0, to: CarromBoardTheme.all.count, by: 4).map { Array(CarromBoardTheme.all[$0..<Swift.min($0 + 4, CarromBoardTheme.all.count)]) }
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rows[r], id: \.id) { item in
                        let selected = item.id == setup.boardID
                        let shape = RoundedCornerShape(14)
                        VStack(spacing: 4) {
                            CarromBoardPlate(theme: item)
                                .padding(5)
                                .aspectRatio(1, contentMode: .fit)
                                .background(CarromRadialFill(colors: item.backdrop))
                                .clipShape(shape)
                                .overlay(shape.strokeBorder(selected ? Royal.Gold : Color.clear, lineWidth: 3))
                            Text(item.name, style: bodyStyle(10, .ExtraBold, selected ? Royal.Ivory : Royal.Smoke))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity)
                        .carromTap {
                            if setup.customLooks {
                                setup.boardID = item.id
                            } else {
                                setup.boardID = item.id
                                setup.coinsID = item.coins
                                setup.strikerID = item.striker
                            }
                        }
                        .accessibilityLabel("\(item.name) board")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct PickerCard<Content: View>: View {
    let selected: Bool
    let label: String
    let onClick: () -> Void
    let content: Content

    init(_ selected: Bool, _ label: String, _ onClick: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.label = label
        self.onClick = onClick
        self.content = content()
    }

    var body: some View {
        let shape = RoundedCornerShape(16)
        VStack(spacing: 6) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Royal.Glass)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? Royal.Gold : Royal.Stroke, lineWidth: selected ? 2.5 : 1))
            .carromTap(onClick: onClick)
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CoinPicker: View {
    @Binding var setup: CarromStore.Setup

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CarromCoinSet.all, id: \.id) { set in
                    let selected = set.id == setup.coinsID
                    PickerCard(selected, "\(set.name) coins", { setup.coinsID = set.id; setup.customLooks = true }) {
                        HStack(spacing: -5) {
                            CarromCoinIcon(kind: .WHITE, set: set, size: 30)
                            CarromCoinIcon(kind: .BLACK, set: set, size: 30)
                            CarromCoinIcon(kind: .QUEEN, set: set, size: 30)
                        }
                        Text(set.name, style: bodyStyle(11, .ExtraBold, selected ? Royal.Ivory : Royal.Smoke)).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct StrikerPicker: View {
    @Binding var setup: CarromStore.Setup

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CarromStrikerStyle.all, id: \.id) { style in
                    let selected = style.id == setup.strikerID
                    PickerCard(selected, "\(style.name) striker", { setup.strikerID = style.id; setup.customLooks = true }) {
                        CarromStrikerIcon(style: style, size: 46, radius: 17)
                        Text(style.name, style: bodyStyle(11, .ExtraBold, selected ? Royal.Ivory : Royal.Smoke)).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// A striker at [radius], centred in a [size] box (the sprite's shadow may spill over).
struct CarromStrikerIcon: View {
    let style: CarromStrikerStyle
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            CarromSpriteImage(piece: .striker(style.id), radius: radius).frame(width: 0, height: 0)
        }
        .frame(width: size, height: size)
    }
}

private struct RulesPanel: View {
    @Binding var setup: CarromStore.Setup
    let mode: CarromMode

    var body: some View {
        let o = setup.options
        RoyalPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                label("Match")
                let lengths: [CarromMatchLength] = mode == .FREESTYLE ? [.ONE, .BEST_OF_THREE] : CarromMatchLength.allCases
                let length: CarromMatchLength = (mode == .FREESTYLE && o.length == .RACE25) ? .BEST_OF_THREE : o.length
                RoyalSegmented(lengths, length, { setup.options.length = $0 }, { $0.title })
                if mode == .CLASSIC {
                    label("Queen rule")
                    RoyalSegmented([false, true], o.tournament, { setup.options.tournament = $0 }, { $0 ? "Tournament" : "Friendly" })
                    Text(o.tournament ? "Tournament: clear your colour before the Queen and you lose the board. 15 s shot clock."
                         : "Friendly: if your last coin drops before the Queen is covered, it comes back.",
                         style: bodyStyle(12, .SemiBold, Royal.Smoke))
                        .fixedSize(horizontal: false, vertical: true)
                }
                label("Aim guide")
                RoyalSegmented(CarromAimGuide.allCases, o.aimGuide, { setup.options.aimGuide = $0 }, { $0.title })
                if !o.tournament {
                    label("Shot clock")
                    RoyalSegmented([0, 15, 30], o.shotClock, { setup.options.shotClock = $0 }, { $0 == 0 ? "Off" : "\($0) s" })
                }
                VStack(spacing: 0) {
                    ToggleRow(icon: Icons.Rounded.Sync, color: CarromColor(0xE8952F).color, title: "Turn the board to each shooter",
                              subtitle: "Off: table mode for a phone lying flat", value: o.turnBoard) { setup.options.turnBoard = $0 }
                    if setup.seats == 4 && mode == .FREESTYLE {
                        RuleDivider()
                        ToggleRow(icon: Icons.Rounded.Groups, color: CarromColor(0x2E8BEF).color, title: "Play as two teams", subtitle: nil,
                                  value: o.freestyleTeams) { setup.options.freestyleTeams = $0 }
                    }
                    RuleDivider()
                    ToggleRow(icon: Icons.Rounded.Speed, color: CarromColor(0x8E5BE8).color, title: "Fast computers", subtitle: nil,
                              value: o.fastBots) { setup.options.fastBots = $0 }
                }
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedCornerShape(16))
                HStack(spacing: 0) {
                    Icon(Icons.Rounded.Schedule, nil, tint: Royal.Gold, size: 16)
                    Spacer().frame(width: 6)
                    Text("About \(CarromStore.estimatedMinutes(setup.seats, setup.peopleCount, o)) min", style: bodyStyle(13, .ExtraBold, Royal.Ivory))
                }
            }
        }
        .animation(.compose(dampingRatio: 0.85, stiffness: 1500), value: mode)
        .animation(.compose(dampingRatio: 0.85, stiffness: 1500), value: o.tournament)
    }

    private func label(_ text: String) -> some View { Text(text, style: bodyStyle(12, .ExtraBold, Royal.Smoke)) }
}

private struct RuleDivider: View {
    var body: some View {
        Rectangle().fill(Royal.Stroke).frame(height: 1).padding(.leading, 56)
    }
}

private struct ToggleRow: View {
    let icon: ImageVector
    let color: Color
    let title: String
    let subtitle: String?
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedCornerShape(9).fill(color)
                Icon(icon, nil, tint: Color.White, size: 18)
            }
            .frame(width: 32, height: 32)
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(title, style: bodyStyle(14, .Bold))
                if let subtitle { Text(subtitle, style: bodyStyle(11, .SemiBold, Royal.Smoke)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoyalSwitch(value, onChange, label: title)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56)
    }
}

// MARK: - Previews and the hub artwork

/// A board with the rack on it, for setup and the hub, rendered once per look and size.
@MainActor
enum CarromPreviews {
    private static var cache: [String: CGImage] = [:]

    static func key(_ theme: CarromBoardTheme, _ coins: CarromCoinSet, _ striker: CarromStrikerStyle, _ side: CGFloat, _ scale: CGFloat) -> String {
        "p\(theme.id)-\(coins.id)-\(striker.id)-\(Int((side * scale).rounded()))"
    }

    static func cached(_ key: String) -> CGImage? { cache[key] }

    static func preview(_ theme: CarromBoardTheme, _ coins: CarromCoinSet, _ striker: CarromStrikerStyle, _ side: CGFloat, _ scale: CGFloat) -> CGImage? {
        let k = key(theme, coins, striker, side, scale)
        if let hit = cache[k] { return hit }
        let image = CarromRaster.image(width: side, height: side, scale: scale) { c, size in
            let m = CarromMetrics(size.width, size.height)
            CarromArt.drawBoard(c, m, theme)
            let rc = m.len(CarromBoard.coinR)
            let rs = m.len(CarromBoard.strikerR)
            for disc in CarromBoard.rack(true) {
                let p = m.pt(disc.p)
                CarromArt.drawCoin(c, p.x, p.y, rc, disc.kind, coins, 1)
            }
            let s = m.pt(CarromBoard.strikerSpot(0, -0.3))
            CarromArt.drawStriker(c, s.x, s.y, rs, striker, 1)
        }
        if let image {
            if cache.count > 24 { cache.removeAll() }
            cache[k] = image
        }
        return image
    }
}

struct CarromBoardPreview: View {
    let theme: CarromBoardTheme
    let coins: CarromCoinSet
    let striker: CarromStrikerStyle

    @Environment(\.displayScale) private var scale
    @State private var rendered = 0

    var body: some View {
        GeometryReader { geo in
            let side = Swift.min(geo.size.width, geo.size.height)
            let key = CarromPreviews.key(theme, coins, striker, side, scale)
            let _ = rendered
            ZStack {
                if side >= 1, let image = CarromPreviews.cached(key) {
                    Image(decorative: image, scale: scale).resizable().frame(width: side, height: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: key) {
                if side >= 1 && CarromPreviews.cached(key) == nil {
                    _ = CarromPreviews.preview(theme, coins, striker, side, scale)
                    rendered += 1
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The hub card's illustration: a tilted board, a few coins and the striker.
struct CarromArtwork: View {
    var body: some View {
        GeometryReader { geo in
            let size = Swift.min(geo.size.width, geo.size.height)
            ZStack {
                CarromBoardPreview(theme: CarromBoardTheme.theme(0), coins: CarromCoinSet.set(0), striker: CarromStrikerStyle.style(0))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .background(RoundedCornerShape(size * 0.9 * 0.063).fill(Color.black).composeShadow(10))
                    .rotation3DEffect(.degrees(24), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .offset(y: size * 0.05)
                Bobbing(amplitude: 2.5, periodMs: 1300) { bob in
                    CarromStrikerIcon(style: CarromStrikerStyle.style(6), size: size, radius: size * 0.12)
                        .offset(x: size * 0.3, y: size * 0.28 + (LocalReduceMotion.current ? 0 : bob - 2.5))
                }
            }
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
