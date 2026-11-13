import Foundation

/// The aim guide: where the striker goes, what it meets, and where that coin heads.
struct CarromGuide: Equatable {
    var path: [CarromVec] = []
    var ghost: CarromVec? = nil
    var coin: Int? = nil
    var coinEnd: CarromVec? = nil
    var pocket: Int? = nil

    init(_ path: [CarromVec] = [], _ ghost: CarromVec? = nil, _ coin: Int? = nil, _ coinEnd: CarromVec? = nil, _ pocket: Int? = nil) {
        self.path = path
        self.ghost = ghost
        self.coin = coin
        self.coinEnd = coinEnd
        self.pocket = pocket
    }

    static func compute(_ table: CarromTable, _ slide: Double, _ angle: Double, _ style: CarromAimGuide) -> CarromGuide {
        if style == .OFF { return CarromGuide() }
        var origin = table.strikerSpot(slide)
        var dir = CarromVec(CarromFdLibm.cos(angle), CarromFdLibm.sin(angle))
        var path = [origin]
        let reach = CarromBoard.coinR + CarromBoard.strikerR
        let wall = CarromBoard.half - CarromBoard.strikerR
        for bounce in 0...(style == .FULL ? 1 : 0) {
            var best = Double.infinity
            var hit: Int? = nil
            for (i, c) in table.coins.enumerated() {
                if !c.live { continue }
                let oc = origin - c.p
                let b = oc.dot(dir)
                let cc = oc.dot(oc) - reach * reach
                let disc = b * b - cc
                if disc < 0 { continue }
                let t = -b - disc.squareRoot()
                if t > 0.01 && t < best { best = t; hit = i }
            }
            var tw = Double.infinity
            var flipX = false
            if dir.x > 1e-9 { let t = (wall - origin.x) / dir.x; if t < tw { tw = t; flipX = true } }
            if dir.x < -1e-9 { let t = (-wall - origin.x) / dir.x; if t < tw { tw = t; flipX = true } }
            if dir.y > 1e-9 { let t = (wall - origin.y) / dir.y; if t < tw { tw = t; flipX = false } }
            if dir.y < -1e-9 { let t = (-wall - origin.y) / dir.y; if t < tw { tw = t; flipX = false } }
            if let hit, best < tw {
                let ghost = origin + dir * best
                path.append(ghost)
                var coinEnd: CarromVec? = nil
                var pocket: Int? = nil
                if style == .FULL {
                    let c = table.coins[hit].p
                    let cd = (c - ghost).normalized
                    coinEnd = c + cd * 18.0
                    for (pi, p) in CarromBoard.pockets.enumerated() {
                        let along = (p - c).dot(cd)
                        if along <= 0 { continue }
                        if (c + cd * along - p).length < CarromBoard.pocketR * 0.95 {
                            pocket = pi
                            coinEnd = p
                            break
                        }
                    }
                    if pocket == nil {
                        let end = coinEnd!
                        let lim = CarromBoard.half - CarromBoard.coinR
                        coinEnd = CarromVec(CarromMath.max(-lim, CarromMath.min(lim, end.x)), CarromMath.max(-lim, CarromMath.min(lim, end.y)))
                    }
                }
                return CarromGuide(path, ghost, hit, coinEnd, pocket)
            }
            let at = origin + dir * CarromMath.min(tw, 140.0)
            path.append(at)
            if !(bounce == 0 && style == .FULL && tw < 140) { break }
            origin = at
            dir = flipX ? CarromVec(-dir.x, dir.y) : CarromVec(dir.x, -dir.y)
        }
        return CarromGuide(path)
    }
}
