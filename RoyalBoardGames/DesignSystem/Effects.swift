import SwiftUI
import GameKit

/// Falling, tumbling confetti in gold, ruby, sapphire, emerald and ivory. Runs for `durationMs` then fades.
/// Fills the frame it is given (usually the whole screen).
struct Confetti: View {
    var count: Int = 160
    var durationMs: Int = 4200

    init(count: Int = 160, durationMs: Int = 4200) {
        self.count = count
        self.durationMs = durationMs
    }

    var body: some View {
        if !LocalReduceMotion.current {
            ConfettiCanvas(count: count, durationMs: durationMs)
                .allowsHitTesting(false)
        }
    }
}

private struct ConfettiPiece {
    let x: Float, delay: Float, speed: Float, drift: Float, spin: Float
    let w: Float, h: Float
    let color: Color
    let round: Bool
}

private struct ConfettiCanvas: View {
    let count: Int
    let durationMs: Int
    @State private var pieces: [ConfettiPiece] = []
    @State private var start = Date()
    @State private var done = false

    var body: some View {
        TimelineView(.animation(paused: done)) { tl in
            let p = Float(min(1, max(0, tl.date.timeIntervalSince(start) / (Double(durationMs) / 1000))))
            Canvas { ctx, size in
                let fade: Float = p > 0.8 ? (1 - p) / 0.2 : 1
                for c in pieces {
                    let local = min(1, max(0, (p - c.delay) / (1 - c.delay)))
                    if local <= 0 { continue }
                    let y = -0.1 + local * c.speed * 1.4
                    let x = c.x + c.drift * local + 0.02 * sin(local * 12 + c.x * 20)
                    let center = CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
                    var g = ctx
                    g.translateBy(x: center.x, y: center.y)
                    g.rotate(by: .degrees(Double(c.spin * local * 57)))
                    let color = c.color.opacity(Double(fade))
                    if c.round {
                        let r = CGFloat(c.w * 0.6)
                        g.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(color))
                    } else {
                        let flip = max(0.2, abs(cos(local * c.spin)))
                        let w = CGFloat(c.w * flip), h = CGFloat(c.h)
                        g.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(color))
                    }
                }
            }
        }
        .onAppear {
            if pieces.isEmpty {
                let palette = [Royal.Gold, Royal.GoldMid, Royal.Ruby, Royal.Sapphire, Royal.Emerald, Royal.Ivory, Royal.Amethyst]
                pieces = (0..<count).map { i in
                    ConfettiPiece(
                        x: Float.random(in: 0..<1),
                        delay: Float.random(in: 0..<1) * 0.35,
                        speed: 0.55 + Float.random(in: 0..<1) * 0.6,
                        drift: (Float.random(in: 0..<1) - 0.5) * 0.35,
                        spin: (Float.random(in: 0..<1) - 0.5) * 14,
                        w: 5 + Float.random(in: 0..<1) * 6,
                        h: 8 + Float.random(in: 0..<1) * 10,
                        color: palette[i % palette.count],
                        round: Int.random(in: 0..<5) == 0
                    )
                }
                start = Date()
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(durationMs) * 1_000_000 + 50_000_000)
            done = true
        }
    }
}

/// Slowly turning sunburst behind trophies and winners. Fills the (square) frame it is given.
/// The 18 s turn runs as a repeating animation, so the face is drawn once and never re-rendered per frame.
struct RotatingRays: View {
    var color: Color = Royal.Gold
    var rays: Int = 14
    @State private var turned = false

    init(color: Color = Royal.Gold, rays: Int = 14) {
        self.color = color
        self.rays = rays
    }

    var body: some View {
        let reduce = LocalReduceMotion.current
        RaysFace(color: color, rays: rays)
            .equatable()
            .rotationEffect(.degrees(!reduce && turned ? 360 : 0))
            .animation(reduce ? nil : .linear(duration: 18).repeatForever(autoreverses: false), value: turned)
            .onAppear { turned = true }
            .allowsHitTesting(false)
    }
}

private struct RaysFace: View, Equatable {
    let color: Color
    let rays: Int

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let shading = GraphicsContext.Shading.radialGradient(Gradient(colors: [color.copy(alpha: 0.45), .clear]), center: c, startRadius: 0, endRadius: r)
            for i in 0..<rays {
                let a0 = Double(i) * 2 * Double.pi / Double(rays)
                let a1 = a0 + Double.pi / Double(rays)
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + r * CGFloat(cos(a0)), y: c.y + r * CGFloat(sin(a0))))
                p.addLine(to: CGPoint(x: c.x + r * CGFloat(cos(a1)), y: c.y + r * CGFloat(sin(a1))))
                p.closeSubpath()
                ctx.fill(p, with: shading)
            }
            let r6 = r * 0.6
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r6, y: c.y - r6, width: r6 * 2, height: r6 * 2)),
                     with: .radialGradient(Gradient(colors: [color.copy(alpha: 0.5), .clear]), center: c, startRadius: 0, endRadius: r6))
        }
    }
}

/// Expanding ring that marks whoever is active. Sized by the frame it is given (the ring grows past it).
/// A 1.4 s repeating animation drives an animatable shape, so no view body runs per frame.
struct PulseRing: View {
    let color: Color
    @State private var running = false

    init(_ color: Color) { self.color = color }

    var body: some View {
        if !LocalReduceMotion.current {
            PulseRingShape(progress: running ? 1 : 0)
                .stroke(color, lineWidth: 3)
                .opacity((running ? 0 : 1) * 0.6)
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: running)
                .onAppear { running = true }
                .allowsHitTesting(false)
        }
    }
}

/// Circle of radius `base * (1 + 0.45 * progress)` centred in its rect (drawn outside it as it grows).
struct PulseRingShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let base = min(rect.width, rect.height) / 2
        let r = base * (1 + progress * 0.45)
        return Path(ellipseIn: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2))
    }
}

/// Gentle up/down float for decorative objects (Compose `bobOffset`): reverse-repeating FastOutSlowIn tween
/// between -amplitude and +amplitude. Read it inside a `TimelineView`; returns 0 when motion is reduced.
func bobOffset(amplitude: CGFloat = 6, periodMs: Int = 1600, at date: Date) -> CGFloat {
    if LocalReduceMotion.current { return 0 }
    let period = Double(periodMs) / 1000
    let phase = (date.timeIntervalSinceReferenceDate / period).truncatingRemainder(dividingBy: 2)
    let u = phase < 1 ? phase : 2 - phase
    return -amplitude + 2 * amplitude * CGFloat(Easing.FastOutSlowIn.transform(u))
}

/// Compose `bobOffset` applied as a vertical offset with a repeating reversed FastOutSlowIn animation
/// (no per-frame body). `inverted` mirrors it (the Kotlin `-bob.value` siblings).
struct BobModifier: ViewModifier {
    let amplitude: CGFloat
    let periodMs: Int
    let inverted: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        let reduce = LocalReduceMotion.current
        let a = reduce ? 0 : amplitude * (inverted ? -1 : 1)
        content
            .offset(y: up ? a : -a)
            .animation(reduce ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: Double(periodMs) / 1000).repeatForever(autoreverses: true), value: up)
            .onAppear { up = true }
    }
}

extension View {
    func bob(amplitude: CGFloat = 6, periodMs: Int = 1600, inverted: Bool = false) -> some View {
        modifier(BobModifier(amplitude: amplitude, periodMs: periodMs, inverted: inverted))
    }
}

/// Re-renders `content` every frame with the current bob value (Compose `val bob = bobOffset(...)`).
struct Bobbing<Content: View>: View {
    let amplitude: CGFloat
    let periodMs: Int
    let content: (CGFloat) -> Content

    init(amplitude: CGFloat = 6, periodMs: Int = 1600, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.amplitude = amplitude
        self.periodMs = periodMs
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(paused: LocalReduceMotion.current)) { tl in
            content(bobOffset(amplitude: amplitude, periodMs: periodMs, at: tl.date))
        }
    }
}

// MARK: - Dialogs

struct RoyalPrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var cancelTitle: String = "Cancel"
    var icon: ImageVector? = nil
    var destructive: Bool = false
    var onConfirm: () -> Void

    init(title: String, message: String, confirmTitle: String, cancelTitle: String = "Cancel", icon: ImageVector? = nil,
         destructive: Bool = false, onConfirm: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.icon = icon
        self.destructive = destructive
        self.onConfirm = onConfirm
    }

    init(_ title: String, _ message: String, _ confirmTitle: String, cancelTitle: String = "Cancel", icon: ImageVector? = nil,
         destructive: Bool = false, onConfirm: @escaping () -> Void) {
        self.init(title: title, message: message, confirmTitle: confirmTitle, cancelTitle: cancelTitle, icon: icon,
                  destructive: destructive, onConfirm: onConfirm)
    }
}

/// The app's only confirmation dialog (the reference never uses system alerts either):
/// a wooden card that springs in over a dimmed scrim. Place it last in a full-screen `ZStack`.
struct RoyalDialogHost: View {
    let prompt: RoyalPrompt?
    let onDismiss: () -> Void

    init(_ prompt: RoyalPrompt?, onDismiss: @escaping () -> Void) {
        self.prompt = prompt
        self.onDismiss = onDismiss
    }

    init(prompt: RoyalPrompt?, onDismiss: @escaping () -> Void) {
        self.init(prompt, onDismiss: onDismiss)
    }

    var body: some View {
        ZStack {
            if let p = prompt {
                RoyalDialogCard(prompt: p, onDismiss: onDismiss)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.linear(duration: 0.16), value: prompt?.id)
    }
}

private struct RoyalDialogCard: View {
    let prompt: RoyalPrompt
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 0.8

    var body: some View {
        let p = prompt
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
            WoodPanel(padding: 22) {
                VStack(spacing: 0) {
                    if let icon = p.icon {
                        ZStack {
                            if p.destructive {
                                Circle().fill(LinearGradient(colors: [Royal.Ruby, Royal.RubyDark], startPoint: .top, endPoint: .bottom))
                            } else {
                                Circle().fill(Royal.goldBrush)
                            }
                            Icon(icon, tint: p.destructive ? .white : Royal.WoodDark, size: 34)
                        }
                        .frame(width: 64, height: 64)
                        Spacer().frame(height: 14)
                    }
                    Text(p.title, style: displayStyle(26, Royal.Ivory, .Center)).multilineTextAlignment(.center)
                    Spacer().frame(height: 8)
                    Text(p.message, style: bodyStyle(15, .SemiBold, Royal.Smoke, .Center)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(height: 20)
                    CandyButton(
                        p.confirmTitle,
                        { onDismiss(); p.onConfirm() },
                        colors: p.destructive ? [Color(argb: 0xFFFF7A84), Royal.Ruby, Royal.RubyDark] : [Royal.GoldLight, Royal.Gold, Royal.GoldMid],
                        textColor: p.destructive ? .white : Royal.WoodDark,
                        height: 52,
                        fontSize: 20
                    )
                    Spacer().frame(height: 10)
                    OutlineButton(p.cancelTitle, onDismiss, tint: Royal.Smoke, fill: true)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture {}
            .frame(maxWidth: 420)
            .padding(28)
            .scaleEffect(scale)
            .onAppear { withAnimation(.compose(dampingRatio: 0.6, stiffness: 500)) { scale = 1 } }
        }
    }
}

/// Little row of dots for pagers.
struct PagerDots: View {
    let count: Int
    let current: Int
    var active: Color = Royal.Gold

    init(_ count: Int, _ current: Int, active: Color = Royal.Gold) {
        self.count = count
        self.current = current
        self.active = active
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                let on = i == current
                Capsule()
                    .fill(on ? active : Color.white.opacity(0.25))
                    .frame(width: on ? 26 : 8, height: 8)
                    .animation(.compose(dampingRatio: 0.6, stiffness: 1500), value: on)
            }
        }
    }
}

/// Scale+fade entrance used by cards and hero elements; `delayMs` staggers lists.
struct SpringInModifier: ViewModifier {
    let delayMs: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        let reduce = LocalReduceMotion.current
        let a: CGFloat = (reduce || shown) ? 1 : 0
        content
            .opacity(Double(a))
            .scaleEffect(0.85 + 0.15 * a)
            .offset(y: (1 - a) * 40 / 3) // 40 px
            .onAppear {
                if reduce { shown = true; return }
                withAnimation(.compose(dampingRatio: 0.7, stiffness: 300).delay(Double(delayMs) / 1000)) { shown = true }
            }
    }
}

extension View {
    func springIn(_ delayMs: Int = 0) -> some View { modifier(SpringInModifier(delayMs: delayMs)) }
}
