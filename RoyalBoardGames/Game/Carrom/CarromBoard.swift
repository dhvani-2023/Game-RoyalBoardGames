import Foundation

/// Kotlin/JVM `Math.max` / `Math.min` on Double (NaN propagates, −0.0 sorts below 0.0), so every clamp in the
/// engine gives the same bits as Android.
enum CarromMath {
    @inline(__always)
    static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0 && b == 0 && a.sign == .minus { return b }
        return a >= b ? a : b
    }

    @inline(__always)
    static func min(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0 && b == 0 && b.sign == .minus { return b }
        return a <= b ? a : b
    }

    /// `java.lang.Double.compare`: total order with −0.0 < 0.0 and NaN above everything.
    @inline(__always)
    static func compare(_ a: Double, _ b: Double) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        let ab = a.isNaN ? Int64(0x7ff8_0000_0000_0000) : Int64(bitPattern: a.bitPattern)
        let bb = b.isNaN ? Int64(0x7ff8_0000_0000_0000) : Int64(bitPattern: b.bitPattern)
        return ab == bb ? 0 : (ab < bb ? -1 : 1)
    }
}

/// A point or vector on the board, in centimetres.
struct CarromVec: Equatable, Hashable, Codable {
    var x: Double = 0.0
    var y: Double = 0.0

    init(_ x: Double = 0.0, _ y: Double = 0.0) {
        self.x = x
        self.y = y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: CarromVec, o: CarromVec) -> CarromVec { CarromVec(a.x + o.x, a.y + o.y) }
    static func - (a: CarromVec, o: CarromVec) -> CarromVec { CarromVec(a.x - o.x, a.y - o.y) }
    static func * (a: CarromVec, s: Double) -> CarromVec { CarromVec(a.x * s, a.y * s) }
    static func / (a: CarromVec, s: Double) -> CarromVec { CarromVec(a.x / s, a.y / s) }
    static prefix func - (a: CarromVec) -> CarromVec { CarromVec(-a.x, -a.y) }

    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: CarromVec {
        let l = length
        return l > 1e-9 ? self / l : CarromVec.ZERO
    }

    func dot(_ o: CarromVec) -> Double { x * o.x + y * o.y }
    func rotated(_ a: Double) -> CarromVec {
        CarromVec(x * CarromFdLibm.cos(a) - y * CarromFdLibm.sin(a), x * CarromFdLibm.sin(a) + y * CarromFdLibm.cos(a))
    }

    static let ZERO = CarromVec(0.0, 0.0)

    enum CodingKeys: String, CodingKey { case x, y }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.carrom(.x, 0.0)
        y = c.carrom(.y, 0.0)
    }
}

enum CarromKind: String, Codable, CaseIterable {
    case WHITE, BLACK, QUEEN, STRIKER

    /// Kotlin `ordinal`.
    var ordinal: Int {
        switch self {
        case .WHITE: return 0
        case .BLACK: return 1
        case .QUEEN: return 2
        case .STRIKER: return 3
        }
    }
}

/// A disc on the board. Position and velocity are kept as plain doubles so the physics loop never allocates;
/// [p] and [v] read them back as vectors.
struct CarromDisc: Equatable, Codable {
    var kind: CarromKind = .WHITE
    var x: Double = 0.0
    var y: Double = 0.0
    var vx: Double = 0.0
    var vy: Double = 0.0
    var live: Bool = true

    init(kind: CarromKind = .WHITE, x: Double = 0.0, y: Double = 0.0, vx: Double = 0.0, vy: Double = 0.0, live: Bool = true) {
        self.kind = kind
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.live = live
    }

    init(_ kind: CarromKind, _ p: CarromVec) {
        self.init(kind: kind, x: p.x, y: p.y)
    }

    var p: CarromVec {
        get { CarromVec(x, y) }
        set { x = newValue.x; y = newValue.y }
    }

    var v: CarromVec {
        get { CarromVec(vx, vy) }
        set { vx = newValue.x; vy = newValue.y }
    }

    var r: Double { kind == .STRIKER ? CarromBoard.strikerR : CarromBoard.coinR }
    var m: Double { kind == .STRIKER ? CarromBoard.strikerM : CarromBoard.coinM }

    enum CodingKeys: String, CodingKey { case kind, x, y, vx, vy, live }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.carrom(.kind, CarromKind.WHITE)
        x = c.carrom(.x, 0.0)
        y = c.carrom(.y, 0.0)
        vx = c.carrom(.vx, 0.0)
        vy = c.carrom(.vy, 0.0)
        live = c.carrom(.live, true)
    }
}

extension Array where Element == CarromDisc {
    /// Deep copy of a disc list (discs are values, so this is the list itself).
    func cloned() -> [CarromDisc] { self }
}

extension KeyedDecodingContainer {
    /// kotlinx `ignoreUnknownKeys` + `coerceInputValues`: a missing, null or unreadable field takes its default.
    func carrom<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        if let v = (try? decodeIfPresent(T.self, forKey: key)) ?? nil { return v }
        return fallback()
    }

    /// An optional field: missing, null or unreadable reads as nil.
    func carromOptional<T: Decodable>(_ key: Key, _ type: T.Type) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

/// The board from the ICF laws (1993), in cm with the origin at the centre, x right and y down.
/// Sides: 0 bottom, 1 right, 2 top, 3 left. See docs/CARROM_SPEC.md §3.
enum CarromBoard {
    /// Pieces, pockets and the circles they must fit are drawn 15% over regulation so they read well on a phone;
    /// the board, its lines and the masses stay regulation.
    static let pieceScale = 1.15
    static let half = 37.0
    static let pocketR = 2.225 * pieceScale
    static let pocketC = half - pocketR
    static let coinR = 1.59 * pieceScale
    static let coinM = 5.25
    static let strikerR = 2.065 * pieceScale
    static let strikerM = 15.0
    /// The thick base line, 10.15 cm in from the frame, and the thin one a coin's width further in.
    static let baseOuter = half - 10.15
    static let baseInner = baseOuter - 3.18 * pieceScale
    /// The striker's centre line: it touches both base lines.
    static let baseY = (baseOuter + baseInner) / 2
    static let baseHalf = 23.5
    static let baseCircleR = 1.59 * pieceScale
    /// At either end the striker covers the base circle fully.
    static let slideMax = baseHalf - baseCircleR
    static let centreR = 1.59 * pieceScale
    static let outerR = 8.5 * pieceScale
    static let pockets: [CarromVec] = [
        CarromVec(-pocketC, -pocketC), CarromVec(pocketC, -pocketC), CarromVec(pocketC, pocketC), CarromVec(-pocketC, pocketC),
    ]

    static func rotation(_ side: Int) -> Double { -Double(side) * Double.pi / 2 }

    /// Where the striker sits for [slide] in −1…1, from the shooter's left to right.
    static func strikerSpot(_ side: Int, _ slide: Double) -> CarromVec {
        CarromVec(CarromMath.max(-1.0, CarromMath.min(1.0, slide)) * slideMax, baseY).rotated(rotation(side))
    }

    /// Straight ahead for a shooter, towards the far side.
    static func forward(_ side: Int) -> CarromVec { CarromVec(0.0, -1.0).rotated(rotation(side)) }

    /// The slide value under a board point, for dragging the striker directly.
    static func slide(_ at: CarromVec, _ side: Int) -> Double {
        let local = at.rotated(-rotation(side))
        return CarromMath.max(-1.0, CarromMath.min(1.0, local.x / slideMax))
    }

    /// How close a board point is to a side's base line (for picking up the striker).
    static func distanceToBaseLine(_ p: CarromVec, _ side: Int) -> Double {
        let local = p.rotated(-rotation(side))
        return Swift.abs(local.y - baseY) + CarromMath.max(0.0, Swift.abs(local.x) - slideMax)
    }

    /// Shots go forward or sideways, never straight back at your own frame.
    static func clampAim(_ angle: Double, _ side: Int) -> Double {
        let f = forward(side)
        let forwardAngle = CarromFdLibm.atan2(f.y, f.x)
        var d = (angle - forwardAngle).remainder(dividingBy: 2 * Double.pi)
        let limit = 95.0 * Double.pi / 180
        d = CarromMath.max(-limit, CarromMath.min(limit, d))
        return forwardAngle + d
    }

    /// The break: the queen in the centre circle, six round her alternating white and black, and twelve in the
    /// second ring with whites forming a "Y" outward from the inner whites.
    static func rack(_ queen: Bool) -> [CarromDisc] {
        var discs: [CarromDisc] = queen ? [CarromDisc(.QUEEN, CarromVec.ZERO)] : []
        let d = 2 * coinR
        for i in 0..<6 {
            let a = Double.pi / 2 + Double(i) * Double.pi / 3
            let inner: CarromKind = i % 2 == 0 ? .WHITE : .BLACK
            discs.append(CarromDisc(inner, CarromVec(CarromFdLibm.cos(a), CarromFdLibm.sin(a)) * d))
            discs.append(CarromDisc(inner, CarromVec(CarromFdLibm.cos(a), CarromFdLibm.sin(a)) * 2.0 * d))
            let b = a + Double.pi / 6
            discs.append(CarromDisc(inner == .WHITE ? .BLACK : .WHITE, CarromVec(CarromFdLibm.cos(b), CarromFdLibm.sin(b)) * d * (3.0).squareRoot()))
        }
        return discs
    }

    /// The nearest free spot to the centre, spiralling out inside the outer circle.
    static func freeSpot(_ centre: CarromVec = CarromVec.ZERO, avoiding: [CarromDisc]) -> CarromVec {
        for ring in 0..<16 {
            let count = Swift.max(1, ring * 6)
            for a in 0..<count {
                let angle = Double(a) / Double(count) * 2 * Double.pi
                let p = centre + CarromVec(CarromFdLibm.cos(angle), CarromFdLibm.sin(angle)) * Double(ring) * 0.9
                if avoiding.allSatisfy({ !$0.live || ($0.p - p).length >= $0.r + coinR + 0.02 }) { return p }
            }
        }
        return centre
    }
}
