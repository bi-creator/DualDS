// DualDS — handheld "shell" colour themes for the emulator screen (original designs).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

enum ShellTheme: String, CaseIterable, Identifiable {
    case lilac = "Lilac", blush = "Blush", silver = "Silver", midnight = "Midnight"
    var id: String { rawValue }

    var palette: ShellPalette {
        switch self {
        case .lilac:
            ShellPalette(shell: Color(red: 0.86, green: 0.83, blue: 0.95), shellEdge: Color(red: 0.74, green: 0.70, blue: 0.86),
                         bezel: Color(red: 0.66, green: 0.62, blue: 0.80), button: Color(red: 0.93, green: 0.91, blue: 0.99),
                         buttonPressed: Color(red: 0.78, green: 0.74, blue: 0.90), label: Color(red: 0.36, green: 0.32, blue: 0.50),
                         chrome: Color(red: 0.30, green: 0.27, blue: 0.42))
        case .blush:
            ShellPalette(shell: Color(red: 0.96, green: 0.80, blue: 0.86), shellEdge: Color(red: 0.88, green: 0.66, blue: 0.75),
                         bezel: Color(red: 0.80, green: 0.58, blue: 0.68), button: Color(red: 0.99, green: 0.90, blue: 0.93),
                         buttonPressed: Color(red: 0.90, green: 0.72, blue: 0.80), label: Color(red: 0.55, green: 0.30, blue: 0.40),
                         chrome: Color(red: 0.45, green: 0.22, blue: 0.32))
        case .silver:
            ShellPalette(shell: Color(red: 0.88, green: 0.88, blue: 0.86), shellEdge: Color(red: 0.74, green: 0.74, blue: 0.72),
                         bezel: Color(red: 0.36, green: 0.37, blue: 0.40), button: Color(red: 0.30, green: 0.30, blue: 0.33),
                         buttonPressed: Color(red: 0.18, green: 0.18, blue: 0.20), label: Color(red: 0.92, green: 0.92, blue: 0.92),
                         chrome: Color(red: 0.25, green: 0.25, blue: 0.28))
        case .midnight:
            ShellPalette(shell: Color(red: 0.07, green: 0.07, blue: 0.09), shellEdge: Color(red: 0.16, green: 0.16, blue: 0.19),
                         bezel: Color(red: 0.02, green: 0.02, blue: 0.03), button: .white.opacity(0.16),
                         buttonPressed: .white.opacity(0.42), label: .white, chrome: .white)
        }
    }
}

struct ShellPalette {
    var shell: Color          // body colour
    var shellEdge: Color      // hinge band, grille dots
    var bezel: Color          // frame around the screens
    var button: Color
    var buttonPressed: Color
    var label: Color          // text/glyphs on buttons
    var chrome: Color         // toolbar icons, captions on the shell
    /// Per-button colours (fill, or letter colour when `tintLabelsOnly`).
    var faceTints: [DSButton: Color] = [:]
    var tintLabelsOnly = false
}

private struct ShellPaletteKey: EnvironmentKey {
    static let defaultValue = ShellTheme.midnight.palette
}

extension EnvironmentValues {
    var shellPalette: ShellPalette {
        get { self[ShellPaletteKey.self] }
        set { self[ShellPaletteKey.self] = newValue }
    }
}

/// Rounded frame drawn behind a DS screen.
struct ScreenBezel: View {
    let rect: CGRect
    @Environment(\.shellPalette) private var palette
    var body: some View {
        let frame = rect.insetBy(dx: -max(6, rect.width * 0.035), dy: -max(6, rect.width * 0.035))
        RoundedRectangle(cornerRadius: max(10, frame.width * 0.045), style: .continuous)
            .fill(palette.bezel)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .accessibilityHidden(true)
    }
}
