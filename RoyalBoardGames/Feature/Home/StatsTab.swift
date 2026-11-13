import SwiftUI
import GameKit

private struct Trophy {
    let title: String
    let detail: String
    let icon: ImageVector
    let unlocked: Bool
}

struct StatsTab: View {
    var body: some View {
        let history = PartyStore.history
        let me = AppSettings.displayName
        let isMine: (PartyMatchRecord) -> Bool = { r in r.players.contains { $0.hasSuffix(" \(me)") } }
        let won: (PartyMatchRecord) -> Bool = { r in r.winner?.hasSuffix(" \(me)") == true }
        let played = history.filter(isMine).count
        let wins = history.filter(won).count
        let rate = played == 0 ? 0 : (wins * 100 / played)
        let bestStreak: Int = {
            var best = 0, cur = 0
            for r in history.filter(isMine).reversed() {
                if won(r) { cur += 1; best = max(best, cur) } else { cur = 0 }
            }
            return best
        }()
        let winsByKind = GameKind.allCases.map { k in history.filter { $0.kind == k.id && won($0) }.count }
        let playedByKind = GameKind.allCases.map { k in history.filter { $0.kind == k.id }.count }

        let trophies = [
            Trophy(title: "First Victory", detail: "Win any match", icon: Icons.Rounded.EmojiEvents, unlocked: wins >= 1),
            Trophy(title: "Regular", detail: "Play 10 matches", icon: Icons.Rounded.Groups, unlocked: history.count >= 10),
            Trophy(title: "On Fire", detail: "Win 3 in a row", icon: Icons.Rounded.LocalFireDepartment, unlocked: bestStreak >= 3),
            Trophy(title: "Champion", detail: "Win 25 matches", icon: Icons.Rounded.WorkspacePremium, unlocked: wins >= 25),
            Trophy(title: "All-Rounder", detail: "Win every game once", icon: Icons.Rounded.Star, unlocked: winsByKind.allSatisfy { $0 > 0 }),
            Trophy(title: "Table Legend", detail: "Play 100 matches", icon: Icons.Rounded.MilitaryTech, unlocked: history.count >= 100),
        ]

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 8)
                Text("Trophy Room", style: displayStyle(34)).springIn()
                Text("Your record at this table.", style: bodyStyle(14, .SemiBold, Royal.Smoke))
                Spacer().frame(height: 16)

                WoodPanel(padding: 18) {
                    HStack(spacing: 0) {
                        ZStack {
                            RotatingRays().frame(width: 120, height: 120)
                            Icon(Icons.Rounded.EmojiEvents, tint: Royal.Gold, size: 64)
                        }
                        .frame(width: 96, height: 96)
                        Spacer().frame(width: 12)
                        VStack(alignment: .leading, spacing: 0) {
                            AnimatedCountText(wins, style: displayStyle(48, Royal.Gold))
                            Text("victories as \(me)", style: bodyStyle(13, .Bold, Royal.Smoke))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer().frame(height: 14)
                    HStack(spacing: 10) {
                        StatPill(title: "Played", value: played, suffix: "", icon: Icons.Rounded.Groups)
                        StatPill(title: "Win rate", value: rate, suffix: "%", icon: Icons.Rounded.Bolt)
                        StatPill(title: "Best run", value: bestStreak, suffix: "", icon: Icons.Rounded.LocalFireDepartment)
                    }
                }
                .springIn(60)

                Spacer().frame(height: 24)
                Text("Trophies", style: displayStyle(22))
                Spacer().frame(height: 10)
                ForEach(0..<2, id: \.self) { r in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<3, id: \.self) { c in
                            TrophyBadge(t: trophies[r * 3 + c])
                                .frame(maxWidth: .infinity)
                                .springIn(120 + (r * 3 + c) * 50)
                        }
                    }
                    .padding(.vertical, 5)
                }

                Spacer().frame(height: 24)
                Text("By Game", style: displayStyle(22))
                Spacer().frame(height: 10)
                RoyalPanel {
                    let maxPlayed = max(1, playedByKind.max() ?? 0)
                    ForEach(Array(GameKind.allCases.enumerated()), id: \.element) { i, k in
                        let p = playedByKind[i]
                        let w = winsByKind[i]
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                Circle().fill(LinearGradient(colors: k.accent, startPoint: .top, endPoint: .bottom)).frame(width: 12, height: 12)
                                Spacer().frame(width: 10)
                                Text(k.title, style: bodyStyle(15, .ExtraBold)).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(w) won · \(p) played", style: bodyStyle(12, .Bold, Royal.Smoke))
                            }
                            Spacer().frame(height: 6)
                            GameBar(fraction: CGFloat(p) / CGFloat(maxPlayed), colors: k.accent)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .springIn(200)
                if history.isEmpty {
                    Spacer().frame(height: 16)
                    Text("Finish a match and it shows up here.", style: bodyStyle(14, .SemiBold, Royal.SmokeDim, .Center))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, BottomBarClearance)
        }
    }
}

/// Played-share bar that grows to its value (Compose `Animatable(0).animateTo(p / max, tween(900))`).
private struct GameBar: View {
    let fraction: CGFloat
    let colors: [Color]
    @State private var shown: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * min(1, max(0.001, shown)))
            }
        }
        .frame(height: 8)
        .onAppear { withAnimation(.tween(900)) { shown = fraction } }
        .onChange(of: fraction) { _, v in withAnimation(.tween(900)) { shown = v } }
    }
}

private struct StatPill: View {
    let title: String
    let value: Int
    let suffix: String
    let icon: ImageVector

    var body: some View {
        VStack(spacing: 0) {
            Icon(icon, tint: Royal.Gold, size: 18)
            AnimatedCountText(value, style: displayStyle(22)) { "\($0)\(suffix)" }
            Text(title, style: bodyStyle(11, .Bold, Royal.Smoke))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedCornerShape(16).fill(Color.black.opacity(0.3)))
        .overlay(RoundedCornerShape(16).strokeBorder(Royal.Stroke, lineWidth: 1))
    }
}

private struct TrophyBadge: View {
    let t: Trophy

    var body: some View {
        let shape = RoundedCornerShape(20)
        VStack(spacing: 0) {
            ZStack {
                if t.unlocked {
                    Circle().fill(Royal.goldBrush)
                } else {
                    Circle().fill(LinearGradient(colors: [Color(argb: 0xFF2A3050), Color(argb: 0xFF1A1F38)], startPoint: .top, endPoint: .bottom))
                }
                Icon(t.unlocked ? t.icon : Icons.Rounded.Lock, tint: t.unlocked ? Royal.WoodDark : Royal.SmokeDim, size: 26)
            }
            .frame(width: 50, height: 50)
            Spacer().frame(height: 8)
            Text(t.title, style: bodyStyle(12, .Black, t.unlocked ? Royal.Ivory : Royal.Smoke, .Center)).lineLimit(1).minimumScaleFactor(0.8)
            Text(t.detail, style: bodyStyle(10, .SemiBold, Royal.SmokeDim, .Center)).lineLimit(2).multilineTextAlignment(.center)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background {
            if t.unlocked {
                shape.fill(LinearGradient(colors: [Royal.PanelHigh, Royal.Panel], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(t.unlocked ? Royal.Gold.copy(alpha: 0.7) : Color.white.opacity(0.08), lineWidth: 1.5))
        .background {
            if t.unlocked { shape.fill(Royal.Panel).composeShadow(10, color: Royal.Gold) }
        }
    }
}
