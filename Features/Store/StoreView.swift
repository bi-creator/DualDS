// DualDS — the FoldPlay Store: original games sold as in-app purchases.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import StoreKit
import SwiftData
import SwiftUI

struct StoreView: View {
    let storage: GameStorage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.purchase) private var purchase
    @Query private var games: [Game]
    @State private var store = StoreService.shared
    @State private var catalog = OriginalsCatalog.shared
    @State private var busy: String?
    @State private var downloads = DownloadProgress()
    @State private var message: String?
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.classic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Games made for FoldPlay. Buy once, play forever, with your Apple Account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(catalog.games) { game in
                        card(game)
                    }
                    if catalog.games.isEmpty && catalog.isRefreshing { ProgressView().frame(maxWidth: .infinity) }
                    if let error = store.loadError ?? (catalog.games.isEmpty ? catalog.lastError : nil) {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Try Again") { Task { await reload() } }
                    }
                    Button("Restore Purchases") { Task { await restore() } }
                        .disabled(busy != nil)
                        .accessibilityIdentifier("store.restore")
                    Text("Payment is handled by Apple through your Apple Account. FoldPlay never sees your card or bank details. Games download from Apple after your purchase is confirmed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background { ThemeBackdrop(theme: theme) }
            .navigationTitle("FoldPlay Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await reload() }
            .alert("FoldPlay Store", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
        .accessibilityIdentifier("store.view")
    }

    private func reload() async {
        await catalog.refresh()
        await store.loadProducts(ids: catalog.games.map(\.productID))
        await store.refreshEntitlements()
    }

    private func card(_ game: OriginalGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            artwork(game)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(game.title).font(.title3.bold())
            Text(game.tagline).font(.subheadline).foregroundStyle(.secondary)
            Text(game.details).font(.footnote)
            action(for: game)
        }
        .padding()
        .background(theme == .classic ? Color(.secondarySystemBackground) : theme.cardFill,
                    in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store.game.\(game.id)")
    }

    @ViewBuilder private func artwork(_ game: OriginalGame) -> some View {
        if let url = game.artwork {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().interpolation(.none)
                } else {
                    Rectangle().fill(.black.opacity(0.3)).overlay { DualScreenGlyph().frame(width: 40, height: 52).opacity(0.5) }
                }
            }
        } else {
            Rectangle().fill(.black.opacity(0.3))
        }
    }

    @ViewBuilder private func action(for game: OriginalGame) -> some View {
        let owned = store.isOwned(game.productID)
        let inLibrary = OriginalsInstaller.isInLibrary(game, games: games)
        HStack {
            if busy == game.id {
                if let p = downloads.values[game.id], p > 0, p < 1 {
                    ProgressView(value: p) { Text("Downloading…").font(.caption) }
                        .accessibilityIdentifier("store.progress.\(game.id)")
                } else {
                    ProgressView()
                }
            } else if owned && inLibrary {
                Label("In your library", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("store.inLibrary.\(game.id)")
            } else if owned {
                Button { Task { await download(game) } } label: {
                    Label("Download \(ByteCountFormatter.string(fromByteCount: game.size, countStyle: .file))", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(theme.onAccent)
                .accessibilityIdentifier("store.download.\(game.id)")
            } else if let product = store.products[game.productID] {
                Button { Task { await buy(game, product) } } label: { Text("Buy \(product.displayPrice)").bold() }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(theme.onAccent)
                    .accessibilityIdentifier("store.buy.\(game.id)")
            } else if store.isLoading {
                ProgressView()
            } else {
                Text("Not available right now").foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func buy(_ game: OriginalGame, _ product: Product) async {
        busy = game.id
        do {
            let result = try await purchase(product)
            if await store.handle(result) {
                InterfaceSound.shared.play(theme.sound)
                busy = nil
                await download(game)
                return
            } else if case .pending = result {
                message = "Your purchase is waiting for approval. The game appears here once it's approved."
            }
        } catch {
            message = "The purchase didn't go through: \(error.localizedDescription)"
        }
        busy = nil
    }

    private func download(_ game: OriginalGame) async {
        busy = game.id
        downloads.values[game.id] = 0
        defer { busy = nil; downloads.values[game.id] = nil }
        let id = game.id
        let tracker = downloads
        do {
            let outcome = try await OriginalsInstaller.install(
                game, store: store, source: OriginalsInstaller.defaultSource(), storage: storage, context: context,
                progress: { value in Task { @MainActor in tracker.values[id] = value } })
            message = outcome == .added ? "\(game.title) is in your library. Have fun!"
                                        : "\(game.title) is already in your library."
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        busy = "restore"
        defer { busy = nil }
        do {
            try await store.restore()
            let owned = catalog.games.filter { store.isOwned($0.productID) }
            message = owned.isEmpty ? "No FoldPlay purchases were found for this Apple Account."
                                    : "Restored: \(owned.map(\.title).joined(separator: ", ")). Tap Download to add a game to your library."
        } catch {
            message = "Couldn't restore purchases: \(error.localizedDescription)"
        }
    }
}

/// Download progress per game (0...1), updated from the downloader's callback.
@MainActor
@Observable
final class DownloadProgress {
    var values: [String: Double] = [:]
}
