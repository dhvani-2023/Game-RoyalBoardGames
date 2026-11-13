import Foundation
import GameKit

/// What a Carrom match is started with.
struct CarromConfig: Codable {
    /// In side order: 0 bottom, 1 right, 2 top, 3 left.
    var seats: [CarromSeat] = []
    var options: CarromOptions = CarromOptions()
    var boardID: Int = 0
    var coinsID: Int = 0
    var strikerID: Int = 0
    /// Continue the saved match instead of starting fresh.
    var resume: Bool = false
    /// Extras: the practice board (one player, free shooting).
    var practice: Bool = false

    init(_ seats: [CarromSeat] = [], _ options: CarromOptions = CarromOptions(), _ boardID: Int = 0, _ coinsID: Int = 0,
         _ strikerID: Int = 0, resume: Bool = false, practice: Bool = false) {
        self.practice = practice
        self.seats = seats
        self.options = options
        self.boardID = boardID
        self.coinsID = coinsID
        self.strikerID = strikerID
        self.resume = resume
    }

    /// Kotlin `copy(resume = …)`.
    func copy(resume: Bool) -> CarromConfig {
        var c = self
        c.resume = resume
        return c
    }

    enum CodingKeys: String, CodingKey { case seats, options, boardID, coinsID, strikerID, resume, practice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seats = c.carrom(.seats, [CarromSeat]())
        options = c.carrom(.options, CarromOptions())
        boardID = c.carrom(.boardID, 0)
        coinsID = c.carrom(.coinsID, 0)
        strikerID = c.carrom(.strikerID, 0)
        resume = c.carrom(.resume, false)
        practice = c.carrom(.practice, false)
    }
}

/// Carrom's setup choices and the saved match, on the device only. Kept apart from the shared party settings so
/// adding Carrom never disturbs the other games' saved settings.
enum CarromStore {
    /// Every field falls back to its default, so adding options never resets the rest.
    struct Setup: Codable {
        var seats: Int = 2
        var peopleCount: Int = 1
        var options: CarromOptions = CarromOptions()
        var boardID: Int = 0
        var coinsID: Int = 0
        var strikerID: Int = 0
        /// Whether coins and striker were picked by hand; otherwise they follow the board.
        var customLooks: Bool = false
        var difficulties: [CarromDifficulty] = [CarromDifficulty](repeating: .NORMAL, count: 3)
        /// The people last seated, in seat order.
        var players: [PartyPlayer] = []

        init() {}

        enum CodingKeys: String, CodingKey { case seats, peopleCount, options, boardID, coinsID, strikerID, customLooks, difficulties, players }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            seats = c.carrom(.seats, 2)
            peopleCount = c.carrom(.peopleCount, 1)
            options = c.carrom(.options, CarromOptions())
            boardID = c.carrom(.boardID, 0)
            coinsID = c.carrom(.coinsID, 0)
            strikerID = c.carrom(.strikerID, 0)
            customLooks = c.carrom(.customLooks, false)
            difficulties = c.carrom(.difficulties, [CarromDifficulty](repeating: .NORMAL, count: 3))
            players = c.carrom(.players, [PartyPlayer]())
        }
    }

    struct SavedMatch: Codable {
        var config: CarromConfig = CarromConfig()
        var match: CarromMatch = CarromMatch()
        var elapsed: Double = 0.0
        var date: Int64 = 0

        init(_ config: CarromConfig = CarromConfig(), _ match: CarromMatch = CarromMatch(), _ elapsed: Double = 0.0, _ date: Int64 = 0) {
            self.config = config
            self.match = match
            self.elapsed = elapsed
            self.date = date
        }

        enum CodingKeys: String, CodingKey { case config, match, elapsed, date }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            config = c.carrom(.config, CarromConfig())
            match = c.carromOptional(.match, CarromMatch.self) ?? CarromMatch()
            elapsed = c.carrom(.elapsed, 0.0)
            date = c.carrom(.date, Int64(0))
        }
    }

    private static let SETUP_KEY = "party.carrom.setup.v1"
    private static let SAVED_KEY = "party.carrom.saved.v1"

    static var setup: Setup {
        get { Prefs.load(SETUP_KEY, as: Setup.self) ?? Setup() }
        set { Prefs.save(SETUP_KEY, newValue) }
    }

    static var saved: SavedMatch? {
        get {
            guard let s = Prefs.load(SAVED_KEY, as: SavedMatch.self) else { return nil }
            return (!s.config.seats.isEmpty && s.match.sides.count == s.config.seats.count) ? s : nil
        }
        set {
            if let value = newValue { Prefs.save(SAVED_KEY, value) } else { Prefs.remove(SAVED_KEY) }
        }
    }

    static func hasSetup() -> Bool { Prefs.has(SETUP_KEY) }

    static func hasSaved() -> Bool { Prefs.has(SAVED_KEY) && saved != nil }

    static let botNames = ["CPU Leo", "CPU Ana", "CPU Max"]
    static let botAvatars = ["🤖", "👾", "🦾"]
    static let teamNames = ["Team Pearl", "Team Onyx"]

    /// Rough minutes for a match, from the simulations (docs/research/carrom/sim-results.md): shots per board by
    /// mode and seats; a person aims for about 7 s, a computer about 2 s, and each shot rolls for about 2.6 s.
    static func estimatedMinutes(_ seats: Int, _ people: Int, _ options: CarromOptions) -> Int {
        let mode: CarromMode = seats == 3 ? .FREESTYLE : options.mode
        let shots: Double
        switch mode {
        case .CLASSIC: shots = 29.0
        case .POOL: shots = 23.0
        case .FREESTYLE: shots = seats == 2 ? 22.0 : 17.0
        }
        let peopleShare = Double(Swift.min(people, seats)) / Double(Swift.max(seats, 1))
        // People pocket less often than Normal computers, so boards run longer with more people.
        let seconds = shots * (1 + peopleShare * 0.35) * (peopleShare * 7 + (1 - peopleShare) * (options.fastBots ? 1.2 : 2.2) + 2.6)
        let length: CarromMatchLength = (mode == .FREESTYLE && options.length == .RACE25) ? .BEST_OF_THREE : options.length
        let boards: Double
        switch length {
        case .ONE: boards = 1.0
        case .BEST_OF_THREE: boards = 2.5
        case .RACE25: boards = 5.0
        }
        return Swift.max(2, roundHalfAway(seconds * boards / 60))
    }

    /// Swift's `.rounded()`: halves round away from zero.
    private static func roundHalfAway(_ v: Double) -> Int {
        v >= 0 ? Kt.toInt((v + 0.5).rounded(.down)) : -Kt.toInt((-v + 0.5).rounded(.down))
    }
}
