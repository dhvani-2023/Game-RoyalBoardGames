import SwiftUI
import GameKit

// MARK: - Avatar

/// Player disc: seat-colour gradient, white rim, emoji avatar, pulsing ring when it's their turn.
struct AvatarBadge: View {
    let avatar: String
    let color: Color
    var size: CGFloat = 44
    var isActive: Bool = false

    init(_ player: PartyPlayer, size: CGFloat = 44, isActive: Bool = false) {
        self.init(player.avatar, player.color, size: size, isActive: isActive)
    }

    init(_ avatar: String, _ color: Color, size: CGFloat = 44, isActive: Bool = false) {
        self.avatar = avatar
        self.color = color
        self.size = size
        self.isActive = isActive
    }

    var body: some View {
        ZStack {
            if isActive { PulseRing(color).frame(width: size, height: size) }
            ZStack {
                Circle().fill(LinearGradient(colors: [lerp(color, Color.White, Float(0.15)), lerp(color, Color.Black, Float(0.25))],
                                             startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Color.white, lineWidth: max(2, size * 0.06))
                Text(verbatim: avatar).font(.system(size: size * 0.5))
            }
            .frame(width: size, height: size)
            .background(Circle().fill(color).composeShadow(isActive ? 12 : 5, color: color))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Turn banner

/// "It's Raj's turn" card. Slides to the next player whenever `turnId` changes.
struct TurnBanner: View {
    let player: PartyPlayer
    let headline: String
    let message: String?
    let turnId: Int

    init(_ player: PartyPlayer, _ headline: String, _ message: String?, _ turnId: Int) {
        self.player = player
        self.headline = headline
        self.message = message
        self.turnId = turnId
    }

    init(player: PartyPlayer, headline: String, message: String?, turnId: Int) {
        self.init(player, headline, message, turnId)
    }

    private struct Key: Hashable { let player: PartyPlayer; let headline: String; let turnId: Int }

    var body: some View {
        let key = Key(player: player, headline: headline, turnId: turnId)
        ZStack {
            TurnBannerCard(player: player, title: headline, message: message)
                .id(key)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .animation(.compose(dampingRatio: 1, stiffness: 400), value: key)
    }
}

private struct TurnBannerCard: View {
    let player: PartyPlayer
    let title: String
    let message: String?

    var body: some View {
        let shape = RoundedCornerShape(24)
        HStack(spacing: 0) {
            AvatarBadge(player, size: 50, isActive: true)
            Spacer().frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(title, style: displayStyle(20)).lineLimit(1).truncationMode(.tail)
                if let message { Text(message, style: bodyStyle(13, .SemiBold, Royal.Smoke)).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(ZStack { Royal.panelBrush; player.color.copy(alpha: 0.14) })
        .clipShape(shape)
        .overlay(shape.strokeBorder(player.color.copy(alpha: 0.7), lineWidth: 2))
        .background(shape.fill(Royal.Panel).composeShadow(14, color: player.color))
    }
}

// MARK: - Pass the device

/// Hides the board until the next player confirms they're holding the device.
struct PassDeviceOverlay: View {
    let player: PartyPlayer
    let detail: String
    let onReady: () -> Void
    @State private var appear: CGFloat = 0

    init(_ player: PartyPlayer, _ detail: String, _ onReady: @escaping () -> Void) {
        self.player = player
        self.detail = detail
        self.onReady = onReady
    }

    init(player: PartyPlayer, detail: String, onReady: @escaping () -> Void) {
        self.init(player, detail, onReady)
    }

    var body: some View {
        let c = player.color
        ZStack {
            ZStack {
                Royal.Night.copy(alpha: 0.97)
                LinearGradient(colors: [c.copy(alpha: 0.35), .clear], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {}
            VStack(spacing: 18) {
                AvatarBadge(player, size: 104, isActive: true)
                Text("Pass to \(player.name)", style: displayStyle(30, Royal.Ivory, .Center)).multilineTextAlignment(.center)
                Text(detail, style: bodyStyle(15, .SemiBold, Royal.Smoke, .Center)).multilineTextAlignment(.center)
                CandyButton("I'm Ready", onReady,
                            colors: [lerp(c, Color.White, Float(0.25)), c, lerp(c, Color.Black, Float(0.25))],
                            textColor: .white)
                    .frame(maxWidth: 320)
            }
            .padding(32)
            .opacity(Double(appear))
            .scaleEffect(0.6 + 0.4 * appear)
        }
        .onAppear { withAnimation(.compose(dampingRatio: 0.7, stiffness: 300)) { appear = 1 } }
    }
}

// MARK: - Results

struct PartyStanding: Hashable {
    let player: PartyPlayer
    let detail: String

    init(_ player: PartyPlayer, _ detail: String) {
        self.player = player
        self.detail = detail
    }

    init(player: PartyPlayer, detail: String) {
        self.init(player, detail)
    }
}

/// End-of-match card: winner (or draw) with crown and confetti, standings, rematch and exits.
struct PartyResultOverlay: View {
    let title: String
    let subtitle: String
    let winner: PartyPlayer?
    let standings: [PartyStanding]
    let accent: [Color]
    let primaryTitle: String
    let onPrimary: () -> Void
    let onHub: () -> Void
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil
    var winnerIsBot: Bool = false

    @State private var appear: CGFloat = 0
    @State private var crown: CGFloat = 0.2
    @State private var rowsIn = false

    init(title: String, subtitle: String, winner: PartyPlayer?, standings: [PartyStanding], accent: [Color],
         primaryTitle: String, onPrimary: @escaping () -> Void, onHub: @escaping () -> Void,
         secondaryTitle: String? = nil, onSecondary: (() -> Void)? = nil, winnerIsBot: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.winner = winner
        self.standings = standings
        self.accent = accent
        self.primaryTitle = primaryTitle
        self.onPrimary = onPrimary
        self.onHub = onHub
        self.secondaryTitle = secondaryTitle
        self.onSecondary = onSecondary
        self.winnerIsBot = winnerIsBot
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55 * Double(appear))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            if winner != nil { Confetti(count: 170).ignoresSafeArea() }
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    card
                        .padding(.vertical, 30)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height)
                }
            }
        }
        .onAppear {
            UiSound.play(winner != nil && !winnerIsBot ? .Fanfare : (winner == nil ? .Draw : .Lose))
            Haptics.play(.Success)
            withAnimation(.compose(dampingRatio: 0.75, stiffness: 260)) { appear = 1 }
            withAnimation(.compose(dampingRatio: 0.45, stiffness: 1500).delay(0.3)) { crown = 1 }
            rowsIn = true
        }
    }

    private var card: some View {
        WoodPanel(padding: 22) {
            VStack(spacing: 0) {
                ZStack {
                    if let winner {
                        RotatingRays().frame(width: 220, height: 220)
                        AvatarBadge(winner, size: 100)
                        Icon(Icons.Rounded.EmojiEvents, tint: Royal.Gold, size: 44)
                            .scaleEffect(crown)
                            .offset(y: -62)
                    } else {
                        Icon(Icons.Rounded.Handshake, tint: accent.first ?? Royal.Gold, size: 92)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                Text(title, style: displayStyle(30, Royal.Gold, .Center)).multilineTextAlignment(.center)
                Spacer().frame(height: 6)
                Text(subtitle, style: bodyStyle(15, .SemiBold, Royal.Smoke, .Center)).multilineTextAlignment(.center)
                if !standings.isEmpty {
                    Spacer().frame(height: 18)
                    ForEach(Array(standings.enumerated()), id: \.offset) { index, s in
                        StandingRow(index: index, standing: s, hasWinner: winner != nil, show: rowsIn)
                    }
                }
                Spacer().frame(height: 20)
                CandyButton(primaryTitle, onPrimary, icon: Icons.Rounded.Replay)
                Spacer().frame(height: 10)
                HStack(spacing: 10) {
                    if let secondaryTitle, let onSecondary {
                        OutlineButton(secondaryTitle, onSecondary, icon: Icons.Rounded.Tune, fill: true)
                    }
                    OutlineButton("Home", onHub, icon: Icons.Rounded.GridView, fill: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .opacity(Double(appear))
        .scaleEffect(0.85 + 0.15 * appear)
    }
}

private struct StandingRow: View {
    let index: Int
    let standing: PartyStanding
    let hasWinner: Bool
    let show: Bool
    @State private var rowIn: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: medal(index, hasWinner)).font(.system(size: 20)).frame(width: 30, alignment: .leading)
            AvatarBadge(standing.player, size: 34)
            Spacer().frame(width: 12)
            Text(standing.player.name, style: bodyStyle(16, .ExtraBold)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(standing.detail, style: bodyStyle(13, .Bold, Royal.Smoke))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedCornerShape(16).fill(index == 0 && hasWinner ? Royal.Gold.copy(alpha: 0.16) : Color.white.opacity(0.06)))
        .opacity(Double(rowIn))
        .offset(y: (1 - rowIn) * 40 / 3)
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(.compose(dampingRatio: 0.8, stiffness: 1500).delay(0.25 + Double(index) * 0.07)) { rowIn = 1 }
        }
    }

    private func medal(_ index: Int, _ hasWinner: Bool) -> String {
        if !hasWinner { return "🤝" }
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(index + 1)."
        }
    }
}

// MARK: - Player editor

/// Edit a seat: name, avatar and (optionally) colour. Shown over the setup screen; place it in a full-screen `ZStack`.
/// `takenColors` are dimmed so two seats never share a colour.
struct PlayerEditDialog: View {
    let player: PartyPlayer?
    let onDismiss: () -> Void
    let onSave: (PartyPlayer) -> Void
    var showColors: Bool = true
    var takenColors: Set<Int> = []

    init(_ player: PartyPlayer?, onDismiss: @escaping () -> Void, onSave: @escaping (PartyPlayer) -> Void,
         showColors: Bool = true, takenColors: Set<Int> = []) {
        self.player = player
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.showColors = showColors
        self.takenColors = takenColors
    }

    init(player: PartyPlayer?, onDismiss: @escaping () -> Void, onSave: @escaping (PartyPlayer) -> Void,
         showColors: Bool = true, takenColors: Set<Int> = []) {
        self.init(player, onDismiss: onDismiss, onSave: onSave, showColors: showColors, takenColors: takenColors)
    }

    var body: some View {
        ZStack {
            if let start = player {
                PlayerEditCard(start: start, onDismiss: onDismiss, onSave: onSave, showColors: showColors, takenColors: takenColors)
                    .id(start.id)
                    .transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.15), value: player?.id)
    }
}

private struct PlayerEditCard: View {
    let start: PartyPlayer
    let onDismiss: () -> Void
    let onSave: (PartyPlayer) -> Void
    let showColors: Bool
    let takenColors: Set<Int>
    @State private var name: String
    @State private var avatar: String
    @State private var color: Int
    @FocusState private var focused: Bool

    init(start: PartyPlayer, onDismiss: @escaping () -> Void, onSave: @escaping (PartyPlayer) -> Void, showColors: Bool, takenColors: Set<Int>) {
        self.start = start
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.showColors = showColors
        self.takenColors = takenColors
        _name = State(initialValue: start.name)
        _avatar = State(initialValue: start.avatar)
        _color = State(initialValue: start.colorIndex)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
            WoodPanel(padding: 20) {
                VStack(spacing: 0) {
                    AvatarBadge(avatar, PartyStyle.color(color), size: 76, isActive: true)
                    Spacer().frame(height: 14)
                    let shape = RoundedCornerShape(16)
                    TextField("", text: $name)
                        .font(RoyalFonts.body(20, .ExtraBold))
                        .foregroundStyle(Royal.Ivory)
                        .multilineTextAlignment(.center)
                        .tint(Royal.Gold)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit { focused = false }
                        .onChange(of: name) { _, v in if v.count > 16 { name = String(v.prefix(16)) } }
                        .padding(14)
                        .background(shape.fill(Color.black.opacity(0.35)))
                        .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1.5))
                    Spacer().frame(height: 16)
                    SectionLabel("Avatar").frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(height: 8)
                    RoyalFlowRow(spacing: 8, lineSpacing: 8, maxItemsInEachRow: 8) {
                        ForEach(PartyStyle.avatars, id: \.self) { a in
                            let on = a == avatar
                            Text(verbatim: a).font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(on ? Royal.Gold.copy(alpha: 0.3) : Color.white.opacity(0.06)))
                                .overlay(Circle().strokeBorder(on ? Royal.Gold : .clear, lineWidth: on ? 2 : 0))
                                .clipShape(Circle())
                                .pressable(sound: .Tap, haptic: .Tick) { avatar = a }
                        }
                    }
                    if showColors {
                        Spacer().frame(height: 16)
                        SectionLabel("Colour").frame(maxWidth: .infinity, alignment: .leading)
                        Spacer().frame(height: 8)
                        HStack(spacing: 10) {
                            ForEach(0..<PartyStyle.tokenColors.count, id: \.self) { i in
                                let on = i == color
                                let taken = takenColors.contains(i) && i != start.colorIndex
                                Circle().fill(PartyStyle.tokenColors[i])
                                    .overlay(Circle().strokeBorder(Color.white, lineWidth: on ? 3 : 0))
                                    .frame(width: 36, height: 36)
                                    .opacity(taken ? 0.3 : 1)
                                    .pressable(enabled: !taken, sound: .Tap) { color = i }
                            }
                        }
                    }
                    Spacer().frame(height: 20)
                    CandyButton("Save", {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(start.copy(name: trimmed.isEmpty ? start.name : trimmed, avatar: avatar, colorIndex: color))
                    }, height: 52, fontSize: 20)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = false }
            .frame(maxWidth: 440)
            .padding(24)
        }
    }
}

// MARK: - In-game quick settings

/// Sound / music / haptics toggles, opened from a game's top bar. Place it in a full-screen `ZStack`.
struct QuickSettingsOverlay: View {
    let visible: Bool
    let onDismiss: () -> Void
    /// Extras: one more button above Done (Chess: Copy PGN).
    var extra: QuickSettingsAction? = nil

    init(_ visible: Bool, _ onDismiss: @escaping () -> Void, extra: QuickSettingsAction? = nil) {
        self.visible = visible
        self.onDismiss = onDismiss
        self.extra = extra
    }

    init(visible: Bool, onDismiss: @escaping () -> Void) {
        self.init(visible, onDismiss)
    }

    var body: some View {
        ZStack {
            if visible {
                QuickSettingsCard(onDismiss: onDismiss, extra: extra).transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.15), value: visible)
    }
}

private struct QuickSettingsCard: View {
    let onDismiss: () -> Void
    var extra: QuickSettingsAction? = nil

    var body: some View {
        let s = AppSettings.data
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
            WoodPanel(padding: 18) {
                Text("Table Settings", style: displayStyle(24, Royal.Gold, .Center))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer().frame(height: 12)
                QuickToggle(icon: Icons.AutoMirrored.Rounded.VolumeUp, title: "Sound effects", value: s.soundEnabled) { v in AppSettings.update { $0.copy(soundEnabled: v) } }
                QuickToggle(icon: Icons.Rounded.MusicNote, title: "Music", value: s.musicEnabled) { v in AppSettings.update { $0.copy(musicEnabled: v) } }
                QuickToggle(icon: Icons.Rounded.Vibration, title: "Haptics", value: s.hapticsEnabled) { v in AppSettings.update { $0.copy(hapticsEnabled: v) } }
                Spacer().frame(height: 14)
                if let extra {
                    OutlineButton(extra.title, extra.action, icon: extra.icon, fill: true)
                    Spacer().frame(height: 10)
                }
                OutlineButton("Done", onDismiss, fill: true)
            }
            .contentShape(Rectangle())
            .onTapGesture {}
            .frame(maxWidth: 400)
            .padding(28)
        }
    }
}

private struct QuickToggle: View {
    let icon: ImageVector
    let title: String
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, tint: Royal.Gold, size: 22)
            Spacer().frame(width: 12)
            Text(title, style: bodyStyle(16, .Bold)).frame(maxWidth: .infinity, alignment: .leading)
            RoyalSwitch(value, onChange, label: title)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Flow layout

/// Compose `FlowRow(horizontalArrangement = spacedBy(spacing, alignment), verticalArrangement = spacedBy(lineSpacing), maxItemsInEachRow)`.
struct RoyalFlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var maxItemsInEachRow: Int = .max
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(bounds.width, subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var cur = Row()
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let needed = cur.indices.isEmpty ? s.width : cur.width + spacing + s.width
            if !cur.indices.isEmpty && (needed > maxWidth + 0.5 || cur.indices.count >= maxItemsInEachRow) {
                rows.append(cur)
                cur = Row()
            }
            cur.width = cur.indices.isEmpty ? s.width : cur.width + spacing + s.width
            cur.height = max(cur.height, s.height)
            cur.indices.append(i)
        }
        if !cur.indices.isEmpty { rows.append(cur) }
        return rows
    }
}
