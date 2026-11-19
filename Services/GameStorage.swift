// DualDS — on-disk layout for imported games and their data.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import Foundation

/// <root>/Games/<hash>.nds   imported ROM copies (only the user's own files)
/// <root>/Saves/<id>.sav     battery saves (native game saves)
/// <root>/States/<id>/       emulator save states (Phase 7)
/// <root>/Artwork/<id>.png   user-chosen custom artwork
struct GameStorage: Sendable {
    let root: URL

    var games: URL { root.appendingPathComponent("Games", isDirectory: true) }
    var saves: URL { root.appendingPathComponent("Saves", isDirectory: true) }
    var states: URL { root.appendingPathComponent("States", isDirectory: true) }
    var artwork: URL { root.appendingPathComponent("Artwork", isDirectory: true) }

    func romURL(fileName: String) -> URL { games.appendingPathComponent(fileName) }
    func saveURL(gameID: UUID) -> URL { saves.appendingPathComponent("\(gameID.uuidString).sav") }
    func statesDirectory(gameID: UUID) -> URL { states.appendingPathComponent(gameID.uuidString, isDirectory: true) }
    func artworkURL(gameID: UUID) -> URL { artwork.appendingPathComponent("\(gameID.uuidString).png") }

    func createDirectories() throws {
        for dir in [games, saves, states, artwork] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Application Support/DualDS. DEBUG builds honour DUALDS_UITEST_FRESH=1 (new empty temp root)
    /// and DUALDS_STORAGE_ROOT so UI tests start clean.
    static func appDefault() -> GameStorage {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DUALDS_UITEST_FRESH"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DualDS-UITest-\(UUID().uuidString)")
            return GameStorage(root: dir)
        }
        if let override = ProcessInfo.processInfo.environment["DUALDS_STORAGE_ROOT"], !override.isEmpty {
            return GameStorage(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return GameStorage(root: base.appendingPathComponent("DualDS", isDirectory: true))
    }
}
