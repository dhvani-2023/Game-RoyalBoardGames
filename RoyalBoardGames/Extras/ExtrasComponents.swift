import SwiftUI
import GameKit

/// Shared pieces of the extras UI, in the Royal design system.
enum ExtrasReplay {
    /// The instant replay's speed.
    static let RATE = 0.4
}

/// The small "Replay" pill on the turn line after a shot.
struct ExtrasReplayButton: View {
    let onClick: () -> Void

    init(_ onClick: @escaping () -> Void) { self.onClick = onClick }

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 5) {
            Icon(Icons.Rounded.Replay, tint: Royal.Ivory, size: 15)
            Text("Replay", style: bodyStyle(12, .Black, Royal.Ivory)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(shape.fill(LinearGradient(colors: [Royal.Ruby, Royal.RubyDark], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
        .clipShape(shape)
        .background(shape.fill(Royal.RubyDark).composeShadow(6, color: Royal.Ruby))
        .fixedSize()
        .pressable(sound: .Swoosh, haptic: .Light, onClick: onClick)
        .accessibilityLabel("Replay the last shot in slow motion")
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

/// While a replay runs: a REPLAY badge at the top and a full-screen tap target that skips it.
struct ExtrasReplayOverlay: View {
    let active: Bool
    let onSkip: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if active {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onSkip() }
                    .accessibilityElement()
                    .accessibilityLabel("Replay playing. Double-tap to skip.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onSkip() }
                ExtrasReplayBadge()
                    .padding(.top, 64)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.compose(dampingRatio: 0.6, stiffness: 420), value: active)
    }
}

private struct ExtrasReplayBadge: View {
    @State private var pulse = false

    var body: some View {
        let reduce = LocalReduceMotion.current
        let shape = Capsule()
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Royal.Ruby)
                    .frame(width: 10, height: 10)
                    .opacity(pulse ? 0.25 : 1)
                Text("REPLAY", style: displayStyle(20, Royal.Ivory).copy(letterSpacing: 2))
                Text("0.4×", style: bodyStyle(11, .Black, Royal.WoodDark))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Royal.goldBrush))
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(shape.fill(Color.black.opacity(0.62)))
            .overlay(shape.strokeBorder(Royal.Ruby.opacity(0.8), lineWidth: 1.5))
            .clipShape(shape)
            Text("Tap to skip", style: bodyStyle(11, .ExtraBold, Color.white.opacity(0.8)))
                .shadow(color: Color.black.opacity(0.5), radius: 0, x: 0, y: 2)
        }
        .onAppear {
            if reduce { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// "Practice" next to "Start game" in the Pool and Carrom setups.
struct ExtrasPracticeButton: View {
    let onClick: () -> Void

    init(_ onClick: @escaping () -> Void) { self.onClick = onClick }

    var body: some View {
        OutlineButton("Practice", onClick, icon: Icons.Rounded.Adjust, height: 58)
            .fixedSize()
            .accessibilityLabel("Practice table: one player, free shooting")
    }
}

/// The practice table's header: the player, a few numbers and the re-rack button.
struct ExtrasPracticeStrip: View {
    let avatar: String
    let name: String
    let stats: String
    let rerackTitle: String
    let canRerack: Bool
    let onRerack: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Royal.PanelHigh, Royal.Panel], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Royal.Gold.opacity(0.8), lineWidth: 2)
                Text(verbatim: avatar).font(.system(size: 20))
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("PRACTICE", style: bodyStyle(9, .Black, Royal.Gold).copy(letterSpacing: 1.2)).lineLimit(1)
                Text(name, style: bodyStyle(14, .ExtraBold, Color.white)).lineLimit(1).truncationMode(.tail)
                Text(stats, style: bodyStyle(10, .ExtraBold, Color.white.opacity(0.7))).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Icon(Icons.Rounded.Refresh, tint: Royal.WoodDark, size: 16)
                Text(rerackTitle, style: bodyStyle(13, .Black, Royal.WoodDark)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Royal.goldBrush))
            .clipShape(Capsule())
            .opacity(canRerack ? 1 : 0.45)
            .fixedSize()
            .pressable(enabled: canRerack, sound: .Swoosh, haptic: .Medium, onClick: onRerack)
            .accessibilityLabel(rerackTitle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxHeight: .infinity)
        .background(shape.fill(Color.black.opacity(0.28)))
        .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1))
        .clipShape(shape)
    }
}
