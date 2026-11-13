import SwiftUI
import GameKit

private struct Page {
    let eyebrow: String
    let title: String
    let body: String
    let glow: Color
}

private let pages = [
    Page(eyebrow: "WELCOME TO THE TABLE", title: "Six classics.\nOne table.", body: "Pool, Ludo, Carrom, Chess, Snakes & Ladders and Tic-Tac-Toe, beautifully hand-drawn.", glow: Royal.Felt),
    Page(eyebrow: "PASS & PLAY", title: "Friends or bots.", body: "Up to six players on one device, or challenge computer rivals at your level.", glow: Royal.Sapphire),
    Page(eyebrow: "REAL FEEL", title: "Real physics.\nReal sound.", body: "Every break, flick and dice roll is simulated, with crisp sounds and haptics.", glow: Royal.FeltLight),
    Page(eyebrow: "ALMOST READY", title: "Who's playing?", body: "Pick a name and an avatar. You can change them any time in Settings.", glow: Royal.GoldDark),
]

/// Compose `HorizontalPager` state: continuous scroll position in pages, snapping with
/// `spring(stiffness = StiffnessMediumLow)` (critically damped), one page per fling.
@MainActor
@Observable
private final class PagerModel {
    let pageCount: Int
    private(set) var position: CGFloat = 0
    private let loop = GameLoop(preferredFPS: 120)
    @ObservationIgnored private var target: CGFloat = 0
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var dragStart: CGFloat? = nil

    init(pageCount: Int) {
        self.pageCount = pageCount
        loop.onTick = { [weak self] dt in self?.step(dt) }
    }

    var currentPage: Int { Int(min(CGFloat(pageCount - 1), max(0, position.rounded()))) }
    var currentPageOffsetFraction: CGFloat { position - CGFloat(currentPage) }

    func drag(_ translation: CGFloat, width: CGFloat) {
        if dragStart == nil {
            dragStart = position
            loop.stop()
        }
        position = min(CGFloat(pageCount - 1), max(0, dragStart! - translation / max(1, width)))
    }

    func endDrag(velocity v: CGFloat, width: CGFloat) {
        let base = Int((dragStart ?? position).rounded())
        dragStart = nil
        var t: Int
        if abs(v) > 400 {
            t = v < 0 ? base + 1 : base - 1
            // a fling never goes back past where the finger already is
            if v < 0 && CGFloat(t) < position.rounded(.down) { t = Int(position.rounded(.down)) }
            if v > 0 && CGFloat(t) > position.rounded(.up) { t = Int(position.rounded(.up)) }
        } else {
            t = Int(position.rounded())
        }
        t = min(base + 1, max(base - 1, t))
        animate(to: t, velocity: -v / max(1, width))
    }

    func animateScrollToPage(_ page: Int) { animate(to: page, velocity: 0) }

    private func animate(to page: Int, velocity v: CGFloat) {
        target = CGFloat(min(pageCount - 1, max(0, page)))
        velocity = v
        loop.start()
    }

    private func step(_ dt: Double) {
        let k: CGFloat = 400, c: CGFloat = 2 * 20
        let n = 4
        let h = CGFloat(dt) / CGFloat(n)
        var x = position
        for _ in 0..<n {
            velocity += (-k * (x - target) - c * velocity) * h
            x += velocity * h
        }
        if abs(x - target) < 0.0005 && abs(velocity) < 0.01 {
            x = target
            velocity = 0
            loop.stop()
        }
        position = min(CGFloat(pageCount - 1), max(0, x))
    }
}

struct OnboardingScreen: View {
    let onDone: () -> Void
    @State private var pager = PagerModel(pageCount: pages.count)
    @State private var name = AppSettings.data.playerName
    @State private var avatar = AppSettings.data.avatar

    private func finish() {
        AppSettings.update { $0.copy(playerName: name.trimmingCharacters(in: .whitespacesAndNewlines), avatar: avatar) }
        UiSound.play(.Fanfare)
        onDone()
    }

    var body: some View {
        let cur = pager.currentPage
        let next = min(cur + 1, pages.count - 1)
        let glow = lerp(pages[cur].glow, pages[next].glow, Float(min(1, max(0, pager.currentPageOffsetFraction))))
        RoyalBackground(glow: glow) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("BOARD GAMES", style: displayStyle(18, Royal.Gold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            // Like Compose's pager, only pages that are at least partly visible exist.
                            ZStack {
                                if abs(pager.position - CGFloat(index)) < 1 {
                                    pageView(index, width: w)
                                }
                            }
                            .frame(width: w, height: geo.size.height)
                        }
                    }
                    .offset(x: -pager.position * w)
                    .frame(width: w, height: geo.size.height, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { v in pager.drag(v.translation.width, width: w) }
                            .onEnded { v in pager.endDrag(velocity: v.velocity.width, width: w) }
                    )
                }
                .clipped()
                PagerDots(pages.count, cur)
                Spacer().frame(height: 18)
                let last = cur == pages.count - 1
                CandyButton(last ? "Let's Play" : "Next", {
                    if last { finish() } else { pager.animateScrollToPage(cur + 1) }
                })
                .padding(.horizontal, 24)
                Spacer().frame(height: 16)
            }
        }
        .onChange(of: pager.currentPage) { _, p in if p > 0 { UiSound.play(.Swoosh) } }
    }

    @ViewBuilder
    private func pageView(_ index: Int, width: CGFloat) -> some View {
        let page = pages[index]
        let offset = pager.position - CGFloat(index)
        VStack(spacing: 0) {
            ZStack {
                switch index {
                case 0: GameFan(isCurrent: pager.currentPage == index)
                case 1: FriendsOrBots()
                case 2: PoolBreakDemo(active: abs(offset) < 1)
                default: ProfilePicker(name: $name, avatar: $avatar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: offset * width * 0.35)
            Text(page.eyebrow, style: bodyStyle(12, .Black, Royal.Gold).copy(letterSpacing: 2))
            Spacer().frame(height: 8)
            Text(page.title, style: displayStyle(36, Royal.Ivory, .Center)).multilineTextAlignment(.center)
            Spacer().frame(height: 10)
            Text(page.body, style: bodyStyle(15, .SemiBold, Royal.Smoke, .Center))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 18)
        }
        .padding(.horizontal, 24)
        .opacity(Double(1 - min(1, abs(offset)) * 0.6))
    }
}

// MARK: - Page 1: fan of game cards

private struct GameFan: View {
    let isCurrent: Bool
    @State private var spreadStart: Date? = nil
    private static let spring = SpringCurve(dampingRatio: 0.55, stiffness: 120)

    var body: some View {
        let modules = GameRegistry.all
        GeometryReader { geo in
            let maxWidth = geo.size.width
            let card = min(maxWidth * 0.36, 150)
            TimelineView(.animation) { tl in
                let spread = CGFloat(spreadStart.map { GameFan.spring.value(tl.date.timeIntervalSince($0)) } ?? 0)
                let bob = bobOffset(amplitude: 5, periodMs: 1800, at: tl.date)
                ZStack {
                    RotatingRays(color: Royal.Gold).frame(width: maxWidth, height: maxWidth)
                    ForEach(Array(modules.enumerated()), id: \.element.kind) { i, m in
                        let t = CGFloat(i) - CGFloat(modules.count - 1) / 2
                        let angle = t * 13 * spread
                        let dx = t * 46 * spread
                        let dy = abs(t) * 14 * spread
                        FanCard(module: m, card: card)
                            .rotationEffect(.degrees(Double(angle)), anchor: UnitPoint(x: 0.5, y: 1.4))
                            .offset(x: dx, y: dy + (i % 2 == 0 ? bob : -bob))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .onAppear { if isCurrent { spreadStart = Date() } }
        .onChange(of: isCurrent) { _, now in if now { spreadStart = Date() } }
    }
}

private struct FanCard: View {
    let module: any BoardGameModule
    let card: CGFloat

    var body: some View {
        let shape = RoundedCornerShape(18)
        VStack(spacing: 0) {
            module.Artwork()
                .frame(width: card - 16, height: card - 16)
            Spacer().frame(height: 4)
            Text(module.kind.title, style: displayStyle(13, .white, .Center)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(width: card, height: card * 1.3, alignment: .top)
        .background(LinearGradient(colors: module.kind.accent, startPoint: .top, endPoint: .bottom))
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Royal.GoldLight, Royal.GoldDark], startPoint: .top, endPoint: .bottom), lineWidth: 2))
        .background(shape.fill(Royal.Night).composeShadow(16))
    }
}

// MARK: - Page 2: friends or bots

private struct FriendsOrBots: View {
    @State private var level = BotLevel.default

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Canvas { ctx, size in
                    let d = RoyalDraw(ctx, size)
                    let px: CGFloat = 1.0 / 3 // Android px
                    let tl = CGPoint(x: 10 * px, y: size.height * 0.2)
                    let sz = CGSize(width: size.width - 20 * px, height: size.height * 0.7)
                    d.oval(RoyalDraw.radial(Royal.feltColors, d.center, d.minDimension / 2), tl, sz)
                    d.oval(Royal.GoldMid, tl, sz, stroke: 6)
                }
                seat(0, PartyStyle.avatars[0], PartyStyle.color(0), -100, -40)
                seat(1, PartyStyle.avatars[1], PartyStyle.color(1), 100, -40)
                seat(2, PartyStyle.botAvatars[0], PartyStyle.color(3), -60, 55)
                seat(3, PartyStyle.botAvatars[1], PartyStyle.color(4), 60, 55)
                Text("VS", style: displayStyle(30, Royal.Gold))
            }
            .frame(width: 280, height: 190)
            Spacer().frame(height: 18)
            SectionLabel("Computer skill")
            Spacer().frame(height: 8)
            RoyalSegmented(BotLevel.entries, level, { v in
                level = v
                AppSettings.update { $0.copy(botLevel: v.ordinal) }
            }, { $0.title })
            .frame(maxWidth: 320)
        }
    }

    private func seat(_ i: Int, _ avatar: String, _ color: Color, _ x: CGFloat, _ y: CGFloat) -> some View {
        AvatarBadge(avatar, color, size: 58, isActive: i == 0)
            .bob(amplitude: 6, periodMs: 1500, inverted: i % 2 == 1)
            .offset(x: x, y: y)
    }
}

// MARK: - Page 3: live pool break

private final class Ball {
    var x: Float
    var y: Float
    let color: Color
    let stripe: Bool
    var vx: Float = 0
    var vy: Float = 0

    init(_ x: Float, _ y: Float, _ color: Color, _ stripe: Bool) {
        self.x = x
        self.y = y
        self.color = color
        self.stripe = stripe
    }
}

private let ASPECT: Float = 1.7
private let BALL_R: Float = 0.045

private func rack() -> [Ball] {
    let colors: [UInt32] = [0xFFF5C518, 0xFF1E5BD8, 0xFFE23B3B, 0xFF7A3FC1, 0xFFFF7F27, 0xFF1F9D55, 0xFF8B2E2E, 0xFF111111, 0xFFF5C518, 0xFF1E5BD8]
    var list = [Ball(0.22, 0.5, Color(argb: 0xFFFFFCF2), false)]
    let d = BALL_R * 2.02
    var k = 0
    for col in 0..<4 {
        for row in 0...col {
            list.append(Ball(0.68 + Float(col) * d * 0.866 / ASPECT, 0.5 + (Float(row) - Float(col) / 2) * d,
                             Color(argb: colors[k % colors.count]), k % 3 == 2))
            k += 1
        }
    }
    return list
}

/// Tiny elastic-ball sim. y is in table heights; x is a fraction of the width, so it is scaled by the aspect.
private func step(_ bs: [Ball], _ dt: Float) {
    let sub = 4
    let minD = BALL_R * 2
    for _ in 0..<sub {
        let h = dt / Float(sub)
        for b in bs {
            b.x += b.vx * h / ASPECT
            b.y += b.vy * h
            let f = 1 - 1.1 * h
            b.vx *= f
            b.vy *= f
            if (b.vx * b.vx + b.vy * b.vy).squareRoot() < 0.01 { b.vx = 0; b.vy = 0 }
            let rx = BALL_R / ASPECT
            if b.x < rx && b.vx < 0 { b.vx = -b.vx * 0.85; b.x = rx }
            if b.x > 1 - rx && b.vx > 0 { b.vx = -b.vx * 0.85; b.x = 1 - rx }
            if b.y < BALL_R && b.vy < 0 { b.vy = -b.vy * 0.85; b.y = BALL_R }
            if b.y > 1 - BALL_R && b.vy > 0 { b.vy = -b.vy * 0.85; b.y = 1 - BALL_R }
        }
        for i in bs.indices {
            for j in (i + 1)..<bs.count {
                let a = bs[i], b = bs[j]
                let dx = (b.x - a.x) * ASPECT
                let dy = b.y - a.y
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist >= 0.0001 && dist <= minD {
                    let nx = dx / dist, ny = dy / dist
                    let rel = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
                    if rel > 0 {
                        a.vx -= rel * nx; a.vy -= rel * ny
                        b.vx += rel * nx; b.vy += rel * ny
                        if rel > 0.4 { UiSound.play(.Tap) }
                    }
                    let push = (minD - dist) / 2
                    a.x -= nx * push / ASPECT; a.y -= ny * push
                    b.x += nx * push / ASPECT; b.y += ny * push
                }
            }
        }
    }
}

@MainActor
@Observable
private final class BreakDemo {
    private(set) var frame = 0
    @ObservationIgnored var balls: [Ball] = rack()
    private let loop = GameLoop(preferredFPS: 120)
    @ObservationIgnored private var elapsed: Float = 0
    @ObservationIgnored private var first = true

    init() {
        loop.maxDelta = 0.1
        loop.onTick = { [weak self] dt in self?.tick(dt) }
    }

    func start() {
        balls = rack()
        elapsed = 0
        first = true
        loop.start()
    }

    func stop() { loop.stop() }

    private func tick(_ realDt: Double) {
        let dt: Float = first ? 0 : min(0.033, Float(realDt))
        first = false
        elapsed += dt
        let bs = balls
        if elapsed > 0.6 && bs[0].vx == 0 && bs[0].vy == 0 && elapsed < 0.7 {
            bs[0].vx = 2.6
            bs[0].vy = 0.04
            UiSound.play(.Tap)
        }
        step(bs, dt)
        if elapsed > 4.8 { balls = rack(); elapsed = 0 }
        frame &+= 1
    }
}

private struct PoolBreakDemo: View {
    let active: Bool
    @State private var demo = BreakDemo()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.92
            let h = w / 1.7
            let rail: CGFloat = 10
            WoodPanel(corner: 22, rail: rail, padding: 0) {
                let tick = demo.frame
                let balls = demo.balls
                Canvas { ctx, size in
                    _ = tick // per-frame redraw: the changing value must be captured by the closure
                    let d = RoyalDraw(ctx, size)
                    d.rect(RoyalDraw.radial(Royal.feltColors, d.center, d.maxDimension * 0.7))
                    let pockets: [(CGFloat, CGFloat)] = [(0, 0), (0.5, 0), (1, 0), (0, 1), (0.5, 1), (1, 1)]
                    for (px, py) in pockets { d.circle(Color.black, size.height * 0.07, CGPoint(x: px * size.width, y: py * size.height)) }
                    d.line(Color.white.opacity(0.12), CGPoint(x: size.width * 0.25, y: 0), CGPoint(x: size.width * 0.25, y: size.height), 0.5)
                    let r = size.height * 0.045
                    for b in balls {
                        let c = CGPoint(x: CGFloat(b.x) * size.width, y: CGFloat(b.y) * size.height)
                        d.circle(Color.black.opacity(0.35), r, CGPoint(x: c.x + r * 0.25, y: c.y + r * 0.35))
                        if b.stripe {
                            d.circle(Color(argb: 0xFFF7F1E3), r, c)
                            d.rect(.color(b.color), CGPoint(x: c.x - r, y: c.y - r * 0.5), CGSize(width: r * 2, height: r))
                        } else {
                            d.circle(RoyalDraw.radial([lerp(b.color, Color.White, Float(0.35)), b.color, lerp(b.color, Color.Black, Float(0.45))],
                                                      CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), r * 1.4), r, c)
                        }
                        d.circle(Color.white.opacity(0.55), r * 0.28, CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4))
                    }
                    let cb = balls[0]
                    if cb.vx == 0 && cb.vy == 0 {
                        d.roundRect(RoyalDraw.horizontal([Color(argb: 0xFF3A200F), Color(argb: 0xFFE8C48A), Color(argb: 0xFFF7E7C6)], 0, size.width),
                                    CGPoint(x: CGFloat(cb.x) * size.width - size.width * 0.42, y: CGFloat(cb.y) * size.height - 3),
                                    CGSize(width: size.width * 0.38, height: 6), 3)
                    }
                }
                .frame(width: w - rail * 2, height: h - rail * 2)
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear { if active && !LocalReduceMotion.current { demo.start() } }
        .onChange(of: active) { _, now in
            if now && !LocalReduceMotion.current { demo.start() } else if !now { demo.stop() }
        }
        .onDisappear { demo.stop() }
    }
}

// MARK: - Page 4: profile

private struct ProfilePicker: View {
    @Binding var name: String
    @Binding var avatar: String
    @State private var popTick = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RotatingRays().frame(width: 170, height: 170)
                AvatarBadge(avatar, Royal.GoldMid, size: 96, isActive: true)
                    .keyframeAnimator(initialValue: 1.0, trigger: popTick) { content, s in
                        content.scaleEffect(s)
                    } keyframes: { _ in
                        MoveKeyframe(0.7)
                        SpringKeyframe(1.0, spring: Spring(mass: 1, stiffness: 400, damping: 2 * 0.4 * 400.0.squareRoot()))
                    }
            }
            Spacer().frame(height: 12)
            let shape = RoundedCornerShape(18)
            ZStack {
                if name.isEmpty {
                    Text("Your name", style: bodyStyle(20, .ExtraBold, Royal.SmokeDim, .Center))
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
                }
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
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(shape.fill(Color.black.opacity(0.4)))
            .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1.5))
            Spacer().frame(height: 14)
            RoyalFlowRow(spacing: 8, lineSpacing: 8, maxItemsInEachRow: 8, alignment: .center) {
                ForEach(PartyStyle.avatars, id: \.self) { a in
                    let on = a == avatar
                    Text(verbatim: a).font(.system(size: 20))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(on ? Royal.Gold.copy(alpha: 0.3) : Color.white.opacity(0.07)))
                        .overlay(Circle().strokeBorder(on ? Royal.Gold : .clear, lineWidth: on ? 2 : 0))
                        .clipShape(Circle())
                        .pressable(sound: .Pop, haptic: .Tick) { avatar = a }
                }
            }
        }
        .frame(maxWidth: 380)
        .onAppear { popTick += 1 }
        .onChange(of: avatar) { _, _ in popTick += 1 }
    }
}
