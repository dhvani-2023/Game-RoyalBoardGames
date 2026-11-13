import Foundation

enum CarromMode: String, Codable, CaseIterable {
    case CLASSIC, POOL, FREESTYLE

    var title: String {
        switch self {
        case .CLASSIC: return "Classic"
        case .POOL: return "Pocket Pool"
        case .FREESTYLE: return "Freestyle"
        }
    }

    var blurb: String {
        switch self {
        case .CLASSIC: return "Your colour, then the Queen + cover"
        case .POOL: return "Clear your colour first, no Queen"
        case .FREESTYLE: return "Any coin scores 20 · 10 · 50"
        }
    }

    var usesQueen: Bool { self != .POOL }
}

enum CarromDifficulty: String, Codable, CaseIterable {
    case EASY, NORMAL, HARD

    var title: String {
        switch self {
        case .EASY: return "Easy"
        case .NORMAL: return "Normal"
        case .HARD: return "Hard"
        }
    }
}

enum CarromMatchLength: String, Codable, CaseIterable {
    case ONE, BEST_OF_THREE, RACE25

    var title: String {
        switch self {
        case .ONE: return "1 board"
        case .BEST_OF_THREE: return "Best of 3"
        case .RACE25: return "First to 25"
        }
    }
}

enum CarromAimGuide: String, Codable, CaseIterable {
    case FULL, SHORT, OFF

    var title: String {
        switch self {
        case .FULL: return "Full"
        case .SHORT: return "Short"
        case .OFF: return "Off"
        }
    }
}

/// Every field has a default, so adding options never resets the rest of a saved setup.
struct CarromOptions: Codable, Equatable {
    var mode: CarromMode = .CLASSIC
    var length: CarromMatchLength = .ONE
    /// ICF laws: last coin before the Queen loses the board; Queen plus one coin on a full board still needs a
    /// cover; a 15 s shot clock.
    var tournament: Bool = false
    var aimGuide: CarromAimGuide = .FULL
    /// Seconds per shot, 0 for no clock.
    var shotClock: Int = 0
    var turnBoard: Bool = true
    var freestyleTeams: Bool = false
    var fastBots: Bool = false

    init(mode: CarromMode = .CLASSIC, length: CarromMatchLength = .ONE, tournament: Bool = false, aimGuide: CarromAimGuide = .FULL,
         shotClock: Int = 0, turnBoard: Bool = true, freestyleTeams: Bool = false, fastBots: Bool = false) {
        self.mode = mode
        self.length = length
        self.tournament = tournament
        self.aimGuide = aimGuide
        self.shotClock = shotClock
        self.turnBoard = turnBoard
        self.freestyleTeams = freestyleTeams
        self.fastBots = fastBots
    }

    /// The shot clock in play: Tournament always runs 15 s.
    var clockSeconds: Int { tournament ? Swift.max(shotClock, 15) : shotClock }

    enum CodingKeys: String, CodingKey { case mode, length, tournament, aimGuide, shotClock, turnBoard, freestyleTeams, fastBots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.carrom(.mode, CarromMode.CLASSIC)
        length = c.carrom(.length, CarromMatchLength.ONE)
        tournament = c.carrom(.tournament, false)
        aimGuide = c.carrom(.aimGuide, CarromAimGuide.FULL)
        shotClock = c.carrom(.shotClock, 0)
        turnBoard = c.carrom(.turnBoard, true)
        freestyleTeams = c.carrom(.freestyleTeams, false)
        fastBots = c.carrom(.fastBots, false)
    }
}

/// One seat at the table.
struct CarromSeat: Codable {
    var player: PartyPlayer
    /// 0 bottom, 1 right, 2 top, 3 left.
    var side: Int = 0
    var isBot: Bool = false
    var difficulty: CarromDifficulty = .NORMAL

    init(_ player: PartyPlayer, _ side: Int = 0, isBot: Bool = false, difficulty: CarromDifficulty = .NORMAL) {
        self.player = player
        self.side = side
        self.isBot = isBot
        self.difficulty = difficulty
    }

    var id: String { player.id }

    static func sides(_ forSeats: Int) -> [Int] {
        switch forSeats {
        case 3: return [0, 1, 3]
        case 4: return [0, 1, 2, 3]
        default: return [0, 2]
        }
    }

    enum CodingKeys: String, CodingKey { case player, side, isBot, difficulty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        player = try c.decode(PartyPlayer.self, forKey: .player)
        side = c.carrom(.side, 0)
        isBot = c.carrom(.isBot, false)
        difficulty = c.carrom(.difficulty, CarromDifficulty.NORMAL)
    }
}

struct CarromShot: Codable, Equatable {
    /// −1…1 along the base line, from the shooter's left to right.
    var slide: Double
    /// Direction in board coordinates (radians).
    var angle: Double
    /// 0…1 before the power curve.
    var power: Double

    init(_ slide: Double, _ angle: Double, _ power: Double) {
        self.slide = slide
        self.angle = angle
        self.power = power
    }

    init(slide: Double, angle: Double, power: Double) {
        self.init(slide, angle, power)
    }
}

struct CarromSideStats: Codable, Equatable {
    var coins: Int = 0
    var points: Int = 0
    var queens: Int = 0
    var fouls: Int = 0
    var bestCombo: Int = 0
    var strokes: Int = 0

    init() {}

    enum CodingKeys: String, CodingKey { case coins, points, queens, fouls, bestCombo, strokes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = c.carrom(.coins, 0)
        points = c.carrom(.points, 0)
        queens = c.carrom(.queens, 0)
        fouls = c.carrom(.fouls, 0)
        bestCombo = c.carrom(.bestCombo, 0)
        strokes = c.carrom(.strokes, 0)
    }
}

/// What one stroke did, for banners, sounds and stats.
final class CarromStroke {
    var seat = 0
    var pocketed: [CarromKind] = []
    var foul = false
    var continues = false
    var queenCovered = false
    var queenWaiting = false
    var queenReturned = false
    /// Coins brought back to the centre (dues and the queen-first rule).
    var returned: [CarromKind] = []
    var queenFirst = false
    var points = 0
    var boardOver = false
    var timedOut = false

    init() {}
}

/// A physics run for a shot, without changing the table.
final class CarromSimulation {
    var discs: [CarromDisc]
    let run: CarromPhysics.Run
    let striker: Int

    init(_ discs: [CarromDisc], _ run: CarromPhysics.Run, _ striker: Int) {
        self.discs = discs
        self.run = run
        self.striker = striker
    }
}

/// One board in progress. [sides] lists the occupied sides in turn order (to the shooter's right).
/// Mutable like the reference's value type: take a [deepCopy] before changing a shared table.
final class CarromTable: Codable {
    let mode: CarromMode
    let sides: [Int]
    let teams: Bool
    let tournament: Bool
    var coins: [CarromDisc]
    var turn: Int
    var strokes: Int
    var broken: Bool
    /// Unit that pocketed the queen and must cover her on the next stroke.
    var queenWaiting: Int?
    var queenCoveredBy: Int?
    /// Freestyle score per unit on this board.
    var points: [Int]
    /// Dues owed per unit, taken as soon as a coin is available.
    var owed: [Int]
    var stats: [CarromSideStats]
    var winner: Int?
    /// What the winner takes from this board (Classic and Pocket Pool).
    var boardPoints: Int
    let target: Int
    /// The winner's match score before this board, for the ICF 22-point queen rule.
    var winnerScoreBefore: [Int]
    /// Extras: a practice board (one player, no fouls, turns or score). Never saved.
    var practice = false

    init(
        mode: CarromMode = .CLASSIC,
        sides: [Int] = [0, 2],
        teams: Bool = false,
        tournament: Bool = false,
        coins: [CarromDisc]? = nil,
        turn: Int = 0,
        strokes: Int = 0,
        broken: Bool = false,
        queenWaiting: Int? = nil,
        queenCoveredBy: Int? = nil,
        points: [Int]? = nil,
        owed: [Int]? = nil,
        stats: [CarromSideStats]? = nil,
        winner: Int? = nil,
        boardPoints: Int = 0,
        target: Int? = nil,
        winnerScoreBefore: [Int]? = nil
    ) {
        let units = teams ? 2 : sides.count
        self.mode = mode
        self.sides = sides
        self.teams = teams
        self.tournament = tournament
        self.coins = coins ?? CarromBoard.rack(mode.usesQueen)
        self.turn = turn
        self.strokes = strokes
        self.broken = broken
        self.queenWaiting = queenWaiting
        self.queenCoveredBy = queenCoveredBy
        self.points = points ?? [Int](repeating: 0, count: units)
        self.owed = owed ?? [Int](repeating: 0, count: units)
        self.stats = stats ?? [CarromSideStats](repeating: CarromSideStats(), count: sides.count)
        self.winner = winner
        self.boardPoints = boardPoints
        self.target = target ?? ((teams || sides.count == 2) ? 160 : (sides.count == 3 ? 120 : 100))
        self.winnerScoreBefore = winnerScoreBefore ?? [Int](repeating: 0, count: units)
    }

    static func create(_ mode: CarromMode, _ sides: [Int], teams: Bool, tournament: Bool, breaker: Int, matchScores: [Int] = []) -> CarromTable {
        let units = teams ? 2 : sides.count
        return CarromTable(
            mode: mode, sides: sides, teams: teams, tournament: tournament, turn: breaker,
            winnerScoreBefore: matchScores.count == units ? matchScores : [Int](repeating: 0, count: units)
        )
    }

    /// Positional twin of the Kotlin call `CarromTable.create(mode, sides, teams, tournament, breaker)`.
    static func create(_ mode: CarromMode, _ sides: [Int], _ teams: Bool, _ tournament: Bool, _ breaker: Int, _ matchScores: [Int] = []) -> CarromTable {
        create(mode, sides, teams: teams, tournament: tournament, breaker: breaker, matchScores: matchScores)
    }

    func deepCopy() -> CarromTable {
        let t = CarromTable(
            mode: mode, sides: sides, teams: teams, tournament: tournament, coins: coins.cloned(), turn: turn, strokes: strokes,
            broken: broken, queenWaiting: queenWaiting, queenCoveredBy: queenCoveredBy, points: points, owed: owed, stats: stats,
            winner: winner, boardPoints: boardPoints, target: target, winnerScoreBefore: winnerScoreBefore
        )
        t.practice = practice
        return t
    }

    var units: Int { teams ? 2 : sides.count }
    var side: Int { sides[turn] }
    /// Team or player index for a seat: partners sit opposite each other.
    func unit(_ ofSeat: Int) -> Int { teams ? sides[ofSeat] % 2 : ofSeat }
    var unitNow: Int { unit(turn) }
    /// Colours stay with each side for the whole match: the first unit plays white.
    func colour(_ of: Int) -> CarromKind { of == 0 ? .WHITE : .BLACK }
    func left(_ kind: CarromKind) -> Int { coins.reduce(0) { $0 + (($1.live && $1.kind == kind) ? 1 : 0) } }
    func pocketed(_ kind: CarromKind) -> Int { coins.reduce(0) { $0 + ((!$1.live && $1.kind == kind) ? 1 : 0) } }
    var queenOnBoard: Bool { coins.contains { $0.live && $0.kind == .QUEEN } }
    var isOver: Bool { winner != nil }

    /// Coins the shooter may aim at.
    func targets() -> [Int] {
        if practice { return coins.indices.filter { coins[$0].live } }
        return coins.indices.filter { i in
            let c = coins[i]
            if !c.live { return false }
            switch mode {
            case .FREESTYLE: return true
            case .POOL: return c.kind == colour(unitNow)
            case .CLASSIC:
                let mine = colour(unitNow)
                if c.kind == mine { return true }
                return c.kind == .QUEEN && queenWaiting == nil && pocketed(mine) > 0
            }
        }
    }

    func strikerSpot(_ slide: Double) -> CarromVec { CarromBoard.strikerSpot(side, slide) }

    func strikerFits(_ slide: Double) -> Bool {
        let s = strikerSpot(slide)
        return coins.allSatisfy { !$0.live || ($0.p - s).length >= CarromBoard.coinR + CarromBoard.strikerR + 0.02 }
    }

    /// The nearest slide value where the striker fits.
    func freeSlide(_ near: Double) -> Double {
        let s = CarromMath.max(-1.0, CarromMath.min(1.0, near))
        if strikerFits(s) { return s }
        for step in 1...100 {
            let a = s + Double(step) * 0.01
            let b = s - Double(step) * 0.01
            if a <= 1 && strikerFits(a) { return a }
            if b >= -1 && strikerFits(b) { return b }
        }
        return s
    }

    @discardableResult
    func returnToCentre(_ kind: CarromKind) -> Bool {
        guard let i = coins.firstIndex(where: { !$0.live && $0.kind == kind }) else { return false }
        coins[i].p = CarromBoard.freeSpot(avoiding: coins)
        coins[i].vx = 0.0
        coins[i].vy = 0.0
        coins[i].live = true
        return true
    }

    /// The physics run for a shot, without changing the table.
    func simulate(_ shot: CarromShot, _ record: Bool) -> CarromSimulation {
        var discs = coins.cloned()
        discs.append(CarromDisc(.STRIKER, strikerSpot(freeSlide(shot.slide))))
        let si = discs.count - 1
        let angle = CarromBoard.clampAim(shot.angle, side)
        discs[si].v = CarromVec(CarromFdLibm.cos(angle), CarromFdLibm.sin(angle)) * CarromPhysics.speedForPower(CarromMath.max(0.02, shot.power))
        let run = CarromPhysics.run(&discs, si, record)
        return CarromSimulation(discs, run, si)
    }

    func simulate(_ shot: CarromShot, record: Bool) -> CarromSimulation { simulate(shot, record) }

    /// Plays a shot and applies the rules.
    @discardableResult
    func play(_ shot: CarromShot) -> CarromStroke {
        let sim = simulate(shot, false)
        return apply(sim.discs, sim.run, sim.striker)
    }

    /// Applies a finished physics run (from [simulate]) to the table.
    @discardableResult
    func apply(_ discs: [CarromDisc], _ run: CarromPhysics.Run, _ striker: Int) -> CarromStroke {
        if practice { return CarromPractice.apply(self, discs, run, striker) }
        let stroke = CarromStroke()
        stroke.seat = turn
        stroke.foul = !discs[striker].live
        stroke.pocketed = run.pocketed.filter { $0.disc != striker }.map { discs[$0.disc].kind }
        var next = [CarromDisc]()
        next.reserveCapacity(coins.count)
        for i in 0..<coins.count {
            var c = discs[i]
            c.vx = 0.0
            c.vy = 0.0
            next.append(c)
        }
        coins = next
        strokes += 1
        broken = true
        stats[turn].strokes += 1
        resolve(stroke)
        if winner == nil && !stroke.continues { turn = (turn + 1) % sides.count }
        return stroke
    }

    /// The shot clock ran out: the turn passes, with no foul.
    @discardableResult
    func timeOut() -> CarromStroke {
        let stroke = CarromStroke()
        stroke.seat = turn
        stroke.timedOut = true
        if queenWaiting == unitNow {
            returnToCentre(.QUEEN)
            queenWaiting = nil
            stroke.queenReturned = true
        }
        turn = (turn + 1) % sides.count
        return stroke
    }

    private func resolve(_ s: CarromStroke) {
        let me = unitNow
        let seat = turn
        stats[seat].bestCombo = Swift.max(stats[seat].bestCombo, s.pocketed.count)
        switch mode {
        case .FREESTYLE:
            func value(_ kind: CarromKind) -> Int {
                switch kind {
                case .WHITE: return 20
                case .BLACK: return 10
                case .QUEEN: return 50
                case .STRIKER: return 0
                }
            }
            let others = s.pocketed.filter { $0 != .QUEEN }
            if let waiting = queenWaiting {
                if waiting == me && !others.isEmpty && !s.foul {
                    points[me] += 50; s.points += 50; s.queenCovered = true; stats[seat].queens += 1
                } else if returnToCentre(.QUEEN) {
                    s.queenReturned = true
                }
                queenWaiting = nil
            }
            if s.pocketed.contains(.QUEEN) {
                if !others.isEmpty && !s.foul {
                    points[me] += 50; s.points += 50; s.queenCovered = true; stats[seat].queens += 1
                } else if !s.foul {
                    queenWaiting = me; s.queenWaiting = true
                } else if returnToCentre(.QUEEN) {
                    s.queenReturned = true
                }
            }
            let gained = others.reduce(0) { $0 + value($1) }
            points[me] += gained
            s.points += gained
            stats[seat].coins += others.count
            if s.foul {
                points[me] = Swift.max(0, points[me] - 10)
                s.points -= 10
                stats[seat].fouls += 1
            }
            stats[seat].points += s.points
            s.continues = !s.foul && (!others.isEmpty || queenWaiting == me)
            if points[me] >= target {
                winner = me
            } else if coins.allSatisfy({ !$0.live }) {
                // maxByOrNull: the first highest wins.
                var best: Int? = nil
                for i in points.indices where best == nil || points[best!] < points[i] { best = i }
                winner = best
            }
            boardPoints = winner.map { points[$0] } ?? 0

        case .CLASSIC, .POOL:
            let mine = colour(me)
            let theirs = colour(1 - me)
            let own = s.pocketed.filter { $0 == mine }.count
            let ownBefore = pocketed(mine) - own
            if !s.foul { stats[seat].coins += own }
            if s.foul {
                stats[seat].fouls += 1
                for _ in 0..<own { if returnToCentre(mine) { s.returned.append(mine) } }
                owed[me] += 1
                if s.pocketed.contains(.QUEEN) || queenWaiting == me {
                    if returnToCentre(.QUEEN) { s.queenReturned = true }
                    queenWaiting = nil
                }
            } else if mode == .CLASSIC {
                if queenWaiting == me {
                    if own > 0 {
                        queenCoveredBy = me; s.queenCovered = true; stats[seat].queens += 1
                    } else if returnToCentre(.QUEEN) {
                        s.queenReturned = true
                    }
                    queenWaiting = nil
                }
                if s.pocketed.contains(.QUEEN) {
                    // ICF 97: the queen with your coin counts as covered, but on a full board (none of yours
                    // pocketed yet) Tournament still asks for a cover.
                    let coveredNow = own > 1 || (own == 1 && (ownBefore > 0 || !tournament))
                    if coveredNow {
                        queenCoveredBy = me; s.queenCovered = true; stats[seat].queens += 1
                    } else if ownBefore + own > 0 {
                        queenWaiting = me; s.queenWaiting = true
                    } else if returnToCentre(.QUEEN) {
                        s.queenReturned = true
                    }
                }
            }
            // Dues are paid from coins already pocketed, as soon as there are any.
            while owed[me] > 0 && pocketed(mine) > 0 {
                if returnToCentre(mine) { s.returned.append(mine) }
                owed[me] -= 1
            }
            // The queen must be covered before a colour is cleared.
            let queenOpen = mode == .CLASSIC && (queenOnBoard || queenWaiting != nil)
            if queenOpen {
                for colour in [mine, theirs] {
                    if left(colour) != 0 { continue }
                    if colour == mine && tournament {
                        // ICF 107: you lose the board by 3 points (1 once the opponent has 22).
                        winner = 1 - me
                        boardPoints = winnerScoreBefore[1 - me] >= 22 ? 1 : 3
                        s.queenFirst = true
                        s.boardOver = true
                        return
                    }
                    if returnToCentre(colour) { s.returned.append(colour) }
                    if colour == mine { s.queenFirst = true }
                }
            }
            s.continues = !s.foul && !s.queenFirst && (own > 0 || queenWaiting == me)
            if left(.WHITE) == 0 || left(.BLACK) == 0 {
                let w = left(.WHITE) == 0 ? 0 : 1
                winner = w
                let queenValue = (queenCoveredBy == w && winnerScoreBefore[w] < 22) ? 3 : 0
                boardPoints = left(colour(1 - w)) + queenValue
            }
        }
        s.boardOver = winner != nil
    }

    // MARK: Codable (kotlinx field names; every field falls back to its default)

    enum CodingKeys: String, CodingKey {
        case mode, sides, teams, tournament, coins, turn, strokes, broken, queenWaiting, queenCoveredBy, points, owed, stats, winner,
             boardPoints, target, winnerScoreBefore
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = c.carrom(.mode, CarromMode.CLASSIC)
        self.init(
            mode: mode,
            sides: c.carrom(.sides, [0, 2]),
            teams: c.carrom(.teams, false),
            tournament: c.carrom(.tournament, false),
            coins: c.carromOptional(.coins, [CarromDisc].self),
            turn: c.carrom(.turn, 0),
            strokes: c.carrom(.strokes, 0),
            broken: c.carrom(.broken, false),
            queenWaiting: c.carromOptional(.queenWaiting, Int.self),
            queenCoveredBy: c.carromOptional(.queenCoveredBy, Int.self),
            points: c.carromOptional(.points, [Int].self),
            owed: c.carromOptional(.owed, [Int].self),
            stats: c.carromOptional(.stats, [CarromSideStats].self),
            winner: c.carromOptional(.winner, Int.self),
            boardPoints: c.carrom(.boardPoints, 0),
            target: c.carromOptional(.target, Int.self),
            winnerScoreBefore: c.carromOptional(.winnerScoreBefore, [Int].self)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(sides, forKey: .sides)
        try c.encode(teams, forKey: .teams)
        try c.encode(tournament, forKey: .tournament)
        try c.encode(coins, forKey: .coins)
        try c.encode(turn, forKey: .turn)
        try c.encode(strokes, forKey: .strokes)
        try c.encode(broken, forKey: .broken)
        try c.encode(queenWaiting, forKey: .queenWaiting)
        try c.encode(queenCoveredBy, forKey: .queenCoveredBy)
        try c.encode(points, forKey: .points)
        try c.encode(owed, forKey: .owed)
        try c.encode(stats, forKey: .stats)
        try c.encode(winner, forKey: .winner)
        try c.encode(boardPoints, forKey: .boardPoints)
        try c.encode(target, forKey: .target)
        try c.encode(winnerScoreBefore, forKey: .winnerScoreBefore)
    }
}

/// A whole match: one board, best of three, or first to 25 points.
final class CarromMatch: Codable {
    let mode: CarromMode
    let sides: [Int]
    let teams: Bool
    let tournament: Bool
    let length: CarromMatchLength
    var table: CarromTable
    var board: Int
    /// Seat index that broke the first board; the break moves round the table each board.
    let firstBreak: Int
    var scores: [Int]
    var wins: [Int]
    var winner: Int?
    /// Per seat, over every board.
    var totals: [CarromSideStats]

    init(
        mode: CarromMode = .CLASSIC,
        sides: [Int] = [0, 2],
        teams: Bool = false,
        tournament: Bool = false,
        length: CarromMatchLength = .ONE,
        table: CarromTable? = nil,
        board: Int = 1,
        firstBreak: Int = 0,
        scores: [Int]? = nil,
        wins: [Int]? = nil,
        winner: Int? = nil,
        totals: [CarromSideStats]? = nil
    ) {
        let units = teams ? 2 : sides.count
        self.mode = mode
        self.sides = sides
        self.teams = teams
        self.tournament = tournament
        self.length = length
        self.table = table ?? CarromTable()
        self.board = board
        self.firstBreak = firstBreak
        self.scores = scores ?? [Int](repeating: 0, count: units)
        self.wins = wins ?? [Int](repeating: 0, count: units)
        self.winner = winner
        self.totals = totals ?? [CarromSideStats](repeating: CarromSideStats(), count: sides.count)
    }

    static func create(_ options: CarromOptions, _ seats: Int, _ firstBreak: Int) -> CarromMatch {
        let sides = CarromSeat.sides(seats)
        let mode: CarromMode = seats == 3 ? .FREESTYLE : options.mode
        let teams = seats == 4 && (mode != .FREESTYLE || options.freestyleTeams)
        let length: CarromMatchLength = (mode == .FREESTYLE && options.length == .RACE25) ? .BEST_OF_THREE : options.length
        return CarromMatch(
            mode: mode, sides: sides, teams: teams, tournament: options.tournament, length: length,
            table: CarromTable.create(mode, sides, teams: teams, tournament: options.tournament, breaker: firstBreak), firstBreak: firstBreak
        )
    }

    func deepCopy() -> CarromMatch {
        CarromMatch(
            mode: mode, sides: sides, teams: teams, tournament: tournament, length: length, table: table.deepCopy(), board: board,
            firstBreak: firstBreak, scores: scores, wins: wins, winner: winner, totals: totals
        )
    }

    var units: Int { teams ? 2 : sides.count }
    var isOver: Bool { winner != nil }
    var breaker: Int { (firstBreak + board - 1) % sides.count }

    /// Records a finished board. Returns true when the match is over too.
    @discardableResult
    func finishBoard() -> Bool {
        guard let w = table.winner else { return false }
        wins[w] += 1
        scores[w] += table.boardPoints
        for i in totals.indices {
            let s = table.stats[i]
            totals[i].coins += s.coins
            totals[i].points += s.points
            totals[i].queens += s.queens
            totals[i].fouls += s.fouls
            totals[i].strokes += s.strokes
            totals[i].bestCombo = Swift.max(totals[i].bestCombo, s.bestCombo)
        }
        switch length {
        case .ONE:
            winner = w
        case .BEST_OF_THREE:
            if wins[w] >= 2 { winner = w }
        case .RACE25:
            if scores[w] >= 25 {
                winner = w
            } else if board >= 8 {
                var best: Int? = nil
                for i in scores.indices where best == nil || scores[best!] < scores[i] { best = i }
                // A tie after eight boards plays an extra board.
                if let best, scores.filter({ $0 == scores[best] }).count == 1 { winner = best }
            }
        }
        return winner != nil
    }

    func nextBoard() {
        board += 1
        table = CarromTable.create(mode, sides, teams: teams, tournament: tournament, breaker: breaker, matchScores: scores)
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey { case mode, sides, teams, tournament, length, table, board, firstBreak, scores, wins, winner, totals }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: c.carrom(.mode, CarromMode.CLASSIC),
            sides: c.carrom(.sides, [0, 2]),
            teams: c.carrom(.teams, false),
            tournament: c.carrom(.tournament, false),
            length: c.carrom(.length, CarromMatchLength.ONE),
            table: c.carromOptional(.table, CarromTable.self),
            board: c.carrom(.board, 1),
            firstBreak: c.carrom(.firstBreak, 0),
            scores: c.carromOptional(.scores, [Int].self),
            wins: c.carromOptional(.wins, [Int].self),
            winner: c.carromOptional(.winner, Int.self),
            totals: c.carromOptional(.totals, [CarromSideStats].self)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(sides, forKey: .sides)
        try c.encode(teams, forKey: .teams)
        try c.encode(tournament, forKey: .tournament)
        try c.encode(length, forKey: .length)
        try c.encode(table, forKey: .table)
        try c.encode(board, forKey: .board)
        try c.encode(firstBreak, forKey: .firstBreak)
        try c.encode(scores, forKey: .scores)
        try c.encode(wins, forKey: .wins)
        try c.encode(winner, forKey: .winner)
        try c.encode(totals, forKey: .totals)
    }
}
