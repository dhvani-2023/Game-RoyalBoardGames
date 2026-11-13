import Foundation
import GameKit

/// Ludo's sound effects, synthesized in code at first use (no audio files).
/// Follows the app's sound setting through the shared mixer.
enum LudoSound {
    enum Effect: Hashable {
        case Shake
        case Land
        case Six
        /// One square of a move; `step` climbs a pentatonic scale along the move.
        case Hop(_ step: Int)
        case ComeOut
        case Safe
        case Capture
        case Home
        case Extra
        case ThreeSixes
        case Turn
        case Win
        case Tap
    }

    /// Rendered natively at the mixer's rate (Android renders the same recipe at 44.1 kHz).
    private static let RATE = Double(AudioMixer.SAMPLE_RATE)
    private static let bank = SoundBank<Effect>(synthesize)

    static func play(_ effect: Effect, throttle: Double = 0.03) { bank.play(effect, throttle) }

    static func warmUp() {
        bank.warmUp([Effect.Shake, .Land, .Six, .ComeOut, .Capture, .Turn] + (0..<6).map { Effect.Hop($0) })
    }

    // MARK: Synthesis

    private enum Wave { case SINE, TRIANGLE, NOISE }

    private static let scale = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28]

    private static func note(_ semitones: Int, _ base: Double = 523.25) -> Double { base * pow(2.0, Double(semitones) / 12.0) }

    /// The Kotlin recipe, sample for sample (mono).
    static func synthesize(_ effect: Effect) -> [Float] {
        switch effect {
        case .Shake:
            // A rattle: short bright clicks, like a die in a cupped hand.
            var out: [Float] = []
            for k in 0..<7 {
                out += tone(2400 + Double(k % 3) * 500, 0.018, .NOISE, 0.22, decay: 8.0)
                out += silence(0.028 + Double(k % 2) * 0.012)
            }
            return out
        case .Land:
            return mix(sweep(210.0, 120.0, 0.1, .SINE, 0.5, decay: 5.0), tone(3200.0, 0.015, .NOISE, 0.18, decay: 8.0))
                + silence(0.05) + mix(sweep(190.0, 130.0, 0.06, .SINE, 0.22, decay: 6.0), tone(3000.0, 0.01, .NOISE, 0.08, decay: 9.0))
        case .Six:
            return mix(tone(note(12, 784.0), 0.32, .SINE, 0.22, decay: 5.0), tone(note(19, 784.0), 0.26, .SINE, 0.12, decay: 6.0))
        case .Hop(let step):
            let f = note(scale[min(max(step, 0), scale.count - 1)], 659.25)
            return mix(tone(f, 0.09, .TRIANGLE, 0.2, decay: 7.0), tone(f * 2, 0.05, .SINE, 0.06, decay: 9.0))
        case .ComeOut:
            return mix(sweep(300.0, 900.0, 0.12, .SINE, 0.28, decay: 3.0), silence(0.02) + sweep(1200.0, 4200.0, 0.18, .NOISE, 0.06, decay: 2.5))
                + tone(note(12), 0.12, .SINE, 0.18, decay: 6.0)
        case .Safe:
            return tone(note(16, 784.0), 0.18, .SINE, 0.14, decay: 6.0)
        case .Capture:
            return mix(sweep(260.0, 90.0, 0.16, .SINE, 0.6, decay: 4.0), tone(2400.0, 0.02, .NOISE, 0.2, decay: 8.0))
                + sweep(1500.0, 300.0, 0.42, .SINE, 0.2, decay: 1.6)
        case .Home:
            return mix(
                mix(tone(note(0), 0.6, .SINE, 0.22, decay: 4.0), tone(note(4), 0.6, .SINE, 0.18, decay: 4.0)),
                mix(tone(note(7), 0.6, .SINE, 0.16, decay: 4.0), silence(0.05) + tone(note(12), 0.55, .SINE, 0.14, decay: 4.0))
            )
        case .Extra:
            return [0, 4, 7].map { tone(note($0, 1046.5), 0.05, .TRIANGLE, 0.16, decay: 6.0) }.reduce([], +)
        case .ThreeSixes:
            return mix(tone(110.0, 0.38, .TRIANGLE, 0.3, decay: 2.5), tone(116.5, 0.38, .TRIANGLE, 0.24, decay: 2.5))
        case .Turn:
            return tone(note(7, 659.25), 0.09, .SINE, 0.14, decay: 5.0) + tone(note(12, 659.25), 0.16, .SINE, 0.13, decay: 5.0)
        case .Win:
            let melody: [(Int, Double)] = [(0, 0.12), (4, 0.12), (7, 0.12), (12, 0.2), (7, 0.1), (12, 0.45)]
            return mix(
                melody.map { tone(note($0.0), $0.1, .TRIANGLE, 0.3) }.reduce([], +),
                silence(0.7) + mix(tone(note(0), 0.7, .SINE, 0.16), tone(note(7), 0.7, .SINE, 0.13))
            )
        case .Tap:
            return tone(1700.0, 0.025, .SINE, 0.12, decay: 6.0)
        }
    }

    private static func silence(_ duration: Double) -> [Float] { [Float](repeating: 0, count: max(0, Int(duration * RATE))) }

    private static func tone(_ frequency: Double, _ duration: Double, _ wave: Wave, _ volume: Float, decay: Double = 3.2) -> [Float] {
        sweep(frequency, frequency, duration, wave, volume, decay: decay)
    }

    /// Ludo's own sweep: low-passed noise and a 3 ms attack.
    private static func sweep(_ start: Double, _ end: Double, _ duration: Double, _ wave: Wave, _ volume: Float, decay: Double = 3.2) -> [Float] {
        let count = max(0, Int(duration * RATE))
        var phase = 0.0
        var seed: Int32 = 0x12345679
        var lowpass = 0.0
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / RATE
            let progress = Double(i) / Double(max(count - 1, 1))
            let frequency = start + (end - start) * progress
            phase += frequency / RATE
            let x = phase - phase.rounded(.down)
            let sample: Double
            switch wave {
            case .SINE:
                sample = sin(2 * Double.pi * x)
            case .TRIANGLE:
                sample = 4 * abs(x - 0.5) - 1
            case .NOISE:
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let white = Double(UInt32(bitPattern: seed)) / Double(UInt32.max) * 2 - 1
                lowpass += (white - lowpass) * min(1.0, max(0.02, frequency / RATE * 6))
                sample = lowpass * 1.6
            }
            out[i] = Float(sample * min(1.0, t / 0.003) * exp(-decay * progress)) * volume
        }
        return out
    }

    private static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: max(a.count, b.count))
        for i in a.indices { out[i] += a[i] }
        for i in b.indices { out[i] += b[i] }
        return out
    }
}
