import SwiftUI
import GameKit

/// The Pool table. Landscape: players across the top, the power bar left, the table in the middle,
/// the return chute and fine-tune wheel right. Portrait: the table stands on end with the power
/// bar, spin and wheel underneath.
struct PoolGameScreen: View {
    let config: PoolConfig
    let onExit: () -> Void
    let onRematch: () -> Void
    let onNewSetup: () -> Void

    @State private var session: PoolSession
    @State private var showPause = false
    @State private var showSpin = false
    @State private var prompt: RoyalPrompt? = nil
    @State private var recorded = false
    @Environment(\.scenePhase) private var scenePhase

    init(_ config: PoolConfig, onExit: @escaping () -> Void, onRematch: @escaping () -> Void, onNewSetup: @escaping () -> Void) {
        self.config = config
        self.onExit = onExit
        self.onRematch = onRematch
        self.onNewSetup = onNewSetup
        _session = State(initialValue: PoolSession(config: config))
    }

    var body: some View {
        let reduce = LocalReduceMotion.current
        let theme = PoolTableTheme.theme(config.tableID)
        let cue = PoolCueStyle.style(config.cueID)
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.1
            let insets = geo.safeAreaInsets
            let screen = CGRect(x: -insets.leading, y: -insets.top, width: geo.size.width + insets.leading + insets.trailing,
                                height: geo.size.height + insets.top + insets.bottom)
            ZStack(alignment: .top) {
                PoolBackdrop(theme).ignoresSafeArea()
                Group {
                    if wide {
                        PoolLandscape(session: session, theme: theme, cue: cue, onPause: openPause, onSpin: openSpin)
                    } else {
                        PoolPortrait(session: session, theme: theme, cue: cue, onPause: openPause, onSpin: openSpin)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // The coin toss for the break.
                ZStack {
                    if let t = session.toss {
                        PoolTossView(name: session.config.seats[t.seat].player.name)
                            .id(t.id)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.compose(dampingRatio: 0.6, stiffness: 300), value: session.toss?.id)
                .allowsHitTesting(false)

                ZStack {
                    if let b = session.banner {
                        PoolBannerView(banner: b)
                            .id(b.id)
                            .transition(reduce ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduce ? .tween(200) : .compose(dampingRatio: 0.55, stiffness: 350), value: session.banner?.id)
                .allowsHitTesting(false)

                // Extras: the instant replay's badge; a tap anywhere skips it.
                ExtrasReplayOverlay(active: session.replay != nil) { session.skipReplay() }

                ZStack {
                    if showSpin {
                        PoolSpinPicker(session: session) { showSpin = false }
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .animation(.tween(300), value: showSpin)
                ZStack {
                    if session.phase == .BETWEEN {
                        PoolRackCard(session: session) { session.nextRack() }
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .animation(.tween(300), value: session.phase == .BETWEEN)
                ZStack {
                    if session.phase == .OVER {
                        PoolResultsView(session: session, onRematch: onRematch, onSetup: onNewSetup, onHub: onExit)
                            .transition(.opacity)
                    }
                }
                .animation(.tween(350), value: session.phase == .OVER)
                ZStack {
                    if showPause {
                        PoolPauseSheet(
                            session: session,
                            onResume: closePause,
                            onRestart: {
                                prompt = RoyalPrompt(
                                    title: "Restart this match?",
                                    message: "The balls are racked again and the score goes back to 0–0.",
                                    confirmTitle: "Restart",
                                    cancelTitle: "Keep playing",
                                    icon: Icons.Rounded.RestartAlt,
                                    destructive: true,
                                    onConfirm: {
                                        showPause = false
                                        session.discard()
                                        onRematch()
                                    }
                                )
                            },
                            onQuit: {
                                showPause = false
                                leave()
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.tween(160), value: showPause)
                RoyalDialogHost(prompt) {
                    prompt = nil
                    if !showPause { session.paused = false }
                }
            }
            .coordinateSpace(.named(PoolTableView.space))
            .environment(\.poolScreenFrame, screen)
        }
        .allowRotation()
        .onAppear {
            session.reduceMotion = reduce
            session.start()
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .OVER && !recorded {
                recorded = true
                PartyStore.record(session.record)
            }
            if phase != .READY { showSpin = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.save() }
        }
        .onDisappear {
            session.save()
            session.dispose()
        }
    }

    private func openPause() {
        session.paused = true
        showPause = true
    }

    private func closePause() {
        showPause = false
        session.paused = false
    }

    private func leave() {
        session.save()
        onExit()
    }

    private func openSpin() {
        if !session.canControl { return }
        PoolSound.play(PoolSound.chalk)
        showSpin = true
    }
}

// MARK: Layouts

private struct PoolLandscape: View {
    let session: PoolSession
    let theme: PoolTableTheme
    let cue: PoolCueStyle
    let onPause: () -> Void
    let onSpin: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                RoundIconButton(Icons.Rounded.Pause, onPause, size: 42, contentDescription: "Pause")
                if session.config.practice {
                    ExtrasPoolPracticeBar(session: session).frame(maxWidth: .infinity)
                } else {
                    PoolPlayersBar(session, compact: true).frame(maxWidth: .infinity)
                }
                PoolSpinButton(session, 42, onSpin)
                SoundButton()
            }
            .frame(height: 54)
            HStack(spacing: 10) {
                PoolPowerBar(session, cue, vertical: true).frame(width: 50).frame(maxHeight: .infinity)
                PoolTableView(session, theme, cue, vertical: false).frame(maxWidth: .infinity, maxHeight: .infinity).zIndex(1)
                VStack(spacing: 8) {
                    PoolChute(session, vertical: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                    PoolFineWheel(session, vertical: true).frame(maxWidth: .infinity).frame(height: 120)
                }
                .frame(width: 40)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            PoolHint(session: session)
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}

private struct PoolPortrait: View {
    let session: PoolSession
    let theme: PoolTableTheme
    let cue: PoolCueStyle
    let onPause: () -> Void
    let onSpin: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                RoundIconButton(Icons.Rounded.Pause, onPause, size: 42, contentDescription: "Pause")
                VStack(spacing: 1) {
                    Text("Pool", style: displayStyle(22, Royal.Ivory))
                    Text("\(theme.name.uppercased()) · \(session.match.game.title.uppercased())",
                         style: bodyStyle(9, .ExtraBold, Color.white.opacity(0.7)).copy(letterSpacing: 1))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                SoundButton()
            }
            if session.config.practice {
                ExtrasPoolPracticeBar(session: session).frame(maxWidth: .infinity).frame(height: 56)
            } else {
                PoolPlayersBar(session, compact: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: session.config.seats.count == 2 ? 56 : 60)
            }
            HStack(spacing: 6) {
                if !session.config.practice {
                    PoolScorePill(session, inline: true)
                    PoolBallOnPill(session)
                }
                PoolChute(session, vertical: false).frame(maxWidth: .infinity).frame(height: 30)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            HStack(spacing: 8) {
                PoolPowerBar(session, cue, vertical: true)
                    .frame(width: 44)
                    .padding(.vertical, 6)
                    .frame(maxHeight: .infinity)
                PoolTableView(session, theme, cue, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) {
                PoolSpinButton(session, 46, onSpin)
                Spacer().frame(width: 16)
                PoolFineWheel(session, vertical: false).frame(width: 130, height: 46)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            PoolHint(session: session)
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }
}

private struct SoundButton: View {
    var body: some View {
        let on = AppSettings.data.soundEnabled
        RoundIconButton(
            on ? Icons.AutoMirrored.Rounded.VolumeUp : Icons.AutoMirrored.Rounded.VolumeOff,
            { AppSettings.update { $0.copy(soundEnabled: !$0.soundEnabled) } },
            size: 42,
            contentDescription: on ? "Sound on" : "Sound off"
        )
    }
}

private struct PoolHint: View {
    let session: PoolSession

    var body: some View {
        let replay = session.canReplay
        HStack(spacing: 8) {
            Text(hintText(session), style: bodyStyle(13, .Bold, Color.white.opacity(0.88), .Center))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            // Extras: replay the last shot.
            if replay { ExtrasReplayButton { session.startReplay() } }
        }
        .frame(height: 20)
        .animation(.compose(dampingRatio: 0.7, stiffness: 500), value: replay)
    }
}

@MainActor
private func hintText(_ session: PoolSession) -> String {
    let t = session.table
    let name = session.currentSeat.player.name
    if session.replay != nil { return "Replay · tap to skip" }
    if session.phase != .READY { return " " }
    if session.config.practice, let text = PoolPractice.hint(session) { return text }
    if session.isBotTurn { return "\(name) is lining up…" }
    if session.placing { return session.cueValid ? "Let go to place the cue ball" : "Touching a ball: move it a little" }
    if session.pulling { return "Let go to shoot · slide back to cancel" }
    if t.ballInHand && t.kitchenOnly { return "Ball in hand: place it behind the line, then aim" }
    if t.ballInHand { return "Ball in hand: drag the cue ball anywhere" }
    if session.needsCall && session.call == nil { return "Call your pocket for the 8: tap a pocket" }
    if session.needsCall { return "\(name) · on the 8 · pocket called" }
    if !t.broken { return "\(name), break! Pull the cue back hard" }
    if t.game == .NINE, let low = t.lowest { return "\(name) · hit the \(low) first" }
    if let g = t.groupNow { return "\(name) · \(g.title) · drag to aim, pull the cue to shoot" }
    return "\(name) · open table · drag to aim, pull the cue to shoot"
}

// MARK: - Overlays

/// Compose `Column(Modifier.verticalScroll(…))` in a centring box: the content at its own height,
/// scrolling only when it does not fit.
private struct PoolFitScroll<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical, showsIndicators: false) { content }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private func bannerIcon(_ icon: PoolBannerIcon) -> ImageVector {
    switch icon {
    case .Trophy: return Icons.Rounded.EmojiEvents
    case .Warning: return Icons.Rounded.Warning
    case .Solids: return Icons.Rounded.Circle
    case .Stripes: return Icons.Rounded.Contrast
    case .Respot: return Icons.AutoMirrored.Rounded.Undo
    case .Sparkles: return Icons.Rounded.AutoAwesome
    case .Tap: return Icons.Rounded.TouchApp
    case .Timer: return Icons.Rounded.Timer
    }
}

private struct PoolBannerView: View {
    let banner: PoolBanner

    var body: some View {
        let shape = Capsule()
        let tint = banner.tint
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Icon(bannerIcon(banner.icon), tint: Color.white, size: 22)
                Text(banner.text, style: bodyStyle(22, .Black, Color.white))
                    .lineLimit(1)
                    .shadow(color: Color.black.opacity(0.4), radius: 0, x: 0, y: 4)
            }
            if let detail = banner.detail {
                Text(detail, style: bodyStyle(13, .ExtraBold, Color.white.opacity(0.85)))
                    .lineLimit(1)
                    .shadow(color: Color.black.opacity(0.4), radius: 0, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(shape.fill(LinearGradient(colors: [tint.lerp(.white, 0.15).color, tint.lerp(.black, 0.2).color], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 2))
        .clipShape(shape)
        .background(shape.fill(tint.color).composeShadow(16, color: tint.color))
        .rotationEffect(.degrees(-2))
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}

/// A coin flips over the table to decide who breaks.
private struct PoolTossView: View {
    let name: String
    @State private var start = poolNow()

    var body: some View {
        let reduce = LocalReduceMotion.current
        VStack(spacing: 14) {
            TimelineView(.animation(minimumInterval: nil, paused: reduce)) { _ in
                let t = reduce ? 0 : poolNow() - start
                let tt = min(t, 1.1)
                let spin = reduce ? 1.0 : cos(tt * Double.pi * 7)
                ZStack {
                    Canvas { ctx, s in
                        let c = CGPoint(x: s.width / 2, y: s.height / 2)
                        let r: CGFloat = 36
                        ctx.fill(PoolArt.circle(c, r), with: .linearGradient(Gradient(colors: [poolHex(0xFFE9A0).color, poolHex(0xC8901E).color]),
                                                                            startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
                        ctx.stroke(PoolArt.circle(c, 31), with: .color(poolHex(0x8A5A10).alpha(0.6).color), lineWidth: 2)
                    }
                    .frame(width: 90, height: 90)
                    Text(spin >= 0 ? "8" : "9", style: bodyStyle(30, .Black, poolHex(0x5A3A08).color))
                }
                .frame(width: 90, height: 90)
                .scaleEffect(x: CGFloat(max(0.06, abs(spin))), y: 1)
                .offset(y: reduce ? 0 : -CGFloat(sin(tt / 1.1 * Double.pi)) * 46)
            }
            .frame(width: 90, height: 90)
            Text("\(name) breaks!", style: displayStyle(26, Color.white))
                .shadow(color: Color.black.opacity(0.4), radius: 0, x: 0, y: 4)
        }
        .padding(26)
        .background(RoundedRectangle(cornerRadius: 30, style: .circular).fill(Color.black.opacity(0.45)))
    }
}

/// A big cue ball: drag the red dot for follow, draw or side spin. Double-tap to recentre.
private struct PoolSpinPicker: View {
    let session: PoolSession
    let onClose: () -> Void

    @State private var lastUp: Double = 0
    @State private var downAt: CGPoint? = nil
    @State private var moved: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let ball = min(220, max(120, geo.size.height - 250))
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }
                WoodPanel(padding: 20) {
                    PoolFitScroll {
                        VStack(spacing: 14) {
                            SectionLabel("Spin", color: poolHex(0xFFC94A).color)
                            spinBall(ball)
                            Text(spinText(session.spin), style: bodyStyle(16, .ExtraBold, Color.white))
                            Text("Top for follow, bottom for draw, sides for english. Double-tap to centre.",
                                 style: bodyStyle(12, .SemiBold, Color.white.opacity(0.7), .Center))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 12) {
                                OutlineButton("Centre", { session.setSpin(Vec2.ZERO) }, fill: true)
                                CandyButton("Done", onClose, height: 50, fontSize: 20).frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: 300)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {}
                .frame(maxWidth: 380)
                .padding(24)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func spinBall(_ ball: CGFloat) -> some View {
        let spin = session.spin
        return Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r = s.width / 2
            ctx.fill(PoolArt.circle(c, r), with: .radialGradient(Gradient(colors: [Color.white, poolHex(0xE9E7DF).color, poolHex(0xA9A69C).color]),
                                                                 center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
            let safe = r * 0.62
            ctx.stroke(PoolArt.circle(c, safe), with: .color(Color.black.opacity(0.25)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - safe, y: c.y)); cross.addLine(to: CGPoint(x: c.x + safe, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - safe)); cross.addLine(to: CGPoint(x: c.x, y: c.y + safe))
            ctx.stroke(cross, with: .color(Color.black.opacity(0.12)), lineWidth: 1)
            let k = safe / 0.5
            let dot = CGPoint(x: c.x + CGFloat(spin.x) * k, y: c.y - CGFloat(spin.y) * k)
            ctx.fill(PoolArt.circle(CGPoint(x: dot.x, y: dot.y + 1), 15), with: .color(Color.black.opacity(0.18)))
            ctx.fill(PoolArt.circle(dot, 13), with: .color(poolHex(0xE0242B).color))
            ctx.stroke(PoolArt.circle(dot, 13), with: .color(Color.white.opacity(0.8)), lineWidth: 2)
        }
        .frame(width: ball, height: ball)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if downAt == nil {
                        downAt = v.startLocation
                        moved = 0
                    }
                    if let d = downAt { moved = max(moved, hypot(v.location.x - d.x, v.location.y - d.y)) }
                    set(v.location, ball)
                }
                .onEnded { _ in
                    let now = poolNow()
                    if moved < 12 && now - lastUp < 0.32 { session.setSpin(Vec2.ZERO) }
                    lastUp = now
                    downAt = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spin")
        .accessibilityValue(spinText(spin))
    }

    private func set(_ p: CGPoint, _ ball: CGFloat) {
        let half = ball / 2
        let k = half * 0.62 / 0.5
        session.setSpin(Vec2(Double((p.x - half) / k), Double(-(p.y - half) / k)))
    }
}

/// Between racks of a race.
private struct PoolRackCard: View {
    let session: PoolSession
    let onNext: () -> Void

    var body: some View {
        let m = session.match
        let w = m.table.winner ?? 0
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            WoodPanel(padding: 22) {
                PoolFitScroll {
                    VStack(spacing: 12) {
                        SectionLabel("Rack \(m.rack)", color: poolHex(0xFFC94A).color)
                        Text("\(session.unitName(w)) takes it!", style: displayStyle(26, Color.white, .Center))
                            .multilineTextAlignment(.center)
                        if !session.finish.isEmpty {
                            Text(session.finish, style: bodyStyle(14, .Bold, Color.white.opacity(0.75), .Center))
                                .multilineTextAlignment(.center)
                        }
                        HStack(spacing: 20) {
                            ForEach(0..<m.units, id: \.self) { u in
                                VStack(spacing: 2) {
                                    Text("\(m.wins[u])", style: displayStyle(30, u == w ? poolHex(0xFFE27A).color : Color.white))
                                    Text(session.unitName(u), style: bodyStyle(12, .ExtraBold, Color.white.opacity(0.75))).lineLimit(1)
                                }
                            }
                        }
                        Text("Race to \(m.target)", style: bodyStyle(12, .Bold, Color.white.opacity(0.6)))
                        CandyButton("Next rack", onNext, height: 52, fontSize: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 28)
        }
    }
}

private struct PoolRule: Identifiable {
    let id = UUID()
    let text: String
    var icon: ImageVector? = nil
    var ball: Int? = nil
}

/// Pause: resume, the rules in short, settings, restart or save and quit.
private struct PoolPauseSheet: View {
    let session: PoolSession
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let settings = AppSettings.data
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onResume() }
            WoodPanel(padding: 18) {
                PoolFitScroll {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Paused", style: displayStyle(28, Royal.Gold))
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(pauseRules(session)) { rule in
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        if let ball = rule.ball {
                                            PoolMiniBall(ball, 18)
                                        } else if let icon = rule.icon {
                                            Icon(icon, tint: Royal.Gold, size: 18)
                                        }
                                    }
                                    .frame(width: 20, height: 20)
                                    Text(rule.text, style: bodyStyle(14, .SemiBold, Royal.Smoke))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        PauseToggle(icon: Icons.AutoMirrored.Rounded.VolumeUp, title: "Sound effects", value: settings.soundEnabled) { v in
                            AppSettings.update { $0.copy(soundEnabled: v) }
                        }
                        PauseToggle(icon: Icons.Rounded.Vibration, title: "Haptics", value: settings.hapticsEnabled) { v in
                            AppSettings.update { $0.copy(hapticsEnabled: v) }
                        }
                        PauseToggle(icon: Icons.Rounded.Speed, title: "Fast computers", value: session.fastBots) { v in session.fastBots = v }
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Aim guide", color: Royal.Smoke)
                            RoyalSegmented(PoolAimGuide.allCases, session.aimGuide, { session.aimGuide = $0 }, { $0.title })
                        }
                        CandyButton("Resume", onResume, height: 52, fontSize: 20)
                        HStack(spacing: 10) {
                            OutlineButton("Restart match", onRestart, icon: Icons.Rounded.Replay, fill: true)
                            OutlineButton("Save & quit", onQuit, icon: Icons.AutoMirrored.Rounded.ExitToApp, fill: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {}
            .frame(maxWidth: 520)
            .padding(20)
        }
    }
}

private struct PauseToggle: View {
    let icon: ImageVector
    let title: String
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Icon(icon, tint: Royal.Gold, size: 22)
            Spacer().frame(width: 12)
            Text(title, style: bodyStyle(15, .Bold)).frame(maxWidth: .infinity, alignment: .leading)
            RoyalSwitch(value, onChange, label: title)
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
private func pauseRules(_ session: PoolSession) -> [PoolRule] {
    if session.config.practice {
        return [
            PoolRule(text: "Drag on the table to aim, fine-tune with the wheel, then pull the cue down the power bar and let go.", icon: Icons.Rounded.PanTool),
            PoolRule(text: "Practice table: no turns, no fouls and no score. Shoot as often as you like.", icon: Icons.Rounded.Adjust),
            PoolRule(text: "Scratch and the cue ball comes back in hand: place it anywhere.", ball: 0),
            PoolRule(text: "Tap Re-rack for a fresh rack at any time.", icon: Icons.Rounded.Refresh),
            PoolRule(text: "Tap Replay after a shot to watch it again in slow motion.", icon: Icons.Rounded.Replay),
        ]
    }
    let common = [
        PoolRule(text: "Drag on the table to aim, fine-tune with the wheel, then pull the cue down the power bar and let go.", icon: Icons.Rounded.PanTool),
        PoolRule(text: "Tap the spin ball for follow, draw or side spin.", icon: Icons.Rounded.Adjust),
        PoolRule(text: "Fouls give the next player ball in hand: a scratch, no ball hit, the wrong ball first, or no cushion after contact.", icon: Icons.Rounded.Warning),
    ]
    switch session.match.game {
    case .EIGHT:
        return common + [
            PoolRule(text: "The first ball you pot after the break makes you solids or stripes.", icon: Icons.Rounded.Contrast),
            PoolRule(text: "Pot one of yours and you shoot again.", icon: Icons.Rounded.Refresh),
            PoolRule(text: session.table.callEight ? "Clear your group, call a pocket and sink the 8 to win." : "Clear your group, then sink the 8 to win.", ball: 8),
            PoolRule(text: "Sink the 8 early, on a foul or in the wrong pocket and you lose the rack.", icon: Icons.Rounded.Block),
        ]
    case .NINE:
        return common + [
            PoolRule(text: "Always hit the lowest ball on the table first.", ball: 1),
            PoolRule(text: "Pot any ball on a legal shot and you shoot again.", icon: Icons.Rounded.Refresh),
            PoolRule(text: "Sink the 9 on a legal shot to win, even on a combination.", ball: 9),
        ]
    }
}

/// The winner, the finishing shot and everyone's stats.
private struct PoolResultsView: View {
    let session: PoolSession
    let onRematch: () -> Void
    let onSetup: () -> Void
    let onHub: () -> Void

    @State private var risen: CGFloat = 0

    var body: some View {
        let m = session.match
        let w = m.winner ?? 0
        let winners = session.seats(w).map { session.config.seats[$0] }
        let decider = m.game == .EIGHT ? 8 : 9
        let reduce = LocalReduceMotion.current
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            PoolFitScroll {
                WoodPanel(padding: 22) {
                    VStack(spacing: 14) {
                        SectionLabel(m.target == 1 ? "Rack won" : "Match won", color: poolHex(0xFFC94A).color)
                        ZStack {
                            RotatingRays(color: poolHex(0xFFE27A).color).frame(width: 200, height: 200)
                            PoolMiniBall(decider, 92)
                                .background(Circle().fill(poolHex(0xFFD24D).color).composeShadow(22, color: poolHex(0xFFD24D).color))
                                .scaleEffect(0.4 + 0.6 * risen)
                                .rotationEffect(.degrees(-120 * Double(1 - risen)))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 130)
                        HStack(spacing: -10) {
                            ForEach(winners) { PoolAvatar($0, 56, active: true) }
                        }
                        Text(resultsHeadline(session), style: displayStyle(26, Color.white, .Center))
                            .multilineTextAlignment(.center)
                        if !session.finish.isEmpty {
                            Text(session.finish, style: bodyStyle(14, .Bold, Color.white.opacity(0.75), .Center))
                                .multilineTextAlignment(.center)
                        }
                        statsTable(m)
                        HStack(spacing: 0) {
                            Icon(Icons.Rounded.Schedule, tint: Color.white.opacity(0.8), size: 16)
                            Spacer().frame(width: 6)
                            Text("Time", style: bodyStyle(13, .Bold, Color.white.opacity(0.8))).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(max(1, Kt.roundToInt(session.elapsed / 60))) min", style: bodyStyle(13, .ExtraBold, Color.white))
                        }
                        .padding(.horizontal, 6)
                        CandyButton("Rematch", onRematch, icon: Icons.Rounded.Replay)
                        HStack(spacing: 10) {
                            OutlineButton("New setup", onSetup, icon: Icons.Rounded.Tune, fill: true)
                            OutlineButton("Home", onHub, icon: Icons.Rounded.GridView, fill: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 18)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
            if !reduce { Confetti(count: 120, durationMs: 4000).ignoresSafeArea() }
        }
        .onAppear {
            withAnimation(.compose(dampingRatio: 0.55, stiffness: 260).delay(0.2)) { risen = 1 }
        }
    }

    private func statsTable(_ m: PoolMatch) -> some View {
        let head = bodyStyle(9, .Black, Color.white.opacity(0.55), .Center).copy(letterSpacing: 0.5)
        let cell = bodyStyle(13, .Bold, Color.white.opacity(0.85), .Center)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("PLAYER", style: head).frame(maxWidth: .infinity, alignment: .leading)
                Text("POTS", style: head).frame(width: 40)
                Text("RUN", style: head).frame(width: 36)
                Text("B&R", style: head).frame(width: 36)
                Text("FOULS", style: head).frame(width: 44)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.top, 8)
            ForEach(Array(session.config.seats.enumerated()), id: \.offset) { index, seat in
                let s = m.totals[index]
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(verbatim: seat.player.avatar).font(.system(size: 18))
                        Text(seat.player.name, style: bodyStyle(14, .ExtraBold, Color.white)).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(s.potted)", style: cell).frame(width: 40)
                    Text("\(s.bestRun)", style: cell).frame(width: 36)
                    Text("\(s.breakAndRuns)", style: cell).frame(width: 36)
                    Text("\(s.fouls)", style: cell.copy(color: s.fouls > 0 ? poolHex(0xFF8A8A).color : Color.white.opacity(0.85))).frame(width: 44)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(seat.player.name): \(s.potted) potted, best run \(s.bestRun), \(s.breakAndRuns) break and runs, \(s.fouls) fouls")
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .circular))
    }
}

@MainActor
private func resultsHeadline(_ session: PoolSession) -> String {
    let m = session.match
    let w = m.winner ?? 0
    let name = session.unitName(w)
    let verb = m.teams ? "win" : "wins"
    if m.target <= 1 { return "\(name) \(verb)!" }
    let best = m.wins.enumerated().filter { $0.offset != w }.map { $0.element }.max() ?? 0
    return "\(name) \(verb) \(m.wins[w])–\(best)!"
}
