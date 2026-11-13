import SwiftUI

/// A colour as Compose keeps it (sRGB + alpha) with Compose's `lerp` (it mixes in Oklab), so every
/// `mix` matches Android. Converts to SwiftUI `Color` and `CGColor` for drawing.
struct SnakesColor: Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Kotlin `hex(v)`: `Color(0xFF000000 or v)`.
    init(_ rgb: UInt32) {
        r = Double((rgb >> 16) & 0xFF) / 255
        g = Double((rgb >> 8) & 0xFF) / 255
        b = Double(rgb & 0xFF) / 255
        a = 1
    }

    /// Compose `Color(0xAARRGGBB)`.
    init(argb: UInt32) {
        r = Double((argb >> 16) & 0xFF) / 255
        g = Double((argb >> 8) & 0xFF) / 255
        b = Double(argb & 0xFF) / 255
        a = Double((argb >> 24) & 0xFF) / 255
    }

    static let White = SnakesColor(r: 1, g: 1, b: 1)
    static let Black = SnakesColor(r: 0, g: 0, b: 0)
    static let Transparent = SnakesColor(r: 0, g: 0, b: 0, a: 0)

    /// A seat colour (`PartyPlayer.color`) in this colour type.
    static func player(_ p: PartyPlayer) -> SnakesColor {
        let n = PartyStyle.tokenArgb.count
        return SnakesColor(argb: PartyStyle.tokenArgb[((p.colorIndex % n) + n) % n])
    }

    var alpha: Double { a }

    /// Compose `copy(alpha = x)`.
    func copy(alpha: Double) -> SnakesColor { SnakesColor(r: r, g: g, b: b, a: alpha) }

    /// Kotlin `Color.argb(alpha)` in SnakesBoardArt: this colour with its alpha multiplied by `alpha`.
    func argb(_ alpha: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a * alpha) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    // MARK: Compose lerp (Oklab)

    /// `Color.mix(other, by)` = Compose `lerp(this, other, by)`.
    func mix(_ other: SnakesColor, _ by: Double) -> SnakesColor {
        let p = toOklab()
        let q = other.toOklab()
        let rgb = SnakesColor.fromOklab(p.0 + (q.0 - p.0) * by, p.1 + (q.1 - p.1) * by, p.2 + (q.2 - p.2) * by)
        return SnakesColor(r: rgb.0, g: rgb.1, b: rgb.2, a: a + (other.a - a) * by)
    }

    private static func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func toGamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    private func toOklab() -> (Double, Double, Double) {
        let lr = Self.toLinear(r), lg = Self.toLinear(g), lb = Self.toLinear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    private static func fromOklab(_ L: Double, _ A: Double, _ B: Double) -> (Double, Double, Double) {
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func c(_ v: Double) -> Double { min(1, max(0, toGamma(v))) }
        return (c(r), c(g), c(b))
    }
}

enum SnakePattern: String, CaseIterable { case STRIPES, SPOTS, DIAMONDS, GLOW }

enum SnakesBackdrop: String, CaseIterable { case DOTS, STARS, BUBBLES, GRID, CONFETTI }

struct LadderStyle: Equatable {
    let rails: [SnakesColor]
    let rung: SnakesColor
    /// Candy-cane style stripes along the rails.
    var stripe: SnakesColor? = nil
    var glow: SnakesColor? = nil
    /// Bamboo-style knots on the rails.
    var knots: Bool = false

    init(_ rails: [SnakesColor], _ rung: SnakesColor, stripe: SnakesColor? = nil, glow: SnakesColor? = nil, knots: Bool = false) {
        self.rails = rails
        self.rung = rung
        self.stripe = stripe
        self.glow = glow
        self.knots = knots
    }
}

/// The look of one board. Rules and the 1–100 path are identical across themes.
struct SnakesTheme: Equatable, Identifiable {
    let id: Int
    let name: String
    let emoji: String
    let tagline: String
    let background: [SnakesColor]
    let frame: SnakesColor
    /// Two-tone checker, light and strong, like a printed board.
    let cellA: SnakesColor
    let cellB: SnakesColor
    /// Number colour on `cellA` and on `cellB`.
    let numberColor: SnakesColor
    let numberColorB: SnakesColor
    let isDark: Bool
    /// Body and pattern colour for each snake, picked to stand out on both cell tones.
    let snakeColors: [[SnakesColor]]
    let snakePattern: SnakePattern
    let ladder: LadderStyle
    let accent: SnakesColor
    let backdrop: SnakesBackdrop

    init(
        _ id: Int, _ name: String, _ emoji: String, _ tagline: String,
        _ background: [SnakesColor], _ frame: SnakesColor,
        _ cellA: SnakesColor, _ cellB: SnakesColor,
        _ numberColor: SnakesColor, _ numberColorB: SnakesColor, _ isDark: Bool,
        _ snakeColors: [[SnakesColor]],
        _ snakePattern: SnakePattern,
        _ ladder: LadderStyle,
        _ accent: SnakesColor, _ backdrop: SnakesBackdrop
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.tagline = tagline
        self.background = background
        self.frame = frame
        self.cellA = cellA
        self.cellB = cellB
        self.numberColor = numberColor
        self.numberColorB = numberColorB
        self.isDark = isDark
        self.snakeColors = snakeColors
        self.snakePattern = snakePattern
        self.ladder = ladder
        self.accent = accent
        self.backdrop = backdrop
    }

    /// Top-to-bottom gradient for `background` (Compose `Brush.verticalGradient(theme.background)`).
    var backgroundGradient: LinearGradient {
        LinearGradient(colors: background.map(\.color), startPoint: .top, endPoint: .bottom)
    }

    static func theme(_ id: Int) -> SnakesTheme { all.first { $0.id == id } ?? all[0] }

    private static func pairs(_ hexes: (UInt32, UInt32)...) -> [[SnakesColor]] {
        hexes.map { [hex($0.0), hex($0.1)] }
    }

    private static func hex(_ v: UInt32) -> SnakesColor { SnakesColor(v) }

    private static let white = SnakesColor.White

    static let all: [SnakesTheme] = [
        SnakesTheme(
            0, "Classic Garden", "🌷", "Sunny lawns and garden snakes",
            [hex(0xEAF6D6), hex(0xB9E08F)], hex(0x9A6332),
            hex(0xFFF8E1), hex(0x58B04A),
            hex(0x2E6B1E), white, false,
            pairs((0xE53935, 0xFFD54F), (0xFB8C00, 0x4E342E), (0x8E24AA, 0xF8BBD0), (0x1E88E5, 0xFFF59D), (0xFDD835, 0x3E2723)),
            .STRIPES,
            LadderStyle([hex(0xB86B35), hex(0x7B3F1A)], hex(0xE0A86A)),
            hex(0x43A047), .DOTS
        ),
        SnakesTheme(
            1, "Candy Kingdom", "🍭", "Candy-cane ladders, licorice snakes",
            [hex(0xFFE6F3), hex(0xFFC2E2)], hex(0xFF5FAE),
            hex(0xFFF4FA), hex(0xFF8CC6),
            hex(0xC2185B), white, false,
            pairs((0x7C4DFF, 0xFFFFFF), (0x00BFA5, 0xFFF59D), (0xFF6D00, 0xFFFFFF), (0x3D5AFE, 0xFF80AB), (0xD50000, 0xFFFFFF)),
            .STRIPES,
            LadderStyle([hex(0xFFFFFF), hex(0xE8D3DD)], hex(0xFFD1E3), stripe: hex(0xFF3B5C)),
            hex(0xFF4F8B), .CONFETTI
        ),
        SnakesTheme(
            2, "Space Adventure", "🚀", "Comet snakes and rocket ladders",
            [hex(0x0B1026), hex(0x2A1B5A)], hex(0x6C63FF),
            hex(0x161B42), hex(0x2B3480),
            hex(0xAEB6FF), white, true,
            pairs((0xFF4FD8, 0xFFE0F7), (0x00E5FF, 0xE0FFFF), (0x76FF03, 0xF1FFE0), (0xFFAB00, 0xFFF3D6), (0xFF5252, 0xFFE3E3)),
            .GLOW,
            LadderStyle([hex(0xE6ECF5), hex(0x8A94A6)], hex(0xC9D2E3), glow: hex(0x8AB4FF)),
            hex(0x6C63FF), .STARS
        ),
        SnakesTheme(
            3, "Underwater World", "🐠", "Eels, coral and rising bubbles",
            [hex(0xBDF3FF), hex(0x3FA7D6)], hex(0x1D6FA3),
            hex(0xE8FBFF), hex(0x2FA8D8),
            hex(0x0E6A93), white, false,
            pairs((0xFF7043, 0xFFE0B2), (0x8E24AA, 0xE1BEE7), (0xFFCA28, 0x5D4037), (0x43A047, 0xC8E6C9), (0xEC407A, 0xFCE4EC)),
            .SPOTS,
            LadderStyle([hex(0xFF8A5C), hex(0xD9452A)], hex(0xFFB38A)),
            hex(0x1D9BD7), .BUBBLES
        ),
        SnakesTheme(
            4, "Jungle Safari", "🌴", "Pythons and bamboo ladders",
            [hex(0xDCEE9C), hex(0x76C893)], hex(0x6B4423),
            hex(0xFBF3D5), hex(0x6A9A3A),
            hex(0x3E5B1E), hex(0xFFF8E1), false,
            pairs((0xF9A825, 0x5D4037), (0xE65100, 0x212121), (0x6A1B9A, 0xFFD54F), (0xC62828, 0xFFE082), (0x0277BD, 0xB3E5FC)),
            .DIAMONDS,
            LadderStyle([hex(0xE9C46A), hex(0xA67C1F)], hex(0xF1DB9C), knots: true),
            hex(0x386641), .DOTS
        ),
        SnakesTheme(
            5, "Fantasy Kingdom", "🏰", "Golden ladders and dragon snakes",
            [hex(0xEADCFD), hex(0xB794F4)], hex(0x6B46C1),
            hex(0xFCF8FF), hex(0x8B5CF6),
            hex(0x5B21B6), white, false,
            pairs((0xE53935, 0xFFD54F), (0x2E7D32, 0xF6E05E), (0x1565C0, 0xE3F2FD), (0xFF8F00, 0x4E342E), (0xD81B60, 0xFFFFFF)),
            .DIAMONDS,
            LadderStyle([hex(0xF6E05E), hex(0xB7791F)], hex(0xFAF089), glow: hex(0xF6E05E)),
            hex(0x6B46C1), .STARS
        ),
        SnakesTheme(
            6, "Desert Adventure", "🌵", "Rattlesnakes and rope ladders",
            [hex(0xFFEBC0), hex(0xF4A261)], hex(0x8B4513),
            hex(0xFFF3DC), hex(0xD9893B),
            hex(0x8A4B0F), white, false,
            pairs((0x2A9D8F, 0xE9F5DB), (0x8D2B2B, 0xF4D58D), (0x6A4C93, 0xFFE5A0), (0x386641, 0xDDE5B6), (0x1D4E89, 0xFFD166)),
            .DIAMONDS,
            LadderStyle([hex(0x8B5A2B), hex(0x5C3A1A)], hex(0xD4A373), stripe: hex(0xC9A26B)),
            hex(0xE76F51), .DOTS
        ),
        SnakesTheme(
            7, "Dinosaur World", "🦖", "Bone ladders and volcano views",
            [hex(0xE2E8BD), hex(0xA9BF6F)], hex(0x5D4037),
            hex(0xF3ECD6), hex(0x8D6E4F),
            hex(0x5D4037), hex(0xFFF6E0), false,
            pairs((0x7CB342, 0x33691E), (0xF4511E, 0xFFE0B2), (0x00897B, 0xB2DFDB), (0xFDD835, 0x5D4037), (0xC62828, 0xFFCDD2)),
            .SPOTS,
            LadderStyle([hex(0xFFFDF5), hex(0xC9BC9C)], hex(0xF5EFE0)),
            hex(0xBC6C25), .DOTS
        ),
        SnakesTheme(
            8, "Neon Cyber World", "👾", "Glowing circuits after dark",
            [hex(0x05010F), hex(0x1A0533)], hex(0x00F5FF),
            hex(0x0C0322), hex(0x22104F),
            hex(0x7DF9FF), hex(0xFF8CF5), true,
            pairs((0xFF00E5, 0xFFFFFF), (0x39FF14, 0xFFFFFF), (0xFFE600, 0xFFFFFF), (0xFF3D71, 0xFFFFFF), (0xFF8A00, 0xFFFFFF)),
            .GLOW,
            LadderStyle([hex(0x00F5FF), hex(0x00A3B8)], hex(0x7DF9FF), glow: hex(0x00F5FF)),
            hex(0xFF00E5), .GRID
        ),
        SnakesTheme(
            9, "Festive Celebration", "🎉", "Ribbons, balloons and confetti",
            [hex(0xFFF2E6), hex(0xFFD3D3)], hex(0xE0A526),
            hex(0xFFF8EE), hex(0xB5173F),
            hex(0xA4133C), white, false,
            pairs((0x2A9D8F, 0xFFFFFF), (0x7B2CBF, 0xFCBF49), (0x277DA1, 0xFFFFFF), (0x43AA8B, 0xFFF3B0), (0xF77F00, 0xFFFFFF)),
            .STRIPES,
            LadderStyle([hex(0xFCBF49), hex(0xC98A1A)], hex(0xFFE8A3), stripe: hex(0xD62828)),
            hex(0xD62828), .CONFETTI
        ),
    ]
}
