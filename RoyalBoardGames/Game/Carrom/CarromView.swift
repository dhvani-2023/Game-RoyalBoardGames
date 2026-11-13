import SwiftUI
import GameKit

/// The reference's crown symbol, used for queen banners, rules and results (24×24 viewport).
struct CarromCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(3, 17.5)); path.addLine(to: p(1.8, 6.5)); path.addLine(to: p(7.4, 11)); path.addLine(to: p(12, 3.5))
        path.addLine(to: p(16.6, 11)); path.addLine(to: p(22.2, 6.5)); path.addLine(to: p(21, 17.5)); path.closeSubpath()
        path.move(to: p(3.2, 19)); path.addLine(to: p(20.8, 19)); path.addLine(to: p(20.8, 21.4)); path.addLine(to: p(3.2, 21.4)); path.closeSubpath()
        return path
    }
}

/// An icon: a mapped Material symbol, or the crown.
enum CarromIcon {
    case vector(ImageVector)
    case crown
}

/// Draws a [CarromIcon] the way Compose's `Icon` does (24-in-24 glyph at [size]).
struct CarromIconView: View {
    let icon: CarromIcon
    var tint: Color
    var size: CGFloat

    init(_ icon: CarromIcon, tint: Color, size: CGFloat) {
        self.icon = icon
        self.tint = tint
        self.size = size
    }

    var body: some View {
        switch icon {
        case .vector(let v): Icon(v, nil, tint: tint, size: size)
        case .crown: CarromCrownShape().fill(tint).frame(width: size, height: size)
        }
    }
}

private func bannerIcon(_ icon: CarromBannerIcon) -> CarromIcon {
    switch icon {
    case .CROWN: return .crown
    case .WARNING: return .vector(Icons.Rounded.Warning)
    case .UNDO: return .vector(Icons.AutoMirrored.Rounded.Undo)
    case .SPARKLES: return .vector(Icons.Rounded.AutoAwesome)
    case .TIMER: return .vector(Icons.Rounded.Timer)
    }
}

/// The Carrom table: players up top, the board (turned to the shooter), the striker slider, pocketed trays, banners,
/// the pause card and the results. Rotates; in landscape the board sits on the left and the controls on the right.
struct CarromGameScreen: View {
    let session: CarromSession
    let onRematch: () -> Void
    let onNewSetup: () -> Void
    let onHub: () -> Void
    let onQuit: () -> Void

    @State private var showPause = false
    @State private var prompt: RoyalPrompt? = nil
    @State private var recorded = false
    @Environment(\.scenePhase) private var scenePhase

    init(session: CarromSession, onRematch: @escaping () -> Void, onNewSetup: @escaping () -> Void, onHub: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.session = session
        self.onRematch = onRematch
        self.onNewSetup = onNewSetup
        self.onHub = onHub
        self.onQuit = onQuit
    }

    private func openPause() {
        session.paused = true
        showPause = true
    }

    private func closePause() {
        showPause = false
        session.paused = false
    }

    private func quit() {
        session.save()
        showPause = false
        onQuit()
    }

    var body: some View {
        let config = session.config
        let theme = CarromBoardTheme.theme(config.boardID)
        let coins = CarromCoinSet.set(config.coinsID)
        let striker = CarromStrikerStyle.style(config.strikerID)
        let phase = session.phase
        ZStack {
            Royal.Night.ignoresSafeArea()
            CarromBackdrop(theme: theme).ignoresSafeArea()
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                if !landscape {
                    VStack(spacing: 8) {
                        CarromTopBar(theme: theme, config: config, onPause: openPause)
                        if config.practice {
                            ExtrasCarromPracticeBar(session: session).frame(height: 60)
                        } else {
                            CarromPlayersHeader(session: session, coins: coins)
                        }
                        CarromTableView(session: session, theme: theme, coins: coins, striker: striker)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        CarromSliderBar(session: session, striker: striker)
                        CarromHint(session: session)
                        if !config.practice { CarromTrays(session: session, coins: coins) }
                    }
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 8, trailing: 10))
                    .frame(maxWidth: 640, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    let boardWidth = Swift.min(geo.size.height, geo.size.width * 0.58)
                    HStack(spacing: 14) {
                        CarromTableView(session: session, theme: theme, coins: coins, striker: striker)
                            .frame(width: boardWidth)
                            .frame(maxHeight: .infinity)
                        VStack(spacing: 8) {
                            CarromTopBar(theme: theme, config: config, onPause: openPause)
                            if config.practice {
                                ExtrasCarromPracticeBar(session: session).frame(height: 60)
                            } else {
                                CarromPlayersHeader(session: session, coins: coins)
                            }
                            CarromSliderBar(session: session, striker: striker)
                            CarromHint(session: session)
                            if !config.practice { CarromTrays(session: session, coins: coins) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            ZStack {
                if let toss = session.toss {
                    CarromTossView(toss: toss, name: config.seats[toss.seat].player.name, coins: coins)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.7).combined(with: .opacity).animation(.compose(dampingRatio: 0.6, stiffness: 1500)),
                            removal: .scale(scale: 0.7).combined(with: .opacity).animation(.compose(dampingRatio: 1, stiffness: 1500))
                        ))
                }
            }
            .animation(.compose(dampingRatio: 0.6, stiffness: 1500), value: session.toss?.id)

            ZStack {
                if let b = session.banner {
                    CarromBannerView(banner: b)
                        .id(b.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity).animation(.compose(dampingRatio: 0.55, stiffness: 500)),
                            removal: .scale(scale: 0.6).combined(with: .opacity).animation(.compose(dampingRatio: 1, stiffness: 1500))
                        ))
                }
            }
            .animation(.compose(dampingRatio: 0.55, stiffness: 500), value: session.banner?.id)
            .allowsHitTesting(false)

            // Extras: the instant replay's badge; a tap anywhere skips it.
            ExtrasReplayOverlay(active: session.replay != nil) { session.skipReplay() }

            ZStack {
                if phase == .BETWEEN {
                    CarromBoardCard(session: session) { session.nextBoard() }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.92)), removal: .opacity))
                }
            }
            .animation(.compose(dampingRatio: 1, stiffness: 400), value: phase == .BETWEEN)

            ZStack {
                if phase == .OVER {
                    CarromResultsView(session: session, onRematch: onRematch, onSetup: onNewSetup, onHub: onHub)
                        .transition(.opacity)
                }
            }
            .animation(.tween(400), value: phase == .OVER)

            ZStack {
                if showPause {
                    CarromPauseCard(
                        mode: session.match.mode,
                        tournament: config.options.tournament,
                        practice: config.practice,
                        onResume: closePause,
                        onRestart: {
                            prompt = RoyalPrompt(
                                title: "Restart this match?",
                                message: "Every coin goes back to the centre.",
                                confirmTitle: "Restart",
                                cancelTitle: "Keep playing",
                                icon: Icons.Rounded.Refresh,
                                destructive: true,
                                onConfirm: {
                                    showPause = false
                                    session.discard()
                                    if !config.practice { CarromStore.saved = nil }
                                    onRematch()
                                }
                            )
                        },
                        onQuit: quit
                    )
                    .transition(.opacity)
                }
            }
            .animation(.linear(duration: 0.16), value: showPause)

            RoyalDialogHost(prompt) {
                prompt = nil
                if !showPause && session.phase != .OVER { session.paused = false }
            }
        }
        .allowRotation()
        .task {
            session.reduceMotion = LocalReduceMotion.current
            session.start()
        }
        .onDisappear {
            session.save()
            session.dispose()
        }
        .onChange(of: scenePhase) { _, p in
            if p == .background { session.save() }
        }
        .onChange(of: phase) { _, p in
            if p == .OVER && !recorded {
                recorded = true
                PartyStore.record(session.record)
            }
        }
    }
}

// MARK: - Top bar and hint

private struct CarromTopBar: View {
    let theme: CarromBoardTheme
    let config: CarromConfig
    let onPause: () -> Void

    var body: some View {
        let soundOn = AppSettings.data.soundEnabled
        HStack(spacing: 0) {
            RoundIconButton(Icons.Rounded.Pause, onPause, size: 44, contentDescription: "Pause")
            VStack(spacing: 0) {
                Text("Carrom", style: displayStyle(22, Royal.Ivory))
                Text("\(theme.name.uppercased()) · \(config.seats.count) PLAYERS", style: bodyStyle(9, .ExtraBold, Royal.Smoke).copy(letterSpacing: 1))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            RoundIconButton(
                soundOn ? Icons.AutoMirrored.Rounded.VolumeUp : Icons.AutoMirrored.Rounded.VolumeOff,
                { AppSettings.update { $0.copy(soundEnabled: !$0.soundEnabled) } },
                size: 44,
                contentDescription: soundOn ? "Mute sound" : "Turn sound on"
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CarromHint: View {
    let session: CarromSession

    var body: some View {
        let seat = session.currentSeat
        let t = session.table
        let text: String
        let replay = session.canReplay
        let practiceHint = session.config.practice ? CarromPractice.hint(session) : nil
        switch session.phase {
        case _ where session.replay != nil:
            text = "Replay · tap to skip"
        case .READY, .AIMING:
            if let practiceHint {
                text = practiceHint
            } else if seat.isBot {
                text = "\(seat.player.name) is lining up…"
            } else if session.blocked {
                text = "Coin in the way, slide a little"
            } else if t.queenWaiting == t.unitNow {
                let what = session.match.mode == .FREESTYLE ? "any coin" : "a \(t.colour(t.unitNow) == .WHITE ? "white" : "black")"
                text = "\(seat.player.name), pocket \(what) to cover the Queen"
            } else if session.phase == .AIMING {
                text = session.fine ? "Fine aim · release to shoot" : "Release to shoot · drag back to cancel"
            } else if !t.broken {
                text = "\(seat.player.name), break! Slide, then pull back hard"
            } else {
                text = "\(seat.player.name)'s shot · slide to place, pull back to aim"
            }
        default:
            text = " "
        }
        return HStack(spacing: 8) {
            Text(text, style: bodyStyle(13, .Bold, Royal.Ivory.copy(alpha: 0.88), .Center))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            // Extras: replay the last shot.
            if replay { ExtrasReplayButton { session.startReplay() } }
        }
        .frame(height: 18)
        .animation(.compose(dampingRatio: 0.7, stiffness: 500), value: replay)
    }
}

// MARK: - Board and gestures

private enum DragMode { case PENDING, SLIDE, AIM, IGNORED }

/// Gesture state for one touch on the board.
@MainActor
private final class BoardDrag {
    var active = false
    var mode: DragMode? = nil
    var fineAnchor: (finger: CGSize, anchor: CGSize)? = nil
    var lastMove = carromNow()
    var lastTranslation = CGSize.zero
    var fineWatch: Task<Void, Never>? = nil
    var angle = 0.0
    var down = CGPoint.zero
}

/// The board, turned so the shooter sits at the bottom, with the mode tab, side names and the gestures.
private struct CarromTableView: View {
    let session: CarromSession
    let theme: CarromBoardTheme
    let coins: CarromCoinSet
    let striker: CarromStrikerStyle

    @State private var drag = BoardDrag()
    /// Resets on end and on cancel; a cancel (no onEnded) must not leave a half-made aim armed.
    @GestureState private var touching = false

    var body: some View {
        let reduce = LocalReduceMotion.current
        let turns = Double(session.viewTurns) * 90
        let over = session.phase == .OVER
        GeometryReader { geo in
            let tab: CGFloat = 26
            let side = Swift.max(10, Swift.min(geo.size.width, geo.size.height - tab))
            let corner = side * 0.07 * 0.9
            VStack(spacing: 0) {
                CarromModeTab(text: tabText(session))
                ZStack(alignment: .topLeading) {
                    ZStack {
                        CarromBoardPlate(theme: theme)
                        CarromPieceLayer(session: session, coins: coins, striker: striker)
                    }
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(turns))
                    .animation(reduce ? nil : .compose(dampingRatio: 0.86, stiffness: 130), value: turns)
                    CarromSideLabels(session: session, side: side)
                }
                .frame(width: side, height: side)
                .clipShape(RoundedCornerShape(corner))
                .background(RoundedCornerShape(corner).fill(Color.black).composeShadow(16))
                .contentShape(Rectangle())
                .gesture(boardGesture(side))
                .onChange(of: touching) { _, now in
                    if now { return }
                    // Deferred a turn of the run loop, so a normal end (onEnded) always wins.
                    let d = drag
                    let s = session
                    Task { @MainActor in
                        if !d.active { return }
                        d.fineWatch?.cancel()
                        d.fineWatch = nil
                        if d.mode == .AIM { s.cancelAim() }
                        d.active = false
                        d.mode = nil
                    }
                }
                .overlay(CarromBoardAccessibility(session: session))
                .rotation3DEffect(.degrees(over ? 26 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.25)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.1), value: over)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Placement and pull-back gestures, in the unturned view's space.

    private func boardGesture(_ side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { v in
                if !drag.active {
                    drag.active = true
                    drag.mode = nil
                    drag.fineAnchor = nil
                    drag.lastMove = carromNow()
                    drag.lastTranslation = .zero
                    drag.fineWatch?.cancel()
                    drag.fineWatch = nil
                    drag.angle = Double(session.viewTurns) * Double.pi / 2
                    drag.down = v.startLocation
                    changed(v.startLocation, .zero, side)
                    if v.translation == .zero { return }
                }
                changed(v.location, v.translation, side)
            }
            .onEnded { _ in
                if drag.mode == .AIM { session.release() }
                drag.fineWatch?.cancel()
                drag.fineWatch = nil
                drag.active = false
                drag.mode = nil
            }
    }

    private func boardPoint(_ p: CGPoint, _ side: CGFloat) -> CarromVec {
        let m = CarromMetrics(side, side)
        let v = CarromVec(Double(p.x - side / 2), Double(p.y - side / 2)).rotated(-drag.angle)
        return m.cm(side / 2 + CGFloat(v.x), side / 2 + CGFloat(v.y))
    }

    private func boardVector(_ t: CGSize) -> CarromVec { CarromVec(Double(t.width), Double(t.height)).rotated(-drag.angle) }

    private func beginAim() {
        drag.lastMove = carromNow()
        drag.fineAnchor = nil
        drag.fineWatch?.cancel()
        // Hold still for half a second and the aim turns four times finer.
        let d = drag
        let s = session
        drag.fineWatch = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                if d.fineAnchor == nil && carromNow() - d.lastMove > 0.5 && s.phase == .AIMING {
                    d.fineAnchor = (d.lastTranslation, d.lastTranslation)
                    CarromSound.play(.Tick)
                }
            }
        }
    }

    private func apply(_ position: CGPoint, _ t: CGSize, _ side: CGFloat) {
        let fullPull: CGFloat = 115
        switch drag.mode {
        case .SLIDE:
            session.slideTo(CarromBoard.slide(boardPoint(position, side), session.table.side))
        case .AIM:
            if hypot(t.width - drag.lastTranslation.width, t.height - drag.lastTranslation.height) > 1.5 { drag.lastMove = carromNow() }
            drag.lastTranslation = t
            var pull = t
            if let fa = drag.fineAnchor {
                pull = CGSize(width: fa.anchor.width + (t.width - fa.finger.width) * 0.25, height: fa.anchor.height + (t.height - fa.finger.height) * 0.25)
            }
            let length = hypot(pull.width, pull.height)
            if length <= 4 {
                session.setAim(session.aim?.angle ?? 0.0, 0.0, drag.fineAnchor != nil)
                return
            }
            let v = boardVector(pull)
            session.setAim(atan2(-v.y, -v.x), Double(Swift.min(1, length / fullPull)), drag.fineAnchor != nil)
        default:
            break
        }
    }

    private func changed(_ position: CGPoint, _ t: CGSize, _ side: CGFloat) {
        let slop: CGFloat = 7
        if !session.canControl || side <= 0 { return }
        if drag.mode == nil {
            let p = boardPoint(drag.down, side)
            let s = session.table.side
            if (p - session.strikerPoint).length < CarromBoard.strikerR * 2.6 {
                drag.mode = .PENDING
            } else if CarromBoard.distanceToBaseLine(p, s) < CarromBoard.strikerR * 1.4 {
                drag.mode = .SLIDE
            } else {
                drag.mode = .IGNORED
            }
        }
        switch drag.mode {
        case .PENDING:
            if hypot(t.width, t.height) <= slop { return }
            // Along the base line slides the striker; anything else pulls back to aim.
            let local = boardVector(t).rotated(-CarromBoard.rotation(session.table.side))
            drag.mode = Swift.abs(local.x) > Swift.abs(local.y) * 2.2 ? .SLIDE : .AIM
            if drag.mode == .AIM { beginAim() }
            apply(position, t, side)
        case .SLIDE, .AIM:
            apply(position, t, side)
        default:
            break
        }
    }
}

@MainActor
private func tabText(_ session: CarromSession) -> String {
    let m = session.match
    if session.config.practice { return "PRACTICE · \(m.mode.title.uppercased())" }
    var parts = [m.mode.title.uppercased()]
    if m.teams { parts.append("2 v 2") }
    if m.mode == .FREESTYLE { parts.append("FIRST TO \(session.table.target)") }
    if m.length != .ONE { parts.append("BOARD \(m.board)") }
    return parts.joined(separator: " · ")
}

/// The board's spoken description, kept in its own view so aiming doesn't re-render the board.
private struct CarromBoardAccessibility: View {
    let session: CarromSession

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(boardDescription(session))
    }
}

@MainActor
private func boardDescription(_ session: CarromSession) -> String {
    let t = session.table
    let who = "\(session.currentSeat.player.name)'s shot."
    let coinsLeft = session.match.mode == .FREESTYLE ? "\(t.coins.filter { $0.live }.count) coins left."
        : "\(t.left(.WHITE)) white and \(t.left(.BLACK)) black left."
    let queen = t.queenCoveredBy != nil ? "Queen covered." : (t.queenWaiting != nil ? "Queen waiting for a cover." : (t.queenOnBoard ? "Queen on the board." : ""))
    var aim = ""
    if let a = session.aim {
        let f = CarromBoard.forward(t.side)
        let off = (a.angle - atan2(f.y, f.x)).remainder(dividingBy: 2 * Double.pi) * 180 / Double.pi
        let clock = ((Kt.roundToInt(12 + off / 30) % 12) + 12) % 12
        aim = "Aiming at \(clock == 0 ? 12 : clock) o'clock, power \(Kt.toInt(a.power * 100)) percent."
    }
    let hint = session.canControl ? "Drag the striker along the base line to place it, then pull back from it to aim and shoot." : ""
    return [who, coinsLeft, queen, aim, hint].filter { !$0.isEmpty }.joined(separator: " ")
}

/// The static board, from the cached plate bitmap.
struct CarromBoardPlate: View {
    let theme: CarromBoardTheme
    @Environment(\.displayScale) private var scale
    @State private var rendered = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let _ = rendered
            ZStack {
                if w >= 1, let image = CarromPlates.cached(theme, w, h, scale) {
                    Image(decorative: image, scale: scale)
                        .resizable()
                        .frame(width: w, height: h)
                }
            }
            .frame(width: w, height: h)
            .task(id: CarromPlates.key(theme, w, h, scale)) {
                if w >= 1 && CarromPlates.cached(theme, w, h, scale) == nil {
                    _ = CarromPlates.plate(theme, w, h, scale)
                    rendered += 1
                }
            }
        }
    }
}

/// Coins, the striker, the aim guide and effects. Redraws every frame only while something moves.
private struct CarromPieceLayer: View {
    let session: CarromSession
    let coins: CarromCoinSet
    let striker: CarromStrikerStyle

    @Environment(\.displayScale) private var scale
    @State private var rendered = 0
    @State private var wake = 0

    var body: some View {
        let snap = carromSnapshot(session)
        let animating = session.animating()
        let end = session.animationEnd
        let token = wake &+ rendered
        GeometryReader { geo in
            let size = geo.size
            let m = CarromMetrics(size.width, size.height)
            let rc = m.len(CarromBoard.coinR)
            let rs = m.len(CarromBoard.strikerR)
            let sprites = lookup(rc, rs)
            TimelineView(.animation(minimumInterval: nil, paused: !animating)) { tl in
                // Capture the tick inside the closure: SwiftUI skips a Canvas whose captures look unchanged.
                let date = tl.date
                Canvas { ctx, _ in
                    _ = date
                    _ = token
                    guard let sprites, size.width >= 1 else { return }
                    CarromPieceArt.draw(ctx, m, snap, carromNow(), sprites)
                }
            }
            .task(id: "\(coins.id)-\(striker.id)-\(Int(rc * 100))-\(Int(rs * 100))-\(scale)") {
                if size.width >= 1 && lookup(rc, rs) == nil {
                    _ = CarromSprites.coin(.WHITE, coins, rc, scale)
                    _ = CarromSprites.coin(.BLACK, coins, rc, scale)
                    _ = CarromSprites.coin(.QUEEN, coins, rc, scale)
                    _ = CarromSprites.striker(striker, rs, scale)
                    rendered += 1
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: end) {
            let wait = end - carromNow()
            if wait > 0 && wait < 60 { try? await Task.sleep(nanoseconds: UInt64((wait + 0.02) * 1_000_000_000)) }
            if !Task.isCancelled { wake += 1 }
        }
    }

    private func lookup(_ rc: CGFloat, _ rs: CGFloat) -> PieceSprites? {
        guard let w = CarromSprites.cached(CarromSprites.coinKey(.WHITE, coins, rc, scale)),
              let b = CarromSprites.cached(CarromSprites.coinKey(.BLACK, coins, rc, scale)),
              let q = CarromSprites.cached(CarromSprites.coinKey(.QUEEN, coins, rc, scale)),
              let s = CarromSprites.cached(CarromSprites.strikerKey(striker, rs, scale)) else { return nil }
        return PieceSprites(white: w, black: b, queen: q, striker: s, scale: scale)
    }
}

@MainActor
private func carromSnapshot(_ session: CarromSession) -> PieceSnapshot {
    let seat = session.currentSeat
    let showStriker = session.playback == nil && session.replay == nil && (session.phase == .READY || session.phase == .AIMING)
    let ring: CarromColor = session.blocked ? CarromColor(0xFF3B30) : (seat.isBot ? CarromColor.player(seat.player) : CarromColor.white.opacity(0.75))
    return PieceSnapshot(
        coins: session.table.coins,
        playback: session.replay ?? session.playback,
        introStart: session.introStart,
        effects: session.effects,
        striker: showStriker ? session.strikerPoint : nil,
        ring: showStriker ? ring : nil,
        aim: session.aim,
        guide: session.guide,
        counter: -Double(session.viewTurns) * 90,
        hideCoins: session.phase == .INTRO && session.introStart == nil && session.table.strokes == 0
    )
}

/// Names along each occupied side of the frame, upright whichever way the board is turned.
private struct CarromSideLabels: View {
    let session: CarromSession
    let side: CGFloat

    var body: some View {
        let frame = side * 0.07
        let fontSize = Swift.max(8, frame * 0.42)
        let seats = session.config.seats
        let turn = session.table.turn
        let over = session.phase == .OVER
        let viewSide = session.viewSide
        ZStack(alignment: .topLeading) {
            ForEach(Array(seats.enumerated()), id: \.element.id) { index, seat in
                // The board turns clockwise by viewSide quarter turns, so side s shows at s − viewSide.
                let shown = (seat.side - viewSide + 4) % 4
                let active = index == turn && !over
                let half = frame / 2
                let full = side
                let pos: CGPoint = {
                    switch shown {
                    case 0: return CGPoint(x: full / 2, y: full - half)
                    case 1: return CGPoint(x: full - half, y: full / 2)
                    case 2: return CGPoint(x: full / 2, y: half)
                    default: return CGPoint(x: half, y: full / 2)
                    }
                }()
                let rot: Double = [0, -90, 0, 90][shown]
                let c = CarromColor.player(seat.player)
                Text(seat.player.name.uppercased(), style: bodyStyle(fontSize, .Black, active ? CarromColor(0x2B1606).color : Color.White.copy(alpha: 0.85)).copy(letterSpacing: 0.5))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, frame * 0.4)
                    .frame(height: frame * 0.72)
                    .background {
                        if active {
                            Capsule().fill(LinearGradient(colors: [c.mix(.white, 0.15).color, c.color], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipShape(Capsule())
                    .background {
                        if active { Capsule().fill(c.color).composeShadow(6, color: c.color) }
                    }
                    .rotationEffect(.degrees(rot))
                    .position(x: pos.x, y: pos.y)
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35), value: shown)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}

private struct CarromModeTab: View {
    let text: String

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12, style: .circular)
        Text(text, style: bodyStyle(12, .Black, CarromColor(0xFFE9B0).color).copy(letterSpacing: 1))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .frame(height: 26)
            .background(LinearGradient(colors: [CarromColor(0x7A3A14).color, CarromColor(0x4A1E08).color], startPoint: .top, endPoint: .bottom))
            .clipShape(shape)
            .overlay(shape.strokeBorder(CarromColor(0xF5C24C).color, lineWidth: 1.5))
    }
}

// MARK: - Around the board

struct CarromBackdrop: View {
    let theme: CarromBoardTheme

    var body: some View {
        Canvas { ctx, size in
            let centre = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            let end: CGFloat = 620
            let start: CGFloat = 20
            let stops = Gradient(stops: [
                .init(color: theme.backdrop[0].color, location: 0),
                .init(color: theme.backdrop[0].color, location: start / end),
                .init(color: theme.backdrop[1].color, location: 1),
            ])
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(stops, center: centre, startRadius: 0, endRadius: end))
            var rng = CarromRandom(4)
            var stars = Path()
            for _ in 0..<26 {
                let cx = CGFloat(rng.unit()) * size.width
                let cy = CGFloat(rng.unit()) * size.height
                let r = CGFloat(20 + rng.unit() * 46)
                stars.addPath(CarromArt.star(cx, cy, 8, r, r * 0.62))
            }
            ctx.stroke(stars, with: .color(Color.white.opacity(0.045)), lineWidth: 1.2)
        }
        .allowsHitTesting(false)
    }
}

/// The wooden slider under the board: drag the thumb to place the striker, double-tap to centre.
private struct CarromSliderBar: View {
    let session: CarromSession
    let striker: CarromStrikerStyle

    @State private var gestureActive = false
    @GestureState private var touching = false
    @State private var ignored = false
    @State private var moved = false
    @State private var lastTap: Double = 0

    var body: some View {
        let active = session.sliderActive
        let slide = session.slide
        let blocked = session.blocked
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = 40
            let inset: CGFloat = 22
            let x = inset + (w - 2 * inset) * CGFloat((slide + 1) / 2)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let barTop = (h - 32) / 2
                    let bar = CGRect(x: 0, y: barTop, width: size.width, height: 32)
                    ctx.fill(Path(roundedRect: bar.offsetBy(dx: 0, dy: 3), cornerRadius: 16, style: .circular), with: .color(Color.black.opacity(0.4)))
                    ctx.fill(Path(roundedRect: bar, cornerRadius: 16, style: .circular),
                             with: .linearGradient(Gradient(colors: [CarromColor(0xE8B37A).color, CarromColor(0xB4733E).color]),
                                                   startPoint: CGPoint(x: 0, y: barTop), endPoint: CGPoint(x: 0, y: barTop + 32)))
                    ctx.stroke(Path(roundedRect: CGRect(x: 1, y: barTop + 1, width: size.width - 2, height: 30), cornerRadius: 15, style: .circular),
                               with: .color(CarromColor(0x5A2E10).opacity(0.7).color), lineWidth: 2)
                    ctx.fill(Path(roundedRect: CGRect(x: 18, y: h / 2 - 2.5, width: size.width - 36, height: 5), cornerRadius: 2.5, style: .circular),
                             with: .color(CarromColor(0x5A2E10).opacity(0.35).color))
                }
                .frame(width: w, height: h)
                CarromStrikerSprite(style: striker, radius: 15)
                    .position(x: x, y: h / 2)
                if blocked {
                    Circle().stroke(CarromColor(0xFF3B30).color, lineWidth: 2.5)
                        .frame(width: 38, height: 38)
                        .position(x: x, y: h / 2)
                }
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { v in
                        if !gestureActive {
                            gestureActive = true
                            moved = false
                            ignored = !session.sliderActive
                            if ignored { return }
                            slideAt(v.startLocation.x, w, inset)
                        }
                        if ignored { return }
                        if hypot(v.translation.width, v.translation.height) > 8 { moved = true }
                        if v.translation != .zero { slideAt(v.location.x, w, inset) }
                    }
                    .onEnded { _ in
                        gestureActive = false
                        if ignored { return }
                        if !moved {
                            let now = carromNow()
                            if now - lastTap < 0.3 {
                                session.slideTo(0.0)
                                lastTap = 0
                            } else {
                                lastTap = now
                            }
                        }
                    }
            )
        }
        .onChange(of: touching) { _, now in
            if !now { gestureActive = false }
        }
        .frame(height: 40)
        .padding(.horizontal, 30)
        .opacity(active ? 1 : 0.35)
        .animation(.linear(duration: 0.2), value: active)
        .accessibilityElement()
        .accessibilityLabel("Striker position, \(Kt.toInt((slide + 1) * 50)) percent from the left")
    }

    private func slideAt(_ px: CGFloat, _ w: CGFloat, _ inset: CGFloat) {
        session.slideTo(Double((px - inset) / (w - 2 * inset)) * 2 - 1)
    }
}

/// Players and their tallies, above the board.
private struct CarromPlayersHeader: View {
    let session: CarromSession
    let coins: CarromCoinSet

    var body: some View {
        let seats = session.config.seats
        if seats.count == 2 {
            HStack(spacing: 0) {
                HeaderPlayer(session: session, coins: coins, index: 0, trailing: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HeaderCentre(session: session)
                HeaderPlayer(session: session, coins: coins, index: 1, trailing: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
        } else {
            HStack(spacing: 6) {
                ForEach(seats.indices, id: \.self) { i in
                    HeaderChip(session: session, coins: coins, index: i)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
        }
    }
}

@MainActor
private func isActive(_ session: CarromSession, _ index: Int) -> Bool {
    index == session.table.turn && session.phase != .OVER && session.phase != .BETWEEN
}

private struct HeaderCentre: View {
    let session: CarromSession

    var body: some View {
        let m = session.match
        VStack(spacing: 0) {
            if m.length == .ONE {
                Text(m.mode == .FREESTYLE ? "\(session.table.target)" : "Board", style: displayStyle(20, Royal.Gold))
                Text(m.mode == .FREESTYLE ? "TO WIN" : m.mode.title.uppercased(), style: bodyStyle(9, .ExtraBold, Royal.Smoke).copy(letterSpacing: 1))
            } else {
                Text("\(m.scores[0]) – \(m.scores[1])", style: displayStyle(22, Royal.Gold))
                Text(m.length == .RACE25 ? "FIRST TO 25" : "BEST OF 3", style: bodyStyle(9, .ExtraBold, Royal.Smoke).copy(letterSpacing: 1))
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct HeaderPlayer: View {
    let session: CarromSession
    let coins: CarromCoinSet
    let index: Int
    let trailing: Bool

    var body: some View {
        let seat = session.config.seats[index]
        let active = isActive(session, index)
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 8) {
                if trailing { PlayerName(seat: seat) }
                CarromAvatar(seat: seat, size: 46, active: active, clockEnds: active ? session.clockEnds : nil, seconds: session.config.options.clockSeconds)
                if !trailing { PlayerName(seat: seat) }
            }
            Tally(session: session, coins: coins, unit: session.table.unit(index))
        }
    }
}

private struct PlayerName: View {
    let seat: CarromSeat

    var body: some View {
        Text(seat.player.name, style: bodyStyle(14, .ExtraBold, Color.White))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 96, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct HeaderChip: View {
    let session: CarromSession
    let coins: CarromCoinSet
    let index: Int

    var body: some View {
        let seat = session.config.seats[index]
        let t = session.table
        let unit = t.unit(index)
        let active = isActive(session, index)
        let shape = RoundedCornerShape(16)
        let border: Color = t.teams ? (unit == 0 ? CarromColor(0xFFF3D6).color : CarromColor(0x2B2B2B).color) : .clear
        VStack(spacing: 3) {
            CarromAvatar(seat: seat, size: 38, active: active, clockEnds: active ? session.clockEnds : nil, seconds: session.config.options.clockSeconds)
            Text(seat.player.name, style: bodyStyle(11, .ExtraBold, Color.White))
                .lineLimit(1)
                .truncationMode(.tail)
            Tally(session: session, coins: coins, unit: unit)
                .scaleEffect(0.85)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(active ? 0.32 : 0.16))
        .clipShape(shape)
        .overlay(shape.strokeBorder(border, lineWidth: 2))
    }
}

private struct Tally: View {
    let session: CarromSession
    let coins: CarromCoinSet
    let unit: Int

    var body: some View {
        let t = session.table
        if t.mode == .FREESTYLE {
            Text("\(t.points[unit]) pts", style: displayStyle(14, Royal.Gold))
        } else {
            let colour = t.colour(unit)
            HStack(spacing: 4) {
                CarromCoinIcon(kind: colour, set: coins, size: 16)
                Text("\(t.pocketed(colour))/9", style: bodyStyle(13, .ExtraBold, Color.White))
                if t.queenCoveredBy == unit { CarromCoinIcon(kind: .QUEEN, set: coins, size: 16) }
            }
        }
    }
}

/// A seat's avatar disc, with the active glow, the shot-clock ring and a CPU tag.
struct CarromAvatar: View {
    let seat: CarromSeat
    let size: CGFloat
    let active: Bool
    var clockEnds: Double? = nil
    var seconds: Int = 0

    init(seat: CarromSeat, size: CGFloat, active: Bool, clockEnds: Double? = nil, seconds: Int = 0) {
        self.seat = seat
        self.size = size
        self.active = active
        self.clockEnds = clockEnds
        self.seconds = seconds
    }

    var body: some View {
        let c = CarromColor.player(seat.player)
        let glow: CGFloat = active ? 1 : 0
        ZStack {
            if let clockEnds, seconds > 0 {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let left = Swift.max(0, Swift.min(1, Swift.max(0.0, clockEnds - carromNow()) / Double(seconds)))
                    Circle()
                        .trim(from: 0, to: CGFloat(left))
                        .stroke(left < 0.3 ? CarromColor(0xFF3B30).color : CarromColor(0x34C759).color,
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.75)
                        .frame(width: size + 8, height: size + 8)
                        .offset(y: 4)
                }
            }
            ZStack {
                Circle().fill(LinearGradient(colors: [c.mix(.white, 0.18).color, c.color, c.mix(.black, 0.12).color], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(active ? CarromColor(0xFFE45C).color : Color.White.copy(alpha: 0.85), lineWidth: active ? 3 : 2)
                Text(seat.player.avatar).font(.system(size: size * 0.5))
            }
            .frame(width: size, height: size)
            .background(
                Circle().fill(CarromColor(0xFFE45C).color)
                    .shadow(color: CarromColor(0xFFE45C).color.opacity(0.9 * glow), radius: 10 * 0.55 * glow, x: 0, y: 0)
                    .opacity(Double(glow))
            )
            .animation(.compose(dampingRatio: 0.7, stiffness: 600), value: active)
            if seat.isBot {
                Text("CPU", style: bodyStyle(7, .Black, Color.White))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(CarromColor(0x1C1B29).color))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 2)
            }
        }
        .frame(width: size + 10, height: size + 10)
    }
}

/// A rendered sprite (coin or striker) at its full padded size, centred on the view's centre.
struct CarromSpriteImage: View {
    enum Piece: Hashable {
        case coin(CarromKind, Int, CarromColor?)
        case striker(Int)
    }

    let piece: Piece
    let radius: CGFloat

    @Environment(\.displayScale) private var scale
    @State private var rendered = 0

    private var key: String {
        switch piece {
        case .coin(let kind, let set, let glow): return CarromSprites.coinKey(kind, CarromCoinSet.set(set), radius, scale, glow: glow)
        case .striker(let id): return CarromSprites.strikerKey(CarromStrikerStyle.style(id), radius, scale)
        }
    }

    var body: some View {
        let side = 2 * radius * CarromSprites.PAD
        let _ = rendered
        ZStack {
            if let image = CarromSprites.cached(key) {
                Image(decorative: image, scale: scale).resizable().frame(width: side, height: side)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .task(id: key) {
            if CarromSprites.cached(key) == nil {
                switch piece {
                case .coin(let kind, let set, let glow): _ = CarromSprites.coin(kind, CarromCoinSet.set(set), radius, scale, glow: glow)
                case .striker(let id): _ = CarromSprites.striker(CarromStrikerStyle.style(id), radius, scale)
                }
                rendered += 1
            }
        }
    }
}

/// The striker sprite at [radius].
struct CarromStrikerSprite: View {
    let style: CarromStrikerStyle
    let radius: CGFloat

    var body: some View {
        CarromSpriteImage(piece: .striker(style.id), radius: radius)
            .frame(width: 0, height: 0)
    }
}

/// A coin from a set, as a small icon.
struct CarromCoinIcon: View {
    let kind: CarromKind
    let set: CarromCoinSet
    let size: CGFloat

    var body: some View {
        let r = size * 0.42
        ZStack {
            CarromSpriteImage(piece: .coin(kind, set.id, nil), radius: r)
                .frame(width: 0, height: 0)
                .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

/// Below the board: each side's pocketed coins in a wooden tray, or the race to the target.
private struct CarromTrays: View {
    let session: CarromSession
    let coins: CarromCoinSet

    var body: some View {
        let t = session.table
        if t.mode == .FREESTYLE {
            VStack(spacing: 6) {
                ForEach(0..<t.units, id: \.self) { unit in RaceBar(session: session, unit: unit) }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedCornerShape(18))
        } else {
            HStack(spacing: 8) {
                Tray(session: session, coins: coins, unit: 0).frame(maxWidth: .infinity)
                Tray(session: session, coins: coins, unit: 1).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct RaceBar: View {
    let session: CarromSession
    let unit: Int

    var body: some View {
        let t = session.table
        let seat = session.config.seats[session.seats(unit).first ?? 0]
        let share = CGFloat(Swift.min(1, Float(t.points[unit]) / Float(t.target)))
        let c = CarromColor.player(seat.player)
        HStack(spacing: 8) {
            Text(t.teams ? (unit == 0 ? "◻︎" : "◼︎") : seat.player.avatar)
                .font(.system(size: 15))
                .frame(width: 22)
                .multilineTextAlignment(.center)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.25))
                    Capsule()
                        .fill(LinearGradient(colors: [c.mix(.white, 0.2).color, c.color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: Swift.max(12, geo.size.width * share))
                        .animation(.compose(dampingRatio: 0.8, stiffness: 200), value: share)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            Text("\(t.points[unit]) / \(t.target)", style: bodyStyle(12, .ExtraBold, Color.White.copy(alpha: 0.85), .End))
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.unitName(unit)): \(t.points[unit]) of \(t.target) points")
    }
}

private struct Tray: View {
    let session: CarromSession
    let coins: CarromCoinSet
    let unit: Int

    var body: some View {
        let t = session.table
        let colour = t.colour(unit)
        let count = t.pocketed(colour)
        let covered = t.queenCoveredBy == unit
        let shape = RoundedCornerShape(16)
        VStack(alignment: .leading, spacing: 3) {
            Text(session.unitName(unit).uppercased(), style: bodyStyle(10, .Black, Color.White.copy(alpha: 0.7)).copy(letterSpacing: 1))
                .lineLimit(1)
                .truncationMode(.tail)
            GeometryReader { geo in
                let wPt = geo.size.width
                let r = Swift.min(8.5, (wPt - 24) / 10.5)
                ZStack(alignment: .topLeading) {
                    if r > 0 {
                        ForEach(0..<9, id: \.self) { i in
                            let x = r + 3 + CGFloat(i % 5) * (r * 2.2)
                            let y = r + 2 + CGFloat(i / 5) * (r * 2.1)
                            if i < count {
                                CarromSpriteImage(piece: .coin(colour, coins.id, nil), radius: r)
                                    .position(x: x, y: y)
                            } else {
                                Circle()
                                    .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    .frame(width: 2 * r, height: 2 * r)
                                    .position(x: x, y: y)
                            }
                        }
                        if covered {
                            CarromSpriteImage(piece: .coin(.QUEEN, coins.id, CarromColor(0xFFD24D)), radius: 10)
                                .position(x: wPt - 14, y: 20)
                        }
                    }
                }
                .frame(width: wPt, height: 40)
            }
            .frame(height: 40)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [CarromColor(0x8A5428).color, CarromColor(0x5A3214).color], startPoint: .top, endPoint: .bottom))
        .clipShape(shape)
        .overlay(shape.strokeBorder(CarromColor(0xE8B37A).opacity(0.5).color, lineWidth: 1.5))
        .background(shape.fill(CarromColor(0x5A3214).color).composeShadow(6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.unitName(unit)): \(count) of 9 \(colour == .WHITE ? "white" : "black") pocketed\(covered ? ", queen covered" : "")")
    }
}

// MARK: - Overlays

private struct CarromBannerView: View {
    let banner: CarromBanner

    var body: some View {
        let tint = banner.tint
        HStack(spacing: 8) {
            CarromIconView(bannerIcon(banner.icon), tint: Color.White, size: 24)
            Text(banner.text, style: displayStyle(24, Color.White))
                .shadow(color: Color.black.opacity(0.4), radius: 0, x: 0, y: 4 / 3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Capsule().fill(LinearGradient(colors: [tint.mix(.white, 0.15).color, tint.mix(.black, 0.2).color], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(Color.White.copy(alpha: 0.6), lineWidth: 2))
        .clipShape(Capsule())
        .background(Capsule().fill(tint.color).composeShadow(16, color: tint.color))
        .rotationEffect(.degrees(-3))
    }
}

/// A coin flips to decide who breaks.
private struct CarromTossView: View {
    let toss: CarromToss
    let name: String
    let coins: CarromCoinSet

    @State private var start = carromNow()

    var body: some View {
        let reduce = LocalReduceMotion.current
        VStack(spacing: 14) {
            TimelineView(.animation(paused: reduce)) { _ in
                let t = carromNow() - start
                let spin = reduce ? 1.0 : Foundation.cos(Swift.min(t, 1.0) * Double.pi * 7)
                let lift = reduce ? 0.0 : -Foundation.sin(Swift.min(t, 1.0) * Double.pi) * 40
                let kind: CarromKind = spin >= 0 ? .WHITE : .BLACK
                ZStack {
                    CarromSpriteImage(piece: .coin(kind, coins.id, nil), radius: 34)
                        .frame(width: 0, height: 0)
                }
                .frame(width: 90, height: 90)
                .scaleEffect(x: CGFloat(Swift.max(0.06, Swift.abs(spin))), y: 1)
                .offset(y: CGFloat(lift))
            }
            Text("\(name) breaks!", style: displayStyle(26, Color.White))
        }
        .padding(26)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedCornerShape(30))
        .onAppear { start = carromNow() }
    }
}

/// Between boards of a longer match.
private struct CarromBoardCard: View {
    let session: CarromSession
    let onNext: () -> Void

    var body: some View {
        let m = session.match
        let w = m.table.winner ?? 0
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().contentShape(Rectangle()).onTapGesture {}
            WoodPanel(padding: 24) {
                VStack(spacing: 14) {
                    Text("BOARD \(m.board)", style: bodyStyle(13, .ExtraBold, Royal.Gold).copy(letterSpacing: 1.6))
                    Text("\(session.unitName(w)) takes it!", style: displayStyle(26, Royal.Ivory, .Center))
                        .multilineTextAlignment(.center)
                    Text(m.mode == .FREESTYLE ? "\(m.table.boardPoints) points" : "+\(m.table.boardPoints) point\(m.table.boardPoints == 1 ? "" : "s")",
                         style: bodyStyle(17, .ExtraBold, Royal.GoldLight))
                    HStack(spacing: 20) {
                        ForEach(0..<m.units, id: \.self) { unit in
                            VStack(spacing: 0) {
                                Text(m.length == .BEST_OF_THREE ? "\(m.wins[unit])" : "\(m.scores[unit])", style: displayStyle(30, Royal.Ivory))
                                Text(session.unitName(unit), style: bodyStyle(12, .ExtraBold, Royal.Smoke)).lineLimit(1)
                            }
                        }
                    }
                    Text(m.length == .BEST_OF_THREE ? "Boards won · best of 3" : "Points · first to 25", style: bodyStyle(12, .Bold, Royal.Smoke))
                    CandyButton("Next board", onNext, height: 54, fontSize: 20)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 28)
        }
    }
}

private func pauseRules(_ mode: CarromMode, _ tournament: Bool, _ practice: Bool = false) -> [(CarromIcon, String)] {
    if practice {
        return [
            (.vector(Icons.Rounded.PanTool), "Slide the striker along your base line, then pull back from it and let go to shoot."),
            (.vector(Icons.Rounded.Adjust), "Practice board: no turns, no fouls and no score. Shoot as often as you like."),
            (.vector(Icons.Rounded.Refresh), "Tap Re-rack to put every coin back in the centre."),
            (.vector(Icons.Rounded.Replay), "Tap Replay after a shot to watch it again in slow motion."),
        ]
    }
    let common: [(CarromIcon, String)] = [
        (.vector(Icons.Rounded.PanTool), "Slide the striker along your base line, then pull back from it and let go to shoot."),
        (.vector(Icons.Rounded.Refresh), "Pocket something you're allowed to and you shoot again."),
    ]
    switch mode {
    case .CLASSIC:
        return common + [
            (.vector(Icons.Rounded.Contrast), "Pocket your own colour. The other colour counts for them and ends your turn."),
            (.crown, "Pocket the Queen once you've pocketed one of yours, then cover her with one of yours the same shot or the next."),
            (.vector(Icons.Rounded.Warning), "Pocketing the striker is a foul: one of your coins comes back."),
            (.vector(Icons.Rounded.Flag), tournament ? "Clear your colour before the Queen and you lose the board." : "The Queen must be covered before your last coin, or it comes back."),
            (.vector(Icons.Rounded.EmojiEvents), "Clear your colour to win: you score their coins left, plus 3 for the Queen if you covered her."),
        ]
    case .POOL:
        return common + [
            (.vector(Icons.Rounded.Contrast), "Pocket your own colour. The other colour counts for them and ends your turn."),
            (.vector(Icons.Rounded.Warning), "Pocketing the striker is a foul: one of your coins comes back."),
            (.vector(Icons.Rounded.EmojiEvents), "Clear your colour first to win the board."),
        ]
    case .FREESTYLE:
        return common + [
            (.vector(Icons.Rounded.Star), "Any coin scores: white 20, black 10, Queen 50."),
            (.crown, "The Queen needs a cover: pocket any coin the same shot or the next."),
            (.vector(Icons.Rounded.Warning), "Pocketing the striker is a foul: −10 points."),
            (.vector(Icons.Rounded.EmojiEvents), "First to the target wins, or the highest score when the board is clear."),
        ]
    }
}

/// Pause: resume, the rules in short, restart or save and quit.
private struct CarromPauseCard: View {
    let mode: CarromMode
    let tournament: Bool
    var practice: Bool = false
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { onResume() }
            WoodPanel(padding: 20) {
                // Hugs its content; scrolls only when the screen is too short (Compose `verticalScroll`).
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView(.vertical, showsIndicators: false) { content }
                }
            }
            .frame(maxWidth: 480)
            .contentShape(Rectangle())
            .onTapGesture {}
            .padding(20)
        }
    }

    private var content: some View {
        let soundOn = AppSettings.data.soundEnabled
        return VStack(alignment: .leading, spacing: 14) {
            Text("Paused", style: displayStyle(28, Royal.Gold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(pauseRules(mode, tournament, practice).enumerated()), id: \.offset) { _, rule in
                    HStack(alignment: .top, spacing: 10) {
                        CarromIconView(rule.0, tint: Royal.Gold, size: 18).offset(y: 1)
                        Text(rule.1, style: bodyStyle(14, .SemiBold, Royal.Ivory.copy(alpha: 0.85)))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack(spacing: 0) {
                Icon(Icons.AutoMirrored.Rounded.VolumeUp, nil, tint: Royal.Gold, size: 20)
                Spacer().frame(width: 10)
                Text("Sound effects", style: bodyStyle(15, .Bold)).frame(maxWidth: .infinity, alignment: .leading)
                RoyalSwitch(soundOn, { v in AppSettings.update { $0.copy(soundEnabled: v) } }, label: "Sound effects")
            }
            CandyButton("Resume", onResume, height: 54, fontSize: 20)
            HStack(spacing: 10) {
                OutlineButton("Restart", onRestart, icon: Icons.Rounded.Refresh, fill: true)
                OutlineButton("Save & quit", onQuit, icon: Icons.Rounded.Save, fill: true)
            }
        }
    }
}

/// The winner, the points and everyone's stats.
private struct CarromResultsView: View {
    let session: CarromSession
    let onRematch: () -> Void
    let onSetup: () -> Void
    let onHub: () -> Void

    @State private var risen: CGFloat = LocalReduceMotion.current ? 1 : 0.4

    var body: some View {
        let m = session.match
        let w = m.winner ?? 0
        let winners = session.seats(w).map { session.config.seats[$0] }
        let reduce = LocalReduceMotion.current
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().contentShape(Rectangle()).onTapGesture {}
            GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    WoodPanel(padding: 22) {
                        VStack(spacing: 14) {
                            Text(m.length == .ONE ? "BOARD WON" : "MATCH WON", style: bodyStyle(13, .ExtraBold, Royal.Gold).copy(letterSpacing: 2))
                            ZStack {
                                RotatingRays(color: CarromColor(0xFFE27A).color).frame(width: 170, height: 170)
                                Icon(Icons.Rounded.EmojiEvents, nil, tint: CarromColor(0xF7C948).color, size: 78)
                                    .scaleEffect(risen)
                                    .shadow(color: CarromColor(0xF0A21C).color.opacity(0.6), radius: 14 * 0.55, x: 0, y: 14 * 0.35)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 130)
                            HStack(spacing: -10) {
                                ForEach(Array(winners.enumerated()), id: \.offset) { _, seat in CarromAvatar(seat: seat, size: 56, active: true) }
                            }
                            Text("\(session.unitName(w)) win\(m.teams ? "" : "s")!", style: displayStyle(26, Royal.Ivory, .Center))
                                .multilineTextAlignment(.center)
                            ResultSummary(session: session)
                            VStack(spacing: 0) {
                                ForEach(session.config.seats.indices, id: \.self) { i in ResultRow(session: session, index: i) }
                            }
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedCornerShape(18))
                            HStack(spacing: 0) {
                                Icon(Icons.Rounded.Schedule, nil, tint: Royal.Smoke, size: 16)
                                Spacer().frame(width: 6)
                                Text("Time", style: bodyStyle(13, .Bold, Royal.Smoke)).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(Swift.max(1, Kt.roundToInt(session.elapsed / 60))) min", style: bodyStyle(13, .ExtraBold, Royal.Ivory))
                            }
                            .padding(.horizontal, 6)
                            CandyButton("Rematch", onRematch, icon: Icons.Rounded.Replay)
                            HStack(spacing: 10) {
                                OutlineButton("New setup", onSetup, icon: Icons.Rounded.Tune, fill: true)
                                OutlineButton("Games Hub", onHub, icon: Icons.Rounded.GridView, fill: true)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 18)
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            }
            if !reduce { Confetti(count: 120, durationMs: 4000).ignoresSafeArea() }
        }
        .task {
            if reduce { risen = 1; return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.compose(dampingRatio: 0.5, stiffness: 260)) { risen = 1 }
        }
    }
}

private struct ResultSummary: View {
    let session: CarromSession

    var body: some View {
        let m = session.match
        let t = m.table
        let w = m.winner ?? 0
        HStack(spacing: 14) {
            if m.length == .ONE && m.mode != .FREESTYLE {
                let left = t.left(t.colour(1 - w))
                let queen = t.boardPoints - left
                stat("\(left)", "coins left")
                if queen > 0 {
                    sign("+")
                    stat("\(queen)", "queen")
                }
                sign("=")
                stat("\(t.boardPoints)", "points")
            } else if m.length == .ONE {
                stat("\(t.points[w])", "points")
            } else {
                ForEach(0..<m.units, id: \.self) { unit in
                    stat(m.length == .BEST_OF_THREE ? "\(m.wins[unit])" : "\(m.scores[unit])", session.unitName(unit))
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value, style: displayStyle(28, Royal.Gold))
            Text(label, style: bodyStyle(11, .ExtraBold, Royal.Smoke)).lineLimit(1)
        }
    }

    private func sign(_ s: String) -> some View { Text(s, style: displayStyle(20, Royal.Smoke)) }
}

private struct ResultRow: View {
    let session: CarromSession
    let index: Int

    var body: some View {
        let seat = session.config.seats[index]
        let s = session.match.totals[index]
        let freestyle = session.match.mode == .FREESTYLE
        HStack(spacing: 10) {
            Text(seat.player.avatar).font(.system(size: 20))
            Text(seat.player.name, style: bodyStyle(14, .ExtraBold, Royal.Ivory))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if s.queens > 0 {
                CarromCrownShape().fill(Royal.Gold).frame(width: 14, height: 14).accessibilityLabel("Queen")
            }
            if s.bestCombo >= 2 { Text("×\(s.bestCombo)", style: bodyStyle(11, .ExtraBold, Royal.GoldLight)) }
            Text(freestyle ? "\(s.points) pts" : "\(s.coins) coin\(s.coins == 1 ? "" : "s")", style: bodyStyle(13, .Bold, Royal.Ivory.copy(alpha: 0.85)))
            if s.fouls > 0 { Text("\(s.fouls) foul\(s.fouls == 1 ? "" : "s")", style: bodyStyle(11, .ExtraBold, CarromColor(0xFF8A8A).color)) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
