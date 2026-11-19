// DualDS — validated import of user-selected .nds files into app storage.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import CryptoKit
import Foundation

/// Result of a successful import; Sendable so it can cross from the import task to the main actor.
struct ImportedROM: Sendable {
    var header: ROMHeader
    var banner: ROMBanner?
    var contentHash: String
    var fileName: String
    var fileSize: Int64

    var displayTitle: String {
        if let name = banner?.name, !name.isEmpty { return name }
        return header.title.isEmpty ? header.gameCode : header.title
    }
}

enum GameImportError: LocalizedError, Equatable {
    case unreadable(String)
    case notANintendoDSGame(String)
    case dsiExclusive
    case duplicate
    case insufficientStorage(needed: Int64, available: Int64)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let why): "The file could not be read. \(why)"
        case .notANintendoDSGame(let why): "This is not a valid Nintendo DS game file (\(why))."
        case .dsiExclusive: "Nintendo DSi-exclusive games are not supported."
        case .duplicate: "This game is already in your library."
        case .insufficientStorage(let needed, let available):
            "Not enough free space: \(Self.bytes(needed)) needed, \(Self.bytes(available)) available."
        case .copyFailed(let why): "The game could not be copied into DualDS. \(why)"
        }
    }

    private static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

struct GameImportService: Sendable {
    let storage: GameStorage

    /// Validates `source`, rejects duplicates (by SHA-256) and copies it into storage.
    /// Runs entirely off the main thread; touches no SwiftData state.
    func importROM(from source: URL, existingHashes: Set<String>) async throws -> ImportedROM {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: source) }
        catch { throw GameImportError.unreadable(error.localizedDescription) }
        defer { try? handle.close() }

        let fileSize: Int
        let headerData: Data
        do {
            fileSize = Int(try handle.seekToEnd())
            try handle.seek(toOffset: 0)
            headerData = try handle.read(upToCount: ROMHeader.headerSize) ?? Data()
        } catch { throw GameImportError.unreadable(error.localizedDescription) }

        let header: ROMHeader
        do { header = try ROMHeader.parse(header: headerData, fileSize: fileSize) }
        catch ROMHeader.ParseError.dsiExclusive { throw GameImportError.dsiExclusive }
        catch let e as ROMHeader.ParseError { throw GameImportError.notANintendoDSGame(Self.describe(e)) }

        var banner: ROMBanner?
        if header.bannerOffset >= 0x200, Int(header.bannerOffset) + ROMBanner.size <= fileSize {
            try? handle.seek(toOffset: UInt64(header.bannerOffset))
            if let data = try? handle.read(upToCount: ROMBanner.size) { banner = ROMBanner.parse(data) }
        }

        let hash: String
        do { hash = try Self.sha256(of: handle) }
        catch { throw GameImportError.unreadable(error.localizedDescription) }
        guard !existingHashes.contains(hash) else { throw GameImportError.duplicate }

        try storage.createDirectories()
        let available = Self.availableCapacity(at: storage.root)
        let margin: Int64 = 50 * 1024 * 1024
        if let available, available < Int64(fileSize) + margin {
            throw GameImportError.insufficientStorage(needed: Int64(fileSize) + margin, available: available)
        }

        let fileName = "\(hash.prefix(32)).nds"
        let destination = storage.romURL(fileName: fileName)
        let temp = storage.games.appendingPathComponent(".import-\(UUID().uuidString)")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination) // stale copy left by a deleted entry
            }
            try FileManager.default.copyItem(at: source, to: temp)
            try FileManager.default.moveItem(at: temp, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw GameImportError.copyFailed(error.localizedDescription)
        }
        return ImportedROM(header: header, banner: banner, contentHash: hash, fileName: fileName, fileSize: Int64(fileSize))
    }

    static func describe(_ e: ROMHeader.ParseError) -> String {
        switch e {
        case .tooSmall: "file too small"
        case .tooLarge: "file larger than 512 MB"
        case .checksumMismatch: "header checksum mismatch; the file may be corrupted"
        case .badCodeSection(let which): "\(which) code section lies outside the file"
        case .dsiExclusive: "DSi-exclusive"
        }
    }

    static func sha256(of handle: FileHandle) throws -> String {
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func availableCapacity(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
