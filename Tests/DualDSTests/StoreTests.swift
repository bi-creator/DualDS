// DualDS — FoldPlay Store: StoreKit purchases (local StoreKit test session) and game packages.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import CryptoKit
import StoreKitTest
import SwiftData
import XCTest
@testable import DualDS

@MainActor
final class StoreTests: XCTestCase {
    private var session: SKTestSession!
    private let game = OriginalsCatalog.backAlleyBrawl

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "FoldPlay")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session.clearTransactions()
    }

    func testCatalogProductsMatchTheStoreKitConfiguration() async throws {
        let store = StoreService()
        await store.loadProducts()
        let product = try XCTUnwrap(store.products[game.productID],
                                    "product missing: \(store.products.keys.sorted()) error: \(store.loadError ?? "none")")
        XCTAssertEqual(product.type, .nonConsumable)
        XCTAssertEqual(product.displayName, "Back Alley Brawl")
        XCTAssertNil(store.loadError)
    }

    func testNotOwnedUntilBought() async throws {
        let store = StoreService()
        await store.refreshEntitlements()
        XCTAssertFalse(store.isOwned(game))
    }

    func testPurchaseGrantsOwnership() async throws {
        let store = StoreService()
        await store.loadProducts()
        let product = try XCTUnwrap(store.products[game.productID])
        let result = try await product.purchase()
        let owned = await store.handle(result)
        XCTAssertTrue(owned)
        XCTAssertTrue(store.isOwned(game))
        await store.refreshEntitlements()
        XCTAssertTrue(store.isOwned(game), "ownership survives a fresh entitlement check")
    }

    func testRefundRemovesOwnership() async throws {
        let store = StoreService()
        await store.loadProducts()
        let product = try XCTUnwrap(store.products[game.productID])
        _ = await store.handle(try await product.purchase())
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        // StoreKit applies the refund asynchronously; give it up to two seconds.
        for _ in 0..<20 {
            await store.refreshEntitlements()
            if !store.isOwned(game) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.isOwned(game))
    }

    // MARK: Packages

    func testPackageRoundTrip() throws {
        // Same algorithm as Scripts/package-originals.py.
        let rom = Data((0..<1000).map { UInt8($0 % 251) })
        let nonce = Data(SHA256.hash(data: rom).prefix(16))
        var scrambled = rom
        var counter: UInt64 = 0
        var offset = 0
        while offset < scrambled.count {
            var block = Data("FoldPlay Originals v1".utf8)
            block.append(nonce)
            withUnsafeBytes(of: counter.littleEndian) { block.append(contentsOf: $0) }
            let stream = Array(SHA256.hash(data: block))
            for i in 0..<min(32, scrambled.count - offset) { scrambled[offset + i] ^= stream[i] }
            offset += 32
            counter += 1
        }
        let package = OriginalPackage.magic + nonce + scrambled
        XCTAssertEqual(try OriginalPackage.decode(package), rom)
        XCTAssertThrowsError(try OriginalPackage.decode(Data("nope".utf8)))
    }

    /// Runs when the app was built with the real game package (Build/Originals); skipped otherwise.
    func testBundledGameUnpacksToAValidDSGameAndInstallsOnce() async throws {
        guard OriginalPackage.url(for: game) != nil else { throw XCTSkip("No packaged game in this build") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = GameStorage(root: root)
        let container = try ModelContainer(for: Game.self, SaveState.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let first = try await OriginalsInstaller.install(game, storage: storage, context: context)
        XCTAssertEqual(first, .added)
        let games = try context.fetch(FetchDescriptor<Game>())
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.title, game.title)
        XCTAssertTrue(OriginalsInstaller.isInLibrary(game, games: games))
        let second = try await OriginalsInstaller.install(game, storage: storage, context: context)
        XCTAssertEqual(second, .alreadyInLibrary)
    }
}
