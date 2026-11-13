import SwiftUI
import GameKit

@MainActor
private struct SavedEntry: Identifiable {
    let module: any BoardGameModule
    let summary: String?
    let id: String

    init(module: any BoardGameModule, summary: String?) {
        self.module = module
        self.summary = summary
        self.id = module.kind.id
    }
}

struct HomeTab: View {
    let navigator: AppNavigator
    let onSeeAll: () -> Void
    let onProfile: () -> Void
    @State private var saved: [SavedEntry] = []

    var body: some View {
        let modules = GameRegistry.all
        let history = PartyStore.history
        let me = AppSettings.displayName
        let mine = history.filter { r in r.players.contains { $0.hasSuffix(" \(me)") } }
        let wins = mine.filter { $0.winner?.hasSuffix(" \(me)") == true }.count

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    AvatarBadge(AppSettings.data.avatar, Royal.GoldMid, size: 54)
                        .clipShape(Circle())
                        .pressable(onClick: onProfile)
                        .accessibilityLabel("Profile and settings")
                    Spacer().frame(width: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(greeting(), style: bodyStyle(13, .Bold, Royal.Smoke))
                        Text(me, style: displayStyle(26)).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        Icon(Icons.Rounded.EmojiEvents, tint: Royal.Gold, size: 20)
                        Spacer().frame(width: 6)
                        Text("\(wins)", style: displayStyle(18, Royal.Gold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(Royal.Stroke, lineWidth: 1.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .springIn()

                // Spin the Table (replaces the poster carousel)
                SpinTheTable(modules: modules, onPlay: { navigator.openGame($0) })
                    .padding(.horizontal, 20)
                    .springIn(80)

                // Continue
                if !saved.isEmpty {
                    SectionHeader(title: "Continue").springIn(140)
                    ForEach(Array(saved.enumerated()), id: \.element.id) { i, entry in
                        ContinueCard(module: entry.module, summary: entry.summary) { navigator.openGame(entry.module.kind, resume: true) }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                            .springIn(160 + i * 50)
                    }
                }

                // Quick play grid
                SectionHeader(title: "Quick Play", action: "See all", onAction: onSeeAll).springIn(200)
                let rows = stride(from: 0, to: modules.count, by: 2).map { Array(modules[$0..<min($0 + 2, modules.count)]) }
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { c, m in
                            QuickTile(module: m) { navigator.openGame(m.kind) }
                                .frame(maxWidth: .infinity)
                                .springIn(240 + (r * 2 + c) * 60)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }

                // Recent matches
                if !history.isEmpty {
                    SectionHeader(title: "Recent Matches").springIn(300)
                    RoyalPanel(padding: 6) {
                        ForEach(Array(history.prefix(4))) { rec in
                            let kind = GameKind.byId(rec.kind)
                            HStack(spacing: 0) {
                                ZStack {
                                    RoundedCornerShape(12).fill(LinearGradient(colors: kind?.accent ?? [Royal.Panel, Royal.Night], startPoint: .top, endPoint: .bottom))
                                    Icon(Icons.Rounded.History, tint: .white, size: 20)
                                }
                                .frame(width: 38, height: 38)
                                Spacer().frame(width: 12)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(kind?.title ?? rec.kind, style: bodyStyle(15, .ExtraBold))
                                    Text(rec.detail, style: bodyStyle(12, .SemiBold, Royal.Smoke)).lineLimit(1).truncationMode(.tail)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(rec.winner ?? "Draw", style: bodyStyle(13, .ExtraBold, Royal.Gold)).lineLimit(1)
                            }
                            .padding(10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .springIn(320)
                }
            }
            .padding(.bottom, BottomBarClearance)
        }
        .task {
            // Saved matches are decoded from JSON: load them after the first frame.
            await Task.yield()
            saved = modules.filter { $0.hasSavedGame() }.map { SavedEntry(module: $0, summary: $0.savedGameSummary()) }
        }
    }

    private func greeting() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5...11: return "Good morning ☀️"
        case 12...16: return "Good afternoon 🎲"
        case 17...21: return "Good evening 🌙"
        default: return "Game night 🌌"
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text(title, style: displayStyle(24)).frame(maxWidth: .infinity, alignment: .leading)
            if let action, let onAction {
                Text(action, style: bodyStyle(14, .ExtraBold, Royal.Gold))
                    .padding(8)
                    .clipShape(Capsule())
                    .pressable(onClick: onAction)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.top, 26)
        .padding(.bottom, 10)
    }
}

private struct ContinueCard: View {
    let module: any BoardGameModule
    let summary: String?
    let onClick: () -> Void

    var body: some View {
        let kind = module.kind
        RoyalPanel(accent: kind.accent.first ?? Royal.Gold, padding: 12) {
            HStack(spacing: 0) {
                module.Artwork()
                    .padding(4)
                    .frame(width: 62, height: 62)
                    .background(LinearGradient(colors: kind.accent, startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedCornerShape(16))
                Spacer().frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.title, style: displayStyle(19))
                    Text(summary ?? "Match in progress", style: bodyStyle(13, .SemiBold, Royal.Smoke)).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().fill(Royal.goldBrush)
                    Icon(Icons.Rounded.PlayArrow, "Resume", tint: Royal.WoodDark, size: 28)
                }
                .frame(width: 46, height: 46)
                .background(Circle().fill(Royal.Gold).composeShadow(8, color: Royal.Gold))
            }
        }
        .pressable(pressedScale: 0.97, onClick: onClick)
    }
}

private struct QuickTile: View {
    let module: any BoardGameModule
    let onClick: () -> Void

    var body: some View {
        let kind = module.kind
        let shape = RoundedCornerShape(24)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1.15, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { g in
                        let side = g.size.height
                        module.Artwork()
                            .frame(width: side, height: side)
                            .position(x: g.size.width / 2, y: g.size.height / 2)
                    }
                }
            Spacer().frame(height: 8)
            Text(kind.title, style: displayStyle(17, .white)).lineLimit(1).truncationMode(.tail)
            Text(kind.playersLabel, style: bodyStyle(12, .Bold, Color.white.opacity(0.75)))
        }
        .padding(12)
        .background(LinearGradient(colors: [kind.accent[0], lerp(kind.accent[1], Color.Black, Float(0.35))], startPoint: .top, endPoint: .bottom))
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Royal.GoldLight.copy(alpha: 0.8), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
        .background(shape.fill(kind.accent[0]).composeShadow(12, color: kind.accent[0]))
        .pressable(pressedScale: 0.95, onClick: onClick)
    }
}
