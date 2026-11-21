// DualDS — whole-app themes.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Each era theme is an original design that evokes a family of games from 1980–2010 through
// genre, colour and texture only. None uses a game's name, characters, logos, music or artwork.

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case neonMaze = "Neon Maze"
    case vectorVoid = "Vector Void"
    case pixelKingdom = "Pixel Kingdom"
    case dungeonMap = "Dungeon Map"
    case blockRain = "Block Rain"
    case pocketGreen = "Pocket Green"
    case speedZone = "Speed Zone"
    case streetBrawl = "Street Brawl"
    case polygonRally = "Polygon Rally"
    case fogTown = "Fog Town"

    var id: String { rawValue }

    /// UserDefaults / @AppStorage key for the selected theme.
    static let storageKey = "app.theme"

    /// The theme currently saved in settings (for code outside SwiftUI views).
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .classic
    }

    /// The ten era themes, oldest first.
    static var eraThemes: [AppTheme] { allCases.filter { $0 != .classic } }

    var era: String {
        switch self {
        case .classic: "Your shell colour and controller look"
        case .neonMaze: "1980 · arcade maze chases"
        case .vectorVoid: "1981 · vector space shooters"
        case .pixelKingdom: "1985 · 8-bit platform kingdoms"
        case .dungeonMap: "1986 · top-down dungeon quests"
        case .blockRain: "1989 · falling-block puzzles"
        case .pocketGreen: "1989 · monochrome pocket handhelds"
        case .speedZone: "1991 · 16-bit speed runs"
        case .streetBrawl: "1991 · arcade street fighters"
        case .polygonRally: "1997 · early 3D rally racing"
        case .fogTown: "1999 · survival horror"
        }
    }

    /// Dark themes force dark appearance; light ones force light. Classic follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .classic: nil
        case .pixelKingdom, .pocketGreen, .polygonRally: .light
        default: .dark
        }
    }

    var accent: Color {
        switch self {
        case .classic: .accentColor
        case .neonMaze: Color(hex: 0x4DE3FF)
        case .vectorVoid: Color(hex: 0x7DFFB2)
        case .pixelKingdom: Color(hex: 0xC2412A)
        case .dungeonMap: Color(hex: 0xF2D27A)
        case .blockRain: Color(hex: 0xF7B32B)
        case .pocketGreen: Color(hex: 0x0F380F)
        case .speedZone: Color(hex: 0xFFD23F)
        case .streetBrawl: Color(hex: 0xFFB347)
        case .polygonRally: Color(hex: 0xB8301F)
        case .fogTown: Color(hex: 0xB9C4B4)
        }
    }

    /// Text colour on top of the accent (filled buttons): dark on light accents, white otherwise.
    var onAccent: Color {
        switch self {
        case .neonMaze, .vectorVoid, .dungeonMap, .blockRain, .speedZone, .streetBrawl, .fogTown: Color(hex: 0x111111)
        default: .white
        }
    }

    /// Top-to-bottom backdrop gradient (Classic has none: it uses the system background).
    var backgroundColors: [Color] {
        switch self {
        case .classic: []
        case .neonMaze: [Color(hex: 0x05051A), Color(hex: 0x0D0D33)]
        case .vectorVoid: [Color(hex: 0x000000), Color(hex: 0x04110B)]
        case .pixelKingdom: [Color(hex: 0x8ED2F5), Color(hex: 0x58B6E8)]
        case .dungeonMap: [Color(hex: 0x1E1D17), Color(hex: 0x2E2B21)]
        case .blockRain: [Color(hex: 0x0E1330), Color(hex: 0x1B2350)]
        case .pocketGreen: [Color(hex: 0x9BBC0F), Color(hex: 0x8BAC0F)]
        case .speedZone: [Color(hex: 0x1A1046), Color(hex: 0x3B1C8C)]
        case .streetBrawl: [Color(hex: 0x2A0F0F), Color(hex: 0x6A2414)]
        case .polygonRally: [Color(hex: 0xF6E3C6), Color(hex: 0xE8B98A)]
        case .fogTown: [Color(hex: 0x121513), Color(hex: 0x222826)]
        }
    }

    /// Fill for cards and panels drawn over the backdrop.
    var cardFill: Color {
        switch self {
        case .classic: Color(.secondarySystemBackground)
        case .pocketGreen: Color(hex: 0x8BAC0F).opacity(0.92)
        case .pixelKingdom, .polygonRally: Color.white.opacity(0.78)
        default: Color.black.opacity(0.55)
        }
    }

    /// Pixel-era themes use a monospaced face; the rest stay rounded.
    var fontDesign: Font.Design {
        switch self {
        case .neonMaze, .pixelKingdom, .dungeonMap, .blockRain, .pocketGreen: .monospaced
        default: .rounded
        }
    }

    var sound: InterfaceSound.Voice {
        switch self {
        case .classic: .click
        case .neonMaze, .pixelKingdom, .blockRain, .pocketGreen: .blip
        case .vectorVoid, .speedZone: .zap
        case .dungeonMap: .chime
        case .fogTown: .toll
        case .streetBrawl: .punch
        case .polygonRally: .rev
        }
    }

    /// Colours for the emulator's shell and on-screen controls. Nil for Classic, which keeps the
    /// controller style's own look and the chosen shell colour.
    var palette: ShellPalette? {
        switch self {
        case .classic:
            return nil
        case .neonMaze:
            var p = ShellPalette(shell: Color(hex: 0x0B0B1E), shellEdge: Color(hex: 0x1B1F5E), bezel: Color(hex: 0x000000),
                                 button: Color(hex: 0x14164A), buttonPressed: Color(hex: 0x2E35C8),
                                 label: Color(hex: 0xFF6FE0), chrome: Color(hex: 0x4DE3FF))
            p.faceTints = [.A: Color(hex: 0xFF6FE0), .B: Color(hex: 0x4DE3FF), .X: Color(hex: 0xFF9A3C), .Y: Color(hex: 0x9CFF6A)]
            p.tintLabelsOnly = true
            return p
        case .vectorVoid:
            return ShellPalette(shell: Color(hex: 0x050807), shellEdge: Color(hex: 0x12201A), bezel: Color(hex: 0x000000),
                                button: Color(hex: 0x0E1A15), buttonPressed: Color(hex: 0x1F4A38),
                                label: Color(hex: 0x7DFFB2), chrome: Color(hex: 0xB8FFE0))
        case .pixelKingdom:
            var p = ShellPalette(shell: Color(hex: 0x58B6E8), shellEdge: Color(hex: 0x2F86C2), bezel: Color(hex: 0x20263A),
                                 button: Color(hex: 0x3F9E4A), buttonPressed: Color(hex: 0x2A6F33),
                                 label: Color(hex: 0xFFF6D8), chrome: Color(hex: 0x14233A))
            p.faceTints = [.A: Color(hex: 0xD9503A), .B: Color(hex: 0xA8650F)]
            return p
        case .dungeonMap:
            return ShellPalette(shell: Color(hex: 0x2B2A22), shellEdge: Color(hex: 0x4A4636), bezel: Color(hex: 0x12110D),
                                button: Color(hex: 0x5B5340), buttonPressed: Color(hex: 0x8A7A52),
                                label: Color(hex: 0xF2D27A), chrome: Color(hex: 0xE8D9A8))
        case .blockRain:
            var p = ShellPalette(shell: Color(hex: 0x141A33), shellEdge: Color(hex: 0x252E57), bezel: Color(hex: 0x070A16),
                                 button: Color(hex: 0x2A3366), buttonPressed: Color(hex: 0x4652A3),
                                 label: .white, chrome: Color(hex: 0xC9D2FF))
            p.faceTints = [.A: Color(hex: 0xE2534B), .B: Color(hex: 0xA2680C), .X: Color(hex: 0x2F8FC4), .Y: Color(hex: 0x2B8355)]
            return p
        case .pocketGreen:
            return ShellPalette(shell: Color(hex: 0x9BBC0F), shellEdge: Color(hex: 0x8BAC0F), bezel: Color(hex: 0x306230),
                                button: Color(hex: 0x306230), buttonPressed: Color(hex: 0x0F380F),
                                label: Color(hex: 0xC4DE5A), chrome: Color(hex: 0x0F380F))
        case .speedZone:
            var p = ShellPalette(shell: Color(hex: 0x1A1046), shellEdge: Color(hex: 0x2D1C78), bezel: Color(hex: 0x08051C),
                                 button: Color(hex: 0x2347D9), buttonPressed: Color(hex: 0x1630A0),
                                 label: .white, chrome: Color(hex: 0xFFD23F))
            p.faceTints = [.A: Color(hex: 0xE0472A), .B: Color(hex: 0x946A0A)]
            return p
        case .streetBrawl:
            var p = ShellPalette(shell: Color(hex: 0x2A0F0F), shellEdge: Color(hex: 0x4A1A12), bezel: Color(hex: 0x0D0505),
                                 button: Color(hex: 0x3B1A16), buttonPressed: Color(hex: 0x7A2A1C),
                                 label: Color(hex: 0xFFD9A0), chrome: Color(hex: 0xFFB347))
            p.faceTints = [.A: Color(hex: 0xC8322A), .B: Color(hex: 0x8E5C0E), .X: Color(hex: 0x2F69C9), .Y: Color(hex: 0x1C7646),
                           .L: Color(hex: 0x7A2A1C), .R: Color(hex: 0x7A2A1C)]
            return p
        case .polygonRally:
            return ShellPalette(shell: Color(hex: 0xE9E4D8), shellEdge: Color(hex: 0xC9C1AE), bezel: Color(hex: 0x2B2B2E),
                                button: Color(hex: 0xB8301F), buttonPressed: Color(hex: 0x7E1E13),
                                label: .white, chrome: Color(hex: 0x2B2B2E))
        case .fogTown:
            var p = ShellPalette(shell: Color(hex: 0x1B1F1D), shellEdge: Color(hex: 0x2C332F), bezel: Color(hex: 0x0A0C0B),
                                 button: Color(hex: 0x2E3532), buttonPressed: Color(hex: 0x4A5650),
                                 label: Color(hex: 0xC9CFC4), chrome: Color(hex: 0x9DA69C))
            p.faceTints = [.A: Color(hex: 0x8E3A32)]
            return p
        }
    }

    /// Seed for the backdrop's deterministic pattern.
    var seed: UInt64 { UInt64(abs(rawValue.hashValueStable)) &+ 0x9E37_79B9_7F4A_7C15 }
}

extension Color {
    /// sRGB colour from 0xRRGGBB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

private extension String {
    /// FNV-1a: stable across launches (unlike `hashValue`), so each backdrop always looks the same.
    var hashValueStable: Int {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return Int(truncatingIfNeeded: h & 0x7FFF_FFFF_FFFF)
    }
}
