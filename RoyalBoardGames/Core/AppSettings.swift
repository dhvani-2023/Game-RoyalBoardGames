import Foundation
import Observation
import GameKit

/// Observable backing for `AppSettings` (views that read `AppSettings.data` redraw on change).
@Observable
final class AppSettingsState {
    var data = AppSettings.Data()
}

/// App-wide preferences. Observable from SwiftUI; every change is written straight to `Prefs`.
enum AppSettings {
    struct Data: Codable, Equatable {
        var soundEnabled: Bool = true
        var musicEnabled: Bool = false
        var volume: Float = 0.8
        var hapticsEnabled: Bool = true
        var reduceMotion: Bool = false
        var confirmLeave: Bool = true
        /// 0 easy, 1 normal, 2 hard. Used as the default for new computer players.
        var botLevel: Int = 1
        var playerName: String = ""
        var avatar: String = "🦊"
        var onboardingDone: Bool = false

        init(soundEnabled: Bool = true, musicEnabled: Bool = false, volume: Float = 0.8, hapticsEnabled: Bool = true,
             reduceMotion: Bool = false, confirmLeave: Bool = true, botLevel: Int = 1, playerName: String = "",
             avatar: String = "🦊", onboardingDone: Bool = false) {
            self.soundEnabled = soundEnabled
            self.musicEnabled = musicEnabled
            self.volume = volume
            self.hapticsEnabled = hapticsEnabled
            self.reduceMotion = reduceMotion
            self.confirmLeave = confirmLeave
            self.botLevel = botLevel
            self.playerName = playerName
            self.avatar = avatar
            self.onboardingDone = onboardingDone
        }

        /// Kotlin `copy(...)`: `AppSettings.update { $0.copy(soundEnabled: v) }`.
        func copy(soundEnabled: Bool? = nil, musicEnabled: Bool? = nil, volume: Float? = nil, hapticsEnabled: Bool? = nil,
                  reduceMotion: Bool? = nil, confirmLeave: Bool? = nil, botLevel: Int? = nil, playerName: String? = nil,
                  avatar: String? = nil, onboardingDone: Bool? = nil) -> Data {
            Data(soundEnabled: soundEnabled ?? self.soundEnabled, musicEnabled: musicEnabled ?? self.musicEnabled,
                 volume: volume ?? self.volume, hapticsEnabled: hapticsEnabled ?? self.hapticsEnabled,
                 reduceMotion: reduceMotion ?? self.reduceMotion, confirmLeave: confirmLeave ?? self.confirmLeave,
                 botLevel: botLevel ?? self.botLevel, playerName: playerName ?? self.playerName,
                 avatar: avatar ?? self.avatar, onboardingDone: onboardingDone ?? self.onboardingDone)
        }

        private enum CodingKeys: String, CodingKey {
            case soundEnabled, musicEnabled, volume, hapticsEnabled, reduceMotion, confirmLeave, botLevel, playerName, avatar, onboardingDone
        }

        /// Missing or invalid fields fall back to their defaults (kotlinx `coerceInputValues` + defaults).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Data()
            soundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .soundEnabled)) ?? d.soundEnabled
            musicEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .musicEnabled)) ?? d.musicEnabled
            volume = (try? c.decodeIfPresent(Float.self, forKey: .volume)) ?? d.volume
            hapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? d.hapticsEnabled
            reduceMotion = (try? c.decodeIfPresent(Bool.self, forKey: .reduceMotion)) ?? d.reduceMotion
            confirmLeave = (try? c.decodeIfPresent(Bool.self, forKey: .confirmLeave)) ?? d.confirmLeave
            botLevel = (try? c.decodeIfPresent(Int.self, forKey: .botLevel)) ?? d.botLevel
            playerName = (try? c.decodeIfPresent(String.self, forKey: .playerName)) ?? d.playerName
            avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar)) ?? d.avatar
            onboardingDone = (try? c.decodeIfPresent(Bool.self, forKey: .onboardingDone)) ?? d.onboardingDone
        }
    }

    private static let KEY = "app.settings.v1"

    static let state = AppSettingsState()

    /// Current settings (observable).
    static var data: Data { state.data }

    static func load() {
        state.data = Prefs.load(KEY, as: Data.self) ?? Data()
        applySideEffects()
    }

    static func update(_ transform: (Data) -> Data) {
        let old = state.data
        state.data = transform(old)
        Prefs.save(KEY, state.data)
        applySideEffects()
        if old.musicEnabled != state.data.musicEnabled || old.volume != state.data.volume { MusicPlayer.sync() }
    }

    /// Swift convenience: `AppSettings.edit { $0.soundEnabled = v }`.
    static func edit(_ change: (inout Data) -> Void) {
        update { var d = $0; change(&d); return d }
    }

    static var soundEnabled: Bool { data.soundEnabled }
    static var hapticsEnabled: Bool { data.hapticsEnabled }
    static var displayName: String {
        let t = data.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Player" : t
    }

    /// Mirrors the settings that audio/haptics read off the main thread or outside SwiftUI.
    private static func applySideEffects() {
        let d = state.data
        AudioMixer.setOutput(enabled: d.soundEnabled, volume: d.volume)
        let apply = {
            MainActor.assumeIsolated {
                GameKit.Haptics.enabled = d.hapticsEnabled
                Motion.appReduceMotion = d.reduceMotion
            }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }
}
