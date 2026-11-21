// DualDS — downloads a purchased FoldPlay Original and adds it to the library.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Order of checks, every time:
//   1. StoreKit: a verified (Apple-signed), unrevoked transaction for the game's product.
//   2. Only then: download the game's Apple-hosted asset pack.
//   3. The file's SHA-256 must match the game list before it is imported.

import BackgroundAssets
import CryptoKit
import Foundation
import SwiftData
import System

/// Where a purchased game's file comes from.
protocol GameFileSource: Sendable {
    /// Makes the game's file available locally and returns its URL. Reports progress 0...1.
    func fetch(_ game: OriginalGame, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    /// Frees whatever `fetch` kept around once the game is in the library.
    func cleanUp(_ game: OriginalGame) async
}

/// Apple-hosted asset packs (Background Assets). One pack per game; pack ID = game ID.
@available(iOS 26.4, *)
struct AppleAssetPackSource: GameFileSource {
    func fetch(_ game: OriginalGame, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let manager = AssetPackManager.shared
        let pack = try await manager.assetPack(withID: game.id)
        let watcher = Task {
            for await update in manager.statusUpdates(forAssetPackWithID: game.id) {
                switch update {
                case .downloading(_, let p): progress(p.fractionCompleted)
                case .finished: progress(1); return
                case .failed: return
                default: break
                }
            }
        }
        defer { watcher.cancel() }
        try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
        return try manager.url(for: FilePath(game.file))
    }

    func cleanUp(_ game: OriginalGame) async {
        // The ROM now lives in the library; don't keep a second copy in the asset pack store.
        try? await AssetPackManager.shared.remove(assetPackWithID: game.id)
    }
}

/// Reads games from a local folder. Debug builds only (tests and the Simulator).
struct LocalDirectorySource: GameFileSource {
    let directory: URL
    func fetch(_ game: OriginalGame, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let url = directory.appendingPathComponent((game.file as NSString).lastPathComponent)
        guard FileManager.default.fileExists(atPath: url.path) else { throw OriginalsInstaller.InstallError.downloadFailed("missing \(url.lastPathComponent)") }
        progress(1)
        return url
    }
    func cleanUp(_ game: OriginalGame) async {}
}

struct UnavailableSource: GameFileSource {
    func fetch(_ game: OriginalGame, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw OriginalsInstaller.InstallError.downloadFailed("Downloading games needs iOS 26.4 or later.")
    }
    func cleanUp(_ game: OriginalGame) async {}
}

@MainActor
enum OriginalsInstaller {
    enum Outcome: Equatable { case added, alreadyInLibrary }

    enum InstallError: LocalizedError, Equatable {
        case notPurchased, downloadFailed(String), corrupt
        var errorDescription: String? {
            switch self {
            case .notPurchased: "This game hasn't been bought with this Apple Account."
            case .downloadFailed(let why): "The download didn't finish: \(why)"
            case .corrupt: "The downloaded game didn't pass its integrity check. Please try again."
            }
        }
    }

    static func defaultSource() -> any GameFileSource {
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["DUALDS_ORIGINALS_DIR"], !dir.isEmpty {
            return LocalDirectorySource(directory: URL(fileURLWithPath: dir))
        }
        #endif
        if #available(iOS 26.4, *) { return AppleAssetPackSource() }
        return UnavailableSource()
    }

    /// Verifies the purchase, downloads the game, checks its hash and adds it to the library.
    static func install(_ game: OriginalGame, store: StoreService, source: any GameFileSource,
                        storage: GameStorage, context: ModelContext,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Outcome {
        guard await store.verifiedOwnership(of: game.productID) else { throw InstallError.notPurchased }
        if isInLibrary(game, games: (try? context.fetch(FetchDescriptor<Game>())) ?? []) { return .alreadyInLibrary }

        let file: URL
        do { file = try await source.fetch(game, progress: progress) }
        catch let e as InstallError { throw e }
        catch { throw InstallError.downloadFailed(error.localizedDescription) }

        let digest = try await Task.detached(priority: .userInitiated) { try Self.sha256Hex(of: file) }.value
        guard digest == game.sha256.lowercased() else { throw InstallError.corrupt }

        let existing = Set(((try? context.fetch(FetchDescriptor<Game>())) ?? []).map(\.contentHash))
        do {
            let imported = try await GameImportService(storage: storage).importROM(from: file, existingHashes: existing)
            let entry = Game(imported: imported)
            entry.title = game.title
            context.insert(entry)
            try context.save()
        } catch GameImportError.duplicate {
            return .alreadyInLibrary
        }
        await source.cleanUp(game)
        return .added
    }

    /// True if this game is already in the library (the importer stores the ROM's SHA-256).
    static func isInLibrary(_ game: OriginalGame, games: [Game]) -> Bool {
        games.contains { $0.contentHash.lowercased() == game.sha256.lowercased() }
    }

    nonisolated static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
