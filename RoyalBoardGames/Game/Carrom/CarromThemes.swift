import SwiftUI
import GameKit

/// An sRGB colour with alpha that can be mixed like Compose's `lerp` (in Oklab) and faded like `copy(alpha = …)`.
/// Carrom's art keeps every colour in this form and hands SwiftUI a `Color` only when drawing.
struct CarromColor: Equatable, Hashable {
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

    /// 0xRRGGBB, opaque (Kotlin `hex(0xRRGGBB)`).
    init(_ rgb: UInt32) {
        self.init(r: Double((rgb >> 16) & 0xFF) / 255, g: Double((rgb >> 8) & 0xFF) / 255, b: Double(rgb & 0xFF) / 255, a: 1)
    }

    /// 0xAARRGGBB.
    init(argb: UInt32) {
        self.init(r: Double((argb >> 16) & 0xFF) / 255, g: Double((argb >> 8) & 0xFF) / 255, b: Double(argb & 0xFF) / 255,
                  a: Double((argb >> 24) & 0xFF) / 255)
    }

    static let white = CarromColor(r: 1, g: 1, b: 1)
    static let black = CarromColor(r: 0, g: 0, b: 0)
    /// Compose `Color.Transparent` (transparent black).
    static let transparent = CarromColor(r: 0, g: 0, b: 0, a: 0)

    /// The seat colour of a player, from the shared palette.
    static func player(_ p: PartyPlayer) -> CarromColor {
        let n = PartyStyle.tokenArgb.count
        return CarromColor(argb: PartyStyle.tokenArgb[((p.colorIndex % n) + n) % n])
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// Kotlin `Color.opacity(a)`: `copy(alpha = alpha * a)`.
    func opacity(_ x: Double) -> CarromColor { CarromColor(r: r, g: g, b: b, a: Swift.max(0, Swift.min(1, a * x))) }

    /// Kotlin `Color.mix(with, by)` = Compose `lerp`, which interpolates in Oklab.
    func mix(_ with: CarromColor, _ by: Double) -> CarromColor {
        let s = oklab
        let e = with.oklab
        let t = by
        let l = s.0 + (e.0 - s.0) * t
        let aa = s.1 + (e.1 - s.1) * t
        let bb = s.2 + (e.2 - s.2) * t
        var out = CarromColor.fromOklab(l, aa, bb)
        out.a = a + (with.a - a) * t
        return out
    }

    private static func decode(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : Foundation.pow((c + 0.055) / 1.055, 2.4) }
    private static func encode(_ c: Double) -> Double {
        let v = Swift.max(0, Swift.min(1, c))
        return v <= 0.0031308 ? v * 12.92 : 1.055 * Foundation.pow(v, 1 / 2.4) - 0.055
    }

    private var oklab: (Double, Double, Double) {
        let lr = CarromColor.decode(r), lg = CarromColor.decode(g), lb = CarromColor.decode(b)
        let l = Foundation.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = Foundation.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = Foundation.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func fromOklab(_ L: Double, _ A: Double, _ B: Double) -> CarromColor {
        let l_ = L + 0.3963377774 * A + 0.2158037573 * B
        let m_ = L - 0.1055613458 * A - 0.0638541728 * B
        let s_ = L - 0.0894841775 * A - 1.2914855480 * B
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return CarromColor(
            r: encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            g: encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            b: encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }
}

/// A board design: backdrop, frame wood, corner caps, surface, markings and the centre design.
final class CarromBoardTheme {
    enum Centre { case COMPASS, MANDALA, STAR, RANGOLI, PULSE, PEACOCK, SUN, CANDY }

    let id: Int
    let name: String
    /// Centre, edge.
    let backdrop: [CarromColor]
    /// Light, dark.
    let frame: [CarromColor]
    /// Light, dark.
    let surface: [CarromColor]
    let grain: CarromColor
    let line: CarromColor
    let circle: CarromColor
    let cap: CarromColor
    let centre: Centre
    let neon: Bool
    /// The coin set and striker that suit this board.
    let coins: Int
    let striker: Int

    init(_ id: Int, _ name: String, _ backdrop: [CarromColor], _ frame: [CarromColor], _ surface: [CarromColor], _ grain: CarromColor,
         _ line: CarromColor, _ circle: CarromColor, _ cap: CarromColor, _ centre: Centre, neon: Bool = false, coins: Int, striker: Int) {
        self.id = id
        self.name = name
        self.backdrop = backdrop
        self.frame = frame
        self.surface = surface
        self.grain = grain
        self.line = line
        self.circle = circle
        self.cap = cap
        self.centre = centre
        self.neon = neon
        self.coins = coins
        self.striker = striker
    }

    static func theme(_ id: Int) -> CarromBoardTheme { all.first { $0.id == id } ?? all[0] }

    private typealias H = CarromColor

    static let all: [CarromBoardTheme] = [
        CarromBoardTheme(0, "Teak Classic", [H(0xB4472F), H(0x3E0F0B)], [H(0xC27434), H(0x5A280E)],
                         [H(0xF6D9A8), H(0xDDA968)], H(0xB77A3A), H(0x4E2410), H(0xD7402B),
                         H(0xF5A021), .COMPASS, coins: 0, striker: 0),
        CarromBoardTheme(1, "Royal Rosewood", [H(0x8A35B0), H(0x24083A)], [H(0x86432A), H(0x2A0F08)],
                         [H(0xEDC892), H(0xC88F55)], H(0xA0652F), H(0x47190A), H(0xE5B23A),
                         H(0xF7CF5A), .MANDALA, coins: 1, striker: 6),
        CarromBoardTheme(2, "Lagoon", [H(0x1FB2A6), H(0x08454B)], [H(0xDCA56A), H(0x86562B)],
                         [H(0xF8E7C6), H(0xE5C392)], H(0xC79C62), H(0x1F7F7A), H(0x4CC3A5),
                         H(0xF6B93E), .STAR, coins: 2, striker: 5),
        CarromBoardTheme(3, "Rangoli Fest", [H(0xDE2C58), H(0x52081F)], [H(0xA9582F), H(0x46200C)],
                         [H(0xF7DCAA), H(0xDEB073)], H(0xBF894A), H(0x8A1838), H(0xF26B1D),
                         H(0xFFD24D), .RANGOLI, coins: 3, striker: 1),
        CarromBoardTheme(4, "Midnight Neon", [H(0x23287A), H(0x05061A)], [H(0x262A4E), H(0x0B0C1C)],
                         [H(0x2A2F5E), H(0x151838)], H(0x343B70), H(0x3EF4FF), H(0xFF3DCB),
                         H(0x3EF4FF), .PULSE, neon: true, coins: 4, striker: 7),
        CarromBoardTheme(5, "Peacock Palace", [H(0x2766B8), H(0x0A1B45)], [H(0x2F6878), H(0x0F2C36)],
                         [H(0xF3E0B4), H(0xD9B67B)], H(0xB88F50), H(0x17566E), H(0x2E9C6A),
                         H(0xEDBB40), .PEACOCK, coins: 6, striker: 4),
        CarromBoardTheme(6, "Desert Sunset", [H(0xF08A33), H(0x5E230B)], [H(0xC97A3D), H(0x6A3315)],
                         [H(0xF9E1BA), H(0xE8B77E)], H(0xCB9154), H(0x873810), H(0xE25A2B),
                         H(0xFFC65E), .SUN, coins: 7, striker: 1),
        CarromBoardTheme(7, "Candy Pop", [H(0xFF92CB), H(0x7A45D2)], [H(0xFFFFFF), H(0xF1BEDF)],
                         [H(0xFFF3F8), H(0xFADCEA)], H(0xF0BDD6), H(0xDE4E99), H(0x7C5CFF),
                         H(0x46D3C6), .CANDY, coins: 5, striker: 2),
    ]
}

/// A white, a black and a queen in one look.
final class CarromCoinSet {
    enum Motif { case RINGS, MANDALA, FACETS, PETALS, NEON, SWIRL, STAR, VEINS }

    struct Face {
        let light: CarromColor
        let body: CarromColor
        let shade: CarromColor
        let ink: CarromColor
    }

    let id: Int
    let name: String
    let white: Face
    let black: Face
    let queen: Face
    let motif: Motif

    init(_ id: Int, _ name: String, _ white: Face, _ black: Face, _ queen: Face, _ motif: Motif) {
        self.id = id
        self.name = name
        self.white = white
        self.black = black
        self.queen = queen
        self.motif = motif
    }

    func face(_ kind: CarromKind) -> Face {
        switch kind {
        case .WHITE: return white
        case .BLACK: return black
        default: return queen
        }
    }

    static func set(_ id: Int) -> CarromCoinSet { all.first { $0.id == id } ?? all[0] }

    private static func face(_ h: UInt32...) -> Face { Face(light: CarromColor(h[0]), body: CarromColor(h[1]), shade: CarromColor(h[2]), ink: CarromColor(h[3])) }

    static let all: [CarromCoinSet] = [
        CarromCoinSet(0, "Classic Wood", face(0xFFFAEE, 0xF0DFC0, 0xC8AD86, 0xB8946A), face(0x5C5C5C, 0x2B2B2B, 0x0E0E0E, 0x6A6A6A),
                      face(0xFF7A7A, 0xD7263D, 0x8A0E21, 0xFFB3B3), .RINGS),
        CarromCoinSet(1, "Mandala", face(0xFFFBF0, 0xF3E3C3, 0xCDB081, 0xC9A24A), face(0x4A3A30, 0x24180F, 0x0C0705, 0xD9B45A),
                      face(0xFF7B6B, 0xC81E2E, 0x7A0A15, 0xF5CF66), .MANDALA),
        CarromCoinSet(2, "Gemstone", face(0xFFFFFF, 0xE6ECF6, 0xAEB9CF, 0x8E9AB4), face(0x55556E, 0x1F1F30, 0x06060C, 0x8A8AB0),
                      face(0xFF9AB0, 0xE0115F, 0x6E052B, 0xFFD0DD), .FACETS),
        CarromCoinSet(3, "Lotus", face(0xFFF8FA, 0xF6E1E9, 0xD5ADBE, 0xE48FB0), face(0x3B3350, 0x1C1729, 0x08060F, 0x9C88D8),
                      face(0xFF8FB8, 0xE23C7E, 0x8A1446, 0xFFE0EC), .PETALS),
        CarromCoinSet(4, "Neon Ring", face(0xF4FFFF, 0xCFF6FA, 0x8FC9D3, 0x00C8D8), face(0x3A2E63, 0x1A1238, 0x07041A, 0xB46BFF),
                      face(0xFF7BE0, 0xFF2DB4, 0x8E0D63, 0xFFFFFF), .NEON),
        CarromCoinSet(5, "Candy Swirl", face(0xFFFDF5, 0xFBEFD9, 0xE2C9A3, 0xFF7BAC), face(0x7A4A2E, 0x4A2614, 0x210E05, 0xE8B36A),
                      face(0xFF6F7D, 0xE81D3A, 0x8A0617, 0xFFFFFF), .SWIRL),
        CarromCoinSet(6, "Starlight", face(0xFFFFF4, 0xF3EBD2, 0xCFC09A, 0xE2B43C), face(0x464A5A, 0x1D2030, 0x080A12, 0xC9D2E8),
                      face(0xFF8A6B, 0xE0402A, 0x84160B, 0xFFE08A), .STAR),
        CarromCoinSet(7, "Marble", face(0xFFFFFF, 0xEEEDEA, 0xC3C0BA, 0xA9A49B), face(0x4E4E52, 0x222225, 0x09090A, 0x8E8E96),
                      face(0xF27D7D, 0xC2273A, 0x6E0E1A, 0xFFC2C2), .VEINS),
    ]
}

/// A striker's look. Every striker has the same size and weight: designs are cosmetic only.
final class CarromStrikerStyle {
    enum Emblem { case COMPASS, SUNWHEEL, PETAL, BOLT, PEACOCK, WAVE, CROWN, PULSE }

    let id: Int
    let name: String
    let light: CarromColor
    let body: CarromColor
    let shade: CarromColor
    let rim: CarromColor
    let emblem: Emblem
    let inkA: CarromColor
    let inkB: CarromColor

    init(_ id: Int, _ name: String, _ light: CarromColor, _ body: CarromColor, _ shade: CarromColor, _ rim: CarromColor, _ emblem: Emblem,
         _ inkA: CarromColor, _ inkB: CarromColor) {
        self.id = id
        self.name = name
        self.light = light
        self.body = body
        self.shade = shade
        self.rim = rim
        self.emblem = emblem
        self.inkA = inkA
        self.inkB = inkB
    }

    static func style(_ id: Int) -> CarromStrikerStyle { all.first { $0.id == id } ?? all[0] }

    private static func make(_ id: Int, _ name: String, _ body: [UInt32], _ rim: UInt32, _ emblem: Emblem, _ ink: [UInt32]) -> CarromStrikerStyle {
        CarromStrikerStyle(id, name, CarromColor(body[0]), CarromColor(body[1]), CarromColor(body[2]), CarromColor(rim), emblem,
                           CarromColor(ink[0]), CarromColor(ink[1]))
    }

    static let all: [CarromStrikerStyle] = [
        make(0, "Compass", [0xFFFFFF, 0xEDEFF5, 0xB9BFCC], 0x2B3A67, .COMPASS, [0x2D5BD3, 0xE23B3B]),
        make(1, "Sunwheel", [0xFFF4C2, 0xF6C843, 0xC48A12], 0x8A4B06, .SUNWHEEL, [0xE2581C, 0x8A2B06]),
        make(2, "Petal", [0xFFFFFF, 0xFBE6EF, 0xE0AFC4], 0xB0336B, .PETAL, [0xE04C8C, 0xF7A9C8]),
        make(3, "Bolt", [0x4B5A8C, 0x1E2850, 0x0B1029], 0xFFD23A, .BOLT, [0xFFD23A, 0xFFF3B0]),
        make(4, "Peacock", [0x6FE0D0, 0x1C9C9A, 0x0D5A5E], 0xE8B53A, .PEACOCK, [0x1E4FB8, 0xE8B53A]),
        make(5, "Wave", [0xFFFFFF, 0xDFF3FF, 0x9FCBEA], 0x1B6FB5, .WAVE, [0x1B6FB5, 0x55B7F2]),
        make(6, "Crown", [0xA77BFF, 0x5B2BB8, 0x2A0F66], 0xF5CF5A, .CROWN, [0xF5CF5A, 0xFFF0B8]),
        make(7, "Pulse", [0x3A3F78, 0x161A3E, 0x070818], 0x3EF4FF, .PULSE, [0x3EF4FF, 0xFF3DCB]),
    ]
}
