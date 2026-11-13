import Foundation

enum PoolTableSize: String, Codable, CaseIterable, Sendable {
    case BAR, PRO

    var title: String {
        switch self {
        case .BAR: return "Bar · 7 ft"
        case .PRO: return "Pro · 9 ft"
        }
    }
}

/// Table geometry from the WPA specifications, in cm with the origin at the centre: x runs along
/// the length (head at −x, foot at +x), y across. See docs/POOL_SPEC.md §3.
final class PoolTableGeometry: @unchecked Sendable {
    struct Segment: Sendable {
        let p: Vec2
        let q: Vec2
        /// A jaw facing leading into a pocket (balls rattle off these).
        let jaw: Bool
        let px: Double
        let py: Double
        let qx: Double
        let qy: Double

        init(_ p: Vec2, _ q: Vec2, _ jaw: Bool) {
            self.p = p
            self.q = q
            self.jaw = jaw
            px = p.x; py = p.y; qx = q.x; qy = q.y
        }
    }

    /// A ball whose centre comes within [r] of [c] has dropped.
    struct Pocket: Sendable {
        let c: Vec2
        let r: Double
        let corner: Bool

        init(_ c: Vec2, _ r: Double, _ corner: Bool) {
            self.c = c
            self.r = r
            self.corner = corner
        }
    }

    let size: PoolTableSize
    let length: Double
    let width: Double
    let cornerMouth: Double
    let sideMouth: Double
    let cushions: [Segment]
    let pockets: [Pocket]
    /// Just inside each pocket's mouth: where to send an object ball.
    let aimPoints: [Vec2]

    var a: Double { length / 2 }
    var b: Double { width / 2 }
    var footSpot: Vec2 { Vec2(a / 2, 0.0) }
    var headString: Double { -a / 2 }

    private init(_ size: PoolTableSize) {
        self.size = size
        let R = PoolTableGeometry.R
        // Bar mouths are a little more generous than WPA, for a phone.
        length = size == .BAR ? 198.0 : 254.0
        width = size == .BAR ? 99.0 : 127.0
        cornerMouth = (size == .BAR ? 2.15 : 2.05) * 2 * R
        sideMouth = (size == .BAR ? 2.3 : 2.2) * 2 * R
        let a = length / 2
        let b = width / 2
        let jc = cornerMouth / (2.0).squareRoot()
        let hs = sideMouth / 2
        var s: [Segment] = []
        for sy in [-1.0, 1.0] {
            s.append(Segment(Vec2(-a + jc, sy * b), Vec2(-hs, sy * b), false))
            s.append(Segment(Vec2(hs, sy * b), Vec2(a - jc, sy * b), false))
            s.append(Segment(Vec2(-hs, sy * b), Vec2(-hs + 0.8, sy * (b + 3.4)), true))
            s.append(Segment(Vec2(hs, sy * b), Vec2(hs - 0.8, sy * (b + 3.4)), true))
        }
        for sx in [-1.0, 1.0] { s.append(Segment(Vec2(sx * a, -b + jc), Vec2(sx * a, b - jc), false)) }
        let corners: [(Double, Double)] = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
        for (sx, sy) in corners {
            let d = Vec2(sx, sy).normalized * 4.0
            let p1 = Vec2(sx * (a - jc), sy * b)
            let p2 = Vec2(sx * a, sy * (b - jc))
            s.append(Segment(p1, p1 + d, true))
            s.append(Segment(p2, p2 + d, true))
        }
        cushions = s
        var pk: [Pocket] = []
        var aims: [Vec2] = []
        for (sx, sy) in corners {
            let mid = Vec2(sx * (a - jc / 2), sy * (b - jc / 2))
            pk.append(Pocket(mid + Vec2(sx, sy).normalized * 3.2, cornerMouth * 0.5, true))
            aims.append(mid + Vec2(sx, sy).normalized * 1.2)
        }
        for sy in [-1.0, 1.0] {
            pk.append(Pocket(Vec2(0.0, sy * (b + R * 1.05)), sideMouth * 0.5, false))
            aims.append(Vec2(0.0, sy * (b + 0.6)))
        }
        pockets = pk
        aimPoints = aims
    }

    func onTable(_ p: Vec2) -> Bool { abs(p.x) <= a - PoolTableGeometry.R && abs(p.y) <= b - PoolTableGeometry.R }
    func inKitchen(_ p: Vec2) -> Bool { p.x <= headString }

    static let R = 2.8575
    static let bar = PoolTableGeometry(.BAR)
    static let pro = PoolTableGeometry(.PRO)
    static func of(_ size: PoolTableSize) -> PoolTableGeometry { size == .BAR ? bar : pro }
}

enum PoolRack {
    /// 8-ball: a triangle on the foot spot, the 8 in the middle, a solid and a stripe in the back corners.
    static func eight(_ t: PoolTableGeometry, _ seed: Int64) -> [PoolBall] {
        let rng = PoolRandom(seed)
        var others = rng.shuffled([1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15])
        let solid = others.remove(at: others.firstIndex { $0 < 8 }!)
        let stripe = others.remove(at: others.firstIndex { $0 > 8 }!)
        // Either back corner may hold the solid.
        let (left, right) = rng.unit() < 0.5 ? (solid, stripe) : (stripe, solid)
        var order: [Int] = []
        for row in 0..<5 {
            for k in 0...row {
                if row == 2 && k == 1 {
                    order.append(8)
                } else if row == 4 && k == 0 {
                    order.append(left)
                } else if row == 4 && k == 4 {
                    order.append(right)
                } else {
                    order.append(others.removeFirst())
                }
            }
        }
        var out = [cueBall(t)]
        for (i, p) in positions(t, [1, 2, 3, 4, 5]).enumerated() { out.append(PoolBall(order[i], p)) }
        return out
    }

    /// 9-ball: a diamond with the 1 on the foot spot and the 9 in the middle.
    static func nine(_ t: PoolTableGeometry, _ seed: Int64) -> [PoolBall] {
        let rng = PoolRandom(seed)
        var others = rng.shuffled([2, 3, 4, 5, 6, 7, 8])
        var balls = [cueBall(t)]
        for (i, p) in positions(t, [1, 2, 3, 2, 1]).enumerated() {
            balls.append(PoolBall(i == 0 ? 1 : (i == 4 ? 9 : others.removeFirst()), p))
        }
        return balls
    }

    static func cueBall(_ t: PoolTableGeometry) -> PoolBall { PoolBall(0, Vec2(t.headString - 6, 0.0)) }

    static func positions(_ t: PoolTableGeometry, _ rows: [Int]) -> [Vec2] {
        let R = PoolTableGeometry.R + 0.004
        var out: [Vec2] = []
        for (r, count) in rows.enumerated() {
            let x = t.footSpot.x + Double(r) * (3.0).squareRoot() * R
            for k in 0..<count { out.append(Vec2(x, (Double(k) - Double(count - 1) / 2.0) * 2 * R)) }
        }
        return out
    }
}
