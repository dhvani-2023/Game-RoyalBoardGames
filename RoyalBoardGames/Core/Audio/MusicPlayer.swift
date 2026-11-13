import Foundation
import GameKit

/// A soft synthesized lounge loop (warm pads, plucked bass and a light brush pattern).
/// Rendered once (off the main thread) and looped gap-free by GameKit's music decks while Music is on
/// and the app is visible.
enum MusicPlayer {
    private static let TRACK = "lounge"
    private static let player = GameKit.MusicPlayer()
    private static var visible = false
    private static var rendered = false
    private static var rendering = false

    /// True while the loop should be audible (the SFX mixer keeps the engine awake then).
    static var isActive: Bool { visible && AppSettings.data.musicEnabled }

    static func onForeground() { visible = true; sync() }
    static func onBackground() { visible = false; sync() }

    static func sync() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { sync() }
            return
        }
        let wanted = visible && AppSettings.data.musicEnabled
        player.volume = 0.32 * AppSettings.data.volume
        if wanted { start() } else { player.play(nil, fade: 0.12) }
    }

    private static func start() {
        if !rendered {
            if rendering { return }
            rendering = true
            DispatchQueue.global(qos: .userInitiated).async {
                let samples = render()
                DispatchQueue.main.async {
                    player.register(TRACK, samples: samples)
                    rendered = true
                    rendering = false
                    sync()
                }
            }
            return
        }
        AudioMixer.start()
        if !AudioSystem.shared.engine.isRunning { AudioSystem.shared.resume() }
        player.play(TRACK, fade: 0.12)
    }

    /// Four bars of Fmaj7 – Em7 – Dm7 – Cmaj7 at 84 bpm.
    private static func render() -> [Float] {
        let rate = Double(AudioMixer.SAMPLE_RATE)
        let beat = 60.0 / 84.0
        let bars = 4
        let total = Int(Double(bars * 4) * beat * rate)
        var out = [Float](repeating: 0, count: total)
        let chords: [[Double]] = [
            [174.61, 220.0, 261.63, 329.63],
            [164.81, 196.0, 246.94, 293.66],
            [146.83, 174.61, 220.0, 261.63],
            [130.81, 164.81, 196.0, 246.94],
        ]
        let bass = [87.31, 82.41, 73.42, 65.41]
        let twoPi = 2 * Double.pi
        for bar in 0..<bars {
            let start = Int(Double(bar * 4) * beat * rate)
            let len = Int(4 * beat * rate)
            for i in 0..<len {
                let t = Double(i) / rate
                let env = min(1.0, t / 0.5) * min(1.0, Double(len - i) / rate / 0.4)
                var s = 0.0
                for f in chords[bar] { s += sin(twoPi * f * t) * 0.6 + sin(twoPi * f * 2.003 * t) * 0.12 }
                if start + i < total { out[start + i] += Float(s * 0.055 * env) }
            }
            for b in 0..<4 {
                let bs = start + Int(Double(b) * beat * rate)
                let f = b == 2 ? bass[bar] * 1.5 : bass[bar]
                let n = Int(beat * rate * 0.9)
                for i in 0..<n {
                    let t = Double(i) / rate
                    if bs + i < total { out[bs + i] += Float(sin(twoPi * f * t) * exp(-t * 4.0) * 0.22) }
                }
                var seed = Int32(12345 + b * 77 + bar * 911)
                let hs = bs + Int(beat * rate * 0.5)
                let hn = Int(0.06 * rate)
                var lp = 0.0
                for i in 0..<hn {
                    seed = seed &* 1_103_515_245 &+ 12345
                    let white = Double((UInt32(bitPattern: seed) >> 8) & 0xFFFF) / 32768.0 - 1
                    lp += (white - lp) * 0.6
                    if hs + i < total { out[hs + i] += Float((white - lp) * exp(-Double(i) / rate * 60) * 0.05) }
                }
            }
        }
        return out
    }
}
