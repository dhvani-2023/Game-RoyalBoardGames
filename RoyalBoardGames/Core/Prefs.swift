import Foundation
import GameKit

/// Device-local key/value storage (Android SharedPreferences "board_games").
/// Values are JSON strings under versioned keys, e.g. `party.pool.saved.v1`, exactly like kotlinx.serialization on Android.
/// Backed by `GameKit.Prefs(name: "board_games")`, so `GameKit.Prefs(name: "board_games").codable(...)` reads the same values.
/// Nothing ever leaves the device.
enum Prefs {
    static let prefs = GameKit.Prefs(name: "board_games")

    /// Kotlin `Prefs.load<T>(key)`: nil when missing or undecodable.
    /// `let s: Saved? = Prefs.load(KEY)` or `Prefs.load(KEY, as: Saved.self)`.
    static func load<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        prefs.codable(key, as: type)
    }

    /// Kotlin `Prefs.save(key, value)`.
    static func save<T: Encodable>(_ key: String, _ value: T) {
        prefs.setCodable(key, value)
    }

    static func remove(_ key: String) {
        prefs.remove(key)
    }

    static func has(_ key: String) -> Bool { prefs.contains(key) }
}
