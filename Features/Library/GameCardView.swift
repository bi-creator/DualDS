// DualDS — one game in the library grid.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI
import UIKit

struct GameCardView: View {
    let game: Game
    let artworkURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameArtwork(game: game, artworkURL: artworkURL)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
            Text(game.title)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
            HStack {
                Text(game.gameCode).font(.caption.monospaced())
                Spacer()
                Text(game.lastPlayedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never played")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Custom artwork if the user chose one, otherwise the game's own banner icon, otherwise a glyph.
struct GameArtwork: View {
    let game: Game
    let artworkURL: URL?

    var body: some View {
        if let url = artworkURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let data = game.iconPNG, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit().padding(24)
        } else {
            DualScreenGlyph().padding(36).opacity(0.5)
        }
    }
}
