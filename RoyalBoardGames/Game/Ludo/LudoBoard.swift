import Foundation

/// A point on the board, in cells, with the board centre at (0, 0).
struct LPoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    static let Zero = LPoint(x: 0.0, y: 0.0)

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A direction or offset, in cells.
struct LVec: Equatable {
    var dx: Double
    var dy: Double

    init(_ dx: Double, _ dy: Double) {
        self.dx = dx
        self.dy = dy
    }
}

/// The shape of a Ludo board, built from one arm geometry so the classic four-arm cross and the
/// six-arm star share the same rules and renderer (docs/LUDO_SPEC.md §3).
///
/// Arm `k` points out from the centre along `direction(k)`; arms go clockwise on screen, arm 0
/// pointing left. Inside an arm a cell is (v: 0 at the centre end … 5 at the rim, u: +1 outward
/// lane, 0 middle, −1 inward lane). The track enters an arm on its outward lane, crosses the tip
/// and comes back on the inward lane: 13 squares per arm. All lengths are in cells, with the board
/// centre at (0, 0).
struct LudoGeometry: Equatable, Hashable {
    let arms: Int

    init(_ arms: Int) {
        self.arms = arms == 6 ? 6 : 4
    }

    static let SQUARES_PER_ARM = 13
    /// Arm-local index of each arm's start square (inward lane, second from the rim).
    static let START_LOCAL = 8
    /// Arm-local index of each arm's star (safe) square.
    static let STAR_LOCAL = 3

    /// Default arms for a number of seats: opposite corners for two, spread out for the rest.
    static func defaultArms(_ seats: Int, _ arms: Int) -> [Int] {
        switch true {
        case arms == 4 && seats == 2: return [0, 2]
        case arms == 4 && seats == 3: return [0, 1, 2]
        case arms == 6 && seats == 2: return [0, 3]
        case arms == 6 && seats == 3: return [0, 2, 4]
        case arms == 6 && seats == 4: return [0, 1, 3, 4]
        case arms == 6 && seats == 5: return [0, 1, 2, 3, 4]
        default: return Array(0..<arms)
        }
    }

    var trackLength: Int { Self.SQUARES_PER_ARM * arms }
    /// Steps along a seat's route: 0 = its start square … `lastTrackStep` = its own tip.
    var lastTrackStep: Int { trackLength - 2 }
    /// Home-lane steps are `lastTrackStep + 1 … + 5`; `homeStep` is the centre.
    var homeStep: Int { lastTrackStep + 6 }

    /// Distance from the centre to an arm's inner end.
    var inner: Double { arms == 4 ? 1.5 : 3 * (3.0).squareRoot() / 2 }
    /// Half the board's extent, for fitting it into a view.
    var radius: Double { arms == 4 ? 7.5 : hypot(inner + 6, 1.5) }

    // MARK: Directions

    func direction(_ arm: Int) -> LVec {
        let angle = Double.pi - Double(arm) * 2 * Double.pi / Double(arms)
        return LVec(cos(angle), -sin(angle))
    }

    /// Points from the inward lane (u = −1) to the outward lane (u = +1).
    func lateral(_ arm: Int) -> LVec {
        let d = direction(arm)
        return LVec(d.dy, -d.dx)
    }

    // MARK: Cells

    func point(_ arm: Int, _ v: Double, _ u: Double) -> LPoint {
        let d = direction(arm)
        let l = lateral(arm)
        return LPoint(d.dx * (inner + v + 0.5) + l.dx * u, d.dy * (inner + v + 0.5) + l.dy * u)
    }

    func cellCorners(_ arm: Int, _ v: Int, _ u: Int) -> [LPoint] {
        let d = direction(arm)
        let l = lateral(arm)
        let c = point(arm, Double(v), Double(u))
        return [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)].map { (a, b) in
            LPoint(c.x + d.dx * a + l.dx * b, c.y + d.dy * a + l.dy * b)
        }
    }

    struct Cell: Equatable {
        let arm: Int
        let v: Int
        let u: Int
    }

    /// Track square `index` (0 ..< trackLength) as an arm cell.
    func cell(ofTrack: Int) -> Cell {
        let i = ((ofTrack % trackLength) + trackLength) % trackLength
        let arm = i / Self.SQUARES_PER_ARM
        let local = i % Self.SQUARES_PER_ARM
        if local <= 5 { return Cell(arm: arm, v: local, u: 1) }
        if local == 6 { return Cell(arm: arm, v: 5, u: 0) }
        return Cell(arm: arm, v: 12 - local, u: -1)
    }

    func trackPoint(_ index: Int) -> LPoint {
        let c = cell(ofTrack: index)
        return point(c.arm, Double(c.v), Double(c.u))
    }

    /// The track square under `step` of the seat on `arm`, or nil off the main track.
    func trackIndex(_ arm: Int, _ step: Int) -> Int? {
        if step < 0 || step > lastTrackStep { return nil }
        return (arm * Self.SQUARES_PER_ARM + Self.START_LOCAL + step) % trackLength
    }

    func isStart(_ index: Int) -> Bool { index % Self.SQUARES_PER_ARM == Self.START_LOCAL }
    func isStar(_ index: Int) -> Bool { index % Self.SQUARES_PER_ARM == Self.STAR_LOCAL }

    /// Where `step` of the seat on `arm` sits (yard and home positions come from `yardSpot` / `homeSpot`).
    func routePoint(_ arm: Int, _ step: Int) -> LPoint {
        if let index = trackIndex(arm, step) { return trackPoint(index) }
        let lane = step - lastTrackStep
        if (1...5).contains(lane) { return point(arm, Double(5 - lane), 0.0) }
        return homeSpot(arm, 0, 1)
    }

    // MARK: Centre

    /// The centre triangle of `arm`, pointing at its arm.
    func homeTriangle(_ arm: Int) -> [LPoint] {
        if arms == 4 {
            let d = direction(arm)
            let l = lateral(arm)
            return [
                LPoint(d.dx * 1.5 - l.dx * 1.5, d.dy * 1.5 - l.dy * 1.5),
                LPoint(d.dx * 1.5 + l.dx * 1.5, d.dy * 1.5 + l.dy * 1.5),
                LPoint.Zero,
            ]
        }
        return [hexVertex(arm), hexVertex((arm + arms - 1) % arms), LPoint.Zero]
    }

    /// Finished tokens gather inside their centre triangle.
    func homeSpot(_ arm: Int, _ slot: Int, _ of: Int) -> LPoint {
        let d = direction(arm)
        let l = lateral(arm)
        let depth = inner * 0.6
        let spread = arms == 4 ? 0.42 : 0.5
        let offset = of <= 1 ? 0.0 : (Double(slot) - Double(of - 1) / 2) * spread
        return LPoint(d.dx * depth + l.dx * offset, d.dy * depth + l.dy * offset)
    }

    func hexVertex(_ arm: Int) -> LPoint {
        let d = direction(arm)
        let l = lateral(arm)
        return LPoint(d.dx * inner - l.dx * 1.5, d.dy * inner - l.dy * 1.5)
    }

    var centreOutline: [LPoint] {
        if arms == 4 {
            return [LPoint(-1.5, -1.5), LPoint(1.5, -1.5), LPoint(1.5, 1.5), LPoint(-1.5, 1.5)]
        }
        return (0..<arms).map(hexVertex)
    }

    // MARK: Yards

    /// The yard of the seat on `arm`: between `arm` and the next arm clockwise, beside its start.
    func yard(_ arm: Int) -> [LPoint] {
        if arms == 4 {
            let d = direction(arm)
            let l = lateral(arm)
            let a = LPoint(d.dx * 1.5 - l.dx * 1.5, d.dy * 1.5 - l.dy * 1.5)
            func corner(_ s: Double, _ t: Double) -> LPoint { LPoint(a.x + d.dx * s - l.dx * t, a.y + d.dy * s - l.dy * t) }
            return [corner(0.0, 0.0), corner(6.0, 0.0), corner(6.0, 6.0), corner(0.0, 6.0)]
        }
        let v = hexVertex(arm)
        let d1 = direction(arm)
        let d2 = direction((arm + 1) % arms)
        return [v, LPoint(v.x + d1.dx * 6, v.y + d1.dy * 6), LPoint(v.x + d2.dx * 6, v.y + d2.dy * 6)]
    }

    func yardCenter(_ arm: Int) -> LPoint {
        let corners = yard(arm)
        let n = Double(corners.count)
        var sx = 0.0
        var sy = 0.0
        for c in corners { sx += c.x }
        for c in corners { sy += c.y }
        return LPoint(sx / n, sy / n)
    }

    /// Radius of the plate holding the yard's token spots.
    var yardPlateRadius: Double { arms == 4 ? 2.0 : 1.38 }

    /// The four token spots in a yard.
    func yardSpot(_ arm: Int, _ token: Int) -> LPoint {
        let c = yardCenter(arm)
        let d = direction(arm)
        let l = lateral(arm)
        let pattern: [(Double, Double)] = [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]
        let (a, b) = pattern[token % 4]
        if arms == 4 {
            // Square yards: a 2×2 grid aligned with the screen.
            let r2 = (2.0).squareRoot()
            let e = LVec((d.dx - l.dx) / r2, (d.dy - l.dy) / r2)
            let f = LVec((d.dx + l.dx) / r2, (d.dy + l.dy) / r2)
            return LPoint(c.x + (e.dx * a + f.dx * b) * 0.94, c.y + (e.dy * a + f.dy * b) * 0.94)
        }
        return LPoint(c.x + (d.dx * a + l.dx * b) * 0.6, c.y + (d.dy * a + l.dy * b) * 0.6)
    }

    // MARK: Layout

    /// How many arms to turn the board by so `arm`'s yard sits at the bottom-left.
    func shift(toBottomLeft: Int) -> Int { ((arms - 1 - toBottomLeft) % arms + arms) % arms }
}

/// Maps board cells to the screen: turns the board by `shift` arms, then scales and centres it.
struct LudoTransform {
    let geometry: LudoGeometry
    let shift: Int
    let width: Double
    let height: Double
    let cell: Double
    private let ca: Double
    private let sa: Double

    init(_ geometry: LudoGeometry, _ shift: Int, _ width: Double, _ height: Double) {
        self.geometry = geometry
        self.shift = shift
        self.width = width
        self.height = height
        cell = min(width, height) / (geometry.radius * 2 + 0.9)
        let angle = Double(shift) * 2 * Double.pi / Double(geometry.arms)
        ca = cos(angle)
        sa = sin(angle)
    }

    func rotate(_ v: LVec) -> LVec { LVec(v.dx * ca - v.dy * sa, v.dx * sa + v.dy * ca) }

    func screen(_ p: LPoint) -> LPoint {
        let r = rotate(LVec(p.x, p.y))
        return LPoint(width / 2 + r.dx * cell, height / 2 + r.dy * cell)
    }

    func board(_ s: LPoint) -> LPoint {
        let vx = (s.x - width / 2) / cell
        let vy = (s.y - height / 2) / cell
        return LPoint(vx * ca + vy * sa, -vx * sa + vy * ca)
    }
}
