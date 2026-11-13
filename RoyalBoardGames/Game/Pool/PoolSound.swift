import Foundation

/// Pool's sound effects, synthesized in code at first use (no audio files). Follows the Sound setting.
/// Rendered at the app mixer's rate (48 kHz); every recipe is time-based, so it sounds as on Android (44.1 kHz).
enum PoolSound {
    enum Kind: Hashable { case Click, Cue, BreakShot, Cushion, Pocket, Jaw, Chute, Stack, Chalk, Tick, Place, Call, Foul, Turn, Toss, Rack, RackWon, Win, Tap }

    /// [level] is used by Click (0–3, the strength of the hit), Cue (0–3, power) and Cushion (0–2).
    struct Effect: Hashable {
        let kind: Kind
        var level: Int = 0

        init(_ kind: Kind, _ level: Int = 0) {
            self.kind = kind
            self.level = level
        }
    }

    static func click(_ level: Int) -> Effect { Effect(.Click, level) }
    static func cue(_ level: Int) -> Effect { Effect(.Cue, level) }
    static func cushion(_ level: Int) -> Effect { Effect(.Cushion, level) }
    static let breakShot = Effect(.BreakShot)
    static let pocket = Effect(.Pocket)
    static let jaw = Effect(.Jaw)
    static let chute = Effect(.Chute)
    static let stack = Effect(.Stack)
    static let chalk = Effect(.Chalk)
    static let tick = Effect(.Tick)
    static let place = Effect(.Place)
    static let call = Effect(.Call)
    static let foul = Effect(.Foul)
    static let turn = Effect(.Turn)
    static let toss = Effect(.Toss)
    static let rack = Effect(.Rack)
    static let rackWon = Effect(.RackWon)
    static let win = Effect(.Win)
    static let tap = Effect(.Tap)

    private static let SAMPLE_RATE = Double(AudioMixer.SAMPLE_RATE)
    /// The reference mixes through eight player nodes, each new sound interrupting the oldest.
    private static let VOICES = 8
    private static let CHANNEL_BASE = 401
    /// The reference's mixer output volume (0.6), relative to the app mixer's own master gain.
    private static let GAIN: Float = 0.67

    private static let bank = SoundBank<Effect> { synthesize($0) }
    private static let lock = NSLock()
    private static var lastPlayed: [Effect: UInt64] = [:]
    private static var lastClick: UInt64 = 0
    private static var nextNode = 0

    static func play(_ effect: Effect, _ throttle: Double = 0.03) {
        if !AppSettings.soundEnabled { return }
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        if let last = lastPlayed[effect], Double(now &- last) / 1e9 < throttle {
            lock.unlock()
            return
        }
        // Hits closer than 12 ms merge, so a break stays a crack and a patter, not noise.
        if effect.kind == .Click {
            if lastClick != 0 && Double(now &- lastClick) / 1e9 < 0.012 {
                lock.unlock()
                return
            }
            lastClick = now
        }
        lastPlayed[effect] = now
        let channel = CHANNEL_BASE + nextNode
        nextNode = (nextNode + 1) % VOICES
        lock.unlock()
        AudioMixer.play(bank.buffer(effect), GAIN, channel)
    }

    static func warmUp() {
        var effects = [pocket, breakShot, tick, turn, chute, stack, foul, jaw]
        for level in 0..<4 { effects.append(click(level)); effects.append(cue(level)) }
        for level in 0..<3 { effects.append(cushion(level)) }
        bank.warmUp(effects)
    }

    // MARK: Synthesis

    private enum Wave { case Sine, Triangle, Noise }

    private static func note(_ semitones: Int, _ base: Double = 523.25) -> Double { base * pow(2.0, Double(semitones) / 12.0) }

    private static func synthesize(_ effect: Effect) -> [Float] {
        var out = render(effect)
        for i in out.indices { out[i] = max(-1, min(1, out[i])) }
        return out
    }

    private static func render(_ effect: Effect) -> [Float] {
        let level = effect.level
        switch effect.kind {
        case .Click:
            // Resin on resin: a bright, glassy click with a ring above it.
            let v = Float(0.1 + 0.09 * Double(level))
            return mix(mix(tone(7200.0, 0.008, .Noise, v, 10.0), tone(3100.0 + Double(level * 180), 0.03, .Sine, v * 0.9, 12.0)),
                       tone(5400.0, 0.02, .Sine, v * 0.35, 12.0))
        case .Cue:
            // Leather tip on the cue ball: a firm, short thock.
            let v = Float(0.14 + 0.09 * Double(level))
            return mix(mix(tone(2400.0, 0.012, .Noise, v * 0.7, 9.0), tone(520.0, 0.05, .Sine, v, 8.0)),
                       tone(1600.0, 0.025, .Sine, v * 0.4, 10.0))
        case .BreakShot:
            // A sharp crack, then the rack scattering.
            var pattern = mix(tone(6500.0, 0.03, .Noise, 0.55, 7.0), tone(950.0, 0.06, .Sine, 0.35, 8.0))
            for i in 0..<7 {
                pattern = mix(pattern, silence(0.03 + Double(i) * 0.035) + tone(2900.0 + Double((i % 3) * 300), 0.02, .Sine, 0.2 - Float(i) * 0.02, 12.0))
            }
            return pattern
        case .Cushion:
            let v = Float(0.12 + 0.08 * Double(level))
            return mix(sweep(150.0, 95.0, 0.09, .Sine, v, 5.0), tone(600.0, 0.02, .Noise, v * 0.3, 8.0))
        case .Pocket:
            // A hollow drop into the pocket.
            return mix(mix(sweep(360.0, 140.0, 0.14, .Sine, 0.4, 4.0), tone(1500.0, 0.012, .Noise, 0.14, 8.0)),
                       silence(0.05) + tone(240.0, 0.12, .Triangle, 0.1, 5.0))
        case .Jaw:
            return join((0..<3).map { tone(2200.0 - Double($0 * 300), 0.018, .Sine, 0.13, 9.0) + silence(0.025) })
        case .Chute:
            // Rolling down the return: a low rumble that fades in and out.
            let count = Int(0.55 * SAMPLE_RATE)
            let rumble = tone(180.0, 0.55, .Noise, 0.16, 0.5)
            return (0..<count).map { i in rumble[i] * Float(sin(Double(i) / Double(count) * Double.pi)) }
        case .Stack:
            return mix(tone(2700.0, 0.025, .Sine, 0.14, 10.0), tone(5200.0, 0.01, .Noise, 0.06, 10.0))
        case .Chalk:
            return sweep(2600.0, 4200.0, 0.08, .Noise, 0.06, 3.0)
        case .Tick:
            return tone(2800.0, 0.01, .Sine, 0.07, 8.0)
        case .Place:
            return tone(1900.0, 0.03, .Sine, 0.1, 8.0)
        case .Call:
            return tone(note(12, 880.0), 0.12, .Sine, 0.13, 5.0) + tone(note(19, 880.0), 0.2, .Sine, 0.1, 5.0)
        case .Foul:
            return mix(tone(110.0, 0.36, .Triangle, 0.3, 2.6), tone(116.5, 0.36, .Triangle, 0.24, 2.6))
        case .Turn:
            return tone(note(5, 659.25), 0.09, .Sine, 0.13, 5.0) + tone(note(12, 659.25), 0.16, .Sine, 0.12, 5.0)
        case .Toss:
            return join((0..<10).map { tone(note($0 % 2 == 0 ? 12 : 16, 1046.5), 0.045, .Sine, 0.07, 6.0) })
        case .Rack:
            return join((0..<8).map { tone(2600.0 + Double(($0 % 3) * 260), 0.02, .Sine, 0.06, 10.0) + silence(0.03) })
        case .RackWon:
            let notes: [(Int, Double)] = [(0, 0.1), (4, 0.1), (7, 0.1), (12, 0.38)]
            return mix(join(notes.map { tone(note($0.0, 784.0), $0.1, .Triangle, 0.22, 4.0) }),
                       silence(0.3) + tone(note(24, 784.0), 0.4, .Sine, 0.08, 4.0))
        case .Win:
            let melody: [(Int, Double)] = [(0, 0.12), (4, 0.12), (7, 0.12), (12, 0.2), (7, 0.1), (12, 0.45)]
            return mix(join(melody.map { tone(note($0.0), $0.1, .Triangle, 0.3) }),
                       silence(0.7) + mix(tone(note(0), 0.7, .Sine, 0.16), tone(note(7), 0.7, .Sine, 0.13)))
        case .Tap:
            return tone(1700.0, 0.025, .Sine, 0.12, 6.0)
        }
    }

    private static func silence(_ duration: Double) -> [Float] { [Float](repeating: 0, count: max(0, Int(duration * SAMPLE_RATE))) }

    private static func join(_ parts: [[Float]]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(parts.reduce(0) { $0 + $1.count })
        for p in parts { out.append(contentsOf: p) }
        return out
    }

    private static func tone(_ frequency: Double, _ duration: Double, _ wave: Wave, _ volume: Float, _ decay: Double = 3.2) -> [Float] {
        sweep(frequency, frequency, duration, wave, volume, decay)
    }

    /// This file's own sweep: low-passed noise and a 2 ms attack, unlike the shared synth.
    private static func sweep(_ start: Double, _ end: Double, _ duration: Double, _ wave: Wave, _ volume: Float, _ decay: Double = 3.2) -> [Float] {
        let count = max(0, Int(duration * SAMPLE_RATE))
        var phase = 0.0
        var seed: Int32 = 0x2468_ACE1
        var lowpass = 0.0
        var out = [Float](repeating: 0, count: count)
        let denom = Double(max(count - 1, 1))
        for i in 0..<count {
            let t = Double(i) / SAMPLE_RATE
            let progress = Double(i) / denom
            let frequency = start + (end - start) * progress
            phase += frequency / SAMPLE_RATE
            let x = phase - floor(phase)
            let sample: Double
            switch wave {
            case .Sine:
                sample = sin(2 * Double.pi * x)
            case .Triangle:
                sample = 4 * abs(x - 0.5) - 1
            case .Noise:
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let white = Double(UInt32(bitPattern: seed)) / Double(UInt32.max) * 2 - 1
                lowpass += (white - lowpass) * min(1.0, max(0.02, frequency / SAMPLE_RATE * 6))
                sample = lowpass * 1.6
            }
            out[i] = Float(sample * min(1.0, t / 0.002) * exp(-decay * progress)) * volume
        }
        return out
    }

    private static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        let count = max(a.count, b.count)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count { out[i] = (i < a.count ? a[i] : 0) + (i < b.count ? b[i] : 0) }
        return out
    }
}
