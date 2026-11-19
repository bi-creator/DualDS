// DualDS — import service and library persistence tests (real files, in-memory SwiftData).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftData
import XCTest
@testable import DualDS

@MainActor
final class GameLibraryTests: XCTestCase {
    private var root: URL!
    private var storage: GameStorage!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = GameStorage(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dualds-test", withExtension: "nds"))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testImportCopiesValidatedROMIntoStorage() async throws {
        let rom = try await GameImportService(storage: storage).importROM(from: try fixtureURL(), existingHashes: [])
        XCTAssertEqual(rom.header.gameCode, "DDST")
        XCTAssertEqual(rom.displayTitle, "DUALDSTEST")
        XCTAssertEqual(rom.contentHash.count, 64)
        let copy = storage.romURL(fileName: rom.fileName)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: try fixtureURL()))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: storage.games.path).filter { $0.hasPrefix(".import-") }
        XCTAssertEqual(leftovers, [], "temporary import files are cleaned up")
    }

    func testDuplicateImportIsRejected() async throws {
        let service = GameImportService(storage: storage)
        let first = try await service.importROM(from: try fixtureURL(), existingHashes: [])
        do {
            _ = try await service.importROM(from: try fixtureURL(), existingHashes: [first.contentHash])
            XCTFail("duplicate accepted")
        } catch {
            XCTAssertEqual(error as? GameImportError, .duplicate)
        }
    }

    func testInvalidAndMissingFilesAreRejectedWithoutCopying() async throws {
        let junk = root.appendingPathComponent("junk.nds")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 0x4000).write(to: junk)
        let service = GameImportService(storage: storage)
        do {
            _ = try await service.importROM(from: junk, existingHashes: [])
            XCTFail("junk accepted")
        } catch GameImportError.notANintendoDSGame {
        } catch { XCTFail("\(error)") }

        do {
            _ = try await service.importROM(from: root.appendingPathComponent("nope.nds"), existingHashes: [])
            XCTFail("missing file accepted")
        } catch GameImportError.unreadable {
        } catch { XCTFail("\(error)") }

        let copied = (try? FileManager.default.contentsOfDirectory(atPath: storage.games.path)) ?? []
        XCTAssertEqual(copied, [], "nothing copied for rejected files")
    }

    func testViewModelImportPersistsAndPreventsDuplicates() async throws {
        let context = try makeContext()
        let model = GameLibraryViewModel(storage: storage)
        await model.importFiles([try fixtureURL(), try fixtureURL()], into: context)
        let games = try context.fetch(FetchDescriptor<Game>())
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.gameCode, "DDST")
        let report = try XCTUnwrap(model.importReport)
        XCTAssertTrue(report.contains("Imported DUALDSTEST"))
        XCTAssertTrue(report.contains("already in your library"))
    }

    func testSearchAndSort() async throws {
        let context = try makeContext()
        let model = GameLibraryViewModel(storage: storage)
        await model.importFiles([try fixtureURL()], into: context)
        let game = try XCTUnwrap(try context.fetch(FetchDescriptor<Game>()).first)

        model.searchText = "ddst"
        XCTAssertEqual(model.visibleGames([game]).count, 1, "search matches game code")
        model.searchText = "zelda"
        XCTAssertEqual(model.visibleGames([game]).count, 0)
        model.searchText = ""

        let other = Game(imported: ImportedROM(header: try ROMHeader.parse(header: try Data(contentsOf: try fixtureURL()), fileSize: 8192),
                                               banner: nil, contentHash: String(repeating: "a", count: 64),
                                               fileName: "x.nds", fileSize: 8192),
                         importedAt: .distantPast)
        other.title = "Alpha"
        other.lastPlayedAt = .now
        model.sort = .title
        XCTAssertEqual(model.visibleGames([game, other]).map(\.title), ["Alpha", "DUALDSTEST"])
        model.sort = .recentlyImported
        XCTAssertEqual(model.visibleGames([game, other]).map(\.title), ["DUALDSTEST", "Alpha"])
        model.sort = .lastPlayed
        XCTAssertEqual(model.visibleGames([game, other]).map(\.title), ["Alpha", "DUALDSTEST"])
    }

    func testFilesFolderImportMovesProcessedFilesAndKeepsInvalidOnes() async throws {
        let context = try makeContext()
        let model = GameLibraryViewModel(storage: storage)
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try fixtureURL(), to: docs.appendingPathComponent("mygame.nds"))
        try Data(repeating: 0x42, count: 0x4000).write(to: docs.appendingPathComponent("broken.nds"))
        try Data("notes".utf8).write(to: docs.appendingPathComponent("readme.txt"))

        await model.importFromDocumentsFolder(docs, into: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Game>()).map(\.gameCode), ["DDST"])
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: docs.appendingPathComponent("Imported/mygame.nds").path), "imported file moved aside")
        XCTAssertFalse(fm.fileExists(atPath: docs.appendingPathComponent("mygame.nds").path))
        XCTAssertTrue(fm.fileExists(atPath: docs.appendingPathComponent("broken.nds").path), "invalid file left for the user")
        XCTAssertTrue(fm.fileExists(atPath: docs.appendingPathComponent("readme.txt").path), "non-ROM files untouched")
        XCTAssertTrue(model.importReport?.contains("broken.nds") ?? false, "failure is reported")

        // Running again doesn't re-import anything.
        await model.importFromDocumentsFolder(docs, into: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Game>()).count, 1)
    }

    func testDeleteRemovesFilesAndEntry() async throws {
        let context = try makeContext()
        let model = GameLibraryViewModel(storage: storage)
        await model.importFiles([try fixtureURL()], into: context)
        let game = try XCTUnwrap(try context.fetch(FetchDescriptor<Game>()).first)
        let romURL = storage.romURL(fileName: game.fileName)
        try Data([1, 2, 3]).write(to: storage.saveURL(gameID: game.id))
        XCTAssertTrue(model.hasSaveData(game))

        try model.delete(game, context: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: romURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.saveURL(gameID: game.id).path))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Game>()).count, 0)
    }
}
