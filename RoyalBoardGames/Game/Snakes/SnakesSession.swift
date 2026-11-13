import Foundation
import Observation

/// One match's setup. `bots` (computer seats) is new on Android; the reference is pass-and-play only.
struct SnakesConfig: Codable, Hashable {
    var players: [PartyPlayer]
    var themeID: Int = 0
    var rules: SnakesRules = SnakesRules()
    var bots: [Bool] = []

    init(players: [PartyPlayer], themeID: Int = 0, rules: SnakesRules = SnakesRules(), bots: [Bool] = []) {
        self.players = players
        self.themeID = themeID
        self.rules = rules
        self.bots = bots
    }

    func isBot(_ index: Int) -> Bool { bots.indices.contains(index) ? bots[index] : false }

    private enum CodingKeys: String, CodingKey { case players, themeID, rules, bots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        players = try c.decode([PartyPlayer].self, forKey: .players)
        themeID = (try? c.decodeIfPresent(Int.self, forKey: .themeID)) ?? 0
        rules = (try? c.decodeIfPresent(SnakesRules.self, forKey: .rules)) ?? SnakesRules()
        bots = (try? c.decodeIfPresent([Bool].self, forKey: .bots)) ?? []
    }
}

/// The reference's PartyStore.Settings snakes fields, kept per game on Android.
struct SnakesSetupSettings: Codable, Hashable {
    var themeID: Int = 0
    var rules: SnakesRules = SnakesRules()
    var playerCount: Int = 2
    var bots: [Bool] = []

    init(themeID: Int = 0, rules: SnakesRules = SnakesRules(), playerCount: Int = 2, bots: [Bool] = []) {
        self.themeID = themeID
        self.rules = rules
        self.playerCount = playerCount
        self.bots = bots
    }

    /// Kotlin `copy(...)`.
    func copy(themeID: Int? = nil, rules: SnakesRules? = nil, playerCount: Int? = nil, bots: [Bool]? = nil) -> SnakesSetupSettings {
        SnakesSetupSettings(themeID: themeID ?? self.themeID, rules: rules ?? self.rules,
                            playerCount: playerCount ?? self.playerCount, bots: bots ?? self.bots)
    }

    private enum CodingKeys: String, CodingKey { case themeID, rules, playerCount, bots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        themeID = (try? c.decodeIfPresent(Int.self, forKey: .themeID)) ?? 0
        rules = (try? c.decodeIfPresent(SnakesRules.self, forKey: .rules)) ?? SnakesRules()
        playerCount = (try? c.decodeIfPresent(Int.self, forKey: .playerCount)) ?? 2
        bots = (try? c.decodeIfPresent([Bool].self, forKey: .bots)) ?? []
    }
}

/// Autosaved unfinished match.
struct SnakesSaved: Codable, Hashable {
    var config: SnakesConfig
    var positions: [Int] = []
    var finishOrder: [Int] = []
    var current: Int = 0
    var sixStreak: Int = 0
    var turnCount: Int = 0
    var diceValue: Int = 6

    init(_ config: SnakesConfig, _ positions: [Int] = [], _ finishOrder: [Int] = [], _ current: Int = 0,
         _ sixStreak: Int = 0, _ turnCount: Int = 0, _ diceValue: Int = 6) {
        self.config = config
        self.positions = positions
        self.finishOrder = finishOrder
        self.current = current
        self.sixStreak = sixStreak
        self.turnCount = turnCount
        self.diceValue = diceValue
    }

    private enum CodingKeys: String, CodingKey { case config, positions, finishOrder, current, sixStreak, turnCount, diceValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        config = try c.decode(SnakesConfig.self, forKey: .config)
        positions = (try? c.decodeIfPresent([Int].self, forKey: .positions)) ?? []
        finishOrder = (try? c.decodeIfPresent([Int].self, forKey: .finishOrder)) ?? []
        current = (try? c.decodeIfPresent(Int.self, forKey: .current)) ?? 0
        sixStreak = (try? c.decodeIfPresent(Int.self, forKey: .sixStreak)) ?? 0
        turnCount = (try? c.decodeIfPresent(Int.self, forKey: .turnCount)) ?? 0
        diceValue = (try? c.decodeIfPresent(Int.self, forKey: .diceValue)) ?? 6
    }
}

/// Drives one Snakes & Ladders match: rolls, token animation and turn messages.
@MainActor
@Observable
final class SnakesSession {
    /// How a token travels to its latest point (the reference used a different animation for each).
    enum TokenAnim { case HOP, LADDER, SNAKE, RELAYOUT }

    struct Spotlight: Equatable {
        enum Kind { case LADDER, SNAKE, FINISH, SIX }

        let id: Int
        let kind: Kind
        let text: String
        let player: PartyPlayer
    }

    let config: SnakesConfig

    private(set) var game: SnakesMatch

    /// Where each token is drawn, in board cell units. Animated hop by hop.
    private(set) var tokenPoints: [BoardPoint] = []
    private(set) var tokenAnims: [TokenAnim] = []
    /// Bumped on every hop of a player's token (drives the bounce).
    private(set) var hops: [Int] = []
    private(set) var movingPlayer: Int? = nil
    private(set) var diceValue: Int = 6
    private(set) var isRolling = false
    private(set) var isBusy = false
    private(set) var rollCount = 0
    private(set) var lastMove: SnakesMove? = nil
    private(set) var headline = ""
    private(set) var message: String? = nil
    /// Bumped when the turn passes to someone else (banner animation).
    private(set) var turnID = 0
    /// A ladder/snake/finish moment for a big toast.
    private(set) var spotlight: Spotlight? = nil
    private(set) var finishedCelebration = 0
    private(set) var isFinished = false
    /// Whose turn the screen shows. Lags the engine until the move animation finishes.
    private(set) var activePlayer = 0

    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored private var spotlightSeq = 0

    init(_ config: SnakesConfig) {
        self.config = config
        game = SnakesMatch(config.players.count, config.rules)
        for i in 0..<config.players.count {
            hops.append(0)
            tokenPoints.append(SnakesGeometry.startPoint(i))
            tokenAnims.append(.RELAYOUT)
        }
        headline = "It's \(config.players[0].name)'s turn"
        message = config.rules.requireSixToStart ? "Roll a 6 to enter the board" : "Roll the dice to start the race!"
    }

    var players: [PartyPlayer] { config.players }
    var currentPlayer: PartyPlayer { players[activePlayer] }
    var theme: SnakesTheme { SnakesTheme.theme(config.themeID) }
    func isBot(_ index: Int) -> Bool { config.isBot(index) }

    private func setPoint(_ player: Int, _ point: BoardPoint, _ anim: TokenAnim) {
        tokenAnims[player] = anim
        tokenPoints[player] = point
    }

    private func makeSpotlight(_ kind: Spotlight.Kind, _ text: String, _ player: PartyPlayer) -> Spotlight {
        spotlightSeq += 1
        return Spotlight(id: spotlightSeq, kind: kind, text: text, player: player)
    }

    /// Kotlin `delay(ms)`: throws when the screen's scope is cancelled, which ends the flow.
    private func delay(_ ms: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
    }

    // MARK: Turn

    func roll() async {
        do { try await rollFlow() } catch {}
    }

    private func rollFlow() async throws {
        if isBusy || game.isOver { return }
        isBusy = true
        spotlight = nil
        rollCount += 1
        UiSound.play(.Dice)

        isRolling = true
        for _ in 0..<(reduceMotion ? 2 : 9) {
            diceValue = Int.random(in: 1...6)
            try await delay(65)
        }
        let value = Int.random(in: 1...6)
        diceValue = value
        isRolling = false

        let player = players[game.current]
        let move = game.roll(value)
        game = game
        lastMove = move
        message = "\(player.name) rolled a \(value)!"
        try await delay(reduceMotion ? 150 : 380)

        switch move.outcome {
        case .NeedSix: message = "\(player.name) rolled a \(value) — needs a 6 to start"
        case let .Overshoot(needed): message = "\(player.name) rolled a \(value) — needs exactly \(needed) to finish"
        case .ThreeSixes: message = "Three sixes in a row! \(player.name)'s turn is over"
        case .Moved, .Finished: try await animate(move, player)
        }

        if case let .Finished(place) = move.outcome {
            finishedCelebration += 1
            UiSound.play(.Win)
            spotlight = makeSpotlight(.FINISH, "\(player.name) finished \(ordinal(place))!", player)
            try await delay(reduceMotion ? 400 : 1300)
        }

        if game.isOver {
            relayout()
            isFinished = true
            isBusy = false
            save()
            return
        }

        if move.extraTurn {
            if spotlight == nil { spotlight = makeSpotlight(.SIX, "Six! \(player.name) rolls again", player) }
            activePlayer = move.player
            headline = "\(player.name) rolls again!"
        } else {
            let next = players[move.nextPlayer]
            turnID += 1
            activePlayer = move.nextPlayer
            headline = "It's \(next.name)'s turn"
            message = summary(move, player) + " — \(next.name), roll the dice!"
            UiSound.play(.Turn)
        }
        isBusy = false
        save()
    }

    private func animate(_ move: SnakesMove, _ player: PartyPlayer) async throws {
        let p = move.player
        movingPlayer = p
        let hop = reduceMotion ? 70 : 210
        for square in move.steps {
            setPoint(p, SnakesGeometry.center(square), .HOP)
            hops[p] = hops[p] + 1
            UiSound.play(.Step)
            try await delay(hop)
        }

        switch move.jump {
        case let .Ladder(from, to)?:
            UiSound.play(.Ladder)
            spotlight = makeSpotlight(.LADDER, "\(player.name) climbed a ladder! \(from) → \(to)", player)
            message = "\(player.name) climbed a ladder! \(from) → \(to)"
            let a = SnakesGeometry.center(from)
            let b = SnakesGeometry.center(to)
            let steps = reduceMotion ? 1 : 10
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                setPoint(p, BoardPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t), .LADDER)
                try await delay(reduceMotion ? 100 : 60)
            }
        case let .Snake(from, to)?:
            UiSound.play(.Snake)
            spotlight = makeSpotlight(.SNAKE, "\(player.name) slid down a snake! \(from) → \(to)", player)
            message = "\(player.name) slid down a snake! \(from) → \(to)"
            // Ride the snake's wavy body from head to tail.
            let steps = reduceMotion ? 1 : 32
            for i in 1...steps {
                setPoint(p, SnakesGeometry.snakePoint(from, Double(i) / Double(steps)), .SNAKE)
                try await delay(reduceMotion ? 100 : 26)
            }
        case nil:
            break
        }
        try await delay(reduceMotion ? 60 : 200)
        movingPlayer = nil
        relayout()
    }

    /// Spreads tokens that share a square so every one stays visible.
    func relayout() {
        var groups: [Int: [Int]] = [:]
        for (player, square) in game.positions.enumerated() where square > 0 { groups[square, default: []].append(player) }
        var waiting = 0
        for player in players.indices {
            let square = game.positions[player]
            if square == 0 {
                setPoint(player, SnakesGeometry.startPoint(waiting), .RELAYOUT)
                waiting += 1
                continue
            }
            let group = groups[square] ?? [player]
            setPoint(player, offset(SnakesGeometry.center(square), max(0, group.firstIndex(of: player) ?? -1), group.count), .RELAYOUT)
        }
    }

    /// Token scale when several share a square.
    func tokenScale(_ player: Int) -> Float {
        if movingPlayer == player { return 1 }
        let square = game.positions[player]
        if square <= 0 { return 0.9 }
        let sharing = game.positions.filter { $0 == square }.count
        return sharing <= 1 ? 1 : (sharing == 2 ? 0.78 : 0.62)
    }

    private func offset(_ c: BoardPoint, _ index: Int, _ count: Int) -> BoardPoint {
        if count <= 1 { return c }
        let d = count == 2 ? 0.2 : 0.24
        let angle = Double(index) / Double(count) * 2 * Double.pi - Double.pi / 2
        return BoardPoint(c.x + cos(angle) * d, c.y + sin(angle) * d)
    }

    // MARK: Text

    private func summary(_ move: SnakesMove, _ player: PartyPlayer) -> String {
        switch (move.outcome, move.jump) {
        case (.NeedSix, _): return "\(player.name) needs a 6"
        case let (.Overshoot(needed), _): return "\(player.name) needs exactly \(needed)"
        case (.ThreeSixes, _): return "\(player.name) rolled three sixes"
        case let (_, .Ladder(from, to)?): return "\(player.name) climbed \(from) → \(to)"
        case let (_, .Snake(from, to)?): return "\(player.name) slid \(from) → \(to)"
        default: return "\(player.name) moved to \(move.to)"
        }
    }

    func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    func clearSpotlight(_ id: Int) {
        if spotlight?.id == id { spotlight = nil }
    }

    // MARK: Restart

    func restart() {
        if isBusy { return }
        game = SnakesMatch(players.count, config.rules)
        lastMove = nil
        spotlight = nil
        isFinished = false
        movingPlayer = nil
        diceValue = 6
        activePlayer = 0
        turnID += 1
        headline = "It's \(players[0].name)'s turn"
        message = config.rules.requireSixToStart ? "Roll a 6 to enter the board" : "Roll the dice to start the race!"
        relayout()
        Prefs.remove(SnakesGame.SAVE_KEY)
    }

    // MARK: Autosave (new on Android)

    func restore(_ saved: SnakesSaved) {
        if saved.positions.count != players.count { return }
        game = SnakesMatch(players.count, config.rules, saved.positions, saved.current, saved.finishOrder, saved.sixStreak, saved.turnCount)
        diceValue = min(max(saved.diceValue, 1), 6)
        activePlayer = saved.current
        headline = "It's \(players[saved.current].name)'s turn"
        message = "Welcome back! \(players[saved.current].name), roll the dice!"
        relayout()
    }

    var inProgress: Bool { game.turnCount > 0 && !isFinished }

    func save() {
        if isFinished || game.turnCount == 0 {
            Prefs.remove(SnakesGame.SAVE_KEY)
            return
        }
        let g = game
        Prefs.save(SnakesGame.SAVE_KEY, SnakesSaved(config, g.positions, g.finishOrder, g.current, g.sixStreak, g.turnCount, diceValue))
    }
}
