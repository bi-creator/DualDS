// DualDS — persisted library entry for one imported game.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import Foundation
import SwiftData

@Model
final class Game {
    @Attribute(.unique) var id: UUID
    /// SHA-256 of the ROM file, used to prevent duplicate imports.
    @Attribute(.unique) var contentHash: String
    /// Display title: the English banner name if present, else the header title.
    var title: String
    var subtitle: String?
    var publisher: String?
    var headerTitle: String
    var gameCode: String
    var makerCode: String
    /// File name inside GameStorage.games.
    var fileName: String
    var fileSize: Int64
    var importedAt: Date
    var lastPlayedAt: Date?
    var playTime: TimeInterval
    /// The game's own 32×32 banner icon, extracted from the user's ROM.
    @Attribute(.externalStorage) var iconPNG: Data?
    var hasCustomArtwork: Bool

    init(id: UUID = UUID(), imported rom: ImportedROM, importedAt: Date = .now) {
        self.id = id
        self.contentHash = rom.contentHash
        self.title = rom.displayTitle
        self.subtitle = rom.banner?.subtitle
        self.publisher = rom.banner?.publisher
        self.headerTitle = rom.header.title
        self.gameCode = rom.header.gameCode
        self.makerCode = rom.header.makerCode
        self.fileName = rom.fileName
        self.fileSize = rom.fileSize
        self.importedAt = importedAt
        self.lastPlayedAt = nil
        self.playTime = 0
        self.iconPNG = rom.banner?.iconPNG
        self.hasCustomArtwork = false
    }
}
