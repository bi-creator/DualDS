// DualDS — library state and actions (import, delete, search, sort).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import Foundation
import Observation
import SwiftData

enum LibrarySort: String, CaseIterable, Identifiable {
    case title = "Title", lastPlayed = "Last Played", recentlyImported = "Recently Imported"
    var id: String { rawValue }
}

@MainActor
@Observable
final class GameLibraryViewModel {
    let storage: GameStorage
    private let importer: GameImportService

    var searchText = ""
    var sort: LibrarySort = .title
    var isImporting = false
    /// Human-readable outcome of the last import batch, shown as an alert.
    var importReport: String?

    init(storage: GameStorage) {
        self.storage = storage
        self.importer = GameImportService(storage: storage)
    }

    func visibleGames(_ all: [Game]) -> [Game] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? all : all.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.gameCode.localizedCaseInsensitiveContains(query)
        }
        switch sort {
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .lastPlayed:
            return filtered.sorted { ($0.lastPlayedAt ?? .distantPast, $0.title) > ($1.lastPlayedAt ?? .distantPast, $1.title) }
        case .recentlyImported:
            return filtered.sorted { $0.importedAt > $1.importedAt }
        }
    }

    enum ImportOutcome: Equatable { case imported, duplicate, failed }

    /// Imports each URL in turn; a failure on one file does not stop the others.
    @discardableResult
    func importFiles(_ urls: [URL], into context: ModelContext) async -> [URL: ImportOutcome] {
        isImporting = true
        defer { isImporting = false }
        var imported: [String] = []
        var failures: [String] = []
        var outcomes: [URL: ImportOutcome] = [:]
        for url in urls {
            let existing = Set(((try? context.fetch(FetchDescriptor<Game>())) ?? []).map(\.contentHash))
            do {
                let rom = try await importer.importROM(from: url, existingHashes: existing)
                context.insert(Game(imported: rom))
                try context.save()
                imported.append(rom.displayTitle)
                outcomes[url] = .imported
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                outcomes[url] = (error as? GameImportError) == .duplicate ? .duplicate : .failed
            }
        }
        importReport = Self.report(imported: imported, failures: failures)
        return outcomes
    }

    /// The app's Documents folder, shown in the Files app as "On My iPhone › DualDS".
    /// `.nds` files placed there are imported automatically; once imported (or found to be
    /// duplicates) they move to the "Imported" subfolder so they are not processed twice.
    /// Files that fail validation stay where they are, and the reason is shown.
    func importFromDocumentsFolder(_ documents: URL, into context: ModelContext) async {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) else { return }
        let roms = entries.filter { $0.pathExtension.lowercased() == "nds" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !roms.isEmpty else { return }
        let outcomes = await importFiles(roms, into: context)
        let done = documents.appendingPathComponent("Imported", isDirectory: true)
        for (url, outcome) in outcomes where outcome != .failed {
            try? fm.createDirectory(at: done, withIntermediateDirectories: true)
            var target = done.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                target = done.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).nds")
            }
            try? fm.moveItem(at: url, to: target)
        }
    }

    static func report(imported: [String], failures: [String]) -> String? {
        var parts: [String] = []
        if !imported.isEmpty { parts.append("Imported \(imported.joined(separator: ", ")).") }
        parts.append(contentsOf: failures)
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    func hasSaveData(_ game: Game) -> Bool {
        FileManager.default.fileExists(atPath: storage.saveURL(gameID: game.id).path)
    }

    func artworkURL(_ game: Game) -> URL? {
        game.hasCustomArtwork ? storage.artworkURL(gameID: game.id) : nil
    }

    func setCustomArtwork(_ pngData: Data?, for game: Game, context: ModelContext) throws {
        let url = storage.artworkURL(gameID: game.id)
        if let pngData {
            try storage.createDirectories()
            try pngData.write(to: url, options: .atomic)
            game.hasCustomArtwork = true
        } else {
            try? FileManager.default.removeItem(at: url)
            game.hasCustomArtwork = false
        }
        try context.save()
    }

    /// Removes the ROM copy, its battery save, save states and artwork, then the library entry.
    func delete(_ game: Game, context: ModelContext) throws {
        let fm = FileManager.default
        for url in [storage.romURL(fileName: game.fileName), storage.saveURL(gameID: game.id),
                    storage.statesDirectory(gameID: game.id), storage.artworkURL(gameID: game.id)]
        where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        for state in SaveStateStore.states(for: game.id, context: context) {
            context.delete(state)
        }
        context.delete(game)
        try context.save()
    }
}
