// DualDS — creating, listing, loading, renaming and deleting save states.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import Foundation
import SwiftData

enum SaveStateError: LocalizedError, Equatable {
    case missingFile
    case wrongGame

    var errorDescription: String? {
        switch self {
        case .missingFile: "This save state's file is missing; it may have been deleted."
        case .wrongGame: "This save state belongs to a different game."
        }
    }
}

@MainActor
struct SaveStateStore {
    static let quickSlot = 0
    static let manualSlots = 8

    let storage: GameStorage

    static func defaultName(slot: Int) -> String { slot == quickSlot ? "Quick Save" : "Slot \(slot)" }

    /// At most `manualSlots + 1` per game, so filtering in memory is cheap and avoids SwiftData
    /// key-path predicates (not Sendable under strict concurrency checking).
    func states(for game: Game, context: ModelContext) -> [SaveState] {
        Self.states(for: game.id, context: context)
    }

    static func states(for gameID: UUID, context: ModelContext) -> [SaveState] {
        let all = (try? context.fetch(FetchDescriptor<SaveState>())) ?? []
        return all.filter { $0.gameID == gameID }.sorted { $0.slot < $1.slot }
    }

    func state(for game: Game, slot: Int, context: ModelContext) -> SaveState? {
        states(for: game, context: context).first { $0.slot == slot }
    }

    func url(for state: SaveState) -> URL {
        storage.statesDirectory(gameID: state.gameID).appendingPathComponent(state.fileName)
    }

    /// Saves the running console into `slot`, replacing what was there only once the new state
    /// has been written successfully.
    @discardableResult
    func save(core: DSCore, game: Game, slot: Int, context: ModelContext) async throws -> SaveState {
        let dir = storage.statesDirectory(gameID: game.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = "slot\(slot)-\(UUID().uuidString.prefix(8)).mln"
        let url = dir.appendingPathComponent(fileName)
        let screenshot = Self.screenshotPNG(core)
        try await Task.detached(priority: .userInitiated) { try core.saveState(to: url) }.value

        let previous = state(for: game, slot: slot, context: context)
        let record = SaveState(gameID: game.id, slot: slot, name: previous?.name ?? Self.defaultName(slot: slot),
                               fileName: fileName, coreVersion: DSCore.melonDSVersion, screenshotPNG: screenshot)
        if let previous {
            try? FileManager.default.removeItem(at: self.url(for: previous))
            context.delete(previous)
        }
        context.insert(record)
        try context.save()
        return record
    }

    /// Restores a state into the running console. On any failure the console keeps its current state.
    func load(_ state: SaveState, into core: DSCore, game: Game) async throws {
        guard state.gameID == game.id else { throw SaveStateError.wrongGame }
        let url = url(for: state)
        guard FileManager.default.fileExists(atPath: url.path) else { throw SaveStateError.missingFile }
        try await Task.detached(priority: .userInitiated) { try core.loadState(from: url) }.value
    }

    func rename(_ state: SaveState, to name: String, context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.name = trimmed.isEmpty ? Self.defaultName(slot: state.slot) : String(trimmed.prefix(40))
        try context.save()
    }

    func delete(_ state: SaveState, context: ModelContext) throws {
        let url = url(for: state)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        context.delete(state)
        try context.save()
    }

    /// Both screens stacked (256 × 384) as PNG; nil if no frame has been produced yet.
    static func screenshotPNG(_ core: DSCore) -> Data? {
        let w = DSCore.screenWidth, h = DSCore.screenHeight, n = w * h
        var bgra = [UInt32](repeating: 0, count: n * 2)
        let ok = bgra.withUnsafeMutableBufferPointer { buf in
            core.copyFramebuffer(top: buf.baseAddress, bottom: buf.baseAddress! + n, frameNumber: nil)
        }
        guard ok else { return nil }
        let rgba = bgra.map { p -> UInt32 in
            let r = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF
            return r | g << 8 | b << 16 | 0xFF00_0000
        }
        return ROMBanner.pngData(rgba: rgba, width: w, height: h * 2)
    }
}
