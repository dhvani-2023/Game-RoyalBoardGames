import SwiftUI
import UIKit
import GameKit

/// "Royal Game Night": dark lounge, felt, metallic gold and polished wood.
enum Royal {
    static let Night = Color(argb: 0xFF0A0D1A)
    static let NightMid = Color(argb: 0xFF121833)
    static let NightHigh = Color(argb: 0xFF1B2347)
    static let Felt = Color(argb: 0xFF0E5E46)
    static let FeltDark = Color(argb: 0xFF0A3F31)
    static let FeltLight = Color(argb: 0xFF1C9A78)
    static let GoldLight = Color(argb: 0xFFFFE9A8)
    static let Gold = Color(argb: 0xFFFFD66B)
    static let GoldMid = Color(argb: 0xFFF2A93B)
    static let GoldDark = Color(argb: 0xFFB8741A)
    static let Ruby = Color(argb: 0xFFE8434F)
    static let RubyDark = Color(argb: 0xFFA3202C)
    static let Sapphire = Color(argb: 0xFF3C8CFF)
    static let SapphireDark = Color(argb: 0xFF1C4FB8)
    static let Emerald = Color(argb: 0xFF2FD18A)
    static let Amethyst = Color(argb: 0xFFA66BFF)
    static let Ivory = Color(argb: 0xFFFFF6E3)
    static let Smoke = Color(argb: 0xFF9AA3C7)
    static let SmokeDim = Color(argb: 0xFF636B90)
    static let Wood = Color(argb: 0xFF6B3E1F)
    static let WoodDark = Color(argb: 0xFF3A200F)
    static let WoodLight = Color(argb: 0xFF8E5A31)
    static let Panel = Color(argb: 0xFF161D3A)
    static let PanelHigh = Color(argb: 0xFF212A52)
    static let Stroke = Color(argb: 0x33FFD66B)
    static let Glass = Color(argb: 0x14FFFFFF)

    // Colour stops (for Canvas shading and custom gradients).
    static let goldColors = [GoldLight, Gold, GoldMid, GoldDark]
    static let goldHorizontalColors = [GoldDark, GoldMid, Gold, GoldLight, Gold, GoldMid]
    static let woodColors = [WoodLight, Wood, WoodDark]
    static let feltColors = [FeltLight, Felt, FeltDark]
    static let nightColors = [NightHigh, NightMid, Night]
    static let panelColors = [PanelHigh, Panel]

    /// Brushes as SwiftUI shape styles (Compose `Brush.verticalGradient` spans the filled shape).
    static let goldBrush = LinearGradient(colors: goldColors, startPoint: .top, endPoint: .bottom)
    static let goldHorizontal = LinearGradient(colors: goldHorizontalColors, startPoint: .leading, endPoint: .trailing)
    static let woodBrush = LinearGradient(colors: woodColors, startPoint: .top, endPoint: .bottom)
    static let feltBrush = LinearGradient(colors: feltColors, startPoint: .top, endPoint: .bottom)
    static let nightBrush = LinearGradient(colors: nightColors, startPoint: .top, endPoint: .bottom)
    static let panelBrush = LinearGradient(colors: panelColors, startPoint: .top, endPoint: .bottom)
}

/// Per-game accent pairs used by cards, banners and result screens.
enum GameAccent {
    static let snakes = [Color(argb: 0xFF2FD18A), Color(argb: 0xFF0B7A5C)]
    static let chess = [Color(argb: 0xFF8C7BFF), Color(argb: 0xFF3B2F8F)]
    static let ticTacToe = [Color(argb: 0xFFFF7AB6), Color(argb: 0xFFB62E7A)]
    static let ludo = [Color(argb: 0xFFFF5A4E), Color(argb: 0xFF2E6BEF)]
    static let carrom = [Color(argb: 0xFFFFB347), Color(argb: 0xFFA3302A)]
    static let pool = [Color(argb: 0xFF26C281), Color(argb: 0xFF0B4F6C)]
}

// MARK: - Type

/// Compose `FontWeight`.
struct FontWeight: Hashable {
    let weight: Int
    init(_ weight: Int) { self.weight = weight }

    static let Thin = FontWeight(100)
    static let ExtraLight = FontWeight(200)
    static let Light = FontWeight(300)
    static let Normal = FontWeight(400)
    static let Medium = FontWeight(500)
    static let SemiBold = FontWeight(600)
    static let Bold = FontWeight(700)
    static let ExtraBold = FontWeight(800)
    static let Black = FontWeight(900)
}

/// Compose `TextAlign`.
enum TextAlign { case Start, Center, End, Left, Right, Justify }

/// Lilita One (display) and variable Nunito (body; Android registers the 400/600/700/800/900 instances).
enum RoyalFonts {
    static let displayName = "LilitaOne"
    static let bodyName = "Nunito-Regular"

    private static let lock = NSLock()
    private static var displayCache: [CGFloat: Font] = [:]
    private static var bodyCache: [Int: Font] = [:]
    private static var uiCache: [String: UIFont] = [:]

    /// The weight Compose picks from the registered instances (CSS matching: 500 → 400, < 400 → 400, > 900 → 900).
    static func resolvedWeight(_ w: FontWeight) -> Int {
        let available = [400, 600, 700, 800, 900]
        if available.contains(w.weight) { return w.weight }
        if w.weight < 400 { return 400 }
        if w.weight <= 500 { return 400 }
        if w.weight > 900 { return 900 }
        return available.first { $0 >= w.weight } ?? 900
    }

    /// Lilita One at `size` points (fixed size, like `sp` at 1× font scale).
    static func display(_ size: CGFloat) -> Font {
        lock.lock(); defer { lock.unlock() }
        if let f = displayCache[size] { return f }
        let f = Font.custom(displayName, fixedSize: size)
        displayCache[size] = f
        return f
    }

    /// Nunito at `size` points and `weight`.
    static func body(_ size: CGFloat, _ weight: FontWeight = .Bold) -> Font {
        let w = resolvedWeight(weight)
        let key = Int(size * 100) * 10 + w / 100
        lock.lock(); defer { lock.unlock() }
        if let f = bodyCache[key] { return f }
        let f = Font(uiBody(size, weight, locked: true) as CTFont)
        bodyCache[key] = f
        return f
    }

    static func uiDisplay(_ size: CGFloat) -> UIFont {
        lock.lock(); defer { lock.unlock() }
        let key = "d\(size)"
        if let f = uiCache[key] { return f }
        let f = UIFont(name: displayName, size: size) ?? .systemFont(ofSize: size, weight: .heavy)
        uiCache[key] = f
        return f
    }

    static func uiBody(_ size: CGFloat, _ weight: FontWeight = .Bold) -> UIFont {
        lock.lock(); defer { lock.unlock() }
        return uiBody(size, weight, locked: true)
    }

    private static func uiBody(_ size: CGFloat, _ weight: FontWeight, locked: Bool) -> UIFont {
        let w = resolvedWeight(weight)
        let key = "b\(size)-\(w)"
        if let f = uiCache[key] { return f }
        let f: UIFont
        if UIFont(name: bodyName, size: size) != nil {
            f = FontRegistry.variable(bodyName, size: size, weight: CGFloat(w))
        } else {
            f = .systemFont(ofSize: size, weight: w >= 800 ? .heavy : (w >= 700 ? .bold : .semibold))
        }
        uiCache[key] = f
        return f
    }
}

/// Compose `TextStyle` subset used by the app: font family, size, weight, colour, alignment and letter spacing.
struct TextStyle {
    enum Family { case display, body }

    var family: Family
    var size: CGFloat
    var weight: FontWeight
    var color: Color
    var align: TextAlign
    var letterSpacing: CGFloat

    var font: Font { family == .display ? RoyalFonts.display(size) : RoyalFonts.body(size, weight) }
    var uiFont: UIFont { family == .display ? RoyalFonts.uiDisplay(size) : RoyalFonts.uiBody(size, weight) }

    /// Kotlin `style.copy(letterSpacing = 2.sp)`.
    func copy(size: CGFloat? = nil, weight: FontWeight? = nil, color: Color? = nil, align: TextAlign? = nil, letterSpacing: CGFloat? = nil) -> TextStyle {
        TextStyle(family: family, size: size ?? self.size, weight: weight ?? self.weight, color: color ?? self.color,
                  align: align ?? self.align, letterSpacing: letterSpacing ?? self.letterSpacing)
    }

    var multilineAlignment: SwiftUI.TextAlignment {
        switch align {
        case .Center: .center
        case .End, .Right: .trailing
        default: .leading
        }
    }

    /// Frame alignment matching the text alignment (for `.frame(maxWidth: .infinity, alignment:)`).
    var frameAlignment: Alignment {
        switch align {
        case .Center: .center
        case .End, .Right: .trailing
        default: .leading
        }
    }
}

/// Big title text, e.g. game names and screen headers.
func displayStyle(_ size: CGFloat, _ color: Color = Royal.Ivory, _ align: TextAlign = .Start) -> TextStyle {
    TextStyle(family: .display, size: size, weight: .Normal, color: color, align: align, letterSpacing: 0.5)
}

/// Rounded body text.
func bodyStyle(_ size: CGFloat, _ weight: FontWeight = .Bold, _ color: Color = Royal.Ivory, _ align: TextAlign = .Start) -> TextStyle {
    TextStyle(family: .body, size: size, weight: weight, color: color, align: align, letterSpacing: 0)
}

extension Text {
    /// Compose `Text(text, style = …)`: font, colour and letter spacing (alignment is a view modifier; see `textStyle`).
    init(_ text: String, style: TextStyle) {
        self = Text(verbatim: text).font(style.font).foregroundColor(style.color).tracking(style.letterSpacing)
    }
}

extension View {
    /// Applies a `TextStyle` to any text-bearing view, including its multi-line alignment.
    func textStyle(_ style: TextStyle) -> some View {
        self.font(style.font)
            .foregroundStyle(style.color)
            .tracking(style.letterSpacing)
            .multilineTextAlignment(style.multilineAlignment)
    }
}

/// Text with a Compose `TextStyle`, `maxLines` and ellipsis overflow; `fill` stretches it across the width
/// (Compose `Modifier.fillMaxWidth()` + `textAlign`).
struct StyledText: View {
    let text: String
    let style: TextStyle
    var maxLines: Int? = nil
    var fill: Bool = false

    init(_ text: String, style: TextStyle, maxLines: Int? = nil, fill: Bool = false) {
        self.text = text
        self.style = style
        self.maxLines = maxLines
        self.fill = fill
    }

    var body: some View {
        let t = Text(text, style: style)
            .multilineTextAlignment(style.multilineAlignment)
            .lineLimit(maxLines)
            .truncationMode(.tail)
        if fill {
            t.frame(maxWidth: .infinity, alignment: style.frameAlignment)
        } else {
            t
        }
    }
}

// MARK: - Theme

/// When true, decorative loops (sparkles, shimmer, bobbing) hold still.
/// Kotlin `LocalReduceMotion.current` → `LocalReduceMotion.current` (the app's Reduce motion setting or iOS Reduce Motion).
enum LocalReduceMotion {
    static var current: Bool { AppSettings.data.reduceMotion || UIAccessibility.isReduceMotionEnabled }
}

/// Root theme: dark scheme, Royal tint, reduce-motion flag in the environment.
struct BoardGamesTheme<Content: View>: View {
    let reduceMotion: Bool
    let content: Content

    init(reduceMotion: Bool = false, @ViewBuilder content: () -> Content) {
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    var body: some View {
        content
            .tint(Royal.Gold)
            .preferredColorScheme(.dark)
            .environment(\.royalReduceMotion, reduceMotion || UIAccessibility.isReduceMotionEnabled)
    }
}

private struct RoyalReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The SwiftUI-environment twin of `LocalReduceMotion.current`.
    var royalReduceMotion: Bool {
        get { self[RoyalReduceMotionKey.self] }
        set { self[RoyalReduceMotionKey.self] = newValue }
    }
}
