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
    @State private var busy: String?
    @State private var message: String?
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.classic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Games made for FoldPlay. Buy once, play forever, on every device with your Apple Account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(OriginalsCatalog.all) { game in
                        card(game)
                    }
                    if let error = store.loadError {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Try Again") { Task { await store.loadProducts() } }
                    }
                    Button("Restore Purchases") { Task { await restore() } }
                        .disabled(busy != nil)
                        .accessibilityIdentifier("store.restore")
                    Text("Payment is handled by Apple through your Apple Account. FoldPlay never sees your card or bank details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background { ThemeBackdrop(theme: theme) }
            .navigationTitle("FoldPlay Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                if store.products.isEmpty { await store.loadProducts() }
                await store.refreshEntitlements()
            }
            .alert("FoldPlay Store", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
        .accessibilityIdentifier("store.view")
    }

    private func card(_ game: OriginalGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(game.artwork)
                .resizable()
                .interpolation(.none)
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

    @ViewBuilder private func action(for game: OriginalGame) -> some View {
        let owned = store.isOwned(game)
        let inLibrary = OriginalsInstaller.isInLibrary(game, games: games)
        HStack {
            if busy == game.id {
                ProgressView()
            } else if owned && inLibrary {
                Label("In your library", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("store.inLibrary.\(game.id)")
            } else if owned {
                Button { Task { await install(game) } } label: { Label("Add to Library", systemImage: "plus.circle") }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.current.onAccent)
                    .accessibilityIdentifier("store.add.\(game.id)")
            } else if let product = store.products[game.productID] {
                Button { Task { await buy(game, product) } } label: { Text("Buy \(product.displayPrice)").bold() }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.current.onAccent)
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
        defer { busy = nil }
        do {
            let result = try await purchase(product)
            if await store.handle(result) {
                InterfaceSound.shared.play(theme.sound)
                await install(game)
            } else if case .pending = result {
                message = "Your purchase is waiting for approval. The game appears here once it's approved."
            }
        } catch {
            message = "The purchase didn't go through: \(error.localizedDescription)"
        }
    }

    private func install(_ game: OriginalGame) async {
        busy = game.id
        defer { busy = nil }
        do {
            switch try await OriginalsInstaller.install(game, storage: storage, context: context) {
            case .added: message = "\(game.title) is in your library. Have fun!"
            case .alreadyInLibrary: message = "\(game.title) is already in your library."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        busy = "restore"
        defer { busy = nil }
        do {
            try await store.restore()
            let owned = OriginalsCatalog.all.filter { store.isOwned($0) }
            for game in owned where !OriginalsInstaller.isInLibrary(game, games: games) {
                _ = try? await OriginalsInstaller.install(game, storage: storage, context: context)
            }
            message = owned.isEmpty ? "No FoldPlay purchases were found for this Apple Account."
                                    : "Restored: \(owned.map(\.title).joined(separator: ", "))."
        } catch {
            message = "Couldn't restore purchases: \(error.localizedDescription)"
        }
    }
}
