import SwiftUI
import GameKit

// MARK: - Press feedback

/// Compose `Role` for `pressable` (accessibility only).
enum Role { case Button, Switch, Checkbox, RadioButton, Tab, Image }

/// Spring press used by `pressable`: Compose `spring(dampingRatio = 0.45f, stiffness = StiffnessMedium)`.
struct PressableStyle: ButtonStyle {
    let pressedScale: CGFloat
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && enabled ? pressedScale : 1)
            .animation(.compose(dampingRatio: 0.45, stiffness: 1500), value: configuration.isPressed)
    }
}

extension View {
    /// Game-feel click: springs down while pressed, plays a click and a haptic tick on release.
    /// Use instead of `onTapGesture` for every tappable surface in the app.
    func pressable(
        enabled: Bool = true,
        sound: UiSound.Effect? = .Click,
        haptic: Haptics.Kind? = .Light,
        pressedScale: CGFloat = 0.94,
        role: Role = .Button,
        onClick: @escaping () -> Void
    ) -> some View {
        Button {
            if let sound { UiSound.play(sound) }
            if let haptic { Haptics.play(haptic) }
            onClick()
        } label: {
            self
        }
        .buttonStyle(PressableStyle(pressedScale: pressedScale, enabled: enabled))
        .disabled(!enabled)
        .accessibilityAddTraits(role == .Switch ? [] : .isButton)
    }

    /// Compose `Modifier.shadow(elevation, shape, spotColor)` approximation: a soft drop shadow (coloured spots glow).
    func composeShadow(_ elevation: CGFloat, color: Color = .black) -> some View {
        shadow(color: color.opacity(color == .black ? 0.45 : 0.4), radius: elevation * 0.55, x: 0, y: elevation * 0.35)
    }
}

// MARK: - Backgrounds

/// The app's velvet-night backdrop: gradient, two soft glows, drifting gold dust and a vignette.
/// Background layers extend under the system bars; `content` keeps the safe area.
struct RoyalBackground<Content: View>: View {
    var glow: Color = Royal.Felt
    var secondGlow: Color = Royal.Amethyst
    var sparkles: Bool = true
    let content: Content

    init(glow: Color = Royal.Felt, secondGlow: Color = Royal.Amethyst, sparkles: Bool = true, @ViewBuilder content: () -> Content) {
        self.glow = glow
        self.secondGlow = secondGlow
        self.sparkles = sparkles
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoyalBackdrop(glow: glow, secondGlow: secondGlow, sparkles: sparkles)
                .ignoresSafeArea()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The drawn layers of `RoyalBackground` (24 s loop).
struct RoyalBackdrop: View {
    let glow: Color
    let secondGlow: Color
    let sparkles: Bool
    @State private var start = Date()

    var body: some View {
        let reduce = LocalReduceMotion.current
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Royal.nightBrush)
                // Glow 1: its gradient centre drifts slowly; 30 fps is plenty for a 24 s drift.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { tl in
                    let time = reduce ? 0 : RoyalBackdrop.loop(tl.date.timeIntervalSince(start), 24)
                    let r = w * 0.9
                    let bx = w * (0.15 + 0.05 * CGFloat(sin(time * 2 * Double.pi)))
                    Circle()
                        .fill(RadialGradient(
                            colors: [glow.copy(alpha: 0.45), .clear],
                            center: UnitPoint(x: (bx - (w * 0.15 - r)) / (2 * r), y: 0.5),
                            startRadius: 0, endRadius: r))
                        .frame(width: r * 2, height: r * 2)
                        .position(x: w * 0.15, y: h * 0.12)
                }
                Circle()
                    .fill(RadialGradient(colors: [secondGlow.copy(alpha: 0.28), .clear], center: .center, startRadius: 0, endRadius: w * 0.85))
                    .frame(width: w * 1.7, height: w * 1.7)
                    .position(x: w * 0.95, y: h * 0.75)
                if sparkles {
                    TimelineView(.animation(paused: reduce)) { tl in
                        let time = reduce ? 0 : RoyalBackdrop.loop(tl.date.timeIntervalSince(start), 24)
                        Canvas { ctx, size in
                            for i in 0..<38 {
                                let seedX = Double((i * 7919) % 1000) / 1000
                                let seedY = Double((i * 104_729) % 1000) / 1000
                                let speed = 0.4 + Double((i * 31) % 10) / 10
                                let y = ((seedY - time * speed).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                                let twinkle = 0.35 + 0.65 * ((sin((time * 40 * speed + Double(i)) * 1.3) + 1) / 2)
                                let r = 0.8 + Double(i % 4) * 0.7
                                let c = CGPoint(x: seedX * size.width, y: y * size.height)
                                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                         with: .color(Royal.Gold.opacity(0.55 * twinkle)))
                            }
                        }
                    }
                }
                Rectangle()
                    .fill(RadialGradient(colors: [.clear, Color.black.opacity(0.55)], center: .center, startRadius: 0, endRadius: max(w, h) * 0.75))
            }
            .frame(width: w, height: h)
        }
        .allowsHitTesting(false)
    }

    /// Fraction 0..<1 of a looping linear animation of `period` seconds.
    static func loop(_ elapsed: TimeInterval, _ period: Double) -> Double {
        let f = (elapsed / period).truncatingRemainder(dividingBy: 1)
        return f < 0 ? f + 1 : f
    }
}

// MARK: - Panels

/// Dark lacquered panel with a fine gold edge. The default card surface. Fills the width it is given.
struct RoyalPanel<Content: View>: View {
    var corner: CGFloat = 22
    var accent: Color = Royal.Gold
    var padding: CGFloat = 16
    var fillHeight: Bool = false
    let content: Content

    init(corner: CGFloat = 22, accent: Color = Royal.Gold, padding: CGFloat = 16, fillHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.corner = corner
        self.accent = accent
        self.padding = padding
        self.fillHeight = fillHeight
        self.content = content()
    }

    var body: some View {
        let shape = RoundedCornerShape(corner)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(Royal.panelBrush)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [accent.copy(alpha: 0.55), accent.copy(alpha: 0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
            .background(shape.fill(Royal.Panel).composeShadow(14))
    }
}

/// Polished wood frame around a dark inset, like a game-table rail. Fills the width it is given.
struct WoodPanel<Content: View>: View {
    var corner: CGFloat = 24
    var rail: CGFloat = 7
    var padding: CGFloat = 16
    var fillHeight: Bool = false
    let content: Content

    init(corner: CGFloat = 24, rail: CGFloat = 7, padding: CGFloat = 16, fillHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.corner = corner
        self.rail = rail
        self.padding = padding
        self.fillHeight = fillHeight
        self.content = content()
    }

    var body: some View {
        let outer = RoundedCornerShape(corner)
        let inner = RoundedCornerShape(corner - rail / 2)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(Royal.panelBrush)
            .clipShape(inner)
            .overlay(inner.strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
            .padding(rail)
            .background(Royal.woodBrush)
            .clipShape(outer)
            .overlay(outer.strokeBorder(LinearGradient(colors: [Royal.GoldLight.copy(alpha: 0.8), Royal.GoldDark.copy(alpha: 0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .background(outer.fill(Royal.WoodDark).composeShadow(18))
    }
}

// MARK: - Buttons

/// Shimmer sweep across a surface, used on gold buttons and banners (draws over the full bounds; clip it to a shape).
/// Compose draws a linear gradient from (w·x − 0.3w, 0) to (w·x, h) with x running −1 → 2; here a band with that
/// gradient is drawn once and slid across by a repeating animation, so nothing is re-rendered per frame.
struct ShimmerModifier: ViewModifier {
    let enabled: Bool
    let periodMs: Int

    func body(content: Content) -> some View {
        if !enabled || LocalReduceMotion.current {
            content
        } else {
            content.overlay {
                GeometryReader { g in
                    ShimmerBand(size: g.size, periodMs: periodMs)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

private struct ShimmerBand: View {
    let size: CGSize
    let periodMs: Int
    @State private var swept = false

    var body: some View {
        let w = max(1, size.width), h = max(1, size.height)
        let dx = 0.3 * w
        // Points whose projection on the gradient axis falls inside it span [Ax − h²/dx, Ax + (dx² + h²)/dx].
        let lead = h * h / dx
        let bandWidth = lead + (dx * dx + h * h) / dx
        let start = UnitPoint(x: lead / bandWidth, y: 0)
        let end = UnitPoint(x: (lead + dx) / bandWidth, y: 1)
        // Band left edge = Ax − lead with Ax = w·x − 0.3w, x from −1 to 2.
        let from = -w - dx - lead
        let to = 2 * w - dx - lead
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.38), .clear], startPoint: start, endPoint: end))
            .frame(width: bandWidth, height: h)
            .offset(x: swept ? to : from)
            .animation(.linear(duration: Double(periodMs) / 1000).repeatForever(autoreverses: false), value: swept)
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
            .onAppear { swept = true }
    }
}

extension View {
    func shimmer(enabled: Bool = true, periodMs: Int = 2600) -> some View {
        modifier(ShimmerModifier(enabled: enabled, periodMs: periodMs))
    }
}

/// Chunky 3D "candy" button: a darker base slab, a glossy gradient face that sinks on press,
/// and an inner highlight. `colors` runs top → bottom. Fills the width it is given.
struct CandyButton: View {
    let text: String
    let onClick: () -> Void
    var colors: [Color] = [Royal.GoldLight, Royal.Gold, Royal.GoldMid]
    var textColor: Color = Royal.WoodDark
    var icon: ImageVector? = nil
    var enabled: Bool = true
    var height: CGFloat = 58
    var fontSize: Int = 22
    var shine: Bool = true
    var sound: UiSound.Effect = .Pop

    init(_ text: String, _ onClick: @escaping () -> Void, colors: [Color] = [Royal.GoldLight, Royal.Gold, Royal.GoldMid],
         textColor: Color = Royal.WoodDark, icon: ImageVector? = nil, enabled: Bool = true, height: CGFloat = 58,
         fontSize: Int = 22, shine: Bool = true, sound: UiSound.Effect = .Pop) {
        self.text = text
        self.onClick = onClick
        self.colors = colors
        self.textColor = textColor
        self.icon = icon
        self.enabled = enabled
        self.height = height
        self.fontSize = fontSize
        self.shine = shine
        self.sound = sound
    }

    var body: some View {
        Button {
            UiSound.play(sound)
            Haptics.play(.Medium)
            onClick()
        } label: {
            Color.clear.frame(height: height + 5)
        }
        .buttonStyle(CandyStyle(button: self))
        .disabled(!enabled)
        .accessibilityLabel(text)
    }

    fileprivate var face: [Color] { enabled ? colors : colors.map { lerp($0, Color.Gray, Float(0.65)) } }
}

private struct CandyStyle: ButtonStyle {
    let button: CandyButton

    func makeBody(configuration: Configuration) -> some View {
        CandyFace(button: button, pressed: configuration.isPressed && button.enabled)
    }
}

private struct CandyFace: View {
    let button: CandyButton
    let pressed: Bool

    var body: some View {
        let h = button.height
        let shape = RoundedCornerShape(h / 2.6)
        let face = button.face
        let base = lerp(face.last ?? Royal.GoldMid, Color.Black, Float(0.45))
        let depth: CGFloat = pressed ? 1 : 5
        ZStack(alignment: .top) {
            shape.fill(base)
                .frame(height: h)
                .background(shape.fill(base).composeShadow(10, color: face.last ?? .black))
                .offset(y: 5)
            ZStack {
                shape.fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                // top gloss
                VStack(spacing: 0) {
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(height: h * 0.32)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 0) {
                    if let icon = button.icon {
                        Icon(icon, tint: button.textColor, size: CGFloat(button.fontSize + 4))
                        Spacer().frame(width: 8)
                    }
                    Text(button.text, style: displayStyle(CGFloat(button.fontSize), button.textColor))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: h)
            .shimmer(enabled: button.enabled && button.shine)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .offset(y: 5 - depth)
            .animation(.compose(dampingRatio: 0.5, stiffness: 900), value: pressed)
        }
        .frame(maxWidth: .infinity)
        .frame(height: h + 5, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// The default gold `CandyButton`.
struct GoldButton: View {
    let text: String
    let onClick: () -> Void
    var icon: ImageVector? = nil
    var enabled: Bool = true
    var height: CGFloat = 58

    init(_ text: String, _ onClick: @escaping () -> Void, icon: ImageVector? = nil, enabled: Bool = true, height: CGFloat = 58) {
        self.text = text
        self.onClick = onClick
        self.icon = icon
        self.enabled = enabled
        self.height = height
    }

    var body: some View { CandyButton(text, onClick, icon: icon, enabled: enabled, height: height) }
}

/// Secondary button: dark glass with a gold outline. Hugs its label unless `fill` (Compose `fillMaxWidth()`/`weight(1f)`).
struct OutlineButton: View {
    let text: String
    let onClick: () -> Void
    var icon: ImageVector? = nil
    var height: CGFloat = 50
    var tint: Color = Royal.Gold
    var fill: Bool = false

    init(_ text: String, _ onClick: @escaping () -> Void, icon: ImageVector? = nil, height: CGFloat = 50, tint: Color = Royal.Gold, fill: Bool = false) {
        self.text = text
        self.onClick = onClick
        self.icon = icon
        self.height = height
        self.tint = tint
        self.fill = fill
    }

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 0) {
            if let icon {
                Icon(icon, tint: tint, size: 20)
                Spacer().frame(width: 8)
            }
            Text(text, style: bodyStyle(16, .ExtraBold, tint))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: fill ? .infinity : nil)
        .frame(height: height)
        .background(shape.fill(Royal.Glass))
        .overlay(shape.strokeBorder(tint.copy(alpha: 0.7), lineWidth: 1.5))
        .clipShape(shape)
        .pressable(onClick: onClick)
    }
}

/// Round wooden button with a gold rim, for back/pause/settings/sound.
struct RoundIconButton: View {
    let icon: ImageVector
    let onClick: () -> Void
    var size: CGFloat = 46
    var tint: Color = Royal.Gold
    var contentDescription: String? = nil
    var sound: UiSound.Effect = .Click

    init(_ icon: ImageVector, _ onClick: @escaping () -> Void, size: CGFloat = 46, tint: Color = Royal.Gold,
         contentDescription: String? = nil, sound: UiSound.Effect = .Click) {
        self.icon = icon
        self.onClick = onClick
        self.size = size
        self.tint = tint
        self.contentDescription = contentDescription
        self.sound = sound
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Royal.PanelHigh, Royal.Night], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(LinearGradient(colors: [Royal.GoldLight, Royal.GoldDark], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            Icon(icon, contentDescription, tint: tint, size: size * 0.48)
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Royal.Night).composeShadow(8))
        .pressable(sound: sound, onClick: onClick)
        .accessibilityLabel(contentDescription ?? "")
    }
}

// MARK: - Bars and labels

struct RoyalTopBar<Trailing: View>: View {
    let title: String
    let onBack: (() -> Void)?
    var subtitle: String? = nil
    let trailing: Trailing

    init(_ title: String, _ onBack: (() -> Void)?, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    init(title: String, subtitle: String? = nil, onBack: (() -> Void)?, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, onBack, subtitle: subtitle, trailing: trailing)
    }

    var body: some View {
        HStack(spacing: 0) {
            if let onBack {
                RoundIconButton(Icons.AutoMirrored.Rounded.ArrowBack, onBack, contentDescription: "Back", sound: .Back)
                Spacer().frame(width: 12)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title, style: displayStyle(24, Royal.Ivory)).lineLimit(1).truncationMode(.tail)
                if let subtitle { Text(subtitle, style: bodyStyle(12, .Bold, Royal.Smoke)).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) { trailing }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

extension RoyalTopBar where Trailing == EmptyView {
    init(_ title: String, _ onBack: (() -> Void)?, subtitle: String? = nil) {
        self.init(title, onBack, subtitle: subtitle) { EmptyView() }
    }

    init(title: String, subtitle: String? = nil, onBack: (() -> Void)?) {
        self.init(title, onBack, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color = Royal.Gold

    init(_ text: String, color: Color = Royal.Gold) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased(), style: bodyStyle(12, .Black, color).copy(letterSpacing: 1.6))
    }
}

/// Small capsule tag.
struct RoyalChip: View {
    let text: String
    var icon: ImageVector? = nil
    var color: Color = Royal.Ivory
    var background: Color = Color.white.opacity(0.12)

    init(_ text: String, icon: ImageVector? = nil, color: Color = Royal.Ivory, background: Color = Color.white.opacity(0.12)) {
        self.text = text
        self.icon = icon
        self.color = color
        self.background = background
    }

    var body: some View {
        HStack(spacing: 0) {
            if let icon {
                Icon(icon, tint: color, size: 14)
                Spacer().frame(width: 5)
            }
            Text(text, style: bodyStyle(12, .ExtraBold, color)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(background))
    }
}

/// Segmented control with a gold thumb. Fills the width it is given.
struct RoyalSegmented<T: Equatable>: View {
    let options: [T]
    let selected: T
    let onSelect: (T) -> Void
    let label: (T) -> String
    var height: CGFloat = 44

    init(_ options: [T], _ selected: T, _ onSelect: @escaping (T) -> Void, _ label: @escaping (T) -> String, height: CGFloat = 44) {
        self.options = options
        self.selected = selected
        self.onSelect = onSelect
        self.label = label
        self.height = height
    }

    var body: some View {
        let shape = RoundedCornerShape(height / 2)
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isOn = option == selected
                Text(label(option), style: bodyStyle(14, .Black, isOn ? Royal.WoodDark : Royal.Smoke, .Center))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        ZStack {
                            shape.fill(Royal.Gold).opacity(isOn ? 1 : 0)
                                .animation(.compose(dampingRatio: 1, stiffness: 1500), value: isOn)
                            if isOn { shape.fill(Royal.goldBrush) }
                        }
                    }
                    .clipShape(shape)
                    .pressable(sound: .Toggle, haptic: .Tick, pressedScale: 0.96) { onSelect(option) }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(shape.fill(Color.black.opacity(0.35)))
        .overlay(shape.strokeBorder(Royal.Stroke, lineWidth: 1))
        .clipShape(shape)
    }
}

/// Gold toggle switch with a springy knob.
struct RoyalSwitch: View {
    let checked: Bool
    let onCheckedChange: (Bool) -> Void
    var label: String? = nil

    init(_ checked: Bool, _ onCheckedChange: @escaping (Bool) -> Void, label: String? = nil) {
        self.checked = checked
        self.onCheckedChange = onCheckedChange
        self.label = label
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(checked ? Royal.GoldMid : Color.white.opacity(0.15))
                .animation(.compose(dampingRatio: 1, stiffness: 1500), value: checked)
            Capsule().strokeBorder(checked ? Royal.GoldLight : Royal.Stroke, lineWidth: 1)
            Circle()
                .fill(LinearGradient(colors: [Color.white, Royal.Ivory], startPoint: .top, endPoint: .bottom))
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.3), radius: 2.5, x: 0, y: 1.5)
                .padding(3)
                .offset(x: checked ? 24 : 0)
                .animation(.compose(dampingRatio: 0.55, stiffness: 700), value: checked)
        }
        .frame(width: 54, height: 30)
        .pressable(sound: .Toggle, haptic: .Tick, role: .Switch) { onCheckedChange(!checked) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "")
        .accessibilityValue(checked ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Animated count-up number, for stats and scores (Compose `animatedCount(target)` = `tween(900)`).
struct AnimatedCountText: View {
    let target: Int
    let style: TextStyle
    var format: (Int) -> String = { "\($0)" }

    init(_ target: Int, style: TextStyle, format: @escaping (Int) -> String = { "\($0)" }) {
        self.target = target
        self.style = style
        self.format = format
    }

    var body: some View {
        CountingText(value: target, format: format)
            .font(style.font)
            .foregroundStyle(style.color)
            .tracking(style.letterSpacing)
            .animation(.tween(900), value: target)
    }
}
