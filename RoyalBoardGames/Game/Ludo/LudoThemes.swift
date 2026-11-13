import SwiftUI

/// A colour as Compose keeps it (sRGB + alpha), with Compose's `lerp` (it mixes in Oklab), so
/// every `mix` matches Android. Converts to SwiftUI `Color` and `CGColor` for drawing.
struct LudoColor: Equatable, Hashable {
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

    /// Kotlin `hex(rgb, alpha)`: `Color(0xFF000000 or rgb).copy(alpha = alpha)`.
    init(_ rgb: UInt32, _ alpha: Double = 1) {
        r = Double((rgb >> 16) & 0xFF) / 255
        g = Double((rgb >> 8) & 0xFF) / 255
        b = Double(rgb & 0xFF) / 255
        a = alpha
    }

    static let White = LudoColor(r: 1, g: 1, b: 1)
    static let Black = LudoColor(r: 0, g: 0, b: 0)
    static let Transparent = LudoColor(r: 0, g: 0, b: 0, a: 0)

    var alpha: Double { a }

    func copy(alpha: Double) -> LudoColor { LudoColor(r: r, g: g, b: b, a: alpha) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    // MARK: Compose lerp (Oklab)

    /// `Color.mix(other, by)` = Compose `lerp(this, other, by)`.
    func mix(_ other: LudoColor, _ by: Double) -> LudoColor {
        let p = toOklab()
        let q = other.toOklab()
        let l = p.0 + (q.0 - p.0) * by
        let aa = p.1 + (q.1 - p.1) * by
        let bb = p.2 + (q.2 - p.2) * by
        var out = LudoColor.fromOklab(l, aa, bb)
        out.a = a + (other.a - a) * by
        return out
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

    private static func fromOklab(_ L0: Double, _ A0: Double, _ B0: Double) -> LudoColor {
        // Compose's Oklab clamps its inputs before converting back.
        let L = min(max(L0, 0), 1), A = min(max(A0, -0.5), 0.5), B = min(max(B0, -0.5), 0.5)
        let l_ = L + 0.3963377774 * A + 0.2158037573 * B
        let m_ = L - 0.1055613458 * A - 0.0638541728 * B
        let s_ = L - 0.0894841775 * A - 1.2914855480 * B
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func c(_ v: Double) -> Double { min(max(toGamma(max(v, 0)), 0), 1) }
        return LudoColor(r: c(lr), g: c(lg), b: c(lb))
    }
}

/// Kotlin `hex(rgb, alpha)` (kept in a namespace: other games have their own `hex`).
@inline(__always) func ludoHex(_ rgb: UInt32, _ alpha: Double = 1) -> LudoColor { LudoColor(rgb, alpha) }

/// A complete Ludo board look: table, board, seat colours, token material and a light ambient
/// touch. Every design works on both the four-arm and six-arm boards.
/// Immutable, so it is safe to hand to the background renderers.
final class LudoTheme: Equatable, Hashable, @unchecked Sendable {
    enum TokenStyle { case GLOSS, GOLD, NEON, CANDY, PEARL, STONE }
    enum Ambient { case NONE, SHIMMER, PULSE, SPRINKLES, BUBBLES, FIREFLIES }

    let id: Int
    let name: String
    let backdrop: [LudoColor]
    /// The board's rim and the plate under the yards.
    let rim: LudoColor
    let cell: LudoColor
    let line: LudoColor
    let star: LudoColor
    let yardPlate: LudoColor
    let isDark: Bool
    let glow: Bool
    let four: [UInt32]
    let six: [UInt32]
    let token: TokenStyle
    let ambient: Ambient

    private let fourColors: [LudoColor]
    private let sixColors: [LudoColor]

    init(id: Int, name: String, backdrop: [LudoColor], rim: LudoColor, cell: LudoColor, line: LudoColor, star: LudoColor,
         yardPlate: LudoColor, isDark: Bool, glow: Bool, four: [UInt32], six: [UInt32], token: TokenStyle, ambient: Ambient) {
        self.id = id
        self.name = name
        self.backdrop = backdrop
        self.rim = rim
        self.cell = cell
        self.line = line
        self.star = star
        self.yardPlate = yardPlate
        self.isDark = isDark
        self.glow = glow
        self.four = four
        self.six = six
        self.token = token
        self.ambient = ambient
        fourColors = four.map { ludoHex($0) }
        sixColors = six.map { ludoHex($0) }
    }

    static func == (a: LudoTheme, b: LudoTheme) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Seat colour of `arm` on a board with `arms` arms.
    func color(_ arm: Int, _ arms: Int) -> LudoColor {
        let palette = arms == 6 ? sixColors : fourColors
        return palette[((arm % palette.count) + palette.count) % palette.count]
    }

    static func colorName(_ arm: Int, _ arms: Int) -> String {
        let names = arms == 6 ? ["Red", "Orange", "Yellow", "Green", "Blue", "Purple"] : ["Red", "Green", "Yellow", "Blue"]
        return names[((arm % names.count) + names.count) % names.count]
    }

    static let classic = LudoTheme(
        id: 0, name: "Classic", backdrop: [ludoHex(0x2A56C6), ludoHex(0x15308A)], rim: .White, cell: .White,
        line: ludoHex(0x1C1B29, 0.22), star: ludoHex(0x1C1B29, 0.45), yardPlate: .White, isDark: false, glow: false,
        four: [0xF0453A, 0x2DB45A, 0xFFC21C, 0x2E8BEF], six: [0xF0453A, 0xFF8A1F, 0xFFC21C, 0x2DB45A, 0x2E8BEF, 0x8E5BE8],
        token: .GLOSS, ambient: .NONE
    )
    static let royal = LudoTheme(
        id: 1, name: "Royal Court", backdrop: [ludoHex(0x5A0F2E), ludoHex(0x2A0616)], rim: ludoHex(0xE8C26A), cell: ludoHex(0xFFF7E6),
        line: ludoHex(0x8A5A1A, 0.35), star: ludoHex(0xB8862B), yardPlate: ludoHex(0xFFF7E6), isDark: false, glow: false,
        four: [0xB0182F, 0x13804A, 0xE0A512, 0x1B4FA8], six: [0xB0182F, 0xD9661E, 0xE0A512, 0x13804A, 0x1B4FA8, 0x6A2D9C],
        token: .GOLD, ambient: .SHIMMER
    )
    static let neon = LudoTheme(
        id: 2, name: "Neon Night", backdrop: [ludoHex(0x1A1440), ludoHex(0x07051F)], rim: ludoHex(0x2A2160), cell: ludoHex(0x1C1745),
        line: ludoHex(0xFFFFFF, 0.12), star: ludoHex(0xFFFFFF, 0.55), yardPlate: ludoHex(0x120E33), isDark: true, glow: true,
        four: [0xFF4D6D, 0x3DFF9A, 0xFFE14D, 0x3DC8FF], six: [0xFF4D6D, 0xFF9A3D, 0xFFE14D, 0x3DFF9A, 0x3DC8FF, 0xC77DFF],
        token: .NEON, ambient: .PULSE
    )
    static let candy = LudoTheme(
        id: 3, name: "Candy Land", backdrop: [ludoHex(0xFFB6D9), ludoHex(0xB9A4FF)], rim: .White, cell: ludoHex(0xFFF6FB),
        line: ludoHex(0xD86AA8, 0.3), star: ludoHex(0xD86AA8, 0.65), yardPlate: .White, isDark: false, glow: false,
        four: [0xFF6B9A, 0x6FD99A, 0xFFD45C, 0x6AB8FF], six: [0xFF6B9A, 0xFFA45C, 0xFFD45C, 0x6FD99A, 0x6AB8FF, 0xB78AFF],
        token: .CANDY, ambient: .SPRINKLES
    )
    static let reef = LudoTheme(
        id: 4, name: "Coral Reef", backdrop: [ludoHex(0x0E7C9C), ludoHex(0x074A66)], rim: ludoHex(0xF3E3B5), cell: ludoHex(0xFFF9E8),
        line: ludoHex(0x6B5A2A, 0.25), star: ludoHex(0x0E7C9C, 0.6), yardPlate: ludoHex(0xFFF9E8), isDark: false, glow: false,
        four: [0xFF6F61, 0x2EC4B6, 0xFFD166, 0x3A86FF], six: [0xFF6F61, 0xFF9F43, 0xFFD166, 0x2EC4B6, 0x3A86FF, 0x9B5DE5],
        token: .PEARL, ambient: .BUBBLES
    )
    static let jungle = LudoTheme(
        id: 5, name: "Jungle Temple", backdrop: [ludoHex(0x1F4D2B), ludoHex(0x0F2A17)], rim: ludoHex(0xB9A77E), cell: ludoHex(0xE9E1C8),
        line: ludoHex(0x5A4A2A, 0.35), star: ludoHex(0x5A4A2A, 0.65), yardPlate: ludoHex(0xE9E1C8), isDark: false, glow: false,
        four: [0xC2412D, 0x4C9A2A, 0xE3B23C, 0x2D6DA8], six: [0xC2412D, 0xD9822B, 0xE3B23C, 0x4C9A2A, 0x2D6DA8, 0x7A4FA8],
        token: .STONE, ambient: .FIREFLIES
    )

    static let all: [LudoTheme] = [classic, royal, neon, candy, reef, jungle]

    static func theme(_ id: Int) -> LudoTheme { all.first { $0.id == id } ?? classic }
}
