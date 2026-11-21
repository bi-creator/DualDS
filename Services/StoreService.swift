// DualDS — in-app purchases for FoldPlay Originals (StoreKit 2).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Apple handles payment, receipts and Family Sharing. FoldPlay keeps nothing on a server: it asks
// StoreKit which products this Apple Account owns, and unpacks owned games into the library.

import Foundation
import Observation
import StoreKit
import SwiftData

@MainActor
@Observable
final class StoreService {
    static let shared = StoreService()

    private(set) var products: [String: Product] = [:]
    private(set) var owned: Set<String> = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private var updatesTask: Task<Void, Never>?

    init() {}

    /// Starts listening for purchases made elsewhere (other devices, Ask to Buy, refunds) and
    /// loads products and ownership. Call once at launch.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.process(update)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: OriginalsCatalog.all.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            loadError = list.isEmpty ? "The FoldPlay Store isn't available right now." : nil
        } catch {
            loadError = "Couldn't reach the App Store: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var current: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { current.insert(t.productID) }
        }
        owned = current
    }

    func isOwned(_ game: OriginalGame) -> Bool { owned.contains(game.productID) }

    /// Handles the outcome of a purchase sheet. Returns true when the game is now owned.
    @discardableResult
    func handle(_ result: Product.PurchaseResult) async -> Bool {
        switch result {
        case .success(let verification):
            return await process(verification)
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    /// Restore Purchases: syncs with the App Store (may ask the user to sign in).
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    @discardableResult
    private func process(_ verification: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = verification else { return false }
        if transaction.revocationDate == nil {
            owned.insert(transaction.productID)
        } else {
            owned.remove(transaction.productID)
        }
        await transaction.finish()
        return transaction.revocationDate == nil
    }
}

/// Puts an owned FoldPlay Original into the library. Main actor: it uses the library's ModelContext;
/// unpacking and copying the file run off the main thread.
@MainActor
enum OriginalsInstaller {
    enum Outcome: Equatable { case added, alreadyInLibrary }

    static func install(_ game: OriginalGame, storage: GameStorage, context: ModelContext,
                        bundle: Bundle = .main) async throws -> Outcome {
        let rom = try await Task.detached(priority: .userInitiated) { try OriginalPackage.unpack(game, bundle: bundle) }.value
        defer { try? FileManager.default.removeItem(at: rom) }
        let existing = Set(((try? context.fetch(FetchDescriptor<Game>())) ?? []).map(\.contentHash))
        do {
            let imported = try await GameImportService(storage: storage).importROM(from: rom, existingHashes: existing)
            let entry = Game(imported: imported)
            entry.title = game.title
            context.insert(entry)
            try context.save()
            return .added
        } catch GameImportError.duplicate {
            return .alreadyInLibrary
        }
    }

    /// True if this game is already in the library. The package's nonce is the first 16 bytes of
    /// the ROM's SHA-256, which is how the importer identifies games (Game.contentHash, hex).
    static func isInLibrary(_ game: OriginalGame, games: [Game], bundle: Bundle = .main) -> Bool {
        guard let prefix = OriginalPackage.hashPrefix(for: game, in: bundle) else { return false }
        return games.contains { $0.contentHash.lowercased().hasPrefix(prefix) }
    }
}
