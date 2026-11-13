import Foundation

/// Shared sounds: the reference's PartySound effects (tap, dice, step, ladder, snake, place,
/// move, capture, check, win, draw, turn) plus new menu sounds for the app shell.
enum UiSound {
    enum Effect: CaseIterable, Hashable {
        // PartySound (ported 1:1)
        case Tap, Dice, Step, Ladder, Snake, Place, Move, Capture, Check, Win, Draw, Turn
        // App shell
        case Click, Pop, Swoosh, Toggle, Back, Coin, Fanfare, Lose, Chime, Whoosh, Sparkle

        static var entries: [Effect] { allCases }
    }

    private static let bank = SoundBank<Effect>(synthesize)

    static func play(_ effect: Effect) { bank.play(effect, throttleSeconds: 0.02) }

    static func warmUp() { bank.warmUp(Effect.allCases) }

    private typealias W = Synth.Wave

    private static func tone(_ f: Double, _ d: Double, _ w: W, _ v: Float, decay: Double = 3.2) -> [Float] {
        Synth.tone(f, d, w, v, decay: decay)
    }

    private static func synthesize(_ effect: Effect) -> [Float] {
        switch effect {
        case .Tap: return tone(1200.0, 0.035, .Sine, 0.35)
        case .Step: return tone(760.0, 0.06, .Triangle, 0.35)
        case .Turn: return Synth.concat(tone(1046.0, 0.09, .Sine, 0.25), tone(1318.0, 0.14, .Sine, 0.22))
        case .Place: return Synth.sweep(520.0, 880.0, 0.09, .Triangle, 0.45)
        case .Move: return Synth.mix(tone(210.0, 0.07, .Sine, 0.55), tone(0.0, 0.03, .Noise, 0.18))
        case .Capture:
            return Synth.concat(
                Synth.mix(tone(180.0, 0.07, .Sine, 0.55), tone(0.0, 0.04, .Noise, 0.25)),
                Synth.silence(0.03),
                tone(260.0, 0.06, .Sine, 0.45)
            )
        case .Check:
            return Synth.concat(tone(880.0, 0.09, .Square, 0.18), Synth.silence(0.02), tone(660.0, 0.14, .Square, 0.18))
        case .Dice:
            let gaps = [0.0, 0.05, 0.035, 0.06, 0.045, 0.08, 0.06]
            return Synth.concat(gaps.map { gap in
                Synth.concat(Synth.silence(gap), Synth.mix(tone(0.0, 0.025, .Noise, 0.35), tone(1500.0, 0.02, .Triangle, 0.15)))
            })
        case .Ladder:
            return Synth.concat([523.25, 659.25, 783.99, 1046.5].map { tone($0, 0.085, .Triangle, 0.32) })
        case .Snake: return Synth.sweep(880.0, 180.0, 0.55, .Triangle, 0.32, vibrato: 9.0)
        case .Win:
            let notes: [(Double, Double)] = [(523.25, 0.11), (659.25, 0.11), (783.99, 0.11), (1046.5, 0.32)]
            return Synth.concat(
                Synth.concat(notes.map { tone($0.0, $0.1, .Triangle, 0.34) }),
                Synth.mix(tone(523.25, 0.45, .Sine, 0.18), tone(783.99, 0.45, .Sine, 0.15))
            )
        case .Draw: return Synth.concat(tone(587.33, 0.16, .Triangle, 0.28), tone(587.33, 0.22, .Triangle, 0.24))

        case .Click: return Synth.mix(tone(1650.0, 0.028, .Sine, 0.28), tone(3300.0, 0.012, .Triangle, 0.06))
        case .Pop: return Synth.sweep(420.0, 980.0, 0.07, .Sine, 0.38, decay: 4.0)
        case .Swoosh:
            return Synth.mix(
                Synth.sweep(1800.0, 500.0, 0.16, .Noise, 0.10, decay: 2.0, attack: 0.04),
                Synth.sweep(300.0, 620.0, 0.12, .Sine, 0.12)
            )
        case .Toggle: return Synth.concat(tone(880.0, 0.03, .Sine, 0.25), tone(1320.0, 0.05, .Sine, 0.22))
        case .Back: return Synth.sweep(900.0, 520.0, 0.08, .Sine, 0.28)
        case .Coin:
            return Synth.concat(tone(987.77, 0.06, .Square, 0.10), Synth.mix(tone(1318.5, 0.28, .Square, 0.10), tone(2637.0, 0.28, .Sine, 0.06)))
        case .Fanfare:
            let lead: [(Double, Double)] = [(392.0, 0.12), (523.25, 0.12), (659.25, 0.12), (783.99, 0.22), (659.25, 0.1), (783.99, 0.5)]
            var out = Synth.concat(lead.map { Synth.mix(tone($0.0, $0.1, .Triangle, 0.30), tone($0.0 * 2, $0.1, .Sine, 0.08)) })
            out = Synth.overlay(out, Synth.mix(tone(261.63, 0.9, .Sine, 0.16, decay: 1.6), tone(392.0, 0.9, .Sine, 0.12, decay: 1.6)), 0.48)
            out = Synth.overlay(out, sparkle(), 0.7)
            return out
        case .Lose:
            return Synth.concat(
                tone(392.0, 0.18, .Triangle, 0.28),
                tone(369.99, 0.18, .Triangle, 0.26),
                Synth.sweep(349.23, 261.63, 0.5, .Triangle, 0.26, vibrato: 6.0)
            )
        case .Chime:
            var out = Synth.mix(tone(783.99, 1.1, .Sine, 0.22, decay: 2.2), tone(1567.98, 0.8, .Sine, 0.08, decay: 3.0))
            out = Synth.overlay(out, Synth.mix(tone(1174.66, 1.0, .Sine, 0.18, decay: 2.4), tone(2349.3, 0.6, .Sine, 0.05)), 0.12)
            return Synth.overlay(out, tone(1567.98, 0.9, .Sine, 0.14, decay: 2.6), 0.24)
        case .Whoosh: return Synth.sweep(200.0, 2400.0, 0.35, .Noise, 0.12, decay: 1.2, attack: 0.12)
        case .Sparkle: return sparkle()
        }
    }

    private static func sparkle() -> [Float] {
        var out = Synth.silence(0.5)
        for (i, f) in [2093.0, 2637.0, 3135.96, 4186.0].enumerated() {
            out = Synth.overlay(out, tone(f, 0.18, .Sine, 0.07, decay: 4.0), Double(i) * 0.06)
        }
        return out
    }
}
