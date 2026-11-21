// DualDS — FoldPlay Originals: games made for FoldPlay, sold as in-app purchases.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// The game files are separate works by FoldPlay Games (not part of this GPL program). Release
// builds carry them in the app bundle as lightly scrambled packages (Build/Originals/*.fpg, made by
// Scripts/package-originals.py); a purchase unpacks one into the player's library. The scrambling
// only stops the file being copied out of the app by accident: it is not encryption.

import CryptoKit
import Foundation

struct OriginalGame: Identifiable, Hashable, Sendable {
    let id: String
    let productID: String
    let title: String
    let tagline: String
    let details: String
    /// Package file name in the app bundle's Originals folder.
    let package: String
    /// Image in the asset catalog.
    let artwork: String
}

enum OriginalsCatalog {
    static let backAlleyBrawl = OriginalGame(
        id: "back-alley-brawl",
        productID: "com.bicreator.dualds.backalleybrawl",
        title: "Back Alley Brawl",
        tagline: "Street brawler · 3 stages · 3 bosses",
        details: "Fight through the night street, the harbor docks and the neon rooftops. "
            + "Punch combos, kicks, jump kicks and a spin special; smash trash cans for food. "
            + "Plays on both screens, made for the iPhone fold.",
        package: "back_alley_brawl.fpg",
        artwork: "OriginalBackAlleyBrawl")

    static let all: [OriginalGame] = [backAlleyBrawl]

    static func game(forProduct id: String) -> OriginalGame? { all.first { $0.productID == id } }
}

enum OriginalPackage {
    enum Failure: LocalizedError {
        case missing, corrupt
        var errorDescription: String? {
            switch self {
            case .missing: "This build of FoldPlay doesn't include the game file. Please update the app."
            case .corrupt: "The game file in this build is damaged. Please reinstall FoldPlay."
            }
        }
    }

    static let magic = Data("FPG1".utf8)
    private static let key = Data("FoldPlay Originals v1".utf8)

    static func url(for game: OriginalGame, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: game.package, withExtension: nil, subdirectory: "Originals")
            ?? bundle.url(forResource: game.package, withExtension: nil)
    }

    /// Unscrambles a package: "FPG1", 16-byte nonce, then the ROM XORed with SHA-256(key|nonce|counter).
    static func decode(_ data: Data) throws -> Data {
        guard data.count > 20, data.prefix(4) == magic else { throw Failure.corrupt }
        let nonce = data.subdata(in: 4..<20)
        var out = Data(data.dropFirst(20))
        out.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            var counter: UInt64 = 0
            var offset = 0
            while offset < buf.count {
                var block = key
                block.append(nonce)
                withUnsafeBytes(of: counter.littleEndian) { block.append(contentsOf: $0) }
                let stream = Array(SHA256.hash(data: block))
                let n = min(stream.count, buf.count - offset)
                for i in 0..<n { buf[offset + i] ^= stream[i] }
                offset += n
                counter += 1
            }
        }
        return out
    }

    /// Lowercase hex of the package nonce (= the first 16 bytes of the ROM's SHA-256).
    static func hashPrefix(for game: OriginalGame, in bundle: Bundle = .main) -> String? {
        guard let url = url(for: game, in: bundle), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 20), head.count == 20, head.prefix(4) == magic else { return nil }
        return head.dropFirst(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes the unscrambled ROM to a temporary file for the importer. Caller deletes it.
    static func unpack(_ game: OriginalGame, bundle: Bundle = .main) throws -> URL {
        guard let url = url(for: game, in: bundle), let data = try? Data(contentsOf: url) else { throw Failure.missing }
        let rom = try decode(data)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(game.id)-\(UUID().uuidString).nds")
        try rom.write(to: out, options: .atomic)
        return out
    }
}
