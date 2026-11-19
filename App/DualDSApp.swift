// DualDS — Nintendo DS emulator for iOS, built on melonDS.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftData
import SwiftUI

@main
struct DualDSApp: App {
    private let storage = GameStorage.appDefault()
    private let container: ModelContainer

    init() {
        do {
            let config = ModelConfiguration(url: storage.root.appendingPathComponent("Library.store"))
            try storage.createDirectories()
            container = try ModelContainer(for: Game.self, configurations: config)
        } catch {
            // Without its library database the app cannot work; fail loudly rather than run degraded.
            fatalError("DualDS could not open its library database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storage: storage)
        }
        .modelContainer(container)
    }
}

/// Top-level navigation. Phase 9 replaces this with the full tab layout
/// (Library, Recently Played, Save States, Settings, About).
struct RootView: View {
    let storage: GameStorage
    @Environment(\.modelContext) private var context
    @State private var model: GameLibraryViewModel

    init(storage: GameStorage) {
        self.storage = storage
        _model = State(initialValue: GameLibraryViewModel(storage: storage))
    }

    var body: some View {
        GameLibraryView(model: model)
            .task { await importForUITestsIfRequested() }
    }

    /// DEBUG-only hook so UI tests can exercise the library without driving the system file picker.
    private func importForUITestsIfRequested() async {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DUALDS_UITEST_IMPORT"], !path.isEmpty {
            await model.importFiles([URL(fileURLWithPath: path)], into: context)
        }
        #endif
    }
}
