import Foundation
import GameKit

/// One Ludo match's setup.
struct LudoConfig: Codable, Equatable {
    var seats: [LudoSeat] = []
    /// 4 or 6.
    var arms: Int = 4
    var themeID: Int = 0
    var rules: LudoRules = LudoRules()
    /// Arms to turn the board by, so a lone person sits at the bottom-left.
    var shift: Int = 0
    /// Continue the saved match instead of starting fresh.
    var resume: Bool = false

    init(seats: [LudoSeat] = [], arms: Int = 4, themeID: Int = 0, rules: LudoRules = LudoRules(), shift: Int = 0, resume: Bool = false) {
        self.seats = seats
        self.arms = arms
        self.themeID = themeID
        self.rules = rules
        self.shift = shift
        self.resume = resume
    }

    /// Kotlin `copy(resume = …)`.
    func copy(resume: Bool) -> LudoConfig {
        var c = self
        c.resume = resume
        return c
    }

    private enum CodingKeys: String, CodingKey { case seats, arms, themeID, rules, shift, resume }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seats = (try c.decodeIfPresent([LudoSeat].self, forKey: .seats)) ?? []
        arms = (try? c.decodeIfPresent(Int.self, forKey: .arms)) ?? 4
        themeID = (try? c.decodeIfPresent(Int.self, forKey: .themeID)) ?? 0
        rules = (try? c.decodeIfPresent(LudoRules.self, forKey: .rules)) ?? LudoRules()
        shift = (try? c.decodeIfPresent(Int.self, forKey: .shift)) ?? 0
        resume = (try? c.decodeIfPresent(Bool.self, forKey: .resume)) ?? false
    }
}

/// Ludo's setup choices and the saved match, on the device only. Kept apart from the other party
/// games' settings so adding Ludo never disturbs them.
enum LudoStore {
    /// Every field has a default, so adding options never resets the rest.
    struct Setup: Codable, Equatable {
        var seats: Int = 4
        var peopleCount: Int = 1
        /// Use the six-arm board for 3–4 seats too.
        var sixArms: Bool = false
        var themeID: Int = 0
        var rules: LudoRules = LudoRules()
        /// Whether the mode was chosen by hand; otherwise it follows the seat count.
        var customMode: Bool = false
        var difficulties: [LudoDifficulty] = Array(repeating: .NORMAL, count: 6)
        /// The people last seated, in seat order.
        var players: [PartyPlayer] = []
        /// Board arm each person sat at last time (their colour).
        var arms: [Int] = []

        init(seats: Int = 4, peopleCount: Int = 1, sixArms: Bool = false, themeID: Int = 0, rules: LudoRules = LudoRules(),
             customMode: Bool = false, difficulties: [LudoDifficulty] = Array(repeating: .NORMAL, count: 6),
             players: [PartyPlayer] = [], arms: [Int] = []) {
            self.seats = seats
            self.peopleCount = peopleCount
            self.sixArms = sixArms
            self.themeID = themeID
            self.rules = rules
            self.customMode = customMode
            self.difficulties = difficulties
            self.players = players
            self.arms = arms
        }

        private enum CodingKeys: String, CodingKey { case seats, peopleCount, sixArms, themeID, rules, customMode, difficulties, players, arms }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Setup()
            seats = (try? c.decodeIfPresent(Int.self, forKey: .seats)) ?? d.seats
            peopleCount = (try? c.decodeIfPresent(Int.self, forKey: .peopleCount)) ?? d.peopleCount
            sixArms = (try? c.decodeIfPresent(Bool.self, forKey: .sixArms)) ?? d.sixArms
            themeID = (try? c.decodeIfPresent(Int.self, forKey: .themeID)) ?? d.themeID
            rules = (try? c.decodeIfPresent(LudoRules.self, forKey: .rules)) ?? d.rules
            customMode = (try? c.decodeIfPresent(Bool.self, forKey: .customMode)) ?? d.customMode
            difficulties = try c.decodeIfPresent([LudoDifficulty].self, forKey: .difficulties) ?? d.difficulties
            players = try c.decodeIfPresent([PartyPlayer].self, forKey: .players) ?? d.players
            arms = (try? c.decodeIfPresent([Int].self, forKey: .arms)) ?? d.arms
        }
    }

    struct SavedMatch: Codable, Equatable {
        var config: LudoConfig
        var engine: LudoEngine
        var elapsed: Double = 0.0
        var date: Int64 = Days.nowMillis()

        init(_ config: LudoConfig, _ engine: LudoEngine, _ elapsed: Double = 0.0, _ date: Int64 = Days.nowMillis()) {
            self.config = config
            self.engine = engine
            self.elapsed = elapsed
            self.date = date
        }

        private enum CodingKeys: String, CodingKey { case config, engine, elapsed, date }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            config = try c.decode(LudoConfig.self, forKey: .config)
            engine = try c.decode(LudoEngine.self, forKey: .engine)
            elapsed = (try? c.decodeIfPresent(Double.self, forKey: .elapsed)) ?? 0.0
            date = (try? c.decodeIfPresent(Int64.self, forKey: .date)) ?? Days.nowMillis()
        }
    }

    private static let SETUP_KEY = "party.ludo.setup.v1"
    private static let SAVED_KEY = "party.ludo.saved.v1"

    static var setup: Setup {
        get { Prefs.load(SETUP_KEY, as: Setup.self) ?? Setup(difficulties: Array(repeating: BotLevel.default.toLudo(), count: 6)) }
        set { Prefs.save(SETUP_KEY, newValue) }
    }

    static var saved: SavedMatch? {
        get {
            guard let s = Prefs.load(SAVED_KEY, as: SavedMatch.self) else { return nil }
            return (!s.config.seats.isEmpty && s.engine.seatCount == s.config.seats.count) ? s : nil
        }
        set {
            if let newValue { Prefs.save(SAVED_KEY, newValue) } else { Prefs.remove(SAVED_KEY) }
        }
    }

    static let botNames = ["CPU Leo", "CPU Ana", "CPU Max", "CPU Ivy", "CPU Kai"]
    static let botAvatars = ["🤖", "👾", "🦾", "🛸", "🧠"]

    /// Rough minutes for a game, from the rules simulation (docs/research/ludo/sim.py).
    static func estimatedMinutes(_ seats: Int, _ people: Int, _ arms: Int, _ rules: LudoRules) -> Int {
        let classic: [Int: Double] = [2: 166.0, 3: 290.0, 4: 430.0, 5: 900.0, 6: 1292.0]
        let quick: [Int: Double] = [2: 69.0, 3: 105.0, 4: 148.0, 5: 250.0, 6: 351.0]
        var rolls = (rules.quick ? quick : classic)[min(max(seats, 2), 6)] ?? 400.0
        if arms == 6 && seats <= 4 { rolls *= 1.45 }
        if rules.allPlaces { rolls *= rules.quick ? 1.6 : 1.3 }
        let peopleShare = Double(min(people, seats)) / Double(max(seats, 1))
        let secondsPerRoll = peopleShare * 2.2 + (1 - peopleShare) * (rules.fastBots ? 0.8 : 1.3)
        return max(2, Kt.roundToInt(rolls * secondsPerRoll / 60))
    }
}

extension BotLevel {
    func toLudo() -> LudoDifficulty {
        switch self {
        case .EASY: return .EASY
        case .NORMAL: return .NORMAL
        case .HARD: return .HARD
        }
    }
}
