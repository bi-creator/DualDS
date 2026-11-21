// DualDS — FoldPlay Store: game list, StoreKit purchases (local test session) and the
// purchase-gated install of FoldPlay Originals.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import StoreKitTest
import SwiftData
import XCTest
@testable import DualDS

@MainActor
final class StoreTests: XCTestCase {
    private var session: SKTestSession!
    private var root: URL!
    private var storage: GameStorage!
    private var context: ModelContext!
    private let productID = "com.bicreator.dualds.backalleybrawl"

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "FoldPlay")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = GameStorage(root: root)
        let container = try ModelContainer(for: Game.self, SaveState.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        session.clearTransactions()
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Game list

    private func catalogJSON(_ games: String, version: Int = 1) -> Data {
        Data("{\"version\": \(version), \"games\": [\(games)]}".utf8)
    }

    private func entry(id: String = "g", product: String = "p", file: String = "games/g.nds",
                       sha: String = String(repeating: "a", count: 64)) -> String {
        """
        {"id":"\(id)","productID":"\(product)","title":"T","tagline":"t","details":"d",
         "file":"\(file)","sha256":"\(sha)","size":1,"artwork":null}
        """
    }

    func testCatalogParsesAndValidates() throws {
        XCTAssertEqual(try OriginalsCatalog.decode(catalogJSON(entry())).count, 1)
        XCTAssertThrowsError(try OriginalsCatalog.decode(catalogJSON(entry(), version: 2)))
        XCTAssertThrowsError(try OriginalsCatalog.decode(catalogJSON(entry() + "," + entry(product: "q"))), "duplicate id")
        XCTAssertThrowsError(try OriginalsCatalog.decode(catalogJSON(entry(sha: "xyz"))), "bad hash")
        XCTAssertThrowsError(try OriginalsCatalog.decode(catalogJSON(entry(file: "../etc/x"))), "path traversal")
        XCTAssertThrowsError(try OriginalsCatalog.decode(catalogJSON(entry(file: "/abs"))), "absolute path")
    }

    func testAppShipsAFallbackGameList() throws {
        let catalog = OriginalsCatalog(remoteURL: URL(string: "https://example.invalid/games.json")!,
                                       cacheURL: root.appendingPathComponent("none.json"))
        let game = try XCTUnwrap(catalog.game(forProduct: productID), "Resources/originals-fallback.json lists Back Alley Brawl")
        XCTAssertEqual(game.id, "back-alley-brawl")
        XCTAssertTrue(game.file.hasPrefix("games/"))
    }

    // MARK: StoreKit

    func testProductLoadsFromTheStoreKitConfiguration() async throws {
        let store = StoreService()
        await store.loadProducts(ids: [productID])
        let product = try XCTUnwrap(store.products[productID], "error: \(store.loadError ?? "none")")
        XCTAssertEqual(product.type, .nonConsumable)
    }

    func testPurchaseGrantsVerifiedOwnershipAndRefundRevokesIt() async throws {
        let store = StoreService()
        let notYet = await store.verifiedOwnership(of: productID)
        XCTAssertFalse(notYet)
        await store.loadProducts(ids: [productID])
        let product = try XCTUnwrap(store.products[productID])
        let bought = await store.handle(try await product.purchase())
        XCTAssertTrue(bought)
        let owned = await store.verifiedOwnership(of: productID)
        XCTAssertTrue(owned)

        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        var stillOwned = true
        for _ in 0..<20 {   // StoreKit applies the refund asynchronously
            stillOwned = await store.verifiedOwnership(of: productID)
            if !stillOwned { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(stillOwned)
    }

    // MARK: Purchase-gated install

    /// A catalog entry for Back Alley Brawl's product that points at DualDS's own test ROM.
    private func fixtureGame(sha: String? = nil) throws -> (OriginalGame, LocalDirectorySource) {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dualds-test", withExtension: "nds"))
        let hash = try sha ?? OriginalsInstaller.sha256Hex(of: fixture)
        let game = OriginalGame(id: "back-alley-brawl", productID: productID, title: "Back Alley Brawl", tagline: "",
                                details: "", file: "games/dualds-test.nds", sha256: hash, size: 0, artwork: nil)
        return (game, LocalDirectorySource(directory: fixture.deletingLastPathComponent()))
    }

    func testInstallRefusesWithoutAPurchase() async throws {
        let (game, source) = try fixtureGame()
        do {
            _ = try await OriginalsInstaller.install(game, store: StoreService(), source: source, storage: storage, context: context)
            XCTFail("installed without a purchase")
        } catch let error as OriginalsInstaller.InstallError {
            XCTAssertEqual(error, .notPurchased)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Game>()).count, 0)
    }

    func testInstallAfterPurchaseAddsTheGameOnce() async throws {
        let store = StoreService()
        await store.loadProducts(ids: [productID])
        _ = await store.handle(try await XCTUnwrap(store.products[productID]).purchase())
        let (game, source) = try fixtureGame()

        let first = try await OriginalsInstaller.install(game, store: store, source: source, storage: storage, context: context)
        XCTAssertEqual(first, .added)
        let games = try context.fetch(FetchDescriptor<Game>())
        XCTAssertEqual(games.map(\.title), ["Back Alley Brawl"])
        XCTAssertTrue(OriginalsInstaller.isInLibrary(game, games: games))
        let second = try await OriginalsInstaller.install(game, store: store, source: source, storage: storage, context: context)
        XCTAssertEqual(second, .alreadyInLibrary)
    }

    func testInstallRejectsAFileThatDoesNotMatchTheGameList() async throws {
        let store = StoreService()
        await store.loadProducts(ids: [productID])
        _ = await store.handle(try await XCTUnwrap(store.products[productID]).purchase())
        let (game, source) = try fixtureGame(sha: String(repeating: "0", count: 64))
        do {
            _ = try await OriginalsInstaller.install(game, store: store, source: source, storage: storage, context: context)
            XCTFail("accepted a file with the wrong hash")
        } catch let error as OriginalsInstaller.InstallError {
            XCTAssertEqual(error, .corrupt)
        }
    }
}
