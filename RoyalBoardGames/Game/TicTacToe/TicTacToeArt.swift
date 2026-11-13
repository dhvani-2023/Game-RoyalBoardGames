import SwiftUI
import GameKit

extension Color {
    /// SwiftUI's `color.gradient` (Kotlin `Color.sheen()`): a soft top-to-bottom sheen of the colour.
    func sheenColors() -> [Color] { [lerp(self, Color.White, Float(0.18)), self, lerp(self, Color.Black, Float(0.12))] }

    func sheen() -> LinearGradient { LinearGradient(colors: sheenColors(), startPoint: .top, endPoint: .bottom) }
}

/// Android `BlurMaskFilter(blur)` stroke under a path. Android blur radius r is a Gaussian of sigma ≈ 0.57735·r + 0.5 px.
private func blurredStroke(_ ctx: GraphicsContext, _ path: Path, _ color: Color, _ width: CGFloat, _ blur: CGFloat, dy: CGFloat = 0) {
    if blur <= 0 { return }
    var c = ctx
    c.addFilter(.blur(radius: 0.57735 * blur + 0.17))
    c.translateBy(x: 0, y: dy)
    c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
}

/// Static X or O.
struct MarkGlyph: View {
    let mark: TTTMark
    let color: Color
    let lineWidth: CGFloat

    init(_ mark: TTTMark, _ color: Color, _ lineWidth: CGFloat) {
        self.mark = mark
        self.color = color
        self.lineWidth = lineWidth
    }

    var body: some View {
        Canvas { ctx, size in
            let w = lineWidth
            if mark == .X {
                var p = Path()
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.move(to: CGPoint(x: size.width, y: 0))
                p.addLine(to: CGPoint(x: 0, y: size.height))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
            } else {
                let r = min(size.width, size.height) / 2 - w / 2
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: w)
            }
        }
        .allowsHitTesting(false)
    }
}

/// X or O that draws itself in when placed (tween 320 ms, LinearOutSlowIn).
struct AnimatedMark: View {
    let mark: TTTMark
    let color: Color
    @State private var progress: CGFloat

    init(_ mark: TTTMark, _ color: Color) {
        self.mark = mark
        self.color = color
        _progress = State(initialValue: LocalReduceMotion.current ? 1 : 0)
    }

    var body: some View {
        MarkStroke(mark: mark, color: color, progress: progress)
            .onAppear { withAnimation(Easing.LinearOutSlowIn.animation(0.32)) { progress = 1 } }
    }
}

/// The drawn stroke of `AnimatedMark` at `progress` (animatable, so the Canvas redraws every frame).
private struct MarkStroke: View, Animatable {
    let mark: TTTMark
    let color: Color
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = progress
        let mark = mark
        let color = color
        Canvas { ctx, size in
            let width = size.width * 0.17
            var path = Path()
            if mark == .X {
                let inset = size.width * 0.1
                let l = inset, t = inset, r = size.width - inset, b = size.height - inset
                let first = min(1, p * 2)
                let second = max(0, p * 2 - 1)
                if first > 0 {
                    path.move(to: CGPoint(x: l, y: t))
                    path.addLine(to: CGPoint(x: l + (r - l) * first, y: t + (b - t) * first))
                }
                if second > 0 {
                    path.move(to: CGPoint(x: r, y: t))
                    path.addLine(to: CGPoint(x: r + (l - r) * second, y: t + (b - t) * second))
                }
            } else {
                let rr = min(size.width, size.height) / 2 - width / 2
                if p > 0 {
                    path.addRelativeArc(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: rr,
                                        startAngle: .degrees(-90), delta: .degrees(359.9 * Double(p)))
                }
            }
            if path.isEmpty { return }
            blurredStroke(ctx, path, color.copy(alpha: 0.35), width, 6, dy: 3)
            ctx.stroke(path, with: .linearGradient(Gradient(colors: color.sheenColors()), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Glowing line drawn across the three winning cells (waits 150 ms, then 450 ms FastOutSlowIn).
struct WinningLine: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let width: CGFloat
    @State private var progress: CGFloat = 0

    init(_ from: CGPoint, _ to: CGPoint, _ color: Color, _ width: CGFloat) {
        self.from = from
        self.to = to
        self.color = color
        self.width = width
    }

    var body: some View {
        WinningStroke(from: from, to: to, color: color, width: width, progress: progress)
            .onAppear { withAnimation(.tween(450, delay: 150)) { progress = 1 } }
    }
}

private struct WinningStroke: View, Animatable {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let width: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = progress
        let from = from, to = to, color = color, width = width
        Canvas { ctx, _ in
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = max(hypot(dx, dy), 1)
            let extend = width * 1.4
            let start = CGPoint(x: from.x - dx / length * extend, y: from.y - dy / length * extend)
            let end = CGPoint(x: to.x + dx / length * extend, y: to.y + dy / length * extend)
            if p <= 0 { return }
            let tip = CGPoint(x: start.x + (end.x - start.x) * p, y: start.y + (end.y - start.y) * p)
            var path = Path()
            path.move(to: start)
            path.addLine(to: tip)
            blurredStroke(ctx, path, color.copy(alpha: 0.8), width, 10)
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            ctx.stroke(path, with: .color(Color.white.opacity(0.6)), style: StrokeStyle(lineWidth: width * 0.3, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Card art: marks pop onto a tilted mini board, one after another, then it clears and repeats.
/// (Defined on Android but not shown anywhere; the cards use `TicTacToeCardArt`.)
struct TicTacToeArtwork: View {
    private static let sequence: [(Int, TTTMark)] = [(4, .X), (0, .O), (2, .X), (6, .O), (8, .X), (5, .O), (3, .X)]
    @State private var shown: Int = LocalReduceMotion.current ? 7 : 0

    var body: some View {
        let reduce = LocalReduceMotion.current
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size * 0.28
            let gap = size * 0.04
            let boardSide = cell * 3 + gap * 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<9, id: \.self) { index in
                    let shape = RoundedCornerShape(cell * 0.24)
                    shape.fill(Color.white.opacity(0.9))
                        .frame(width: cell, height: cell)
                        .background(shape.fill(Color.black.opacity(0.4)).composeShadow(6))
                        .offset(x: (cell + gap) * CGFloat(index % 3), y: (cell + gap) * CGFloat(index / 3))
                }
                ForEach(Array(Self.sequence.enumerated()), id: \.offset) { i, step in
                    let on = i < shown
                    MarkGlyph(step.1, step.1 == .X ? PartyStyle.tokenColors[0] : PartyStyle.tokenColors[1], cell * 0.13)
                        .padding(cell * 0.24)
                        .frame(width: cell, height: cell)
                        .scaleEffect(on ? 1 : 0.3)
                        .animation(.compose(dampingRatio: 0.6, stiffness: 320), value: on)
                        .opacity(on ? 1 : 0)
                        .animation(.tween(on ? 200 : 350), value: on)
                        .offset(x: (cell + gap) * CGFloat(step.0 % 3), y: (cell + gap) * CGFloat(step.0 / 3))
                }
            }
            .frame(width: boardSide, height: boardSide, alignment: .topLeading)
            .rotationEffect(.degrees(-6))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: reduce) {
            if reduce { return }
            while !Task.isCancelled {
                for i in 1...Self.sequence.count {
                    try? await Task.sleep(for: .milliseconds(520))
                    if Task.isCancelled { return }
                    shown = i
                }
                try? await Task.sleep(for: .milliseconds(1400))
                if Task.isCancelled { return }
                shown = 0
            }
        }
    }
}
