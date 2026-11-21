// DualDS — how FoldPlay shares audio with other apps (music apps keep playing by default).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import AVFoundation

enum AudioSessionPolicy {
    /// UserDefaults key: let Spotify, Apple Music, YouTube Music and others keep playing during games.
    static let mixKey = "audio.mixWithOthers"

    static var mixWithOthers: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: mixKey) == nil ? true : defaults.bool(forKey: mixKey)
    }

    /// Library and menus: never interrupts other apps' audio and follows the silent switch.
    static func applyInterface() throws {
        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
    }

    /// In a game: plays even with the silent switch on. Mixes with other apps' audio unless the
    /// user turned that off, in which case other audio pauses as it did before.
    static func applyGame(mixWithOthers: Bool) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                        options: mixWithOthers ? [.mixWithOthers] : [])
    }
}
