import Foundation

/// One Tic-Tac-Toe match.
struct TicTacToeConfig: Hashable {
    var playerX: PartyPlayer
    var playerO: PartyPlayer
    var bestOf: Int
    var passDevice: Bool
    /// The computer's mark, or nil for two people.
    var botMark: TTTMark? = nil
    var botLevel: BotLevel = .NORMAL

    init(playerX: PartyPlayer, playerO: PartyPlayer, bestOf: Int, passDevice: Bool, botMark: TTTMark? = nil, botLevel: BotLevel = .NORMAL) {
        self.playerX = playerX
        self.playerO = playerO
        self.bestOf = bestOf
        self.passDevice = passDevice
        self.botMark = botMark
        self.botLevel = botLevel
    }

    func player(_ mark: TTTMark) -> PartyPlayer { mark == .X ? playerX : playerO }
    func isBot(_ mark: TTTMark) -> Bool { botMark == mark }
}

/// Tic-Tac-Toe's setup choices, on the device only (the reference kept them in the party settings).
enum TicTacToeStore {
    struct Setup: Codable, Hashable {
        var bestOf: Int = 1
        var passDevice: Bool = false
        var vsBot: Bool = false
        /// BotLevel ordinal; −1 follows the app's default.
        var botLevel: Int = -1
        /// Which row the computer sits in: 0 = X, 1 = O.
        var botSeat: Int = 1
        var botColor: Int = 1

        init(bestOf: Int = 1, passDevice: Bool = false, vsBot: Bool = false, botLevel: Int = -1, botSeat: Int = 1, botColor: Int = 1) {
            self.bestOf = bestOf
            self.passDevice = passDevice
            self.vsBot = vsBot
            self.botLevel = botLevel
            self.botSeat = botSeat
            self.botColor = botColor
        }

        /// Kotlin `copy(...)`.
        func copy(bestOf: Int? = nil, passDevice: Bool? = nil, vsBot: Bool? = nil, botLevel: Int? = nil, botSeat: Int? = nil, botColor: Int? = nil) -> Setup {
            Setup(bestOf: bestOf ?? self.bestOf, passDevice: passDevice ?? self.passDevice, vsBot: vsBot ?? self.vsBot,
                  botLevel: botLevel ?? self.botLevel, botSeat: botSeat ?? self.botSeat, botColor: botColor ?? self.botColor)
        }

        private enum CodingKeys: String, CodingKey { case bestOf, passDevice, vsBot, botLevel, botSeat, botColor }

        /// Missing or invalid fields fall back to their defaults (kotlinx `coerceInputValues` + defaults).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bestOf = (try? c.decodeIfPresent(Int.self, forKey: .bestOf)) ?? 1
            passDevice = (try? c.decodeIfPresent(Bool.self, forKey: .passDevice)) ?? false
            vsBot = (try? c.decodeIfPresent(Bool.self, forKey: .vsBot)) ?? false
            botLevel = (try? c.decodeIfPresent(Int.self, forKey: .botLevel)) ?? -1
            botSeat = (try? c.decodeIfPresent(Int.self, forKey: .botSeat)) ?? 1
            botColor = (try? c.decodeIfPresent(Int.self, forKey: .botColor)) ?? 1
        }
    }

    private static let SETUP_KEY = "party.tictactoe.setup.v1"

    static var setup: Setup {
        get { Prefs.load(SETUP_KEY, as: Setup.self) ?? Setup() }
        set { Prefs.save(SETUP_KEY, newValue) }
    }

    /// The computer opponent as a player card.
    static func botPlayer(_ colorIndex: Int) -> PartyPlayer {
        PartyPlayer(
            id: "tictactoe.cpu",
            name: "CPU \(PartyStyle.botNames[0])",
            avatar: PartyStyle.botAvatars[0],
            colorIndex: colorIndex
        )
    }
}
