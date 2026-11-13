import SwiftUI
import GameKit

/// The Ludo table: seat panels with their dice above and below the board, the board itself,
/// banners, the pause sheet and the results podium.
struct LudoScreen: View {
    let config: LudoConfig
    let onQuit: () -> Void
    let onReplace: (LudoConfig) -> Void
    let onNewSetup: () -> Void
    let onHub: () -> Void

    @State private var session: LudoSession
    @State private var showPause = false
    @State private var prompt: RoyalPrompt? = nil
    @State private var recorded = false
    @Environment(\.scenePhase) private var scenePhase

    private let theme: LudoTheme
    private let geometry: LudoGeometry

    init(config: LudoConfig, onQuit: @escaping () -> Void, onReplace: @escaping (LudoConfig) -> Void,
         onNewSetup: @escaping () -> Void, onHub: @escaping () -> Void) {
        self.config = config
        self.onQuit = onQuit
        self.onReplace = onReplace
        self.onNewSetup = onNewSetup
        self.onHub = onHub
        _session = State(wrappedValue: LudoSession(config, LocalReduceMotion.current))
        theme = LudoTheme.theme(config.themeID)
        geometry = LudoGeometry(config.arms)
    }

    private func quit() {
        session.save()
        showPause = false
        onQuit()
    }

    private func openPause() {
        session.paused = true
        showPause = true
    }

    private func closePause() {
        showPause = false
        session.paused = false
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.backdrop.map(\.color), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            DiceDotPattern().ignoresSafeArea()
            LudoAmbientLayer(theme: theme).ignoresSafeArea()

            VStack(spacing: 10) {
                LudoTopBar(config: config, theme: theme, onPause: openPause)
                LudoSeatPanels(session: session, theme: theme, geometry: geometry, top: true)
                LudoBoardArea(session: session, theme: theme, geometry: geometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                LudoSeatPanels(session: session, theme: theme, geometry: geometry, top: false)
                LudoHint(session: session)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)

            // Centred on the whole screen, like the Compose Box it sits in.
            LudoBannerHost(banner: session.banner, theme: theme, arms: config.arms)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if session.phase == .OVER {
                LudoResults(session: session, theme: theme,
                            onRematch: { onReplace(config.copy(resume: false)) },
                            onSetup: onNewSetup,
                            onHub: onHub)
                    .transition(.opacity.animation(.tween(350)))
                    .zIndex(2)
            }

            LudoPauseSheet(
                visible: showPause,
                rules: config.rules,
                onResume: closePause,
                onRestart: {
                    prompt = RoyalPrompt(
                        title: "Restart this game?",
                        message: "Every token goes back to its yard.",
                        confirmTitle: "Restart",
                        cancelTitle: "Keep playing",
                        icon: Icons.Rounded.Replay,
                        destructive: true,
                        onConfirm: {
                            showPause = false
                            session.abandon()
                            onReplace(config.copy(resume: false))
                        }
                    )
                },
                onQuit: quit
            )
            .zIndex(3)

            RoyalDialogHost(prompt) {
                prompt = nil
                if !showPause { session.paused = false }
            }
            .zIndex(4)
        }
        .onAppear {
            session.reduceMotion = LocalReduceMotion.current
            session.start()
        }
        .onDisappear {
            session.save()
            session.dispose()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.save() }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .OVER && !recorded {
                recorded = true
                session.record()
            }
        }
    }
}

// MARK: - Top bar

private struct LudoTopBar: View {
    let config: LudoConfig
    let theme: LudoTheme
    let onPause: () -> Void

    var body: some View {
        let sound = AppSettings.data.soundEnabled
        HStack(spacing: 0) {
            RoundIconButton(Icons.Rounded.Pause, onPause, size: 44, contentDescription: "Pause")
            VStack(spacing: 0) {
                Text("Ludo", style: displayStyle(24, .White))
                    .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 1)
                Text("\(theme.name.uppercased()) · \(config.seats.count) PLAYERS\(config.rules.quick ? " · QUICK" : "")",
                     style: bodyStyle(10, .Black, Color.White.copy(alpha: 0.75)).copy(letterSpacing: 1))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            RoundIconButton(
                sound ? Icons.AutoMirrored.Rounded.VolumeUp : Icons.AutoMirrored.Rounded.VolumeOff,
                { AppSettings.update { $0.copy(soundEnabled: !$0.soundEnabled) } },
                size: 44,
                contentDescription: sound ? "Mute sound" : "Turn sound on"
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Panels

private func ludoRotatedYard(_ geometry: LudoGeometry, _ shift: Int, _ arm: Int) -> LVec {
    let t = LudoTransform(geometry, shift, 2.0, 2.0)
    let c = geometry.yardCenter(arm)
    return t.rotate(LVec(c.x, c.y))
}

/// Seats whose yards are in the top half of the (turned) board sit above it, the rest below.
private func ludoSeatsFor(_ config: LudoConfig, _ geometry: LudoGeometry, _ top: Bool) -> [Int] {
    config.seats.indices
        .filter { (ludoRotatedYard(geometry, config.shift, config.seats[$0].arm).dy < 0) == top }
        .enumerated()
        .sorted {
            let a = ludoRotatedYard(geometry, config.shift, config.seats[$0.element].arm).dx
            let b = ludoRotatedYard(geometry, config.shift, config.seats[$1.element].arm).dx
            return a != b ? a < b : $0.offset < $1.offset
        }
        .map(\.element)
}

private struct LudoSeatPanels: View {
    let session: LudoSession
    let theme: LudoTheme
    let geometry: LudoGeometry
    let top: Bool

    var body: some View {
        let config = session.config
        let list = ludoSeatsFor(config, geometry, top)
        let engine = session.engine
        let phase = session.phase
        HStack(spacing: 8) {
            ForEach(list, id: \.self) { index in
                let right = ludoRotatedYard(geometry, config.shift, config.seats[index].arm).dx > 0.5
                if list.count == 1 && right { Spacer(minLength: 0) }
                let current = index == engine.current
                LudoSeatPanel(
                    seat: config.seats[index],
                    color: theme.color(config.seats[index].arm, config.arms),
                    isActive: current && phase != .OVER,
                    canRoll: current && phase == .ROLL && !config.seats[index].isBot,
                    rolling: current && phase == .ROLLING,
                    dice: session.diceValue,
                    landTick: session.landTick,
                    extraTick: session.extraTick,
                    rank: engine.ranks.firstIndex(of: index).map { $0 + 1 },
                    home: engine.tokensHome(index),
                    tokens: config.rules.tokens,
                    recent: engine.stats[index].recent,
                    compact: list.count > 2,
                    mirrored: right,
                    onRoll: { session.rollTapped() }
                )
                .frame(maxWidth: list.count > 1 ? .infinity : nil)
                .frame(width: list.count > 1 ? nil : 220)
                if list.count == 1 && !right { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
    }
}

/// One seat's panel: avatar, name, dice pad, roll history and finish crown.
private struct LudoSeatPanel: View {
    let seat: LudoSeat
    let color: LudoColor
    let isActive: Bool
    let canRoll: Bool
    let rolling: Bool
    let dice: Int
    let landTick: Int
    let extraTick: Int
    let rank: Int?
    let home: Int
    let tokens: Int
    let recent: [Int]
    let compact: Bool
    let mirrored: Bool
    let onRoll: () -> Void

    var body: some View {
        let shape = RoundedCornerShape(18)
        let glow: CGFloat = isActive ? 1 : 0
        let description = "\(seat.player.name)\(seat.isBot ? ", computer" : ""), \(home) of \(tokens) home\(rank.map { ", finished \($0)" } ?? "")"
        HStack(spacing: compact ? 4 : 8) {
            if mirrored { pad }
            if compact {
                VStack(spacing: 2) {
                    LudoSeatAvatar(seat: seat, color: color, rank: rank, size: 36)
                    Text(seat.player.name, style: bodyStyle(11, .Black, .White)).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
            } else {
                LudoSeatAvatar(seat: seat, color: color, rank: rank, size: 44)
                VStack(alignment: mirrored ? .trailing : .leading, spacing: 2) {
                    Text(seat.player.name, style: bodyStyle(14, .Black, .White)).lineLimit(1).truncationMode(.tail)
                    let status = rank != nil ? "Finished" : (isActive ? (seat.isBot ? "Playing" : "Your turn") : (seat.isBot ? seat.difficulty.title : "\(home)/\(tokens) home"))
                    Text(status, style: bodyStyle(10, .Bold, Color.White.copy(alpha: 0.72))).lineLimit(1)
                    LudoRollHistory(recent: recent)
                }
                .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)
            }
            if !mirrored { pad }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, compact ? 6 : 8)
        .background {
            ZStack {
                shape.fill(Color.White.copy(alpha: 0.08 + 0.12 * Double(glow)))
                shape.fill(LinearGradient(colors: [Royal.Night.copy(alpha: 0.25), Royal.Night.copy(alpha: 0.45)], startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(isActive ? color.color : Color.White.copy(alpha: 0.15), lineWidth: isActive ? 2.5 : 1))
        .background(shape.stroke(color.color, lineWidth: 5).blur(radius: 7).offset(y: 3).opacity(0.75 * Double(glow)))
        .animation(.compose(dampingRatio: 0.7, stiffness: 500), value: isActive)
        .opacity(isActive || rank != nil ? 1 : 0.78)
        .animation(.compose(dampingRatio: 1, stiffness: 600), value: isActive || rank != nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(description)
    }

    private var pad: some View {
        LudoDicePad(color: color, isActive: isActive, canRoll: canRoll, rolling: rolling, dice: dice, landTick: landTick,
                extraTick: extraTick, recent: recent, compact: compact, onRoll: onRoll)
    }
}

private struct LudoSeatAvatar: View {
    let seat: LudoSeat
    let color: LudoColor
    let rank: Int?
    let size: CGFloat

    var body: some View {
        ZStack {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.mix(.White, 0.15).color, color.mix(.Black, 0.2).color], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Color.White, lineWidth: 2.5)
                Text(seat.player.avatar).font(.system(size: size * 0.5))
            }
            .frame(width: size, height: size)
            if seat.isBot {
                Text("CPU", style: bodyStyle(7, .Black, .White))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(ludoHex(0x1C1B29).color))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 6)
            }
            ZStack {
                if let rank {
                    ZStack {
                        LudoCrownIcon()
                            .frame(width: size * 0.46, height: size * 0.46)
                        Text("\(rank)", style: bodyStyle(size * 0.2, .Black, ludoHex(0x5A3A00).color))
                            .offset(y: size * 0.04)
                    }
                    .transition(.scale.combined(with: .opacity).animation(.compose(dampingRatio: 0.45, stiffness: 1500)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(y: -size * 0.42)
        }
        .frame(width: size, height: size)
    }
}

/// A gold crown, drawn so it needs no icon font.
struct LudoCrownIcon: View {
    var color: LudoColor = ludoHex(0xFFC94A)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.08, y: h * 0.3))
            path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.14))
            path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.3))
            path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.84))
            path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.84))
            path.closeSubpath()
            // drawBlurred(path, hex(0xFFB020).copy(alpha = 0.8), w * 0.12): BlurMaskFilter radius → Gaussian sigma.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.57735 * w * 0.12 + 0.17))
                layer.fill(path, with: .color(ludoHex(0xFFB020).copy(alpha: 0.8).color))
            }
            ctx.fill(path, with: .linearGradient(Gradient(colors: [color.mix(.White, 0.3).color, color.color, color.mix(.Black, 0.15).color]),
                                                 startPoint: CGPoint(x: 0, y: h * 0.14), endPoint: CGPoint(x: 0, y: h * 0.84)))
            ctx.stroke(path, with: .color(Color.White.copy(alpha: 0.5)), lineWidth: w * 0.04)
            for x in [0.08, 0.5, 0.92] as [CGFloat] {
                let c = CGPoint(x: w * x, y: h * (x == 0.5 ? 0.14 : 0.3))
                let r = w * 0.07
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color.mix(.White, 0.2).color))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LudoRollHistory: View {
    let recent: [Int]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(recent.suffix(5).enumerated()), id: \.offset) { _, value in
                Text("\(value)", style: bodyStyle(8, .Black, value == 6 ? ludoHex(0x5A3A00).color : .White))
                    .frame(width: 13, height: 13)
                    .background(RoundedCornerShape(3).fill(value == 6 ? ludoHex(0xFFC94A).color : Color.White.copy(alpha: 0.18)))
            }
        }
    }
}

private struct LudoDicePad: View {
    let color: LudoColor
    let isActive: Bool
    let canRoll: Bool
    let rolling: Bool
    let dice: Int
    let landTick: Int
    let extraTick: Int
    let recent: [Int]
    let compact: Bool
    let onRoll: () -> Void

    var body: some View {
        let side: CGFloat = compact ? 42 : 50
        let shape = RoundedCornerShape(12)
        ZStack {
            shape.fill(Color.White.copy(alpha: isActive ? 0.16 : 0.06))
            if isActive {
                LudoDie(value: dice, rolling: rolling, landTick: landTick, pip: color.mix(.Black, 0.35), size: compact ? 34 : 40)
                    .scaleEffect(canRoll ? 1.04 : 1)
                    .animation(.compose(dampingRatio: 0.4, stiffness: 400), value: canRoll)
            } else {
                LudoGhostDie(value: recent.last ?? 1, color: Color.White.copy(alpha: 0.25))
            }
            if canRoll { LudoTapRing(color: color.color) }
            LudoExtraRollBadge(tick: extraTick, active: isActive)
        }
        .frame(width: side, height: side)
        .pressable(enabled: canRoll, sound: nil, pressedScale: 0.9, onClick: onRoll)
        .accessibilityLabel(canRoll ? "Roll the dice" : "Dice")
    }
}

/// "+1 roll" popping up over the dice pad after a capture or reaching home.
private struct LudoExtraRollBadge: View {
    let tick: Int
    /// Only the seat that earned the bonus shows it (Android keys this on a per-seat tick that also jumps when a seat
    /// becomes current, which flashed the badge at turn changes).
    let active: Bool

    @State private var started: Date? = nil

    var body: some View {
        ZStack {
            if let started {
                TimelineView(.animation) { timeline in
                    // tween(900, LinearEasing)
                    let p = CGFloat(min(1, max(0, timeline.date.timeIntervalSince(started) / 0.9)))
                    let s: CGFloat = p < 0.15 ? 0.6 + p / 0.15 * 0.4 : 1
                    Text("+1 roll", style: bodyStyle(11, .Black, ludoHex(0x5A3A00).color))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ludoHex(0xFFC94A).color))
                        .fixedSize()
                        .scaleEffect(s)
                        .opacity(Double(p < 0.7 ? 1 : (1 - p) / 0.3))
                        .offset(y: -30 - 16 * p)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: tick) { _, t in
            if !active || t == 0 { return }
            let now = Date()
            started = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) { if started == now { started = nil } }
        }
    }
}

/// A breathing ring inviting a tap.
private struct LudoTapRing: View {
    let color: Color

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            // infiniteRepeatable(tween(1000, easing = 1 - (1 - t)²))
            let t = max(0, timeline.date.timeIntervalSince(start)).truncatingRemainder(dividingBy: 1.0)
            let on = CGFloat(1 - (1 - t) * (1 - t))
            RoundedCornerShape(14)
                .inset(by: 1.5)
                .stroke(color, lineWidth: 3)
                .scaleEffect(1 + 0.18 * on)
                .opacity(Double(0.9 * (1 - on)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Board

private struct LudoBoardArea: View {
    let session: LudoSession
    let theme: LudoTheme
    let geometry: LudoGeometry

    @State private var downAt: CGPoint? = nil
    @State private var hold: Task<Void, Never>? = nil

    var body: some View {
        let config = session.config
        let reduce = LocalReduceMotion.current
        let armsInPlay = Set(config.seats.map { $0.arm })
        let description: String = {
            switch session.phase {
            case .CHOOSE: return "\(session.currentSeat.player.name) rolled \(session.diceValue). \(session.legal.count) moves possible."
            case .OVER: return "Game over"
            default: return "\(session.currentSeat.player.name)'s turn"
            }
        }()
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LudoBoardPlate(geometry: geometry, theme: theme, shift: config.shift, armsInPlay: armsInPlay)
                LudoActiveYardGlow(geometry: geometry, shift: config.shift, arm: session.currentSeat.arm, theme: theme,
                                   armsInPlay: armsInPlay, visible: session.phase != .OVER)
                LudoTokenLayer(session: session, theme: theme)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(boardGesture(side))
            .keyframeAnimator(initialValue: 0.0, trigger: session.captureTick) { content, x in
                content.offset(x: reduce ? 0 : x)
            } keyframes: { _ in
                let ease = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1))
                LinearKeyframe(7.0, duration: 0.045, timingCurve: ease)
                LinearKeyframe(-6.0, duration: 0.045, timingCurve: ease)
                LinearKeyframe(4.0, duration: 0.045, timingCurve: ease)
                LinearKeyframe(-3.0, duration: 0.045, timingCurve: ease)
                LinearKeyframe(1.5, duration: 0.045, timingCurve: ease)
                LinearKeyframe(0.0, duration: 0.045, timingCurve: ease)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(description)
            .accessibilityAddTraits(.allowsDirectInteraction)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func hitMove(_ location: CGPoint, _ side: CGFloat) -> LudoMove? {
        if session.phase != .CHOOSE || session.isBotTurn || side <= 0 { return nil }
        let config = session.config
        let t = LudoTransform(geometry, config.shift, Double(side), Double(side))
        let p = t.board(LPoint(Double(location.x), Double(location.y)))
        let points = ludoRestingPoints(session.engine, config)
        let seat = session.engine.current
        var best: LudoMove? = nil
        var bestDistance = Double.greatestFiniteMagnitude
        for token in session.engine.steps[seat].indices {
            guard let move = session.move(seat, token), let point = points[LudoTokenRef(seat, token)]?.0 else { continue }
            let d = hypot(point.x - p.x, point.y - p.y)
            if d < 1.05 && d < bestDistance {
                best = move
                bestDistance = d
            }
        }
        return best
    }

    private func boardGesture(_ side: CGFloat) -> some Gesture {
        let slop: CGFloat = 20
        let cancel: CGFloat = 30
        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if downAt == nil {
                    let start = v.startLocation
                    downAt = start
                    hold?.cancel()
                    // Holding a token for a moment previews where it would go.
                    hold = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        if Task.isCancelled { return }
                        if let m = hitMove(start, side) {
                            session.preview = m
                            LudoSound.play(.Tap)
                            Haptics.play(.Tick)
                        }
                    }
                }
                let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
                if moved > cancel && session.preview != nil { session.preview = nil }
            }
            .onEnded { v in
                hold?.cancel()
                hold = nil
                let start = downAt ?? v.startLocation
                downAt = nil
                let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
                if let previewed = session.preview {
                    session.preview = nil
                    session.tapToken(previewed.seat, previewed.token)
                } else if moved < slop {
                    if session.phase == .ROLL {
                        session.rollTapped()
                    } else if let m = hitMove(start, side) {
                        session.tapToken(m.seat, m.token)
                    }
                }
            }
    }
}

/// A pulsing outline around the yard of the seat to play.
private struct LudoActiveYardGlow: View {
    let geometry: LudoGeometry
    let shift: Int
    let arm: Int
    let theme: LudoTheme
    let armsInPlay: Set<Int>
    let visible: Bool

    @Environment(\.displayScale) private var scale
    @State private var start = Date()
    @State private var shown: (key: String, image: CGImage)? = nil

    var body: some View {
        let reduce = LocalReduceMotion.current
        GeometryReader { proxy in
            let size = proxy.size
            let key = LudoYardGlow.key(geometry, shift, arm, theme.color(arm, geometry.arms), size, scale)
            let img = LudoImageCache.shared.cached(key) ?? (shown?.key == key ? shown?.image : nil)
            ZStack {
                if let img {
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduce || !visible)) { timeline in
                        // infiniteRepeatable(tween(800), Reverse) between 0.45 and 1.
                        let phase = (max(0, timeline.date.timeIntervalSince(start)) / 0.8).truncatingRemainder(dividingBy: 2)
                        let u = phase < 1 ? phase : 2 - phase
                        let pulse = 0.45 + 0.55 * ludoEase(0.4, 0, 0.2, 1, u)
                        let r = LudoYardGlow.rect(geometry, shift, arm, size)
                        Image(decorative: img, scale: scale)
                            .resizable()
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .opacity(reduce ? 1 : pulse)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .task(id: key) {
                guard size.width >= 1, size.height >= 1 else { return }
                let (g, shift, scale, theme) = (geometry, shift, scale, theme)
                // This seat's glow first, then every other seat's, so later turns never wait.
                for a in [arm] + armsInPlay.sorted() where a == arm || LudoImageCache.shared.cached(LudoYardGlow.key(g, shift, a, theme.color(a, g.arms), size, scale)) == nil {
                    let color = theme.color(a, g.arms)
                    let img = await LudoImageCache.shared.render(LudoYardGlow.key(g, shift, a, color, size, scale)) {
                        LudoYardGlow.draw(g, shift, a, color, size, scale)
                    }
                    if a == arm, let img { shown = (key, img) }
                }
            }
        }
        .opacity(visible ? 1 : 0)
        .animation(.tween(300), value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Hint

private struct LudoHint: View {
    let session: LudoSession

    var body: some View {
        let seat = session.currentSeat
        let config = session.config
        let text: String = {
            switch session.phase {
            case .ROLL:
                let waiting = session.engine.steps[session.engine.current].allSatisfy { $0 < 0 }
                if seat.isBot { return "\(seat.player.name) is rolling…" }
                if waiting { return "\(seat.player.name), roll a \(config.rules.oneOrSix ? "1 or 6" : "6") to bring a token out" }
                return "\(seat.player.name), tap the dice to roll"
            case .ROLLING:
                return "Rolling…"
            case .CHOOSE:
                if seat.isBot { return "\(seat.player.name) is thinking…" }
                if session.diceValue == 6 && session.legal.contains(where: { $0.comesOut }) { return "A 6! Bring a token out or move one. Hold to preview." }
                return "Move a glowing token \(session.diceValue). Hold to preview."
            case .MOVING, .OVER:
                return " "
            }
        }()
        Text(text, style: bodyStyle(13, .Bold, Color.White.copy(alpha: 0.9), .Center))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
    }
}

// MARK: - Banner

private struct LudoBannerHost: View {
    let banner: LudoBanner?
    let theme: LudoTheme
    let arms: Int

    var body: some View {
        ZStack {
            if let banner {
                LudoBannerView(banner: banner, theme: theme, arms: arms)
                    .id(banner.id)
                    .transition(.asymmetric(
                        insertion: AnyTransition.scale(scale: 0.6).combined(with: .opacity).animation(.compose(dampingRatio: 0.55, stiffness: 1500)),
                        removal: AnyTransition.scale(scale: 0.6).combined(with: .opacity).animation(.compose(dampingRatio: 1, stiffness: 400))
                    ))
            }
        }
        .animation(.compose(dampingRatio: 0.55, stiffness: 1500), value: banner?.id)
    }
}

/// "Captured!", "Home!", "Three 6s!" and other moments, popping over the board.
private struct LudoBannerView: View {
    let banner: LudoBanner
    let theme: LudoTheme
    let arms: Int

    var body: some View {
        let tint = banner.arm.map { theme.color($0, arms) } ?? ludoHex(0xFFB020)
        let icon: ImageVector = {
            switch banner.icon {
            case .STOP: return Icons.Rounded.Block
            case .HAND: return Icons.Rounded.PanTool
            case .BOLT: return Icons.Rounded.Bolt
            case .HOUSE: return Icons.Rounded.Home
            }
        }()
        HStack(spacing: 0) {
            Icon(icon, tint: .White, size: 26)
            Spacer().frame(width: 8)
            Text(banner.text, style: displayStyle(26, .White))
                .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 1.5)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Capsule().fill(LinearGradient(colors: [tint.mix(.White, 0.15).color, tint.mix(.Black, 0.2).color], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(Color.White.copy(alpha: 0.6), lineWidth: 2))
        .background(Capsule().fill(tint.color).composeShadow(16, color: tint.color))
        .rotationEffect(.degrees(-4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(banner.text)
    }
}

// MARK: - Pause

/// Pause: resume, the rules in short, restart or save and quit.
private struct LudoPauseSheet: View {
    let visible: Bool
    let rules: LudoRules
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            if visible {
                LudoPauseCard(rules: rules, onResume: onResume, onRestart: onRestart, onQuit: onQuit)
                    .transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.16), value: visible)
    }

    private struct LudoPauseCard: View {
        let rules: LudoRules
        let onResume: () -> Void
        let onRestart: () -> Void
        let onQuit: () -> Void

        @State private var scale: CGFloat = 0.85

        var body: some View {
            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onResume() }
                WoodPanel(padding: 20) {
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
            VStack(alignment: .leading, spacing: 0) {
                Text("Paused", style: displayStyle(30, Royal.Gold))
                Spacer().frame(height: 12)
                SectionLabel("Rules")
                Spacer().frame(height: 8)
                VStack(alignment: .leading, spacing: 9) {
                    LudoRuleLine(icon: Icons.Rounded.Casino, text: rules.oneOrSix ? "Roll a 1 or 6 to bring a token out." : "Roll a 6 to bring a token out.")
                    LudoRuleLine(icon: Icons.Rounded.Autorenew, text: "A 6\(rules.captureBonus ? ", a capture" : "") or reaching home gives another roll. Three 6s in a row lose the turn.")
                    LudoRuleLine(icon: Icons.Rounded.Bolt, text: "Land on an opponent to send it back to its yard.")
                    LudoRuleLine(icon: Icons.Rounded.Star, text: rules.safeStars ? "Start and star squares are safe." : "Start squares are safe.")
                    LudoRuleLine(icon: Icons.Rounded.Home, text: "Reach home with an exact roll. \(rules.allPlaces ? "Play on for every place." : "First home with every token wins.")")
                    if rules.blockades { LudoRuleLine(icon: Icons.Rounded.Shield, text: "Two tokens of one colour block a square.") }
                }
                Spacer().frame(height: 14)
                HStack(spacing: 0) {
                    Icon(Icons.AutoMirrored.Rounded.VolumeUp, tint: Royal.Gold, size: 22)
                    Spacer().frame(width: 12)
                    Text("Sound effects", style: bodyStyle(16, .Bold)).frame(maxWidth: .infinity, alignment: .leading)
                    RoyalSwitch(AppSettings.data.soundEnabled, { v in AppSettings.update { $0.copy(soundEnabled: v) } }, label: "Sound effects")
                }
                .padding(.vertical, 4)
                Spacer().frame(height: 16)
                CandyButton("Resume", onResume, height: 54, fontSize: 21)
                Spacer().frame(height: 10)
                HStack(spacing: 10) {
                    OutlineButton("Restart", onRestart, icon: Icons.Rounded.Replay, fill: true)
                    OutlineButton("Save & quit", onQuit, icon: Icons.AutoMirrored.Rounded.Logout, fill: true)
                }
            }
        }
    }
}

private struct LudoRuleLine: View {
    let icon: ImageVector
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Icon(icon, tint: Royal.Gold, size: 17)
                .padding(.top, 1)
                .frame(width: 18, height: 18, alignment: .bottom)
            Spacer().frame(width: 10)
            Text(text, style: bodyStyle(14, .SemiBold, Royal.Smoke))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Results

/// The podium, stats and what's next.
private struct LudoResults: View {
    let session: LudoSession
    let theme: LudoTheme
    let onRematch: () -> Void
    let onSetup: () -> Void
    let onHub: () -> Void

    @State private var risen: CGFloat = LocalReduceMotion.current ? 1 : 0

    private func best(_ key: (LudoSeatStats) -> Int) -> String {
        let engine = session.engine
        guard !engine.stats.isEmpty else { return "None" }
        // maxByOrNull: the first maximum wins.
        var top = 0
        for i in engine.stats.indices where key(engine.stats[i]) > key(engine.stats[top]) { top = i }
        let value = key(engine.stats[top])
        return value > 0 ? "\(session.config.seats[top].player.name) · \(value)" : "None"
    }

    var body: some View {
        let config = session.config
        let engine = session.engine
        let order = engine.standings
        let winner = order.first.map { config.seats[$0] }
        let reduce = LocalReduceMotion.current
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                WoodPanel(padding: 20) {
                    VStack(spacing: 0) {
                        Text("GAME OVER", style: bodyStyle(13, .Black, ludoHex(0xFFC94A).color).copy(letterSpacing: 1.6))
                        Spacer().frame(height: 6)
                        Text(winner.map { $0.isBot ? "\($0.player.name) wins!" : "\($0.player.name) is the Ludo champ!" } ?? "Game over",
                             style: displayStyle(28, Royal.Ivory, .Center))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer().frame(height: 14)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach([1, 0, 2].filter { $0 < order.count }, id: \.self) { place in
                                let seat = config.seats[order[place]]
                                LudoPodium(seat: seat, color: theme.color(seat.arm, config.arms), place: place + 1, risen: risen)
                            }
                        }
                        Spacer().frame(height: 16)
                        VStack(spacing: 8) {
                            LudoStatRow(icon: Icons.Rounded.Bolt, title: "Most captures", value: best { $0.captures })
                            LudoStatRow(icon: Icons.Rounded.Casino, title: "Most sixes", value: best { $0.sixes })
                            LudoStatRow(icon: Icons.Rounded.Home, title: "Tokens home", value: order.map { "\(engine.tokensHome($0))" }.joined(separator: " · "))
                            LudoStatRow(icon: Icons.Rounded.Schedule, title: "Time", value: "\(max(1, Kt.roundToInt(session.elapsed / 60))) min")
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedCornerShape(20).fill(Color.White.copy(alpha: 0.07)))
                        Spacer().frame(height: 18)
                        CandyButton("Rematch", onRematch, icon: Icons.Rounded.Replay)
                        Spacer().frame(height: 10)
                        HStack(spacing: 10) {
                            OutlineButton("New setup", onSetup, icon: Icons.Rounded.Tune, fill: true)
                            OutlineButton("Home", onHub, icon: Icons.Rounded.GridView, fill: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            }
            if !reduce {
                Confetti(count: 130, durationMs: 4000)
                    .ignoresSafeArea()
            }
        }
        .task {
            if reduce { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.compose(dampingRatio: 0.6, stiffness: 220)) { risen = 1 }
        }
    }
}

private struct LudoPodium: View {
    let seat: LudoSeat
    let color: LudoColor
    let place: Int
    let risen: CGFloat

    var body: some View {
        let height: CGFloat = [140, 104, 76][place - 1]
        let shown = Double(min(max(risen, 0), 1))
        VStack(spacing: 6) {
            if place == 1 {
                ZStack {
                    RotatingRays()
                        .frame(width: 70, height: 70)
                        .opacity(shown)
                    LudoCrownIcon()
                        .frame(width: 30, height: 30)
                        .offset(y: (1 - risen) * -30)
                        .opacity(shown)
                }
                .frame(width: 70, height: 70)
            }
            let avatar: CGFloat = place == 1 ? 66 : 52
            ZStack {
                Circle().fill(LinearGradient(colors: [color.mix(.White, 0.15).color, color.mix(.Black, 0.2).color], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Color.White, lineWidth: 3)
                Text(seat.player.avatar).font(.system(size: place == 1 ? 32 : 25))
            }
            .frame(width: avatar, height: avatar)
            .background(Circle().fill(color.color).composeShadow(8, color: color.color))
            Text(seat.player.name, style: bodyStyle(13, .Black, .White)).lineLimit(1).truncationMode(.tail)
            ZStack(alignment: .top) {
                RoundedCornerShape(14).fill(LinearGradient(colors: [color.color, color.mix(.Black, 0.35).color], startPoint: .top, endPoint: .bottom))
                RoundedCornerShape(14).strokeBorder(Color.White.copy(alpha: 0.25), lineWidth: 1)
                Text("\(place)", style: displayStyle(36, Color.White.copy(alpha: 0.9)))
                    .padding(.top, 6)
                    .opacity(shown)
            }
            .frame(width: 88, height: 10 + (height - 10) * min(max(risen, 0), 1.2))
            .clipShape(RoundedCornerShape(14))
        }
        .frame(width: 88)
    }
}

private struct LudoStatRow: View {
    let icon: ImageVector
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, tint: Royal.Gold, size: 16)
            Spacer().frame(width: 8)
            Text(title, style: bodyStyle(13, .Bold, Color.White.copy(alpha: 0.8))).frame(maxWidth: .infinity, alignment: .leading)
            Text(value, style: bodyStyle(13, .Black, .White)).lineLimit(1)
        }
    }
}
