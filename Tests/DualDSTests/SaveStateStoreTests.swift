// DualDS — save-state store tests against the real core and real files.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftData
import UIKit
import XCTest
@testable import DualDS

@MainActor
final class SaveStateStoreTests: XCTestCase {
    private var root: URL!
    private var storage: GameStorage!
    private var context: ModelContext!
    private var game: Game!
    private var core: DSCore!
    private var store: SaveStateStore { SaveStateStore(storage: storage) }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = GameStorage(root: root)
        let container = try ModelContainer(for: Game.self, SaveState.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dualds-test", withExtension: "nds"))
        let rom = try await GameImportService(storage: storage).importROM(from: fixture, existingHashes: [])
        game = Game(imported: rom)
        context.insert(game)
        try context.save()
        core = DSCore()
        try core.loadGame(at: storage.romURL(fileName: game.fileName), save: storage.saveURL(gameID: game.id))
        core.runFramesBlocking(30)
    }

    override func tearDown() async throws {
        core.stop()
        try? FileManager.default.removeItem(at: root)
    }

    func testSaveCreatesRecordFileAndScreenshot() async throws {
        let s = try await store.save(core: core, game: game, slot: 1, context: context)
        XCTAssertEqual(s.name, "Slot 1")
        XCTAssertEqual(s.coreVersion, DSCore.melonDSVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: s).path))
        let png = try XCTUnwrap(s.screenshotPNG)
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(image.size, CGSize(width: 256, height: 384), "both screens stacked")
        XCTAssertEqual(store.states(for: game, context: context).map(\.slot), [1])
    }

    func testSavingIntoAnOccupiedSlotReplacesItAndKeepsTheName() async throws {
        let first = try await store.save(core: core, game: game, slot: 2, context: context)
        try store.rename(first, to: "Before the boss", context: context)
        let oldURL = store.url(for: first)
        core.runFramesBlocking(5)
        let second = try await store.save(core: core, game: game, slot: 2, context: context)
        XCTAssertEqual(store.states(for: game, context: context).count, 1)
        XCTAssertEqual(second.name, "Before the boss")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path), "old file removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: second).path))
    }

    func testLoadRestoresTheExactConsoleState() async throws {
        let saved = try await store.save(core: core, game: game, slot: 1, context: context)
        core.setButton(.A, pressed: true)
        core.runFramesBlocking(20)
        core.setButton(.A, pressed: false)
        try await store.load(saved, into: core, game: game)
        let again = try await store.save(core: core, game: game, slot: 3, context: context)
        XCTAssertEqual(try Data(contentsOf: store.url(for: saved)), try Data(contentsOf: store.url(for: again)))
    }

    func testQuickSlotRenameAndDelete() async throws {
        let quick = try await store.save(core: core, game: game, slot: SaveStateStore.quickSlot, context: context)
        XCTAssertEqual(quick.name, "Quick Save")
        try store.rename(quick, to: "   ", context: context)
        XCTAssertEqual(quick.name, "Quick Save", "blank names fall back to the default")
        let url = store.url(for: quick)
        try store.delete(quick, context: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.states(for: game, context: context).isEmpty)
    }

    func testMissingFileAndWrongGameAreRejectedWithoutTouchingTheConsole() async throws {
        let s = try await store.save(core: core, game: game, slot: 4, context: context)
        try FileManager.default.removeItem(at: store.url(for: s))
        do { try await store.load(s, into: core, game: game); XCTFail("loaded a missing file") }
        catch { XCTAssertEqual(error as? SaveStateError, .missingFile) }

        let other = SaveState(gameID: UUID(), slot: 1, name: "x", fileName: "x.mln", coreVersion: "1.1", screenshotPNG: nil)
        do { try await store.load(other, into: core, game: game); XCTFail("loaded another game's state") }
        catch { XCTAssertEqual(error as? SaveStateError, .wrongGame) }
        XCTAssertEqual(core.runFramesBlocking(2), 2, "console still runs")
    }
}
