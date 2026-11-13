import SwiftUI
import CoreGraphics

/// An sRGB colour usable by SwiftUI and CoreGraphics alike (the Kotlin code's Compose `Color`).
/// Named apart from the other games' `hex` helpers so the module has no clashes.
struct PoolRGBA: Equatable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// 0xRRGGBB, opaque (the Kotlin `hex(0x…)`).
    init(_ rgb: UInt32) {
        r = Double((rgb >> 16) & 0xFF) / 255
        g = Double((rgb >> 8) & 0xFF) / 255
        b = Double(rgb & 0xFF) / 255
        a = 1
    }

    /// 0xAARRGGBB.
    init(argb: UInt32) {
        self.init(argb & 0xFF_FFFF)
        a = Double((argb >> 24) & 0xFF) / 255
    }

    static let white = PoolRGBA(r: 1, g: 1, b: 1)
    static let black = PoolRGBA(r: 0, g: 0, b: 0)
    static let clear = PoolRGBA(r: 0, g: 0, b: 0, a: 0)

    /// Compose `copy(alpha = …)`.
    func alpha(_ v: Double) -> PoolRGBA { PoolRGBA(r: r, g: g, b: b, a: min(1, max(0, v))) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    /// Compose `lerp(start, stop, fraction)`: interpolated in Oklab, like Compose.
    func lerp(_ to: PoolRGBA, _ t: Double) -> PoolRGBA {
        let s = PoolRGBA.oklab(self)
        let e = PoolRGBA.oklab(to)
        return PoolRGBA.fromOklab(s.0 + (e.0 - s.0) * t, s.1 + (e.1 - s.1) * t, s.2 + (e.2 - s.2) * t, a + (to.a - a) * t)
    }

    private static func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func toSRGB(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    private static func oklab(_ c: PoolRGBA) -> (Double, Double, Double) {
        let r = toLinear(c.r), g = toLinear(c.g), b = toLinear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func fromOklab(_ L: Double, _ A: Double, _ B: Double, _ alpha: Double) -> PoolRGBA {
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func c(_ v: Double) -> Double { min(1, max(0, toSRGB(max(0, v)))) }
        return PoolRGBA(r: c(r), g: c(g), b: c(b), a: min(1, max(0, alpha)))
    }
}

/// The Kotlin `hex(0xRRGGBB)` for this game's files.
@inline(__always)
func poolHex(_ v: UInt32) -> PoolRGBA { PoolRGBA(v) }

/// A table design: cloth, rails and their pattern, trim, backdrop and the cloth's centre emblem.
final class PoolTableTheme: Identifiable, @unchecked Sendable {
    enum Rail: Sendable { case Wood, Studded, Ornate, Neon, Baroque, Frost, Sandstone, Bamboo }
    enum Emblem: Sendable { case Crest, Wave, Flame, Circuit, Crown, Snowflake, Sun, Lotus }

    let id: Int
    let name: String
    /// Centre, edge.
    let cloth: [PoolRGBA]
    /// Light, dark.
    let rail: [PoolRGBA]
    let style: Rail
    let trim: PoolRGBA
    /// Top, bottom.
    let backdrop: [PoolRGBA]
    let emblem: Emblem
    let neon: Bool
    /// The cue that suits this table.
    let cue: Int

    init(_ id: Int, _ name: String, _ cloth: [PoolRGBA], _ rail: [PoolRGBA], _ style: Rail, _ trim: PoolRGBA,
         _ backdrop: [PoolRGBA], _ emblem: Emblem, neon: Bool = false, cue: Int) {
        self.id = id; self.name = name; self.cloth = cloth; self.rail = rail; self.style = style; self.trim = trim
        self.backdrop = backdrop; self.emblem = emblem; self.neon = neon; self.cue = cue
    }

    static func theme(_ id: Int) -> PoolTableTheme { all.first { $0.id == id } ?? all[0] }

    static let all: [PoolTableTheme] = [
        PoolTableTheme(0, "Club Green", [poolHex(0x36B062), poolHex(0x157038)], [poolHex(0x9A4524), poolHex(0x4A1A0A)],
                       .Wood, poolHex(0xD9A441), [poolHex(0x163326), poolHex(0x07120C)], .Crest, cue: 0),
        PoolTableTheme(1, "Ocean Blue", [poolHex(0x45B2E0), poolHex(0x1A6898)], [poolHex(0xA6362C), poolHex(0x58140F)],
                       .Studded, poolHex(0xC8D0D8), [poolHex(0x1D2E52), poolHex(0x0A1226)], .Wave, cue: 2),
        PoolTableTheme(2, "Crimson Club", [poolHex(0xE03535), poolHex(0x8A0E0E)], [poolHex(0x34343A), poolHex(0x0E0E10)],
                       .Ornate, poolHex(0xCDD2DA), [poolHex(0x2A1F36), poolHex(0x0E0A14)], .Flame, cue: 1),
        PoolTableTheme(3, "Midnight Neon", [poolHex(0x262B42), poolHex(0x0C0E18)], [poolHex(0x1A1C33), poolHex(0x07080F)],
                       .Neon, poolHex(0x3EF4FF), [poolHex(0x10133A), poolHex(0x020309)], .Circuit, neon: true, cue: 3),
        PoolTableTheme(4, "Royal Velvet", [poolHex(0x8A48DC), poolHex(0x47188A)], [poolHex(0xF6D982), poolHex(0xA0701A)],
                       .Baroque, poolHex(0xFFE7A0), [poolHex(0x33164E), poolHex(0x12061E)], .Crown, cue: 4),
        PoolTableTheme(5, "Frost Lounge", [poolHex(0xD8EAF3), poolHex(0x9BBFD3)], [poolHex(0xF6F9FC), poolHex(0xAFBCCB)],
                       .Frost, poolHex(0x2F6FB0), [poolHex(0x213656), poolHex(0x0B1426)], .Snowflake, cue: 5),
        PoolTableTheme(6, "Desert Mirage", [poolHex(0xDDB884), poolHex(0xA5773E)], [poolHex(0xEDCF9F), poolHex(0x96632F)],
                       .Sandstone, poolHex(0x7A3E14), [poolHex(0x432914), poolHex(0x1A0E06)], .Sun, cue: 6),
        PoolTableTheme(7, "Jade Temple", [poolHex(0x26B2A3), poolHex(0x0B675E)], [poolHex(0xD0AC60), poolHex(0x7A561E)],
                       .Bamboo, poolHex(0xE8C76A), [poolHex(0x12302D), poolHex(0x051211)], .Lotus, cue: 7),
    ]
}

/// A cue's look. Every cue plays the same: designs are cosmetic only.
final class PoolCueStyle: Identifiable, @unchecked Sendable {
    enum Inlay: Sendable { case Plain, Rings, Points, Neon, Gems, Crystal, Tiger, Stars }

    let id: Int
    let name: String
    let shaft: [PoolRGBA]
    let forearm: [PoolRGBA]
    let butt: [PoolRGBA]
    let accent: PoolRGBA
    let inlay: Inlay

    init(_ id: Int, _ name: String, _ shaft: [PoolRGBA], _ forearm: [PoolRGBA], _ butt: [PoolRGBA], _ accent: PoolRGBA, _ inlay: Inlay) {
        self.id = id; self.name = name; self.shaft = shaft; self.forearm = forearm; self.butt = butt; self.accent = accent; self.inlay = inlay
    }

    static func style(_ id: Int) -> PoolCueStyle { all.first { $0.id == id } ?? all[0] }

    private static func make(_ id: Int, _ name: String, _ shaft: [UInt32], _ forearm: [UInt32], _ butt: [UInt32], _ accent: UInt32, _ inlay: Inlay) -> PoolCueStyle {
        PoolCueStyle(id, name, shaft.map(poolHex), forearm.map(poolHex), butt.map(poolHex), poolHex(accent), inlay)
    }

    static let all: [PoolCueStyle] = [
        make(0, "Oak Classic", [0xF3E2C2, 0xD9BF8E], [0xB07A3E, 0x7A4E22], [0x5A3414, 0x2E1808], 0xF5EBD6, .Plain),
        make(1, "Ebony Pro", [0xF5E9D2, 0xDCC9A6], [0x2B2B30, 0x0E0E10], [0x1C1C20, 0x050506], 0xD8DEE6, .Rings),
        make(2, "Copper Strike", [0xF4E5CB, 0xDBC49F], [0xE08A4B, 0x9A4A1C], [0x6E2E10, 0x3A1606], 0xFFD2A0, .Points),
        make(3, "Neon Pulse", [0xE9F6FF, 0xB9D3E6], [0x1A1C33, 0x07080F], [0x12142A, 0x05060F], 0x3EF4FF, .Neon),
        make(4, "Royal Gold", [0xFBF1D9, 0xE4CFA3], [0xF6D982, 0xB07F1E], [0x7A3BD0, 0x3E1478], 0xE0115F, .Gems),
        make(5, "Frost", [0xF7FBFF, 0xD6E6F2], [0xBFE6FF, 0x5FA6D6], [0x2F6FB0, 0x173A66], 0xFFFFFF, .Crystal),
        make(6, "Tiger Maple", [0xF6E6C6, 0xDEC294], [0xE7A64B, 0x9A5A14], [0x3A2008, 0x1A0E04], 0x1A0E04, .Tiger),
        make(7, "Galaxy", [0xF2ECFF, 0xD2C6F0], [0x3B1E78, 0x120634], [0x1E0E44, 0x07021A], 0xFFD24D, .Stars),
    ]
}

enum PoolBallColour {
    private static let base: [Int: UInt32] = [1: 0xF5C518, 2: 0x1F4FD8, 3: 0xE0242B, 4: 0x6B2FA8, 5: 0xF57C12, 6: 0x138A3E, 7: 0x8A1E1E, 8: 0x141414]
    private static let table: [PoolRGBA] = (0...15).map { n in poolHex(base[n > 8 ? n - 8 : n] ?? 0x141414) }

    static func colour(_ n: Int) -> PoolRGBA { n >= 0 && n < 16 ? table[n] : poolHex(base[n > 8 ? n - 8 : n] ?? 0x141414) }
}
