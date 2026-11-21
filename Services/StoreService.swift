// DualDS — in-app purchases for FoldPlay Originals (StoreKit 2).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Apple handles payment and receipts. FoldPlay keeps nothing on a server: it asks StoreKit which
// products this Apple Account owns. StoreKit 2 verifies Apple's signature on each transaction on
// the device; only `.verified`, unrevoked transactions count as owned.

import Foundation
import Observation
import StoreKit

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

    /// Listens for purchases made elsewhere (other devices, Ask to Buy, refunds). Call once at launch.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.process(update)
            }
        }
        Task { await refreshEntitlements() }
    }

    func loadProducts(ids: [String]) async {
        guard !ids.isEmpty else { products = [:]; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: ids)
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

    func isOwned(_ productID: String) -> Bool { owned.contains(productID) }

    /// Fresh check straight from StoreKit (not the cached set): an Apple-signed, verified,
    /// unrevoked transaction for this product. Gates every game download.
    func verifiedOwnership(of productID: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == productID, t.revocationDate == nil {
                owned.insert(productID)
                return true
            }
        }
        owned.remove(productID)
        return false
    }

    /// Handles the outcome of a purchase sheet. Returns true when the product is now owned.
    @discardableResult
    func handle(_ result: Product.PurchaseResult) async -> Bool {
        switch result {
        case .success(let verification): return await process(verification)
        case .pending, .userCancelled: return false
        @unknown default: return false
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
        if transaction.revocationDate == nil { owned.insert(transaction.productID) }
        else { owned.remove(transaction.productID) }
        await transaction.finish()
        return transaction.revocationDate == nil
    }
}
