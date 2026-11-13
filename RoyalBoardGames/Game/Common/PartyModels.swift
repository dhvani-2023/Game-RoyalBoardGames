import SwiftUI
import GameKit

/// The six games. Ids are permanent: saved games and stats are keyed by them.
/// Case names are the Kotlin ones (`GameKind.TIC_TAC_TOE`); `id` is the stored key ("tictactoe").
enum GameKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case POOL, CARROM, LUDO, CHESS, SNAKES, TIC_TAC_TOE

    var id: String {
        switch self {
        case .POOL: "pool"
        case .CARROM: "carrom"
        case .LUDO: "ludo"
        case .CHESS: "chess"
        case .SNAKES: "snakes"
        case .TIC_TAC_TOE: "tictactoe"
        }
    }

    var title: String {
        switch self {
        case .POOL: "Pool: 8-Ball & 9-Ball"
        case .CARROM: "Carrom"
        case .LUDO: "Ludo"
        case .CHESS: "Chess"
        case .SNAKES: "Snakes & Ladders"
        case .TIC_TAC_TOE: "Tic-Tac-Toe"
        }
    }

    var tagline: String {
        switch self {
        case .POOL: "8-Ball and 9-Ball with real spin on eight hand-drawn tables."
        case .CARROM: "Flick, cut and pocket on eight boards. Classic, Pocket Pool or Freestyle."
        case .LUDO: "Race your tokens home on a classic or six-arm board."
        case .CHESS: "The royal duel with full rules, clocks and a computer rival."
        case .SNAKES: "Race to 100 across ten themed boards. Climb ladders, dodge snakes."
        case .TIC_TAC_TOE: "Quick-fire X and O. A single game or a best-of match."
        }
    }

    var minPlayers: Int { 2 }

    var maxPlayers: Int {
        switch self {
        case .POOL, .CARROM: 4
        case .LUDO, .SNAKES: 6
        case .CHESS, .TIC_TAC_TOE: 2
        }
    }

    var accent: [Color] {
        switch self {
        case .POOL: GameAccent.pool
        case .CARROM: GameAccent.carrom
        case .LUDO: GameAccent.ludo
        case .CHESS: GameAccent.chess
        case .SNAKES: GameAccent.snakes
        case .TIC_TAC_TOE: GameAccent.ticTacToe
        }
    }

    var modes: String {
        switch self {
        case .POOL: "8-Ball · 9-Ball"
        case .CARROM: "3 modes"
        case .LUDO: "4-arm · 6-arm"
        case .CHESS: "Clocks · Bot"
        case .SNAKES: "10 boards"
        case .TIC_TAC_TOE: "Best of 1 · 3 · 5"
        }
    }

    var playersLabel: String { minPlayers == maxPlayers ? "\(minPlayers) players" : "\(minPlayers)–\(maxPlayers) players" }

    /// Kotlin `ordinal`.
    var ordinal: Int { GameKind.allCases.firstIndex(of: self)! }
    /// Kotlin `entries`.
    static var entries: [GameKind] { allCases }

    static func byId(_ id: String) -> GameKind? { allCases.first { $0.id == id } }
}

/// Everything the app shell needs from one game. Each game folder exposes one module implementing this,
/// named like the Kotlin `object` (PoolGame, CarromGame, LudoGame, ChessGame, SnakesGame, TicTacToeGame):
///
///     final class PoolGame: BoardGameModule {
///         static let shared = PoolGame()
///         let kind = GameKind.POOL
///         ...
///     }
///
/// and handles its own setup → play → result → rematch flow inside `Content`.
@MainActor
protocol BoardGameModule {
    var kind: GameKind { get }

    /// True when an unfinished match is autosaved and can be resumed.
    func hasSavedGame() -> Bool

    /// Short line for the Continue card, e.g. "Raj vs CPU Leo · 8-Ball". Nil when nothing is saved.
    func savedGameSummary() -> String?

    func clearSavedGame()

    /// Full game flow. `resume` = open the autosaved match directly. `onExit` returns to the app shell.
    func Content(resume: Bool, onExit: @escaping () -> Void) -> AnyView

    /// Animated mini board for cards and tiles, drawn with the game's own art. Fills the frame it is given.
    func Artwork() -> AnyView
}

extension BoardGameModule {
    func savedGameSummary() -> String? { nil }
}

// MARK: - Players

struct PartyPlayer: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString.lowercased()
    var name: String
    var avatar: String
    var colorIndex: Int

    init(id: String = UUID().uuidString.lowercased(), name: String, avatar: String, colorIndex: Int) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.colorIndex = colorIndex
    }

    var color: Color { PartyStyle.color(colorIndex) }

    /// Trimmed name, or a numbered fallback when left blank.
    func displayName(_ fallbackIndex: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Player \(fallbackIndex + 1)" : String(trimmed.prefix(16))
    }

    /// Kotlin `copy(...)`.
    func copy(id: String? = nil, name: String? = nil, avatar: String? = nil, colorIndex: Int? = nil) -> PartyPlayer {
        PartyPlayer(id: id ?? self.id, name: name ?? self.name, avatar: avatar ?? self.avatar, colorIndex: colorIndex ?? self.colorIndex)
    }

    private enum CodingKeys: String, CodingKey { case id, name, avatar, colorIndex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString.lowercased()
        name = try c.decode(String.self, forKey: .name)
        avatar = try c.decode(String.self, forKey: .avatar)
        colorIndex = try c.decode(Int.self, forKey: .colorIndex)
    }
}

enum PartyStyle {
    static let avatars = ["🦊", "🐼", "🐯", "🐸", "🦄", "🐙", "🐧", "🦁", "🐨", "🐵", "🐰", "🐲", "🦉", "🐝", "🐬", "🦖"]
    static let botAvatars = ["🤖", "👾", "🎩", "🧠", "🦾", "🛸"]
    static let botNames = ["Leo", "Mia", "Ava", "Max", "Zoe", "Kai"]

    /// Six seat colours that stay distinct from each other on the dark theme.
    static let tokenColors: [Color] = [
        Color(argb: 0xFFFF5A5F), Color(argb: 0xFF3C8CFF), Color(argb: 0xFF2FD18A),
        Color(argb: 0xFFFFC23D), Color(argb: 0xFFA66BFF), Color(argb: 0xFFFF7AB6),
    ]
    /// The same colours as 0xAARRGGBB, for Canvas/CoreGraphics code.
    static let tokenArgb: [UInt32] = [0xFFFF5A5F, 0xFF3C8CFF, 0xFF2FD18A, 0xFFFFC23D, 0xFFA66BFF, 0xFFFF7AB6]
    static let colorNames = ["Ruby", "Sapphire", "Emerald", "Gold", "Amethyst", "Rose"]

    static func color(_ index: Int) -> Color { tokenColors[((index % tokenColors.count) + tokenColors.count) % tokenColors.count] }

    /// Seat 0 is the device owner (profile name/avatar from Settings); the rest are numbered.
    static func defaultPlayers(_ count: Int) -> [PartyPlayer] {
        (0..<max(0, count)).map { i in
            i == 0
                ? PartyPlayer(name: AppSettings.displayName, avatar: AppSettings.data.avatar, colorIndex: 0)
                : PartyPlayer(name: "Player \(i + 1)", avatar: avatars[i % avatars.count], colorIndex: i)
        }
    }
}

/// Computer-player strength shared by every game's setup.
enum BotLevel: String, CaseIterable, Codable, Hashable {
    case EASY, NORMAL, HARD

    var title: String {
        switch self {
        case .EASY: "Easy"
        case .NORMAL: "Normal"
        case .HARD: "Hard"
        }
    }

    var ordinal: Int { BotLevel.allCases.firstIndex(of: self)! }
    static var entries: [BotLevel] { allCases }

    /// The level picked in Settings (Kotlin `BotLevel.default`).
    static var `default`: BotLevel {
        let i = AppSettings.data.botLevel
        return allCases.indices.contains(i) ? allCases[i] : .NORMAL
    }
}

// MARK: - History & stats

struct PartyMatchRecord: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString.lowercased()
    var kind: String
    var date: Int64 = Days.nowMillis()
    /// Names with avatars, e.g. "🦊 Raj".
    var players: [String]
    /// Winner's name and avatar, or nil for a draw.
    var winner: String?
    /// Short result line, e.g. "Checkmate in 34 moves".
    var detail: String

    init(id: String = UUID().uuidString.lowercased(), kind: String, date: Int64 = Days.nowMillis(), players: [String], winner: String?, detail: String) {
        self.id = id
        self.kind = kind
        self.date = date
        self.players = players
        self.winner = winner
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey { case id, kind, date, players, winner, detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString.lowercased()
        kind = try c.decode(String.self, forKey: .kind)
        date = (try? c.decodeIfPresent(Int64.self, forKey: .date)) ?? Days.nowMillis()
        players = try c.decode([String].self, forKey: .players)
        winner = try? c.decodeIfPresent(String.self, forKey: .winner)
        detail = try c.decode(String.self, forKey: .detail)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(date, forKey: .date)
        try c.encode(players, forKey: .players)
        try c.encode(winner, forKey: .winner) // explicit null, like kotlinx encodeDefaults
        try c.encode(detail, forKey: .detail)
    }
}

/// Observable backing for `PartyStore` (SwiftUI views that read `PartyStore.history` redraw on change).
@Observable
final class PartyStoreState {
    var history: [PartyMatchRecord] = []
}

/// Match history and last-used players, stored on this device only.
enum PartyStore {
    private static let HISTORY_KEY = "party.history.v1"
    private static let PLAYERS_KEY = "party.lastPlayers.v1"
    private static let LIMIT = 200

    static let state = PartyStoreState()

    static var history: [PartyMatchRecord] {
        ensureLoaded()
        return state.history
    }

    private static var lastPlayers: [String: [PartyPlayer]] = [:]
    private static var loaded = false

    static func ensureLoaded() {
        if loaded { return }
        loaded = true
        state.history = Prefs.load(HISTORY_KEY, as: [PartyMatchRecord].self) ?? []
        lastPlayers = Prefs.load(PLAYERS_KEY, as: [String: [PartyPlayer]].self) ?? [:]
    }

    static func record(_ record: PartyMatchRecord) {
        ensureLoaded()
        state.history = Array(([record] + state.history).prefix(LIMIT))
        Prefs.save(HISTORY_KEY, state.history)
    }

    static func record(_ kind: GameKind, _ players: [PartyPlayer], _ winner: PartyPlayer?, _ detail: String) {
        record(PartyMatchRecord(
            kind: kind.id,
            players: players.map { "\($0.avatar) \($0.name)" },
            winner: winner.map { "\($0.avatar) \($0.name)" },
            detail: detail
        ))
    }

    static func record(kind: GameKind, players: [PartyPlayer], winner: PartyPlayer?, detail: String) {
        record(kind, players, winner, detail)
    }

    static func clearHistory() {
        ensureLoaded()
        state.history = []
        Prefs.remove(HISTORY_KEY)
    }

    static func players(_ kind: GameKind) -> [PartyPlayer]? {
        ensureLoaded()
        return lastPlayers[kind.id]
    }

    static func remember(_ players: [PartyPlayer], _ kind: GameKind) {
        ensureLoaded()
        lastPlayers[kind.id] = players
        Prefs.save(PLAYERS_KEY, lastPlayers)
    }
}

// MARK: - Orientation

/// Lets the screen rotate while this is on screen (Pool, Carrom); the app is portrait otherwise.
/// Use `AllowRotation()` inside a view (like the Kotlin composable) or `.allowRotation()` on it.
/// Nested/overlapping users are reference-counted, so a crossfade between two rotating screens stays unlocked.
struct AllowRotation: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .allowRotation()
    }
}

private struct AllowRotationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { RotationGate.acquire() }
            .onDisappear { RotationGate.release() }
    }
}

extension View {
    /// Kotlin `AllowRotation()`: free rotation while this view is on screen.
    func allowRotation() -> some View { modifier(AllowRotationModifier()) }
}

@MainActor
private enum RotationGate {
    static var count = 0

    static func acquire() {
        count += 1
        if count == 1 { OrientationLock.shared.set(.all) }
    }

    static func release() {
        count = max(0, count - 1)
        if count == 0 { OrientationLock.shared.set(.portrait, rotateTo: .portrait) }
    }
}
