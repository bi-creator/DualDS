// DualDS — choose a theme from preview tiles.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

struct ThemePickerView: View {
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.classic
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        theme = option
                        InterfaceSound.shared.play(option.sound)
                    } label: {
                        ThemeTile(theme: option, selected: option == theme)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("theme.\(option.rawValue)")
                    .accessibilityAddTraits(option == theme ? .isSelected : [])
                }
            }
            .padding()
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemeTile: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                ThemeBackdrop(theme: theme, fullScreen: false)
                if let palette = theme.palette {
                    HStack(spacing: 6) {
                        Circle().fill(palette.shell).overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                        Circle().fill(palette.button)
                        Circle().fill(palette.faceTints[.A] ?? palette.label)
                    }
                    .frame(height: 16)
                    .padding(8)
                }
            }
            .frame(height: 96)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color.accentColor : .secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
            HStack {
                Text(theme.rawValue).font(.system(.subheadline, design: theme.fontDesign, weight: .semibold))
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
            }
            Text(theme.era).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
