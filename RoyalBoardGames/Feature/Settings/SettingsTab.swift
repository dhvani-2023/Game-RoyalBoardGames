import SwiftUI
import GameKit

struct SettingsTab: View {
    let navigator: AppNavigator
    @Environment(HomeShellState.self) private var shell
    @State private var prompt: RoyalPrompt? = nil
    @State private var editing: PartyPlayer? = nil

    var body: some View {
        let s = AppSettings.data
        let overlay = prompt != nil || editing != nil
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 8)
                    Text("Settings", style: displayStyle(34)).springIn()
                    Spacer().frame(height: 16)

                    // Profile
                    WoodPanel(padding: 16) {
                        HStack(spacing: 0) {
                            AvatarBadge(s.avatar, Royal.GoldMid, size: 62)
                            Spacer().frame(width: 14)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(AppSettings.displayName, style: displayStyle(24))
                                Text("Tap to change name & avatar", style: bodyStyle(13, .SemiBold, Royal.Smoke))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Icon(Icons.Rounded.Edit, "Edit profile", tint: Royal.Gold)
                        }
                    }
                    .springIn(40)
                    .pressable(pressedScale: 0.98) {
                        editing = PartyPlayer(name: AppSettings.displayName, avatar: s.avatar, colorIndex: 3)
                    }

                    SettingsGroup(title: "Sound", delay: 80) {
                        ToggleRow(icon: Icons.AutoMirrored.Rounded.VolumeUp, title: "Sound effects", value: s.soundEnabled) { v in AppSettings.update { $0.copy(soundEnabled: v) } }
                        ToggleRow(icon: Icons.Rounded.MusicNote, title: "Lounge music", value: s.musicEnabled) { v in AppSettings.update { $0.copy(musicEnabled: v) } }
                        HStack(spacing: 0) {
                            Text("Volume", style: bodyStyle(15, .Bold, Royal.Smoke)).frame(width: 76, alignment: .leading)
                            GoldSlider(value: s.volume, onChange: { v in AppSettings.update { $0.copy(volume: v) } }, onRelease: { UiSound.play(.Coin) })
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 10)
                    }

                    SettingsGroup(title: "Feel", delay: 120) {
                        ToggleRow(icon: Icons.Rounded.Vibration, title: "Haptics", value: s.hapticsEnabled) { v in AppSettings.update { $0.copy(hapticsEnabled: v) } }
                        ToggleRow(icon: Icons.Rounded.Accessibility, title: "Reduce motion", value: s.reduceMotion) { v in AppSettings.update { $0.copy(reduceMotion: v) } }
                    }

                    SettingsGroup(title: "Gameplay", delay: 160) {
                        HStack(spacing: 0) {
                            IconTile(icon: Icons.Rounded.SmartToy)
                            Spacer().frame(width: 12)
                            Text("Computer skill", style: bodyStyle(16, .Bold))
                        }
                        .padding(.vertical, 6)
                        RoyalSegmented(BotLevel.entries, BotLevel.default, { v in AppSettings.update { $0.copy(botLevel: v.ordinal) } }, { $0.title })
                            .padding(.vertical, 6)
                        ToggleRow(icon: Icons.Rounded.WarningAmber, title: "Confirm before leaving a game", value: s.confirmLeave) { v in AppSettings.update { $0.copy(confirmLeave: v) } }
                    }

                    SettingsGroup(title: "Data", delay: 200) {
                        LinkRow(icon: Icons.Rounded.RestartAlt, title: "Reset stats & trophies", tint: Royal.Ruby) {
                            prompt = RoyalPrompt(
                                "Reset stats?", "All match history and trophies on this device will be cleared. This can't be undone.",
                                "Reset", icon: Icons.Rounded.RestartAlt, destructive: true
                            ) { PartyStore.clearHistory(); UiSound.play(.Swoosh) }
                        }
                        LinkRow(icon: Icons.Rounded.DeleteSweep, title: "Clear saved games", tint: Royal.Ruby) {
                            prompt = RoyalPrompt(
                                "Clear saved games?", "Every unfinished match will be removed from Continue.",
                                "Clear", icon: Icons.Rounded.DeleteSweep, destructive: true
                            ) { GameRegistry.all.forEach { $0.clearSavedGame() }; UiSound.play(.Swoosh) }
                        }
                    }

                    SettingsGroup(title: "About", delay: 240) {
                        LinkRow(icon: Icons.Rounded.Description, title: "Terms & Conditions") { navigator.openLegal(.Terms) }
                        LinkRow(icon: Icons.Rounded.PrivacyTip, title: "Privacy Policy") { navigator.openLegal(.Privacy) }
                        LinkRow(icon: Icons.Rounded.Star, title: "Rate the app") { AppLinks.requestReview() }
                        LinkRow(icon: Icons.Rounded.Email, title: "Contact us") {
                            AppLinks.mail("ngendevtech@gmail.com", subject: "Board Games: Royal Club")
                        }
                        HStack(spacing: 0) {
                            IconTile(icon: Icons.Rounded.Info)
                            Spacer().frame(width: 12)
                            Text("App version", style: bodyStyle(16, .Bold)).frame(maxWidth: .infinity, alignment: .leading)
                            Text(SettingsTab.versionLabel, style: bodyStyle(15, .ExtraBold, Royal.Gold))
                        }
                        .padding(.vertical, 10)
                    }

                    Spacer().frame(height: 24)
                    RoyalEmblem()
                        .frame(width: 84, height: 84)
                        .frame(maxWidth: .infinity)
                    Text("Board Games · Royal Game Night", style: bodyStyle(12, .Bold, Royal.SmokeDim, .Center))
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    Text("Plays fully offline. Nothing leaves your device.", style: bodyStyle(11, .SemiBold, Royal.SmokeDim, .Center))
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)

                    Spacer().frame(height: 24)
                    VStack(spacing: 0) {
                        Text("PROVIDED BY", style: bodyStyle(10, .ExtraBold, Royal.SmokeDim, .Center).copy(letterSpacing: 2.5))
                        Spacer().frame(height: 8)
                        StudioLogo(height: 56)
                        Spacer().frame(height: 12)
                        Text("NGENDEV TECHNOLABS LLP (NGD Technolab)", style: bodyStyle(11, .Bold, Royal.Smoke, .Center))
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        Text("1213, R K Prime, 12th, Near Nana Mava Circle,\n150 Feet Ring Road, Rajkot, Gujarat 360005, India", style: bodyStyle(10, .SemiBold, Royal.SmokeDim, .Center))
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, BottomBarClearance)
            }

            PlayerEditDialog(editing, onDismiss: { editing = nil }, onSave: { p in
                AppSettings.update { $0.copy(playerName: p.name.trimmingCharacters(in: .whitespacesAndNewlines), avatar: p.avatar) }
                editing = nil
            }, showColors: false)
            RoyalDialogHost(prompt) { prompt = nil }
        }
        .onChange(of: overlay) { _, v in shell.barHidden = v }
        .onDisappear { shell.barHidden = false }
    }

    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let code = info?["CFBundleVersion"] as? String ?? "1"
        return "\(name) (\(code))"
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let delay: Int
    let content: Content

    init(title: String, delay: Int, @ViewBuilder content: () -> Content) {
        self.title = title
        self.delay = delay
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)
            SectionLabel(title).padding(.leading, 6).padding(.bottom, 8)
            RoyalPanel(padding: 14) { content }.springIn(delay)
        }
    }
}

private struct IconTile: View {
    let icon: ImageVector
    var tint: Color = Royal.Gold

    var body: some View {
        ZStack {
            RoundedCornerShape(11).fill(tint.copy(alpha: 0.16))
            Icon(icon, tint: tint, size: 20)
        }
        .frame(width: 36, height: 36)
    }
}

private struct ToggleRow: View {
    let icon: ImageVector
    let title: String
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            IconTile(icon: icon)
            Spacer().frame(width: 12)
            Text(title, style: bodyStyle(16, .Bold)).frame(maxWidth: .infinity, alignment: .leading)
            RoyalSwitch(value, onChange, label: title)
        }
        .padding(.vertical, 8)
        .clipShape(RoundedCornerShape(12))
        .pressable(sound: .Toggle, pressedScale: 0.98) { onChange(!value) }
    }
}

private struct LinkRow: View {
    let icon: ImageVector
    let title: String
    var tint: Color = Royal.Gold
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            IconTile(icon: icon, tint: tint)
            Spacer().frame(width: 12)
            Text(title, style: bodyStyle(16, .Bold)).frame(maxWidth: .infinity, alignment: .leading)
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, tint: Royal.Smoke)
        }
        .padding(.vertical, 10)
        .clipShape(RoundedCornerShape(12))
        .pressable(pressedScale: 0.98, onClick: onClick)
    }
}

/// Gold slider with a glossy knob; `onRelease` plays a preview sound at the new volume.
private struct GoldSlider: View {
    let value: Float
    let onChange: (Float) -> Void
    let onRelease: () -> Void

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            Canvas { ctx, size in
                let d = RoyalDraw(ctx, size)
                let h: CGFloat = 8
                let y = size.height / 2
                let knob: CGFloat = 12
                let x = knob + (size.width - knob * 2) * CGFloat(value)
                d.roundRect(Color.white.opacity(0.12), CGPoint(x: 0, y: y - h / 2), CGSize(width: size.width, height: h), h)
                d.roundRect(RoyalDraw.horizontal([Royal.GoldDark, Royal.Gold], 0, size.width), CGPoint(x: 0, y: y - h / 2), CGSize(width: x, height: h), h)
                d.circle(Color.black.opacity(0.35), knob, CGPoint(x: x, y: y + 2))
                d.circle(RoyalDraw.vertical([Color.white, Royal.GoldLight], y - knob, y + knob), knob, CGPoint(x: x, y: y))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in onChange(Float(min(1, max(0, v.location.x / max(1, w))))) }
                    .onEnded { v in
                        onChange(Float(min(1, max(0, v.location.x / max(1, w)))))
                        onRelease()
                    }
            )
        }
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onChange(min(1, value + 0.1)); onRelease()
            case .decrement: onChange(max(0, value - 0.1)); onRelease()
            @unknown default: break
            }
        }
    }
}
