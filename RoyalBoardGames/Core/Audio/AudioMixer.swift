import Foundation
import AVFoundation
import os
import GameKit

/// Low-latency software mixer: one `AVAudioSourceNode` on GameKit's shared engine with up to 32 overlapping voices
/// (a pool break can fire dozens of clicks at once), summed in float and passed through a tanh soft limiter.
/// Every game sound is synthesized into a `[Float]` at 48 kHz mono and handed to `play`.
/// All entry points are thread-safe; the render callback never allocates or frees.
enum AudioMixer {
    static let SAMPLE_RATE = 48_000
    fileprivate static let MAX_VOICES = 32
    fileprivate static let GRAVE = 128

    fileprivate static let core = MixerCore()

    /// Master gain for effects (music has its own path).
    static var masterGain: Float {
        get { core.masterGain }
        set { core.setMaster(newValue) }
    }

    /// Queue a sound. `channel` > 0 makes it exclusive: a new sound on the same channel cuts the previous one
    /// (like the reference's `.interrupts` player nodes).
    static func play(_ samples: [Float], gain: Float = 1, channel: Int = 0) {
        if !core.soundEnabled || samples.isEmpty { return }
        start()
        core.enqueue(samples, gain, channel)
        if !AudioSystem.shared.engine.isRunning { AudioSystem.shared.resume() }
        scheduleIdleCheck()
    }

    /// Positional form of `play` (Kotlin `AudioMixer.play(buffer, GAIN, channel)`).
    static func play(_ samples: [Float], _ gain: Float, _ channel: Int = 0) {
        play(samples, gain: gain, channel: channel)
    }

    static func stopAll() { core.clear() }

    /// Kept in sync by `AppSettings` (sound on/off and the shared volume slider).
    static func setOutput(enabled: Bool, volume: Float) { core.setOutput(enabled: enabled, volume: volume) }

    private static let startLock = NSLock()
    private static var started = false

    /// Attaches the mixer node to GameKit's engine and starts it. Called at launch; safe to call again.
    static func start() {
        startLock.lock()
        defer { startLock.unlock() }
        if started { return }
        started = true
        let system = AudioSystem.shared
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(SAMPLE_RATE), channels: 1)!
        let node = core.makeNode(format: format)
        system.engine.attach(node)
        system.engine.connect(node, to: system.sfxMixer, format: format)
        system.start()
    }

    // MARK: Idle pause (Android pauses its AudioTrack after 3 s of silence)

    private static let idleLock = NSLock()
    private static var idleScheduled = false

    private static func scheduleIdleCheck() {
        idleLock.lock()
        defer { idleLock.unlock() }
        if idleScheduled { return }
        idleScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { idleCheck() }
    }

    private static func idleCheck() {
        idleLock.lock()
        idleScheduled = false
        idleLock.unlock()
        core.drain()
        if core.isBusy { scheduleIdleCheck(); return }
        if MusicPlayer.isActive { return }
        if AudioSystem.shared.engine.isRunning { AudioSystem.shared.suspend() }
    }
}

/// The mixer state. Voices live in fixed, preallocated memory guarded by an unfair lock that the render
/// thread holds only while summing one block.
private final class MixerCore: @unchecked Sendable {
    struct Voice {
        var ptr: UnsafeMutablePointer<Float>
        var count: Int
        var position: Int
        var gain: Float
        var channel: Int
    }

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let voices: UnsafeMutablePointer<Voice>
    private var voiceCount = 0
    /// Buffers finished on the render thread, freed later on a normal thread.
    private let grave: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    private var graveCount = 0

    private(set) var masterGain: Float = 0.9
    private var outputGain: Float = 0.9 * 0.8
    private(set) var soundEnabled = true
    private var volume: Float = 0.8

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        voices = .allocate(capacity: AudioMixer.MAX_VOICES)
        grave = .allocate(capacity: AudioMixer.GRAVE)
        grave.initialize(repeating: nil, count: AudioMixer.GRAVE)
    }

    var isBusy: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return voiceCount > 0
    }

    func setMaster(_ g: Float) {
        os_unfair_lock_lock(lock)
        masterGain = g
        outputGain = masterGain * volume
        os_unfair_lock_unlock(lock)
    }

    func setOutput(enabled: Bool, volume v: Float) {
        os_unfair_lock_lock(lock)
        soundEnabled = enabled
        volume = v
        outputGain = masterGain * volume
        os_unfair_lock_unlock(lock)
    }

    func enqueue(_ samples: [Float], _ gain: Float, _ channel: Int) {
        let copy = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        samples.withUnsafeBufferPointer { copy.initialize(from: $0.baseAddress!, count: samples.count) }
        var freeList: [UnsafeMutablePointer<Float>] = []
        os_unfair_lock_lock(lock)
        if channel > 0 {
            var w = 0
            for r in 0..<voiceCount {
                if voices[r].channel == channel { freeList.append(voices[r].ptr) } else { voices[w] = voices[r]; w += 1 }
            }
            voiceCount = w
        }
        if voiceCount >= AudioMixer.MAX_VOICES {
            freeList.append(voices[0].ptr)
            for i in 1..<voiceCount { voices[i - 1] = voices[i] }
            voiceCount -= 1
        }
        (voices + voiceCount).initialize(to: Voice(ptr: copy, count: samples.count, position: 0, gain: gain, channel: channel))
        voiceCount += 1
        for i in 0..<graveCount { if let p = grave[i] { freeList.append(p); grave[i] = nil } }
        graveCount = 0
        os_unfair_lock_unlock(lock)
        for p in freeList { p.deallocate() }
    }

    func clear() {
        var freeList: [UnsafeMutablePointer<Float>] = []
        os_unfair_lock_lock(lock)
        for i in 0..<voiceCount { freeList.append(voices[i].ptr) }
        voiceCount = 0
        for i in 0..<graveCount { if let p = grave[i] { freeList.append(p); grave[i] = nil } }
        graveCount = 0
        os_unfair_lock_unlock(lock)
        for p in freeList { p.deallocate() }
    }

    /// Frees buffers of finished voices.
    func drain() {
        var freeList: [UnsafeMutablePointer<Float>] = []
        os_unfair_lock_lock(lock)
        for i in 0..<graveCount { if let p = grave[i] { freeList.append(p); grave[i] = nil } }
        graveCount = 0
        os_unfair_lock_unlock(lock)
        for p in freeList { p.deallocate() }
    }

    func makeNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [unowned self] isSilence, _, frameCount, bufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = Int(frameCount)
            guard let first = abl.first, let raw = first.mData else { return noErr }
            let out = raw.assumingMemoryBound(to: Float.self)
            out.update(repeating: 0, count: frames)
            var any = false
            var g: Float = 0
            os_unfair_lock_lock(self.lock)
            g = self.outputGain
            var w = 0
            for r in 0..<self.voiceCount {
                var v = self.voices[r]
                let n = min(frames, v.count - v.position)
                if n > 0 {
                    let src = v.ptr + v.position
                    let gain = v.gain
                    for i in 0..<n { out[i] += src[i] * gain }
                    v.position += n
                    any = true
                }
                if v.position >= v.count {
                    if self.graveCount < AudioMixer.GRAVE {
                        self.grave[self.graveCount] = v.ptr
                        self.graveCount += 1
                        continue
                    }
                    // Grave full (no play() for a long time): keep the finished voice parked silently.
                    v.position = v.count
                }
                self.voices[w] = v
                w += 1
            }
            self.voiceCount = w
            os_unfair_lock_unlock(self.lock)
            if !any {
                isSilence.pointee = true
                return noErr
            }
            // Soft limiter: overlapping hits never clip harshly.
            let k = g * 1.15
            for i in 0..<frames { out[i] = tanhf(out[i] * k) }
            // Copy to any further channel buffers (format is mono, but be safe).
            if abl.count > 1 {
                for b in 1..<abl.count {
                    if let d = abl[b].mData { d.copyMemory(from: raw, byteCount: frames * MemoryLayout<Float>.size) }
                }
            }
            return noErr
        }
    }
}
