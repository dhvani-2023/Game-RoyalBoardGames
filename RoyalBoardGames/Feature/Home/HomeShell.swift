import SwiftUI
import UIKit
import GameKit

enum AppTab: Int, CaseIterable, Hashable {
    case Home, Games, Stats, Settings

    var title: String {
        switch self {
        case .Home: "Home"
        case .Games: "Games"
        case .Stats: "Trophies"
        case .Settings: "Settings"
        }
    }

    var icon: ImageVector {
        switch self {
        case .Home: Icons.Rounded.Home
        case .Games: Icons.Rounded.Casino
        case .Stats: Icons.Rounded.EmojiEvents
        case .Settings: Icons.Rounded.Settings
        }
    }
}

/// Bottom height reserved by the floating bar so tab content can scroll clear of it.
let BottomBarClearance: CGFloat = 124

/// The shell's state: selected tab (kept while games sit on top) and the bar-hidden flag that tabs set while
/// they show a dialog, so the bar slides away instead of floating over the scrim (Compose `LocalBottomBarHidden`).
@MainActor
@Observable
final class HomeShellState {
    var tab: AppTab = .Home
    /// Direction of the last tab change (picks the slide direction).
    var forward = true
    var barHidden = false

    func select(_ t: AppTab) {
        guard t != tab else { return }
        forward = t.rawValue > tab.rawValue
        // Let the outgoing tab pick up its exit direction first, then switch.
        DispatchQueue.main.async {
            withAnimation(.tween(280)) { self.tab = t }
        }
    }
}

struct HomeShell: View {
    let navigator: AppNavigator

    var body: some View {
        let shell = navigator.shell
        RoyalBackground {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .top) {
                    ZStack {
                        tabView(shell.tab, shell: shell)
                            .id(shell.tab)
                            .transition(.asymmetric(
                                insertion: .modifier(active: SlideFade(x: shell.forward ? w / 4 : -w / 4, opacity: 0), identity: SlideFade(x: 0, opacity: 1)),
                                removal: .modifier(active: SlideFade(x: shell.forward ? -w / 4 : w / 4, opacity: 0), identity: SlideFade(x: 0, opacity: 1))
                            ))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Fade under the status bar so scrolled content never collides with the clock and icons.
                    let top = WindowInsets.top
                    LinearGradient(colors: [Royal.Night, Royal.Night.copy(alpha: 0.85), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: top + 18)
                        .frame(maxWidth: .infinity)
                        .offset(y: -top)
                        .allowsHitTesting(false)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if !shell.barHidden {
                            RoyalBottomBar(selected: shell.tab, onSelect: { shell.select($0) })
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.compose(dampingRatio: 1, stiffness: 400), value: shell.barHidden)
                }
            }
        }
        .environment(shell)
    }

    @ViewBuilder
    private func tabView(_ tab: AppTab, shell: HomeShellState) -> some View {
        switch tab {
        case .Home: HomeTab(navigator: navigator, onSeeAll: { shell.select(.Games) }, onProfile: { shell.select(.Settings) })
        case .Games: GamesTab(navigator: navigator)
        case .Stats: StatsTab()
        case .Settings: SettingsTab(navigator: navigator)
        }
    }
}

/// Floating wooden bar with a gold rim. The active tab rises out of the bar into a glowing gold
/// medallion set in a dark socket; nothing is clipped, so the medallion sits proud of the rail.
private struct RoyalBottomBar: View {
    let selected: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        let shape = RoundedCornerShape(30)
        ZStack(alignment: .bottom) {
            RoundedCornerShape(26)
                .fill(LinearGradient(colors: [Royal.NightHigh, Royal.Night], startPoint: .top, endPoint: .bottom))
                .padding(5)
                .background(shape.fill(Royal.woodBrush))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Royal.GoldLight, Royal.GoldDark], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                .frame(height: 70)
                .background(shape.fill(Royal.WoodDark).composeShadow(20))
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { t in
                    BarItem(tab: t, selected: t == selected) { if t != selected { onSelect(t) } }
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 94)
        .padding(.horizontal, 14)
        .padding(.bottom, 11)
    }
}

private struct BarItem: View {
    let tab: AppTab
    let selected: Bool
    let onClick: () -> Void
    @State private var bounceTick = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                // dark socket ring + gold medallion
                Circle()
                    .fill(Royal.goldBrush)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                    .padding(5)
                    .background(Circle().fill(LinearGradient(colors: [Royal.WoodLight, Royal.WoodDark], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Royal.GoldLight, Royal.GoldDark], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                    .background(Circle().fill(Royal.Gold).shadow(color: Royal.Gold.opacity(0.55), radius: 9, x: 0, y: 3))
                    .frame(width: 60, height: 60)
                    .scaleEffect(selected ? 1 : 0.001)
                    .opacity(selected ? 1 : 0)
                    .animation(.compose(dampingRatio: 0.55, stiffness: 500), value: selected)
                Icon(tab.icon, tint: selected ? Royal.WoodDark : Royal.Smoke, size: selected ? 28 : 25)
                    .keyframeAnimator(initialValue: 1.0, trigger: bounceTick) { content, s in
                        content.scaleEffect(s)
                    } keyframes: { _ in
                        MoveKeyframe(0.7)
                        SpringKeyframe(1.0, spring: Spring(mass: 1, stiffness: 500, damping: 2 * 0.35 * 500.0.squareRoot()))
                    }
            }
            .frame(width: 60, height: 60)
            .offset(y: selected ? -16 : 0)
            .animation(.compose(dampingRatio: 0.5, stiffness: 500), value: selected)
            .padding(.bottom, 11)
            Text(tab.title, style: bodyStyle(11, .Black, selected ? Royal.Gold : Royal.Smoke))
                .lineLimit(1)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pressable(sound: .Swoosh, haptic: .Tick, pressedScale: 0.9, role: .Tab, onClick: onClick)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onChange(of: selected) { _, now in if now { bounceTick += 1 } }
    }
}

/// The key window's safe-area insets (status bar / home indicator), for layers that must cover them exactly.
@MainActor
enum WindowInsets {
    static var current: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.keyWindow?.safeAreaInsets ?? scenes.first?.windows.first?.safeAreaInsets ?? .zero
    }

    static var top: CGFloat { current.top }
    static var bottom: CGFloat { current.bottom }
}
