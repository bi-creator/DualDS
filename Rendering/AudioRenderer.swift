// DualDS — plays the emulated DS audio through AVAudioEngine.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// The core's emulation thread fills a lock-free SPSC ring (DSSession, 48 kHz stereo s16). An
// AVAudioSourceNode pulls from that ring on the real-time audio thread: no allocation, no locks
// held across the copy, no main-thread work. Latency is capped by discarding excess buffered audio;
// underruns play silence. Both are counted for tests and diagnostics.

import AVFoundation
import os

/// State shared with the real-time render callback.
final class AudioPipe: @unchecked Sendable {
    struct Stats: Sendable { var fromCore = 0; var silent = 0; var discarded = 0 }

    let core: DSCore
    let maxLatencyFrames: Int
    private let scratch: UnsafeMutablePointer<Int16>
    private let scratchFrames = 4096
    private let stats = OSAllocatedUnfairLock(initialState: Stats())

    init(core: DSCore, maxLatency: TimeInterval) {
        self.core = core
        self.maxLatencyFrames = Int(core.audioSampleRate * maxLatency)
        scratch = .allocate(capacity: scratchFrames * 2)
    }

    deinit { scratch.deallocate() }

    var snapshot: Stats { stats.withLock { $0 } }

    /// Real-time thread. Fills `frames` float frames into two non-interleaved channel buffers.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        var discarded = 0
        let excess = core.audioFramesAvailable - maxLatencyFrames - frames
        if excess > 0 {
            var remaining = excess
            while remaining > 0 {
                let n = core.readAudio(into: scratch, frames: min(remaining, scratchFrames))
                if n <= 0 { break }
                remaining -= n
                discarded += n
            }
        }
        var written = 0
        while written < frames {
            let want = min(frames - written, scratchFrames)
            let got = core.readAudio(into: scratch, frames: want)
            for i in 0..<got {
                left[written + i] = Float(scratch[i * 2]) / 32768
                right[written + i] = Float(scratch[i * 2 + 1]) / 32768
            }
            written += got
            if got < want { break }
        }
        for i in written..<frames { left[i] = 0; right[i] = 0 }
        let delta = Stats(fromCore: written, silent: frames - written, discarded: discarded)
        stats.withLock {
            $0.fromCore += delta.fromCore
            $0.silent += delta.silent
            $0.discarded += delta.discarded
        }
    }
}

@MainActor
final class AudioRenderer {
    private let engine = AVAudioEngine()
    private let pipe: AudioPipe
    private var source: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false
    private var wantsToRun = false

    var stats: AudioPipe.Stats { pipe.snapshot }

    var volume: Float = 1 { didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : volume } }
    var isMuted = false { didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : volume } }

    init(core: DSCore, maxLatency: TimeInterval = 0.12) {
        pipe = AudioPipe(core: core, maxLatency: maxLatency)
    }

    /// Starts audio output. Throws if the audio session or engine cannot start; the emulator keeps
    /// running silently in that case (the caller reports it).
    /// - Parameter mixWithOthers: keep other apps' music playing under the game sound.
    func start(mixWithOthers: Bool = AudioSessionPolicy.mixWithOthers) async throws {
        wantsToRun = true
        // Activating the session can block, so it happens off the main thread.
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try AudioSessionPolicy.applyGame(mixWithOthers: mixWithOthers)
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        }.value

        if source == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: pipe.core.audioSampleRate, channels: 2)!
            let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(pipe))
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
            observe()
        }
        engine.mainMixerNode.outputVolume = isMuted ? 0 : volume
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func pause() {
        wantsToRun = false
        engine.pause()
        isRunning = false
    }

    func resume() {
        wantsToRun = true
        restartIfWanted()
    }

    func stop() {
        wantsToRun = false
        engine.stop()
        isRunning = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try? AudioSessionPolicy.applyInterface()   // back to library sounds that never interrupt music
        }
    }

    private func restartIfWanted() {
        guard wantsToRun, !engine.isRunning else { return }
        Task { @MainActor [weak self] in
            _ = try? await Task.detached(priority: .userInitiated) { try AVAudioSession.sharedInstance().setActive(true) }.value
            guard let self, self.wantsToRun, !self.engine.isRunning else { return }
            self.engine.prepare()
            self.isRunning = (try? self.engine.start()) != nil
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        // Phone calls, Siri, alarms: the system stops us; restart when the interruption ends.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
            MainActor.assumeIsolated { if ended { self?.restartIfWanted() } else { self?.isRunning = false } }
        })
        // Headphones / Bluetooth connect or disconnect, sample-rate changes: the engine stops itself.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartIfWanted() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartIfWanted() }
        })
    }

    /// Built outside the main actor: the render block runs on the real-time audio thread.
    nonisolated private static func renderBlock(_ pipe: AudioPipe) -> AVAudioSourceNodeRenderBlock {
        { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            pipe.render(left: l, right: r, frames: Int(frameCount))
            return noErr
        }
    }
}
