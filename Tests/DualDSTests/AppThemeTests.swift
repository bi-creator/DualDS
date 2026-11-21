// DualDS — unit tests for themes, interface sounds and the audio-sharing policy.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI
import UIKit
import XCTest
@testable import DualDS

final class AppThemeTests: XCTestCase {
    func testTenEraThemesPlusClassic() {
        XCTAssertEqual(AppTheme.eraThemes.count, 10)
        XCTAssertEqual(AppTheme.allCases.first, .classic)
        XCTAssertEqual(Set(AppTheme.allCases.map(\.rawValue)).count, AppTheme.allCases.count)
    }

    func testEveryEraThemeHasACompleteLook() {
        for theme in AppTheme.eraThemes {
            XCTAssertNotNil(theme.palette, "\(theme) needs controller colours")
            XCTAssertEqual(theme.backgroundColors.count, 2, "\(theme) needs a backdrop gradient")
            XCTAssertNotNil(theme.colorScheme, "\(theme) must pin light or dark so text stays readable")
            XCTAssertFalse(theme.era.isEmpty)
        }
        XCTAssertNil(AppTheme.classic.palette, "Classic keeps the controller style's own colours")
    }

    /// Button letters must stay readable: WCAG contrast of at least 3:1 against the button fill.
    func testButtonLabelsAreReadable() {
        for theme in AppTheme.eraThemes {
            guard let p = theme.palette else { continue }
            XCTAssertGreaterThanOrEqual(Self.contrast(p.label, p.button), 3, "\(theme): label on button")
            XCTAssertGreaterThanOrEqual(Self.contrast(p.chrome, p.shell), 3, "\(theme): toolbar icons on shell")
            for (button, tint) in p.faceTints {
                if p.tintLabelsOnly {
                    XCTAssertGreaterThanOrEqual(Self.contrast(tint, p.button), 3, "\(theme): \(button) letter")
                } else {
                    XCTAssertGreaterThanOrEqual(Self.contrast(p.label, tint), 3, "\(theme): label on \(button)")
                }
            }
        }
    }

    func testSavedThemeIsReadBack() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppTheme.storageKey)
        defer { defaults.set(previous, forKey: AppTheme.storageKey) }
        defaults.set(AppTheme.fogTown.rawValue, forKey: AppTheme.storageKey)
        XCTAssertEqual(AppTheme.current, .fogTown)
        defaults.set("not a theme", forKey: AppTheme.storageKey)
        XCTAssertEqual(AppTheme.current, .classic)
    }

    func testBackdropRandomIsDeterministic() {
        var a = SeededRandom(seed: AppTheme.neonMaze.seed), b = SeededRandom(seed: AppTheme.neonMaze.seed)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        XCTAssertNotEqual(AppTheme.neonMaze.seed, AppTheme.fogTown.seed)
    }

    func testEveryVoiceSynthesizesAValidWAV() {
        for voice in InterfaceSound.Voice.allCases {
            let samples = InterfaceSound.samples(for: voice)
            XCTAssertGreaterThan(samples.count, 500, "\(voice) too short")
            XCTAssertLessThan(samples.count, Int(InterfaceSound.sampleRate * 0.6), "\(voice) too long for a tap sound")
            XCTAssertTrue(samples.allSatisfy { $0 >= -1 && $0 <= 1 })
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.05, "\(voice) is silent")
            let wav = InterfaceSound.wav(for: voice)
            XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(wav.count, 44 + samples.count * 2)
        }
    }

    func testOtherMusicKeepsPlayingByDefault() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AudioSessionPolicy.mixKey)
        defer { defaults.set(previous, forKey: AudioSessionPolicy.mixKey) }
        defaults.removeObject(forKey: AudioSessionPolicy.mixKey)
        XCTAssertTrue(AudioSessionPolicy.mixWithOthers)
        defaults.set(false, forKey: AudioSessionPolicy.mixKey)
        XCTAssertFalse(AudioSessionPolicy.mixWithOthers)
    }

    func testStarterListHasTheEightRequestedSongs() {
        XCTAssertEqual(SoundtrackPlayer.starterList.count, 8)
    }

    // MARK: Helpers

    private static func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double { c <= 0.03928 ? Double(c) / 12.92 : pow((Double(c) + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private static func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
