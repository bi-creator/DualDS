// DualDS — game details, custom artwork and deletion.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct GameDetailView: View {
    let game: Game
    let model: GameLibraryViewModel
    let onPlay: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var errorMessage: String?

    private var saveStateCount: Int {
        SaveStateStore.states(for: game.id, context: context).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        GameArtwork(game: game, artworkURL: model.artworkURL(game))
                            .frame(width: 96, height: 96)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                            .clipShape(.rect(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title).font(.title3.bold())
                            if let subtitle = game.subtitle { Text(subtitle).foregroundStyle(.secondary) }
                            if let publisher = game.publisher { Text(publisher).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section {
                    Button {
                        InterfaceSound.shared.play(AppTheme.current.sound)
                        dismiss()
                        onPlay()
                    } label: {
                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity).font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("detail.play")
                }
                Section("Details") {
                    LabeledContent("Game code", value: game.gameCode)
                    LabeledContent("Header title", value: game.headerTitle)
                    LabeledContent("Maker code", value: game.makerCode)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: game.fileSize, countStyle: .file))
                    LabeledContent("Imported", value: game.importedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Last played", value: game.lastPlayedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    LabeledContent("Play time", value: Self.playTime(game.playTime))
                    LabeledContent("Save data", value: model.hasSaveData(game) ? "Yes" : "None yet")
                        .accessibilityIdentifier("detail.saveData")
                    LabeledContent("Save states", value: "\(saveStateCount)")
                }
                Section("Artwork") {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose Custom Artwork", systemImage: "photo")
                    }
                    if game.hasCustomArtwork {
                        Button("Remove Custom Artwork", role: .destructive) { setArtwork(nil) }
                    }
                }
                Section {
                    Button("Delete Game", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                    .accessibilityIdentifier("detail.delete")
                }
            }
            .navigationTitle(game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    // Normalise to a bounded PNG so arbitrary photos don't bloat storage.
                    setArtwork(data.flatMap(UIImage.init(data:)).flatMap(Self.thumbnailPNG))
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func setArtwork(_ png: Data?) {
        do { try model.setCustomArtwork(png, for: game, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    static func thumbnailPNG(_ image: UIImage) -> Data? {
        let side: CGFloat = 512
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).pngData { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static func playTime(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return seconds > 0 ? "Under a minute" : "None" }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: seconds) ?? "—"
    }
}
