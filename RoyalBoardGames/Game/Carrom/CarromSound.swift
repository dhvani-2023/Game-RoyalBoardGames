import Foundation

/// Carrom's sound effects, synthesized in code at first use (no audio files).
/// Follows the app's sound setting through [AudioMixer].
enum CarromSound {
    enum Effect: Hashable {
        /// Coin on coin; [level] 0–3 follows the strength of the hit.
        case Clack(Int)
        /// Striker on coin: deeper and fuller.
        case Strike(Int)
        case Frame(Int)
        case Pocket
        case Queen
        case Cover
        case Foul
        case Tick
        case Release
        case Turn
        case Toss
        case Rack
        case Pop
        case Win
        case Tap
        /// Builds while pulling back; [level] 0–5.
        case Charge(Int)
        /// Two or more in one stroke.
        case Combo(Int)
    }

    private static let bank = SoundBank<Effect> { e in
        var s = synthesize(e)
        for i in s.indices { s[i] = Swift.max(-1, Swift.min(1, s[i])) }
        return s
    }

    private static let lock = NSLock()
    private static var lastPlayed: [Effect: UInt64] = [:]
    private static var lastAny: UInt64 = 0
    private static var nextNode = 0

    /// The reference's engine ran at 0.6 against the party sounds' 0.5.
    private static let GAIN: Float = 1.15
    /// Eight round-robin voices, each cut by the next sound sent to it (like `.interrupts`).
    private static let NODES = 8
    private static let CHANNEL_BASE = 7_400

    static func play(_ effect: Effect, throttle: Double = 0.03) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        if let last = lastPlayed[effect], Double(now &- last) / 1e9 < throttle {
            lock.unlock()
            return
        }
        // Hits closer than 15 ms merge, so a break doesn't turn into noise.
        if case .Clack = effect, Double(now &- lastAny) / 1e9 < 0.015 {
            lock.unlock()
            return
        }
        lastPlayed[effect] = now
        lastAny = now
        let channel = CHANNEL_BASE + nextNode
        nextNode = (nextNode + 1) % NODES
        lock.unlock()
        AudioMixer.play(bank.buffer(effect), gain: GAIN, channel: channel)
    }

    static func warmUp() {
        var effects: [Effect] = [.Pocket, .Release, .Tick, .Turn, .Queen, .Foul]
        for level in 0..<4 {
            effects.append(.Clack(level))
            effects.append(.Strike(level))
        }
        bank.warmUp(effects)
    }

    // MARK: Synthesis

    private enum Wave { case SINE, TRIANGLE, NOISE }

    private static let RATE = Double(AudioMixer.SAMPLE_RATE)

    private static func note(_ semitones: Int, _ base: Double = 523.25) -> Double { base * Foundation.pow(2.0, Double(semitones) / 12.0) }

    /// Exposed for tests: the raw synthesized buffer of an effect.
    static func samples(_ effect: Effect) -> [Float] { bank.buffer(effect) }

    private static func synthesize(_ effect: Effect) -> [Float] {
        switch effect {
        case .Clack(let l):
            // Hard wood on wood: a bright click and a short hollow knock.
            let v = Float(0.12 + 0.1 * Double(l))
            return mix(tone(3400 - Double(l) * 300.0, 0.012, .NOISE, v * 0.9, 9.0), tone(1250 + Double(l) * 60.0, 0.045, .SINE, v, 9.0))
        case .Strike(let level):
            let v = Float(0.16 + 0.11 * Double(level))
            return mix(mix(tone(2600.0, 0.014, .NOISE, v * 0.8, 9.0), tone(760.0, 0.07, .SINE, v, 7.0)),
                       tone(380.0, 0.06, .TRIANGLE, v * 0.35, 7.0))
        case .Frame(let level):
            let v = Float(0.14 + 0.1 * Double(level))
            return mix(sweep(170.0, 105.0, 0.11, .SINE, v, 5.0), tone(900.0, 0.02, .NOISE, v * 0.4, 8.0))
        case .Pocket:
            // A hollow wooden drop, then a soft net rustle.
            return mix(mix(sweep(420.0, 170.0, 0.12, .SINE, 0.42, 4.0), tone(1800.0, 0.015, .NOISE, 0.14, 8.0)),
                       silence(0.07) + tone(700.0, 0.22, .NOISE, 0.07, 3.0))
        case .Queen:
            return mix(tone(note(19, 784.0), 0.5, .SINE, 0.2, 4.0), tone(note(24, 784.0), 0.42, .SINE, 0.12, 5.0))
        case .Cover:
            let notes: [(Int, Double)] = [(0, 0.1), (4, 0.1), (7, 0.1), (12, 0.38)]
            return mix(concat(notes.map { tone(note($0.0, 784.0), $0.1, .TRIANGLE, 0.22, 4.0) }),
                       silence(0.3) + tone(note(24, 784.0), 0.4, .SINE, 0.08, 4.0))
        case .Foul:
            return mix(tone(110.0, 0.36, .TRIANGLE, 0.3, 2.6), tone(116.5, 0.36, .TRIANGLE, 0.24, 2.6))
        case .Tick:
            return tone(2600.0, 0.012, .SINE, 0.08, 8.0)
        case .Release:
            return mix(sweep(2200.0, 6000.0, 0.05, .NOISE, 0.1, 4.0), tone(1500.0, 0.02, .SINE, 0.08, 9.0))
        case .Charge(let level):
            return tone(note(level * 2, 392.0), 0.06, .SINE, 0.05 + Float(level) * 0.012, 5.0)
        case .Combo(let count):
            let steps = [0, 4, 7, 12, 16, 19]
            return concat((0..<(Swift.min(Swift.max(count, 2), 5) + 1)).map { tone(note(steps[$0], 1046.5), 0.05, .TRIANGLE, 0.15, 6.0) })
        case .Turn:
            return tone(note(7, 659.25), 0.09, .SINE, 0.13, 5.0) + tone(note(12, 659.25), 0.16, .SINE, 0.12, 5.0)
        case .Toss:
            return concat((0..<10).map { tone(note($0 % 2 == 0 ? 12 : 16, 1046.5), 0.045, .SINE, 0.07, 6.0) })
        case .Rack:
            return concat((0..<6).map { tone(1500 + Double($0 % 3) * 180.0, 0.03, .SINE, 0.06, 8.0) + silence(0.02) })
        case .Pop:
            return sweep(500.0, 1100.0, 0.07, .SINE, 0.16, 5.0)
        case .Win:
            let melody: [(Int, Double)] = [(0, 0.12), (4, 0.12), (7, 0.12), (12, 0.2), (7, 0.1), (12, 0.45)]
            return mix(concat(melody.map { tone(note($0.0), $0.1, .TRIANGLE, 0.3) }),
                       silence(0.7) + mix(tone(note(0), 0.7, .SINE, 0.16), tone(note(7), 0.7, .SINE, 0.13)))
        case .Tap:
            return tone(1700.0, 0.025, .SINE, 0.12, 6.0)
        }
    }

    private static func silence(_ duration: Double) -> [Float] { [Float](repeating: 0, count: Swift.max(0, Int(duration * RATE))) }

    private static func tone(_ frequency: Double, _ duration: Double, _ wave: Wave, _ volume: Float, _ decay: Double = 3.2) -> [Float] {
        sweep(frequency, frequency, duration, wave, volume, decay)
    }

    /// Carrom's own sweep: noise runs through a one-pole low-pass that follows the frequency, 2 ms attack.
    private static func sweep(_ start: Double, _ end: Double, _ duration: Double, _ wave: Wave, _ volume: Float, _ decay: Double = 3.2) -> [Float] {
        let count = Swift.max(0, Int(duration * RATE))
        var phase = 0.0
        var seed: UInt32 = 0x1234_5679
        var lowpass = 0.0
        var out = [Float](repeating: 0, count: count)
        let denom = Double(Swift.max(count - 1, 1))
        for i in 0..<count {
            let t = Double(i) / RATE
            let progress = Double(i) / denom
            let frequency = start + (end - start) * progress
            phase += frequency / RATE
            let x = phase - phase.rounded(.down)
            let sample: Double
            switch wave {
            case .SINE:
                sample = Foundation.sin(2 * Double.pi * x)
            case .TRIANGLE:
                sample = 4 * Swift.abs(x - 0.5) - 1
            case .NOISE:
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let white = Double(seed) / Double(UInt32.max) * 2 - 1
                lowpass += (white - lowpass) * Swift.min(1.0, Swift.max(0.02, frequency / RATE * 6))
                sample = lowpass * 1.6
            }
            out[i] = Float(sample * Swift.min(1.0, t / 0.002) * Foundation.exp(-decay * progress)) * volume
        }
        return out
    }

    private static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: Swift.max(a.count, b.count))
        for i in a.indices { out[i] += a[i] }
        for i in b.indices { out[i] += b[i] }
        return out
    }

    private static func concat(_ parts: [[Float]]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(parts.reduce(0) { $0 + $1.count })
        for p in parts { out.append(contentsOf: p) }
        return out
    }
}
