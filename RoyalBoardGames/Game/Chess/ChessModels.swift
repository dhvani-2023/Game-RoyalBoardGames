import SwiftUI
import GameKit

/// Stored by case name ("OFF", "BLITZ3", …) like kotlinx.serialization does on Android.
enum ChessClockOption: String, CaseIterable, Codable, Hashable, Sendable {
    case OFF, BLITZ3, RAPID5, RAPID10, CLASSICAL15

    /// Kotlin `rawValue` (the reference's id; not what is stored).
    var key: String {
        switch self {
        case .OFF: "off"
        case .BLITZ3: "blitz3"
        case .RAPID5: "rapid5"
        case .RAPID10: "rapid10"
        case .CLASSICAL15: "classical15"
        }
    }

    var title: String {
        switch self {
        case .OFF: "No clock"
        case .BLITZ3: "3 + 2"
        case .RAPID5: "5 min"
        case .RAPID10: "10 min"
        case .CLASSICAL15: "15 + 10"
        }
    }

    var seconds: Double? {
        switch self {
        case .OFF: nil
        case .BLITZ3: 180.0
        case .RAPID5: 300.0
        case .RAPID10: 600.0
        case .CLASSICAL15: 900.0
        }
    }

    var increment: Double {
        switch self {
        case .BLITZ3: 2.0
        case .CLASSICAL15: 10.0
        default: 0.0
        }
    }

    static var entries: [ChessClockOption] { allCases }
}

/// One match's setup. `whiteIsBot`/`blackIsBot` and `botLevel` are new on Android (the reference is
/// pass-and-play only); everything else matches the reference ChessConfig.
struct ChessConfig: Codable, Hashable {
    var white: PartyPlayer
    var black: PartyPlayer
    var clock: ChessClockOption = .OFF
    var passDevice: Bool = false
    var autoRotate: Bool = false
    var boardStyle: Int = 0
    var whiteIsBot: Bool = false
    var blackIsBot: Bool = false
    /// 0 easy, 1 normal, 2 hard.
    var botLevel: Int = 1

    init(white: PartyPlayer, black: PartyPlayer, clock: ChessClockOption = .OFF, passDevice: Bool = false, autoRotate: Bool = false,
         boardStyle: Int = 0, whiteIsBot: Bool = false, blackIsBot: Bool = false, botLevel: Int = 1) {
        self.white = white
        self.black = black
        self.clock = clock
        self.passDevice = passDevice
        self.autoRotate = autoRotate
        self.boardStyle = boardStyle
        self.whiteIsBot = whiteIsBot
        self.blackIsBot = blackIsBot
        self.botLevel = botLevel
    }

    func isBot(_ color: ChessColor) -> Bool { color == .WHITE ? whiteIsBot : blackIsBot }
    var hasBot: Bool { whiteIsBot || blackIsBot }

    /// Kotlin `copy(...)`.
    func copy(white: PartyPlayer? = nil, black: PartyPlayer? = nil, clock: ChessClockOption? = nil, passDevice: Bool? = nil,
              autoRotate: Bool? = nil, boardStyle: Int? = nil, whiteIsBot: Bool? = nil, blackIsBot: Bool? = nil, botLevel: Int? = nil) -> ChessConfig {
        ChessConfig(white: white ?? self.white, black: black ?? self.black, clock: clock ?? self.clock,
                    passDevice: passDevice ?? self.passDevice, autoRotate: autoRotate ?? self.autoRotate,
                    boardStyle: boardStyle ?? self.boardStyle, whiteIsBot: whiteIsBot ?? self.whiteIsBot,
                    blackIsBot: blackIsBot ?? self.blackIsBot, botLevel: botLevel ?? self.botLevel)
    }

    private enum CodingKeys: String, CodingKey {
        case white, black, clock, passDevice, autoRotate, boardStyle, whiteIsBot, blackIsBot, botLevel
    }

    /// Missing or invalid fields fall back to their defaults (kotlinx `coerceInputValues` + defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        white = try c.decode(PartyPlayer.self, forKey: .white)
        black = try c.decode(PartyPlayer.self, forKey: .black)
        clock = (try? c.decodeIfPresent(ChessClockOption.self, forKey: .clock)) ?? .OFF
        passDevice = (try? c.decodeIfPresent(Bool.self, forKey: .passDevice)) ?? false
        autoRotate = (try? c.decodeIfPresent(Bool.self, forKey: .autoRotate)) ?? false
        boardStyle = (try? c.decodeIfPresent(Int.self, forKey: .boardStyle)) ?? 0
        whiteIsBot = (try? c.decodeIfPresent(Bool.self, forKey: .whiteIsBot)) ?? false
        blackIsBot = (try? c.decodeIfPresent(Bool.self, forKey: .blackIsBot)) ?? false
        botLevel = (try? c.decodeIfPresent(Int.self, forKey: .botLevel)) ?? 1
    }
}

/// The reference's PartyStore.Settings chess fields, kept per game on Android.
struct ChessSetupSettings: Codable, Hashable {
    var clock: ChessClockOption = .OFF
    var passDevice: Bool = false
    var autoRotate: Bool = false
    var boardStyle: Int = 0
    var vsComputer: Bool = false
    var botLevel: Int = 1

    init(clock: ChessClockOption = .OFF, passDevice: Bool = false, autoRotate: Bool = false, boardStyle: Int = 0,
         vsComputer: Bool = false, botLevel: Int = 1) {
        self.clock = clock
        self.passDevice = passDevice
        self.autoRotate = autoRotate
        self.boardStyle = boardStyle
        self.vsComputer = vsComputer
        self.botLevel = botLevel
    }

    /// Kotlin `copy(...)`.
    func copy(clock: ChessClockOption? = nil, passDevice: Bool? = nil, autoRotate: Bool? = nil, boardStyle: Int? = nil,
              vsComputer: Bool? = nil, botLevel: Int? = nil) -> ChessSetupSettings {
        ChessSetupSettings(clock: clock ?? self.clock, passDevice: passDevice ?? self.passDevice, autoRotate: autoRotate ?? self.autoRotate,
                           boardStyle: boardStyle ?? self.boardStyle, vsComputer: vsComputer ?? self.vsComputer, botLevel: botLevel ?? self.botLevel)
    }

    private enum CodingKeys: String, CodingKey { case clock, passDevice, autoRotate, boardStyle, vsComputer, botLevel }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clock = (try? c.decodeIfPresent(ChessClockOption.self, forKey: .clock)) ?? .OFF
        passDevice = (try? c.decodeIfPresent(Bool.self, forKey: .passDevice)) ?? false
        autoRotate = (try? c.decodeIfPresent(Bool.self, forKey: .autoRotate)) ?? false
        boardStyle = (try? c.decodeIfPresent(Int.self, forKey: .boardStyle)) ?? 0
        vsComputer = (try? c.decodeIfPresent(Bool.self, forKey: .vsComputer)) ?? false
        botLevel = (try? c.decodeIfPresent(Int.self, forKey: .botLevel)) ?? 1
    }
}

/// Autosaved unfinished match: the moves are replayed through `ChessMatch` on resume.
struct ChessSaved: Codable, Hashable {
    var config: ChessConfig
    var moves: [String] = []
    var whiteClock: Double? = nil
    var blackClock: Double? = nil
    var flipped: Bool = false

    init(config: ChessConfig, moves: [String] = [], whiteClock: Double? = nil, blackClock: Double? = nil, flipped: Bool = false) {
        self.config = config
        self.moves = moves
        self.whiteClock = whiteClock
        self.blackClock = blackClock
        self.flipped = flipped
    }

    private enum CodingKeys: String, CodingKey { case config, moves, whiteClock, blackClock, flipped }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        config = try c.decode(ChessConfig.self, forKey: .config)
        moves = (try? c.decodeIfPresent([String].self, forKey: .moves)) ?? []
        whiteClock = (try? c.decodeIfPresent(Double.self, forKey: .whiteClock)) ?? nil
        blackClock = (try? c.decodeIfPresent(Double.self, forKey: .blackClock)) ?? nil
        flipped = (try? c.decodeIfPresent(Bool.self, forKey: .flipped)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(config, forKey: .config)
        try c.encode(moves, forKey: .moves)
        try c.encode(whiteClock, forKey: .whiteClock) // explicit null, like kotlinx encodeDefaults
        try c.encode(blackClock, forKey: .blackClock)
        try c.encode(flipped, forKey: .flipped)
    }
}

struct ChessBoardStyle: Hashable {
    let name: String
    /// 0xAARRGGBB, for Core Graphics drawing.
    let lightArgb: UInt32
    let darkArgb: UInt32

    var light: Color { Color(argb: lightArgb) }
    var dark: Color { Color(argb: darkArgb) }

    static let all: [ChessBoardStyle] = [
        ChessBoardStyle(name: "Walnut", lightArgb: 0xFFF0DAB5, darkArgb: 0xFFB0805A),
        ChessBoardStyle(name: "Tournament", lightArgb: 0xFFEEEED2, darkArgb: 0xFF769656),
        ChessBoardStyle(name: "Ocean", lightArgb: 0xFFDEE7F1, darkArgb: 0xFF6F8FB3),
        ChessBoardStyle(name: "Amethyst", lightArgb: 0xFFEFE9FF, darkArgb: 0xFF8C7BD6),
    ]

    static func style(_ index: Int) -> ChessBoardStyle { all[((index % all.count) + all.count) % all.count] }
}
