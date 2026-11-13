import Foundation
import GameKit

/// Haptic ticks that respect the Haptics setting (Android Vibrator effects mapped to Core Haptics / UIKit feedback).
/// Callable from any thread: the feedback is always fired on the main thread.
enum Haptics {
    enum Kind { case Tick, Light, Medium, Heavy, Success, Warning, Error }

    static func play(_ kind: Kind = .Light) {
        guard AppSettings.hapticsEnabled else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { fire(kind) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { fire(kind) } }
        }
    }

    // Passthroughs for code written against GameKit names.
    static func tick() { play(.Tick) }
    static func tap() { play(.Light) }
    static func medium() { play(.Medium) }
    static func heavy() { play(.Heavy) }
    static func success() { play(.Success) }
    static func warning() { play(.Warning) }
    static func error() { play(.Error) }

    @MainActor
    private static func fire(_ kind: Kind) {
        switch kind {
        case .Tick: GameKit.Haptics.tick() // EFFECT_TICK
        case .Light: GameKit.Haptics.tap(0.75) // EFFECT_CLICK
        case .Medium: GameKit.Haptics.medium() // EFFECT_HEAVY_CLICK
        case .Heavy: GameKit.Haptics.heavy() // one shot 40 ms at full amplitude
        case .Success: GameKit.Haptics.pattern(timings: [0, 18, 60, 28], amplitudes: [0, 160, 0, 255])
        case .Warning: GameKit.Haptics.warning() // EFFECT_DOUBLE_CLICK
        case .Error: GameKit.Haptics.pattern(timings: [0, 30, 50, 30, 50, 30], amplitudes: [0, 200, 0, 200, 0, 200])
        }
    }
}
