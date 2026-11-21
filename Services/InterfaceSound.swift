// DualDS — short interface sounds for the themes, synthesized in code (no audio files).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import AVFoundation
import Foundation

@MainActor
final class InterfaceSound {
    enum Voice: String, CaseIterable {
        case click, blip, zap, chime, toll, punch, rev
    }

    static let shared = InterfaceSound()
    /// UserDefaults key; on by default.
    static let enabledKey = "ui.sounds"

    private var players: [Voice: AVAudioPlayer] = [:]

    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey)
    }

    func play(_ voice: Voice) {
        guard isEnabled else { return }
        let player: AVAudioPlayer
        if let cached = players[voice] {
            player = cached
        } else {
            guard let made = try? AVAudioPlayer(data: Self.wav(for: voice)) else { return }
            made.volume = 0.5
            made.prepareToPlay()
            players[voice] = made
            player = made
        }
        player.currentTime = 0
        player.play()
    }

    // MARK: Synthesis

    nonisolated static let sampleRate = 44_100.0

    /// Mono Float samples in -1...1 for a voice.
    nonisolated static func samples(for voice: Voice) -> [Float] {
        switch voice {
        case .click: return tone(duration: 0.025, decay: 90) { t in sin(2 * .pi * 1_000 * t) }
        case .blip:  return tone(duration: 0.11, decay: 18) { t in square(t < 0.045 ? 660 : 990, t) * 0.55 }
        case .zap:   return tone(duration: 0.16, decay: 14) { t in sin(2 * .pi * (1_500 * t - 3_400 * t * t)) }
        case .chime: return tone(duration: 0.30, decay: 9) { t in 0.6 * sin(2 * .pi * 523.25 * t) + 0.4 * sin(2 * .pi * 783.99 * t) }
        case .toll:  return tone(duration: 0.45, decay: 6) { t in 0.7 * sin(2 * .pi * 196 * t) + 0.3 * sin(2 * .pi * 293.66 * t) }
        case .punch:
            var noise = SeededRandom(seed: 7)
            return tone(duration: 0.09, decay: 35) { t in
                0.6 * sin(2 * .pi * 120 * t) + 0.4 * (noise.unit() * 2 - 1)
            }
        case .rev:   return tone(duration: 0.14, decay: 10) { t in saw(110 + 380 * t, t) * 0.5 }
        }
    }

    nonisolated private static func tone(duration: Double, decay: Double, _ wave: (Double) -> Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let attack = min(1, t / 0.003)                      // 3 ms fade-in avoids a click
            out[i] = Float(max(-1, min(1, wave(t) * attack * exp(-decay * t))))
        }
        return out
    }

    nonisolated private static func square(_ f: Double, _ t: Double) -> Double { (t * f).truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1 }
    nonisolated private static func saw(_ f: Double, _ t: Double) -> Double { 2 * (t * f).truncatingRemainder(dividingBy: 1) - 1 }

    /// 16-bit mono PCM WAV file in memory.
    nonisolated static func wav(for voice: Voice) -> Data {
        let pcm = samples(for: voice).map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for s in pcm { append(s) }
        return data
    }
}
