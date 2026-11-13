import Foundation

/// The reference app's tiny synthesizer, ported 1:1: every sound is generated in code, so there are no audio files.
/// Renders at `AudioMixer.SAMPLE_RATE` (48 kHz). Games with their own flavour (filtered noise, custom decay)
/// keep a private copy of `sweep` next to their sound bank, exactly like the Kotlin sources.
enum Synth {
    static let RATE = Double(AudioMixer.SAMPLE_RATE)

    enum Wave { case Sine, Triangle, Square, Noise }

    static func note(_ semitones: Int, _ base: Double = 523.25) -> Double { base * pow(2.0, Double(semitones) / 12.0) }

    static func silence(_ duration: Double) -> [Float] { [Float](repeating: 0, count: max(0, Int(duration * RATE))) }

    static func tone(_ frequency: Double, _ duration: Double, _ wave: Wave, _ volume: Float, decay: Double = 3.2) -> [Float] {
        sweep(frequency, frequency, duration, wave, volume, decay: decay)
    }

    /// A note gliding from `start` to `end` Hz with a short attack and exponential decay.
    static func sweep(
        _ start: Double,
        _ end: Double,
        _ duration: Double,
        _ wave: Wave,
        _ volume: Float,
        vibrato: Double = 0.0,
        decay: Double = 3.2,
        attack: Double = 0.004
    ) -> [Float] {
        let count = max(0, Int(duration * RATE))
        var phase = 0.0
        var seed = Int32(bitPattern: 0x9E37_79B9)
        var out = [Float](repeating: 0, count: count)
        let denom = Double(max(count - 1, 1))
        for i in 0..<count {
            let t = Double(i) / RATE
            let progress = Double(i) / denom
            var frequency = start + (end - start) * progress
            if vibrato > 0 { frequency *= 1 + 0.02 * sin(2 * Double.pi * vibrato * t) }
            phase += frequency / RATE
            let x = phase - floor(phase)
            let sample: Double
            switch wave {
            case .Sine: sample = sin(2 * Double.pi * x)
            case .Triangle: sample = 4 * abs(x - 0.5) - 1
            case .Square: sample = x < 0.5 ? 1.0 : -1.0
            case .Noise:
                seed = seed &* 1_664_525 &+ 1_013_904_223
                sample = (Double(UInt32(bitPattern: seed)) / Double(UInt32.max)) * 2 - 1
            }
            let env = min(1.0, t / attack) * exp(-decay * progress)
            out[i] = Float(sample * env) * volume
        }
        return out
    }

    static func mix(_ parts: [Float]...) -> [Float] { mix(parts) }

    static func mix(_ parts: [[Float]]) -> [Float] {
        let count = parts.map(\.count).max() ?? 0
        var out = [Float](repeating: 0, count: count)
        for p in parts { for i in p.indices { out[i] += p[i] } }
        return out
    }

    static func concat(_ parts: [Float]...) -> [Float] { concat(parts) }

    static func concat(_ parts: [[Float]]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(parts.reduce(0) { $0 + $1.count })
        for p in parts { out.append(contentsOf: p) }
        return out
    }

    /// Place `b` starting `offset` seconds into `a`.
    static func overlay(_ a: [Float], _ b: [Float], _ offset: Double) -> [Float] {
        let start = Int(offset * RATE)
        var out = [Float](repeating: 0, count: max(a.count, start + b.count))
        for i in a.indices { out[i] = a[i] }
        for i in b.indices { out[start + i] += b[i] }
        return out
    }
}

/// A cache of synthesized buffers keyed by effect, with per-effect throttling.
/// Every game's sound object (PoolSound, LudoSound…) wraps one of these:
///
///     private static let bank = SoundBank<Effect>(synthesize)
///     static func play(_ e: Effect) { bank.play(e, throttleSeconds: 0.03) }
final class SoundBank<E: Hashable>: @unchecked Sendable {
    private let synthesize: (E) -> [Float]
    private var buffers: [E: [Float]] = [:]
    private var lastPlayed: [E: UInt64] = [:]
    private let bufferLock = NSLock()
    private let playLock = NSLock()

    init(_ synthesize: @escaping (E) -> [Float]) {
        self.synthesize = synthesize
    }

    func buffer(_ effect: E) -> [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        if let b = buffers[effect] { return b }
        let b = synthesize(effect)
        buffers[effect] = b
        return b
    }

    /// Plays `effect` unless it already played within `throttleSeconds`.
    func play(_ effect: E, throttleSeconds: Double = 0.03, gain: Float = 1, channel: Int = 0) {
        let now = DispatchTime.now().uptimeNanoseconds
        playLock.lock()
        if let last = lastPlayed[effect], Double(now &- last) / 1e9 < throttleSeconds {
            playLock.unlock()
            return
        }
        lastPlayed[effect] = now
        playLock.unlock()
        AudioMixer.play(buffer(effect), gain: gain, channel: channel)
    }

    /// Positional form (Kotlin `bank.play(effect, throttle)`).
    func play(_ effect: E, _ throttleSeconds: Double, _ gain: Float = 1, _ channel: Int = 0) {
        play(effect, throttleSeconds: throttleSeconds, gain: gain, channel: channel)
    }

    /// Pre-renders buffers off the main thread so the first hit has no delay.
    func warmUp<C: Collection>(_ effects: C) where C.Element == E {
        let list = Array(effects)
        DispatchQueue.global(qos: .utility).async { for e in list { _ = self.buffer(e) } }
    }
}
