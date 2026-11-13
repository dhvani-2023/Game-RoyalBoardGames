import Foundation
import GameKit

struct PoolSeat: Equatable, Codable, Identifiable {
    var player: PartyPlayer
    var isBot: Bool = false
    var difficulty: PoolDifficulty = .NORMAL

    init(_ player: PartyPlayer, isBot: Bool = false, difficulty: PoolDifficulty = .NORMAL) {
        self.player = player
        self.isBot = isBot
        self.difficulty = difficulty
    }

    var id: String { player.id }

    /// Kotlin `copy(...)`.
    func copy(player: PartyPlayer? = nil, isBot: Bool? = nil, difficulty: PoolDifficulty? = nil) -> PoolSeat {
        PoolSeat(player ?? self.player, isBot: isBot ?? self.isBot, difficulty: difficulty ?? self.difficulty)
    }

    private enum CodingKeys: String, CodingKey { case player, isBot, difficulty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        player = try c.decode(PartyPlayer.self, forKey: .player)
        isBot = try c.poolValue(.isBot, false)
        difficulty = c.poolEnum(.difficulty, .NORMAL)
    }
}

struct PoolConfig: Equatable, Codable {
    /// In turn order. 8-Ball with four players: seats 0 and 2 against 1 and 3.
    var seats: [PoolSeat] = []
    var options: PoolOptions = PoolOptions()
    var tableID: Int = 0
    var cueID: Int = 0
    /// Continue the saved match instead of starting fresh.
    var resume: Bool = false
    /// Extras: the practice table (one player, free shooting).
    var practice: Bool = false

    init(_ seats: [PoolSeat] = [], _ options: PoolOptions = PoolOptions(), _ tableID: Int = 0, _ cueID: Int = 0, resume: Bool = false,
         practice: Bool = false) {
        self.seats = seats
        self.options = options
        self.tableID = tableID
        self.cueID = cueID
        self.resume = resume
        self.practice = practice
    }

    /// Kotlin `copy(resume = …)`.
    func copy(resume: Bool) -> PoolConfig { PoolConfig(seats, options, tableID, cueID, resume: resume, practice: practice) }

    private enum CodingKeys: String, CodingKey { case seats, options, tableID, cueID, resume, practice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seats = try c.poolValue(.seats, [])
        options = try c.poolValue(.options, PoolOptions())
        tableID = try c.poolValue(.tableID, 0)
        cueID = try c.poolValue(.cueID, 0)
        resume = try c.poolValue(.resume, false)
        practice = try c.poolValue(.practice, false)
    }
}

/// Pool's setup choices and the saved match, on the device only. Kept apart from the shared
/// party settings so adding Pool never disturbs the other games' saved settings.
enum PoolStore {
    /// Every field falls back to its default, so adding options never resets the rest.
    struct Setup: Equatable, Codable {
        var seats: Int = 2
        var peopleCount: Int = 1
        var options: PoolOptions = PoolOptions()
        var tableID: Int = 0
        var cueID: Int = 0
        /// Whether the cue was picked by hand; otherwise it follows the table.
        var customCue: Bool = false
        var difficulties: [PoolDifficulty] = [PoolDifficulty](repeating: .NORMAL, count: 3)
        /// The people last seated, in seat order.
        var players: [PartyPlayer] = []

        init(seats: Int = 2, peopleCount: Int = 1, options: PoolOptions = PoolOptions(), tableID: Int = 0, cueID: Int = 0,
             customCue: Bool = false, difficulties: [PoolDifficulty] = [PoolDifficulty](repeating: .NORMAL, count: 3),
             players: [PartyPlayer] = []) {
            self.seats = seats
            self.peopleCount = peopleCount
            self.options = options
            self.tableID = tableID
            self.cueID = cueID
            self.customCue = customCue
            self.difficulties = difficulties
            self.players = players
        }

        private enum CodingKeys: String, CodingKey { case seats, peopleCount, options, tableID, cueID, customCue, difficulties, players }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            seats = try c.poolValue(.seats, 2)
            peopleCount = try c.poolValue(.peopleCount, 1)
            options = try c.poolValue(.options, PoolOptions())
            tableID = try c.poolValue(.tableID, 0)
            cueID = try c.poolValue(.cueID, 0)
            customCue = try c.poolValue(.customCue, false)
            difficulties = (try? c.decodeIfPresent([String].self, forKey: .difficulties))
                .map { list in list.map { PoolDifficulty(rawValue: $0) ?? .NORMAL } } ?? [PoolDifficulty](repeating: .NORMAL, count: 3)
            players = try c.poolValue(.players, [])
        }
    }

    struct SavedMatch: Codable {
        var config: PoolConfig = PoolConfig()
        var match: PoolMatch = PoolMatch()
        var elapsed: Double = 0.0
        var date: Int64 = 0

        init(_ config: PoolConfig = PoolConfig(), _ match: PoolMatch = PoolMatch(), _ elapsed: Double = 0.0, _ date: Int64 = 0) {
            self.config = config
            self.match = match
            self.elapsed = elapsed
            self.date = date
        }

        private enum CodingKeys: String, CodingKey { case config, match, elapsed, date }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            config = try c.poolValue(.config, PoolConfig())
            match = try c.poolValue(.match, PoolMatch())
            elapsed = try c.poolValue(.elapsed, 0.0)
            date = try c.poolValue(.date, 0)
        }
    }

    private static let SETUP_KEY = "party.pool.setup.v1"
    private static let SAVED_KEY = "party.pool.saved.v1"

    static var setup: Setup {
        get {
            Prefs.load(SETUP_KEY, as: Setup.self)
                ?? Setup(difficulties: [PoolDifficulty](repeating: fromBotLevel(BotLevel.default), count: 3))
        }
        set { Prefs.save(SETUP_KEY, newValue) }
    }

    static var saved: SavedMatch? {
        get {
            guard let s = Prefs.load(SAVED_KEY, as: SavedMatch.self), !s.config.seats.isEmpty else { return nil }
            return s
        }
        set {
            if let v = newValue { Prefs.save(SAVED_KEY, v) } else { Prefs.remove(SAVED_KEY) }
        }
    }

    static func hasSaved() -> Bool { Prefs.has(SAVED_KEY) }

    static let botNames = ["CPU Leo", "CPU Ana", "CPU Max"]
    static let botAvatars = ["🤖", "👾", "🦾"]
    static let teamNames = ["Team Gold", "Team Azure"]

    static func fromBotLevel(_ level: BotLevel) -> PoolDifficulty {
        switch level {
        case .EASY: return .EASY
        case .NORMAL: return .NORMAL
        case .HARD: return .HARD
        }
    }

    /// Rough minutes for a match, from the simulations: shots per rack by game and seats; a person
    /// aims for about 8 s, a computer about 2.5 s, and each shot rolls for about 4 s.
    static func estimatedMinutes(_ seats: Int, _ people: Int, _ options: PoolOptions) -> Int {
        let game: PoolVariant = seats == 3 ? .NINE : options.game
        let shots = game == .EIGHT ? 22.0 : (seats == 2 ? 9.0 : 7.0)
        let peopleShare = Double(min(people, seats)) / Double(max(seats, 1))
        // People pot less often than Normal computers, so racks run longer with more people.
        let seconds = shots * (1 + peopleShare * 0.5) * (peopleShare * 8 + (1 - peopleShare) * (options.fastBots ? 1.3 : 2.5) + 4)
        let target = Double(options.length.target)
        // A race to N takes N racks for the winner plus some for the others.
        let racks = target == 1.0 ? 1.0 : target + (target - 1) * (seats == 2 ? 0.7 : 1.1)
        return max(2, Kt.roundToInt(seconds * racks / 60))
    }
}
