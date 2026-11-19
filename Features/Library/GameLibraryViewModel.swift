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

    /// Imports each URL in turn; a failure on one file does not stop the others.
    func importFiles(_ urls: [URL], into context: ModelContext) async {
        isImporting = true
        defer { isImporting = false }
        var imported: [String] = []
        var failures: [String] = []
        for url in urls {
            let existing = Set(((try? context.fetch(FetchDescriptor<Game>())) ?? []).map(\.contentHash))
            do {
                let rom = try await importer.importROM(from: url, existingHashes: existing)
                context.insert(Game(imported: rom))
                try context.save()
                imported.append(rom.displayTitle)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        importReport = Self.report(imported: imported, failures: failures)
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
        context.delete(game)
        try context.save()
    }
}
