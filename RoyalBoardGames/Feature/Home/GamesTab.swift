import SwiftUI
import GameKit

struct GamesTab: View {
    let navigator: AppNavigator

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Game Room", style: displayStyle(34))
                    Text("Six classics, all offline. Pick a table.", style: bodyStyle(14, .SemiBold, Royal.Smoke))
                }
                .padding(.vertical, 8)
                .springIn()
                ForEach(Array(GameRegistry.all.enumerated()), id: \.element.kind) { i, m in
                    GameTile(module: m, flip: i % 2 == 1) { navigator.openGame(m.kind) }
                        .springIn(60 + i * 70)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, BottomBarClearance)
        }
    }
}

/// Large illustrated game card with a felt sheen, live artwork and a Play button.
private struct GameTile: View {
    let module: any BoardGameModule
    let flip: Bool
    let onPlay: () -> Void

    var body: some View {
        let kind = module.kind
        let shape = RoundedCornerShape(28)
        ZStack(alignment: flip ? .leading : .trailing) {
            Circle()
                .fill(Color.white)
                .frame(width: 240, height: 240)
                .offset(x: flip ? -80.0 / 3 : 80.0 / 3)
                .opacity(0.18)
            module.Artwork()
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(flip ? 5 : -5))
                .bob(amplitude: 4, periodMs: 1900)
                .padding(.horizontal, 10)
            FractionWidthLayout(fraction: 0.56, alignment: flip ? .trailing : .leading) {
                VStack(alignment: flip ? .trailing : .leading, spacing: 0) {
                    Text(kind.title, style: displayStyle(kind.title.count > 12 ? 22 : 26, .white))
                        .lineLimit(2)
                        .multilineTextAlignment(flip ? .trailing : .leading)
                    Spacer().frame(height: 6)
                    RoyalChip(kind.playersLabel, icon: Icons.Rounded.Groups, background: Color.black.opacity(0.28))
                    Spacer().frame(height: 5)
                    RoyalChip(kind.modes, icon: Icons.Rounded.Style, background: Color.black.opacity(0.28))
                    Spacer().frame(height: 5)
                    RoyalChip("Offline", icon: Icons.Rounded.WifiOff, background: Color.black.opacity(0.28))
                    Spacer().frame(height: 10)
                    CandyButton("Play", onPlay, icon: Icons.Rounded.PlayArrow, height: 44, fontSize: 18)
                        .frame(width: 118)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: flip ? .trailing : .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(LinearGradient(colors: [kind.accent[0], kind.accent[1], lerp(kind.accent[1], Color.Black, Float(0.5))],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Royal.GoldLight.copy(alpha: 0.85), Royal.GoldDark.copy(alpha: 0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
        .background(shape.fill(kind.accent[0]).composeShadow(18, color: kind.accent[0]))
        .pressable(pressedScale: 0.97, onClick: onPlay)
    }
}
