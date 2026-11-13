import Foundation

/// The engine's math is Java's StrictMath (see PoolStrictMath), for bit-identical results.
typealias PoolSM = PoolStrictMath

/// A table point or direction in centimetres (the reference's `CarromVec` / `SIMD2<Double>`).
struct Vec2: Equatable, Hashable, Codable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double = 0.0, _ y: Double = 0.0) {
        self.x = x
        self.y = y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: Vec2, o: Vec2) -> Vec2 { Vec2(a.x + o.x, a.y + o.y) }
    static func - (a: Vec2, o: Vec2) -> Vec2 { Vec2(a.x - o.x, a.y - o.y) }
    static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    static func / (a: Vec2, k: Double) -> Vec2 { Vec2(a.x / k, a.y / k) }
    static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }

    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: Vec2 { let l = length; return l > 1e-9 ? self / l : Vec2.ZERO }
    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    var perpendicular: Vec2 { Vec2(-y, x) }
    func rotated(_ a: Double) -> Vec2 { Vec2(x * PoolSM.cos(a) - y * PoolSM.sin(a), x * PoolSM.sin(a) + y * PoolSM.cos(a)) }

    static let ZERO = Vec2(0.0, 0.0)

    private enum CodingKeys: String, CodingKey { case x, y }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.0
    }
}

struct Vec3: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func + (a: Vec3, o: Vec3) -> Vec3 { Vec3(a.x + o.x, a.y + o.y, a.z + o.z) }
    static func - (a: Vec3, o: Vec3) -> Vec3 { Vec3(a.x - o.x, a.y - o.y, a.z - o.z) }
    static func * (a: Vec3, k: Double) -> Vec3 { Vec3(a.x * k, a.y * k, a.z * k) }
    static func / (a: Vec3, k: Double) -> Vec3 { Vec3(a.x / k, a.y / k, a.z / k) }
    static prefix func - (a: Vec3) -> Vec3 { Vec3(-a.x, -a.y, -a.z) }
    func cross(_ o: Vec3) -> Vec3 { Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var normalized: Vec3 { self / length }
}

/// A unit quaternion (x, y, z, w).
struct Quat: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

/// SplitMix64, identical to the reference's `PoolRandom`, so racks and the computers' noise match.
final class PoolRandom {
    /// The Kotlin `Long` state, kept as its bit pattern.
    private var bits: UInt64

    var state: Int64 {
        get { Int64(bitPattern: bits) }
        set { bits = UInt64(bitPattern: newValue) }
    }

    init(_ seed: Int64) { bits = UInt64(bitPattern: seed) }

    @inline(__always)
    func next() -> Int64 {
        bits = bits &+ 0x9E37_79B9_7F4A_7C15
        var z = bits
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int64(bitPattern: z ^ (z >> 31))
    }

    @inline(__always)
    func unit() -> Double { Double(UInt64(bitPattern: next()) >> 11) / 9_007_199_254_740_992.0 }

    func normal() -> Double {
        let a = unit()
        let b = unit()
        return (-2 * PoolSM.log(poolMax(a, 1e-12))).squareRoot() * PoolSM.cos(2 * Double.pi * b)
    }

    /// Swift's `RandomNumberGenerator.next(upperBound:)` (Lemire), used by `shuffled(using:)`.
    func nextBelow(_ bound: Int) -> Int {
        let ub = UInt64(bitPattern: Int64(bound))
        var random = UInt64(bitPattern: next())
        var (high, low) = random.multipliedFullWidth(by: ub)
        if low < ub {
            let t = (0 &- ub) % ub
            while low < t {
                random = UInt64(bitPattern: next())
                (high, low) = random.multipliedFullWidth(by: ub)
            }
        }
        return Int(Int32(truncatingIfNeeded: high))
    }

    /// Swift's `MutableCollection.shuffle(using:)`.
    func shuffled<T>(_ list: [T]) -> [T] {
        var out = list
        if out.count <= 1 { return out }
        var amount = out.count
        var current = 0
        while amount > 1 {
            let r = nextBelow(amount)
            amount -= 1
            let other = current + r
            let tmp = out[current]; out[current] = out[other]; out[other] = tmp
            current += 1
        }
        return out
    }
}

/// A ball's orientation, as a unit quaternion. z points into the table; the viewer sees z < 0.
enum PoolQuat {
    static let identity = Quat(0.0, 0.0, 0.0, 1.0)

    @inline(__always)
    static func mul(_ a: Quat, _ b: Quat) -> Quat {
        Quat(
            a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        )
    }

    @inline(__always)
    static func axisAngle(_ axis: Vec3, _ angle: Double) -> Quat {
        let s = PoolSM.sin(angle / 2)
        return Quat(axis.x * s, axis.y * s, axis.z * s, PoolSM.cos(angle / 2))
    }

    @inline(__always)
    static func rotate(_ q: Quat, _ v: Vec3) -> Vec3 {
        let u = Vec3(q.x, q.y, q.z)
        let t = u.cross(v) * 2.0
        return v + t * q.w + u.cross(t)
    }

    /// Rolling without slipping over table displacement (dx, dy).
    static func roll(_ q: Quat, _ dx: Double, _ dy: Double) -> Quat {
        let l = (dx * dx + dy * dy).squareRoot()
        if l <= 1e-6 { return q }
        let r = mul(axisAngle(Vec3(dy / l, -dx / l, 0.0), l / PoolTableGeometry.R), q)
        let n = (r.x * r.x + r.y * r.y + r.z * r.z + r.w * r.w).squareRoot()
        return Quat(r.x / n, r.y / n, r.z / n, r.w / n)
    }

    /// A varied resting orientation for each ball.
    static func start(_ n: Int) -> Quat {
        let rng = PoolRandom(Int64(n) &* 977 &+ 13)
        let ax = rng.unit() - 0.5
        let ay = rng.unit() - 0.5
        let az = rng.unit() * 0.3
        let axis = Vec3(ax, ay, az)
        let l = poolMax(0.01, (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot())
        return axisAngle(axis / l, 0.4 + rng.unit() * 0.9)
    }
}

func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { poolMax(lo, poolMin(hi, v)) }

/// Swift's `remainder(_:_:)` (= Java's `Math.IEEEremainder`).
func ieeeRemainder(_ x: Double, _ y: Double) -> Double { Foundation.remainder(x, y) }

/// Kotlin `max(a, b)` on Doubles (java.lang.Math.max: NaN wins, 0.0 beats -0.0).
@inline(__always)
func poolMax(_ a: Double, _ b: Double) -> Double {
    if a != a { return a }
    if a == 0.0 && b == 0.0 && a.sign == .minus { return b }
    return a >= b ? a : b
}

/// Kotlin `min(a, b)` on Doubles (java.lang.Math.min: NaN wins, -0.0 beats 0.0).
@inline(__always)
func poolMin(_ a: Double, _ b: Double) -> Double {
    if a != a { return a }
    if a == 0.0 && b == 0.0 && b.sign == .minus { return b }
    return a <= b ? a : b
}

/// `java.lang.Double.compare`: a total order (-0.0 < 0.0, NaN above everything).
@inline(__always)
func poolCompare(_ a: Double, _ b: Double) -> Int {
    if a < b { return -1 }
    if a > b { return 1 }
    let x = a.isNaN ? Int64(0x7ff8_0000_0000_0000) : Int64(bitPattern: a.bitPattern)
    let y = b.isNaN ? Int64(0x7ff8_0000_0000_0000) : Int64(bitPattern: b.bitPattern)
    return x == y ? 0 : (x < y ? -1 : 1)
}

extension Array {
    /// Kotlin `minByOrNull`: the first element with the smallest key.
    func poolMinBy(_ key: (Element) -> Double) -> Element? {
        guard var best = first else { return nil }
        var bestKey = key(best)
        for e in dropFirst() {
            let k = key(e)
            if poolCompare(bestKey, k) > 0 { best = e; bestKey = k }
        }
        return best
    }

    /// Kotlin `sortedByDescending` (stable, by `Double.compareTo`).
    func poolSortedByDescending(_ key: (Element) -> Double) -> [Element] {
        let keyed = enumerated().map { (offset: $0.offset, key: key($0.element), element: $0.element) }
        return keyed.sorted { a, b in
            let c = poolCompare(b.key, a.key)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map { $0.element }
    }
}
