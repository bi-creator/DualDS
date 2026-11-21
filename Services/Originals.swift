// DualDS — FoldPlay Originals: games made for FoldPlay, sold as in-app purchases.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// The list of games lives at AppConfiguration.originalsCatalogURL (a static JSON file on the
// FoldPlay website), so new games appear without an app update. Each game is an Apple-hosted
// asset pack whose ID is the game's `id`; it is downloaded only after StoreKit confirms that the
// player owns the game (see OriginalsInstaller). The game files are separate works by FoldPlay
// Games, not part of this GPL program.

import Foundation
import Observation

struct OriginalGame: Codable, Identifiable, Hashable, Sendable {
    /// Also the Apple-hosted asset pack ID.
    let id: String
    let productID: String
    let title: String
    let tagline: String
    let details: String
    /// Path of the ROM inside the asset pack (asset packs share one namespace), e.g. "games/x.nds".
    let file: String
    /// Lowercase hex SHA-256 of the ROM; checked before the game is added to the library.
    let sha256: String
    let size: Int64
    let artwork: URL?
}

struct OriginalsCatalogFile: Codable, Sendable {
    let version: Int
    let games: [OriginalGame]
}

@MainActor
@Observable
final class OriginalsCatalog {
    static let shared = OriginalsCatalog()

    private(set) var games: [OriginalGame] = []
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private let cacheURL: URL
    private let remoteURL: URL

    init(remoteURL: URL = AppConfiguration.originalsCatalogURL,
         cacheURL: URL = OriginalsCatalog.defaultCacheURL,
         bundle: Bundle = .main) {
        self.remoteURL = remoteURL
        self.cacheURL = cacheURL
        // Last good copy from the website, else the list shipped with this build.
        if let data = try? Data(contentsOf: cacheURL), let games = try? Self.decode(data) {
            self.games = games
        } else if let url = bundle.url(forResource: "originals-fallback", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let games = try? Self.decode(data) {
            self.games = games
        }
    }

    nonisolated static var defaultCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("originals-catalog.json")
    }

    func game(id: String) -> OriginalGame? { games.first { $0.id == id } }
    func game(forProduct productID: String) -> OriginalGame? { games.first { $0.productID == productID } }

    /// Downloads the current list from the website. Keeps the old list if that fails.
    func refresh(session: URLSession = .shared) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: remoteURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let fresh = try Self.decode(data)
            games = fresh
            lastError = nil
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            lastError = "Couldn't update the game list: \(error.localizedDescription)"
        }
    }

    enum CatalogError: LocalizedError {
        case unsupportedVersion(Int), invalid(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v): "This game list needs a newer FoldPlay (format \(v))."
            case .invalid(let why): "The game list is invalid: \(why)"
            }
        }
    }

    /// Parses and sanity-checks a catalog file.
    nonisolated static func decode(_ data: Data) throws -> [OriginalGame] {
        let file = try JSONDecoder().decode(OriginalsCatalogFile.self, from: data)
        guard file.version == 1 else { throw CatalogError.unsupportedVersion(file.version) }
        var ids = Set<String>(), products = Set<String>()
        for g in file.games {
            guard ids.insert(g.id).inserted else { throw CatalogError.invalid("duplicate id \(g.id)") }
            guard products.insert(g.productID).inserted else { throw CatalogError.invalid("duplicate product \(g.productID)") }
            guard g.sha256.count == 64, g.sha256.allSatisfy(\.isHexDigit) else { throw CatalogError.invalid("bad sha256 for \(g.id)") }
            guard !g.file.hasPrefix("/"), !g.file.contains("..") else { throw CatalogError.invalid("bad file path for \(g.id)") }
        }
        return file.games
    }
}
