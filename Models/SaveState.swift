// DualDS — one emulator save state (full console snapshot), distinct from the game's own battery save.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import Foundation
import SwiftData

@Model
final class SaveState {
    @Attribute(.unique) var id: UUID
    var gameID: UUID
    /// 0 = Quick Save, 1…SaveStateStore.manualSlots = manual slots.
    var slot: Int
    var name: String
    var createdAt: Date
    /// File inside GameStorage.statesDirectory(gameID:).
    var fileName: String
    /// melonDS version that wrote the state; states from another version may not load.
    var coreVersion: String
    /// Both DS screens (256 × 384) at the moment of saving.
    @Attribute(.externalStorage) var screenshotPNG: Data?

    init(gameID: UUID, slot: Int, name: String, fileName: String, coreVersion: String, screenshotPNG: Data?) {
        self.id = UUID()
        self.gameID = gameID
        self.slot = slot
        self.name = name
        self.createdAt = .now
        self.fileName = fileName
        self.coreVersion = coreVersion
        self.screenshotPNG = screenshotPNG
    }
}
