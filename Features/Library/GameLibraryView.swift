// DualDS — game library screen (Phase 1 shell; import and listing arrive in Phase 3).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

struct GameLibraryView: View {
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                BrandHeader()
                    .padding(.top, 24)

                ContentUnavailableView {
                    Label("No Games Yet", systemImage: "square.stack")
                } description: {
                    Text("Import a Nintendo DS game (.nds) that you legally own. DualDS does not include any games.")
                } actions: {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Game", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("library.import")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("library.settings")
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.ndsROM]) { result in
                switch result {
                case .success(let url):
                    // Phase 3 implements validated, security-scoped import into app storage.
                    notice = "Selected \(url.lastPathComponent). Importing games is not implemented yet."
                case .failure(let error):
                    notice = error.localizedDescription
                }
            }
            .alert("Import", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

/// The DualDS wordmark with its two-screen glyph.
struct BrandHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            DualScreenGlyph()
                .frame(width: 56, height: 72)
                .accessibilityHidden(true)
            Text(AppConfiguration.appName)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .accessibilityIdentifier("brand.title")
            Text("Nintendo DS emulation for iPhone and iPad")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct DualScreenGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let gap = geo.size.height * 0.08
            let screenHeight = (geo.size.height - gap) / 2
            VStack(spacing: gap) {
                RoundedRectangle(cornerRadius: screenHeight * 0.18, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(height: screenHeight)
                RoundedRectangle(cornerRadius: screenHeight * 0.18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(height: screenHeight)
            }
        }
    }
}

#Preview {
    GameLibraryView()
}
