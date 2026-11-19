// DualDS — Nintendo DS emulator for iOS, built on melonDS.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

@main
struct DualDSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Top-level navigation. Phase 9 replaces this with the full tab layout
/// (Library, Recently Played, Save States, Settings, About).
struct RootView: View {
    var body: some View {
        GameLibraryView()
    }
}
