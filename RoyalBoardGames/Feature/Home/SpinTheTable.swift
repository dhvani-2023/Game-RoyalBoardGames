import SwiftUI
import GameKit

extension GameKind {
    fileprivate var glyph: String {
        switch self {
        case .POOL: "🎱"
        case .CARROM: "🎯"
        case .LUDO: "🎲"
        case .CHESS: "♛"
        case .SNAKES: "🐍"
        case .TIC_TAC_TOE: "❌"
        }
    }

    fileprivate var shortName: String {
        switch self {
        case .POOL: "POOL"
        case .CARROM: "CARROM"
        case .LUDO: "LUDO"
        case .CHESS: "CHESS"
        case .SNAKES: "SNAKES"
        case .TIC_TAC_TOE: "X · O"
        }
    }
}

/// Drives the wheel frame by frame: eased rotation, a tick + pointer flick at every wedge boundary, landing.
@MainActor
@Observable
private final class SpinModel {
    var rotation: Double = 0
    var kick: Double = 0
    var selected: Int = 0
    var spinning = false
    var landedTick = 0

    private let loop = GameLoop(preferredFPS: 120)
    @ObservationIgnored private var from = 0.0
    @ObservationIgnored private var to = 0.0
    @ObservationIgnored private var elapsed = 0.0
    @ObservationIgnored private var duration = 3.6
    @ObservationIgnored private var target = 0
    @ObservationIgnored private var kickVelocity = 0.0
    @ObservationIgnored private var lastBoundary = 0
    @ObservationIgnored private var count = 6
    private static let easing = CubicBezierEasing(0.1, 0.75, 0.18, 1)

    init() {
        loop.onTick = { [weak self] dt in self?.tick(dt) }
    }

    private var wedge: Double { 360.0 / Double(count) }

    func spin(count: Int, reduce: Bool) {
        if spinning { return }
        self.count = count
        spinning = true
        UiSound.play(.Whoosh)
        target = (selected + 1 + Int.random(in: 0..<(count - 1))) % count
        let current = rotation
        // Final angle must put wedge `target` under the pointer: rotation ≡ -target·wedge (mod 360).
        let want = ((-Double(target) * wedge - current).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let jitter = (Double.random(in: 0..<1) - 0.5) * wedge * 0.6
        from = current
        to = current + 360 * (reduce ? 1 : 5) + want + jitter
        duration = reduce ? 0.9 : 3.6
        elapsed = 0
        lastBoundary = boundary(current)
        loop.start()
    }

    private func boundary(_ r: Double) -> Int { Int(floor((r + wedge / 2) / wedge)) }

    private func tick(_ dt: Double) {
        if spinning {
            elapsed += dt
            let f = min(1, elapsed / duration)
            rotation = from + (to - from) * SpinModel.easing.transform(f)
            let b = boundary(rotation)
            if b != lastBoundary {
                lastBoundary = b
                UiSound.play(.Tap)
                Haptics.play(.Tick)
                kick = -18
                kickVelocity = 0
            }
            if f >= 1 {
                selected = target
                spinning = false
                landedTick += 1
                UiSound.play(.Coin)
                UiSound.play(.Sparkle)
                Haptics.play(.Success)
            }
        }
        // Pointer spring: Compose spring(dampingRatio = 0.35, stiffness = 900) back to 0.
        if kick != 0 || kickVelocity != 0 {
            let k = 900.0, c = 2 * 0.35 * 30.0
            let steps = 4
            let h = dt / Double(steps)
            for _ in 0..<steps {
                kickVelocity += (-k * kick - c * kickVelocity) * h
                kick += kickVelocity * h
            }
            if abs(kick) < 0.01 && abs(kickVelocity) < 0.05 { kick = 0; kickVelocity = 0 }
        }
        if !spinning && kick == 0 && kickVelocity == 0 { loop.stop() }
    }

    func stop() { loop.stop() }
}

/// "Spin the Table": a casino prize wheel with one wedge per game, chasing marquee lights and a gold
/// SPIN hub. The wheel decelerates with a tick per wedge, lands on a game, and the strip below offers
/// to play it. Replaces a plain poster carousel with something you play with.
struct SpinTheTable: View {
    let modules: [any BoardGameModule]
    let onPlay: (GameKind) -> Void
    @State private var model = SpinModel()

    init(modules: [any BoardGameModule], onPlay: @escaping (GameKind) -> Void) {
        self.modules = modules
        self.onPlay = onPlay
    }

    var body: some View {
        let shape = RoundedCornerShape(30)
        let kinds = modules.map(\.kind)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("CAN'T DECIDE?", style: bodyStyle(11, .Black, Royal.GoldLight).copy(letterSpacing: 2))
                    Text("Spin the Table", style: displayStyle(26, .white))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.spinning ? "Spinning…" : "Tap SPIN", style: bodyStyle(12, .ExtraBold, Color.white.opacity(0.75)))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.25))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            Spacer().frame(height: 10)

            ZStack {
                MarqueeLights(spinning: model.spinning)
                WheelFace(kinds: kinds)
                    .equatable()
                    .frame(width: 232, height: 232)
                    .overlay(LandingFlash(count: kinds.count, selected: model.selected, landedTick: model.landedTick, spinning: model.spinning))
                    .rotationEffect(.degrees(model.rotation))
                VStack(spacing: 0) {
                    PointerShape()
                        .frame(width: 34, height: 40)
                        .rotationEffect(.degrees(model.kick), anchor: UnitPoint(x: 0.5, y: 0.15))
                    Spacer(minLength: 0)
                }
                // hub
                ZStack {
                    Circle().fill(Royal.goldBrush)
                    Text("SPIN", style: displayStyle(20, Royal.WoodDark))
                }
                .frame(width: 66, height: 66)
                .pressable(enabled: !model.spinning, sound: .Pop, haptic: .Medium) {
                    model.spin(count: kinds.count, reduce: LocalReduceMotion.current)
                }
                .accessibilityLabel("Spin the wheel")
                .padding(6)
                .background(Circle().fill(LinearGradient(colors: [Royal.WoodLight, Royal.WoodDark], startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [Royal.GoldLight, Royal.GoldDark], startPoint: .top, endPoint: .bottom), lineWidth: 2).allowsHitTesting(false))
                .background(Circle().fill(Royal.Gold).composeShadow(14, color: Royal.Gold))
            }
            .frame(width: 270, height: 270)

            Spacer().frame(height: 12)
            ZStack {
                PickStrip(kind: kinds[model.selected], landed: model.landedTick > 0, enabled: !model.spinning) { onPlay($0) }
                    .id(model.selected)
                    .transition(.asymmetric(
                        insertion: .modifier(active: SlideFade(x: 0, y: 31, opacity: 0), identity: SlideFade(x: 0, y: 0, opacity: 1)),
                        removal: .modifier(active: SlideFade(x: 0, y: -31, opacity: 0), identity: SlideFade(x: 0, y: 0, opacity: 1))))
            }
            .animation(.compose(dampingRatio: 1, stiffness: 400), value: model.selected)
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(RadialGradient(colors: Royal.feltColors, center: .center, startRadius: 0, endRadius: 300))
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Royal.GoldLight, Royal.GoldDark], startPoint: .top, endPoint: .bottom), lineWidth: 2))
        .background(shape.fill(Royal.FeltDark).composeShadow(22))
        .onDisappear { model.stop() }
    }
}

private struct PickStrip: View {
    let kind: GameKind
    let landed: Bool
    let enabled: Bool
    let onPlay: (GameKind) -> Void

    var body: some View {
        let strip = RoundedCornerShape(22)
        HStack(spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient(colors: kind.accent, startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                Text(verbatim: kind.glyph).font(.system(size: 22))
            }
            .frame(width: 46, height: 46)
            Spacer().frame(width: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(landed ? "TONIGHT'S PICK" : "ON THE TABLE", style: bodyStyle(10, .Black, Royal.Gold).copy(letterSpacing: 1.5))
                Text(kind.title, style: displayStyle(19, .white)).lineLimit(1).minimumScaleFactor(0.7).truncationMode(.tail)
                Text(kind.playersLabel, style: bodyStyle(11, .Bold, Color.white.opacity(0.7)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CandyButton("Play", { onPlay(kind) }, icon: Icons.Rounded.PlayArrow, enabled: enabled, height: 44, fontSize: 18)
                .frame(width: 104)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.32))
        .clipShape(strip)
        .overlay(strip.strokeBorder(Royal.Gold.copy(alpha: 0.35), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

/// The wheel face, drawn once (its inputs never change) and spun with a cheap rotation.
private struct WheelFace: View, Equatable {
    let kinds: [GameKind]

    var body: some View {
        Canvas { ctx, size in
            let d = RoyalDraw(ctx, size)
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let n = kinds.count
            let wedge = 360.0 / Double(n)
            // outer wood + gold rim
            d.circle(RoyalDraw.vertical([Royal.WoodLight, Royal.WoodDark], c.y - r, c.y + r), r, c)
            d.circle(RoyalDraw.sweep([Royal.GoldLight, Royal.GoldDark, Royal.Gold, Royal.GoldDark, Royal.GoldLight], c), r * 0.93, c, stroke: r * 0.05)
            let face = r * 0.88
            for (i, k) in kinds.enumerated() {
                let start = -90 + Double(i) * wedge - wedge / 2
                let a = k.accent
                d.arc(RoyalDraw.radial([lerp(a[0], Color.White, Float(0.18)), a[0], lerp(a[1], Color.Black, Float(0.25))], c, face),
                      start, wedge, true, CGPoint(x: c.x - face, y: c.y - face), CGSize(width: face * 2, height: face * 2))
            }
            // gold dividers + rivets
            for i in 0..<n {
                let ang = (-90 + Double(i) * wedge - wedge / 2) * Double.pi / 180
                let end = CGPoint(x: c.x + CGFloat(cos(ang)) * face, y: c.y + CGFloat(sin(ang)) * face)
                d.line(Royal.GoldLight, c, end, r * 0.025)
                d.circle(Royal.GoldLight, r * 0.035, CGPoint(x: c.x + CGFloat(cos(ang)) * face * 0.97, y: c.y + CGFloat(sin(ang)) * face * 0.97))
            }
            // labels: glyph + short name along each wedge's centre line
            for (i, k) in kinds.enumerated() {
                d.rotated(Double(i) * wedge, c) { d in
                    d.ctx.draw(Text(verbatim: k.glyph).font(.system(size: r * 0.2)).foregroundColor(.white),
                               at: CGPoint(x: c.x, y: c.y - face * 0.86), anchor: .top)
                    d.ctx.draw(Text(verbatim: k.shortName).font(RoyalFonts.display(r * 0.11)).foregroundColor(.white),
                               at: CGPoint(x: c.x, y: c.y - face * 0.52), anchor: .top)
                }
            }
            // inner shading ring + gloss
            d.circle(RoyalDraw.radial([.clear, Color.black.opacity(0.28)], c, face), face, c)
            var gloss = Path()
            gloss.addRelativeArc(center: c, radius: face, startAngle: .degrees(200), delta: .degrees(140))
            gloss.closeSubpath()
            d.path(gloss, RoyalDraw.vertical([Color.white.opacity(0.22), .clear], c.y - face, c.y))
        }
    }
}

/// Landing flash on the chosen wedge (rotates with the wheel; kept off the cached face).
private struct LandingFlash: View {
    let count: Int
    let selected: Int
    let landedTick: Int
    let spinning: Bool

    var body: some View {
        Canvas { ctx, size in
            let d = RoyalDraw(ctx, size)
            let r = min(size.width, size.height) / 2 * 0.88
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let wedge = 360.0 / Double(count)
            d.arc(.color(Color.white.opacity(0.45)), -90 + Double(selected) * wedge - wedge / 2, wedge, true,
                  CGPoint(x: c.x - r, y: c.y - r), CGSize(width: r * 2, height: r * 2))
        }
        .opacity(spinning ? 0 : 1)
        .keyframeAnimator(initialValue: 0.0, trigger: landedTick) { content, g in
            content.opacity(g)
        } keyframes: { _ in
            MoveKeyframe(1.0)
            LinearKeyframe(0.0, duration: 1.4, timingCurve: .bezier(startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1)))
        }
        .allowsHitTesting(false)
    }
}

/// Ring of bulbs that chase around the wheel; faster while spinning.
private struct MarqueeLights: View {
    let spinning: Bool
    @State private var start = Date()

    var body: some View {
        let reduce = LocalReduceMotion.current
        let stepTime = spinning ? 0.1 : 0.3
        TimelineView(.periodic(from: start, by: stepTime)) { tl in
            let step = reduce ? 0 : Int(tl.date.timeIntervalSince(start) / stepTime) % 3
            Canvas { ctx, size in
                let d = RoyalDraw(ctx, size)
                let bulbs = 24
                let r = min(size.width, size.height) / 2 * 0.95
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for k in 0..<bulbs {
                    let a = Double(k) * 2 * Double.pi / Double(bulbs)
                    let p = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                    let on = (k + step) % 3 == 0
                    if on { d.circle(RoyalDraw.radial([Royal.GoldLight.copy(alpha: 0.7), .clear], p, 11), 11, p) }
                    d.circle(on ? Color(argb: 0xFFFFF4C9) : Color(argb: 0xFF7A5A2A), 3.6, p)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Gold pointer with a ruby gem, hanging over the top of the wheel.
private struct PointerShape: View {
    var body: some View {
        Canvas { ctx, size in
            let d = RoyalDraw(ctx, size)
            let w = size.width, h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.5, y: h))
            path.addCurve(to: CGPoint(x: 0, y: h * 0.28), control1: CGPoint(x: w * 0.15, y: h * 0.55), control2: CGPoint(x: 0, y: h * 0.35))
            path.addCurve(to: CGPoint(x: w * 0.5, y: 0), control1: CGPoint(x: 0, y: h * 0.05), control2: CGPoint(x: w * 0.25, y: 0))
            path.addCurve(to: CGPoint(x: w, y: h * 0.28), control1: CGPoint(x: w * 0.75, y: 0), control2: CGPoint(x: w, y: h * 0.05))
            path.addCurve(to: CGPoint(x: w * 0.5, y: h), control1: CGPoint(x: w, y: h * 0.35), control2: CGPoint(x: w * 0.85, y: h * 0.55))
            path.closeSubpath()
            d.path(path, Color.black.opacity(0.35), stroke: 4)
            d.path(path, RoyalDraw.vertical([Royal.GoldLight, Royal.Gold, Royal.GoldDark], 0, h))
            d.path(path, Royal.WoodDark, stroke: 1.2)
            d.circle(RoyalDraw.radial([Color(argb: 0xFFFF8A93), Royal.Ruby, Royal.RubyDark], CGPoint(x: w * 0.45, y: h * 0.24), w * 0.22), w * 0.17,
                     CGPoint(x: w * 0.5, y: h * 0.28))
            d.circle(Color.white.opacity(0.7), w * 0.05, CGPoint(x: w * 0.43, y: h * 0.22))
        }
    }
}
