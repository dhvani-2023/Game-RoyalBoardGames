import SwiftUI
import UIKit
import GameKit

/// Animated intro (about 2.8 s): game pieces spiral in from the dark, a gold ring draws itself,
/// the crowned 8-ball punches in and the title shines. Follows the system launch screen with no seam.
struct SplashScreen: View {
    let onFinished: () -> Void
    @State private var start: Date? = nil

    // Timeline (seconds), from the Kotlin coroutine: orbit at 0, ring at 0.25, emblem/burst at 0.95,
    // crown at 1.21, title at 1.39, finish 0.9 s after the title spring settles.
    private static let ringAt = 0.25
    private static let emblemAt = 0.95
    private static let crownAt = 1.21
    private static let titleAt = 1.39
    private static let emblemSpring = SpringCurve(dampingRatio: 0.45, stiffness: 260)
    private static let crownSpring = SpringCurve(dampingRatio: 0.4, stiffness: 300)
    private static let titleSpring = SpringCurve(dampingRatio: 0.6, stiffness: 220)

    var body: some View {
        RoyalBackground(glow: Royal.Felt, secondGlow: Royal.GoldDark) {
            TimelineView(.animation(paused: start == nil)) { tl in
                let t = start.map { tl.date.timeIntervalSince($0) } ?? 0
                frame(t)
            }
        }
        .task {
            start = Date()
            UiSound.play(.Whoosh)
            try? await Task.sleep(nanoseconds: UInt64(Self.emblemAt * 1e9))
            UiSound.play(.Chime)
            Haptics.play(.Medium)
            try? await Task.sleep(nanoseconds: UInt64((Self.crownAt - Self.emblemAt) * 1e9))
            UiSound.play(.Sparkle)
            let finish = Self.titleAt + Self.titleSpring.settleTime + 0.9
            try? await Task.sleep(nanoseconds: UInt64((finish - Self.crownAt) * 1e9))
            onFinished()
        }
    }

    private func frame(_ t: Double) -> some View {
        let orbit = CGFloat(Easing.FastOutSlowIn.transform(min(1, max(0, t / 1.3))))
        let ring = CGFloat(Easing.FastOutSlowIn.transform(min(1, max(0, (t - Self.ringAt) / 0.9))))
        let emblem = CGFloat(Self.emblemSpring.value(t - Self.emblemAt))
        let burst = CGFloat(min(1, max(0, (t - Self.emblemAt) / 0.9)))
        let crown = CGFloat(Self.crownSpring.value(t - Self.crownAt))
        let title = CGFloat(Self.titleSpring.value(t - Self.titleAt))
        let titleAlpha = Double(min(1, max(0, title)))
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                SplashArt(orbit: orbit, ring: ring, emblem: emblem, burst: burst, crown: crown)
                    .frame(width: 300, height: 300)
                Spacer().frame(height: 8)
                Text("BOARD GAMES", style: displayStyle(44, Royal.Gold, .Center))
                    .shimmer(periodMs: 1800)
                    .scaleEffect(0.6 + 0.4 * title)
                    .opacity(titleAlpha)
                Spacer().frame(height: 6)
                Text("ROYAL GAME NIGHT", style: bodyStyle(13, .Black, Royal.Smoke, .Center).copy(letterSpacing: 5))
                    .opacity(titleAlpha)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                Text("PROVIDED BY", style: bodyStyle(10, .ExtraBold, Royal.SmokeDim, .Center).copy(letterSpacing: 2.5))
                Spacer().frame(height: 8)
                StudioLogo(height: 72)
            }
            .padding(.bottom, 16)
            .opacity(titleAlpha)
        }
    }
}

/// The 300×300 splash canvas, split into layers so only small areas redraw each frame
/// (the burst and the incoming pieces reach well outside the box, like the unclipped Compose Canvas).
private struct SplashArt: View {
    let orbit: CGFloat
    let ring: CGFloat
    let emblem: CGFloat
    let burst: CGFloat
    let crown: CGFloat

    var body: some View {
        let size: CGFloat = 300
        let r = size * 0.27
        ZStack {
            // light burst behind the emblem
            if burst > 0 {
                let br = r * (1 + burst * 2.2)
                Circle()
                    .fill(RadialGradient(colors: [Royal.Gold.copy(alpha: 0.55 * Double(1 - burst)), .clear], center: .center, startRadius: 0, endRadius: br))
                    .frame(width: br * 2, height: br * 2)
                let dotDist = r * (1.1 + burst * 1.5)
                let dotR = 3 * (1 - burst * 0.5)
                ForEach(0..<16, id: \.self) { i in
                    let a = CGFloat(i) * (2 * .pi / 16)
                    Circle()
                        .fill(Royal.GoldLight.opacity(Double(1 - burst)))
                        .frame(width: dotR * 2, height: dotR * 2)
                        .offset(x: cos(a) * dotDist, y: sin(a) * dotDist)
                }
            }
            // pieces spiralling in to sit around the ring
            let p = orbit
            let settle = r * 1.55
            let s = r * 0.42
            ForEach(0..<4, id: \.self) { i in
                let home = -CGFloat.pi / 2 + CGFloat.pi / 4 + CGFloat(i) * CGFloat.pi / 2
                let angle = home + (1 - p) * 3.2
                let dist = settle + (1 - p) * size * 0.9
                SplashPiece(index: i, s: s, spinDegrees: Double((1 - p) * 540 + 12))
                    .frame(width: s * 3, height: s * 3)
                    .offset(x: cos(angle) * dist, y: sin(angle) * dist)
            }
            // ring, ball and crown
            Canvas { ctx, sz in
                let d = RoyalDraw(ctx, sz)
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                if ring > 0 { RoyalArt.goldRing(d, c, r, ring) }
                if emblem > 0 { RoyalArt.eightBall(d, c, r * 0.84 * emblem) }
                if crown > 0 { RoyalArt.crown(d, CGPoint(x: c.x, y: c.y - r * 1.02 - (1 - crown) * r), r * 0.62 * crown) }
            }
            .frame(width: size + 80, height: size + 80)
        }
        .frame(width: size, height: size)
    }
}

private struct SplashPiece: View {
    let index: Int
    let s: CGFloat
    let spinDegrees: Double

    var body: some View {
        Canvas { ctx, sz in
            let d = RoyalDraw(ctx, sz)
            let pos = CGPoint(x: sz.width / 2, y: sz.height / 2)
            switch index {
            case 0: RoyalArt.die(d, pos, s * 1.1, 6, angle: spinDegrees)
            case 1: RoyalArt.pawn(d, CGPoint(x: pos.x, y: pos.y + s * 0.55), s * 1.4, Royal.Sapphire)
            case 2: RoyalArt.coin(d, pos, s * 0.55, light: true)
            default: RoyalArt.eightBall(d, pos, s * 0.55)
            }
        }
    }
}

/// The NG Studio logo (bundled `ng_studio_logo.webp`, shared with the legal pages).
struct StudioLogo: View {
    let height: CGFloat

    static let image: UIImage? = {
        if let path = Bundle.main.path(forResource: "ng_studio_logo", ofType: "webp"), let img = UIImage(contentsOfFile: path) { return img }
        for sub in ["Legal", "Resources/Legal"] {
            if let path = Bundle.main.path(forResource: "ng_studio_logo", ofType: "webp", inDirectory: sub),
               let img = UIImage(contentsOfFile: path) { return img }
        }
        return nil
    }()

    var body: some View {
        if let img = StudioLogo.image {
            Image(uiImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .accessibilityLabel("NG Studio")
        } else {
            Text("NG Studio", style: displayStyle(height * 0.4, Royal.Ivory)).frame(height: height)
        }
    }
}
