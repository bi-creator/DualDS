// DualDS — game library screen.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftData
import SwiftUI

struct GameLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var games: [Game]
    @State var model: GameLibraryViewModel

    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var selected: Game?
    @State private var pendingDelete: Game?
    @State private var pendingPlay: Game?
    @State private var playing: Game?
    @State private var errorMessage: String?
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.classic

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .background { ThemeBackdrop(theme: theme) }
                .navigationTitle("Library")
                .searchable(text: $model.searchText, prompt: "Search title or game code")
                .toolbar { toolbar }
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.ndsROM],
                              allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): Task { await model.importFiles(urls, into: context) }
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                }
                .alert("Import", isPresented: present($model.importReport)) {
                    Button("OK", role: .cancel) {}
                } message: { Text(model.importReport ?? "") }
                .alert("Error", isPresented: present($errorMessage)) {
                    Button("OK", role: .cancel) {}
                } message: { Text(errorMessage ?? "") }
                .confirmationDialog("Delete \(pendingDelete?.title ?? "game")?", isPresented: present($pendingDelete),
                                    titleVisibility: .visible) {
                    Button("Delete Game, Saves and States", role: .destructive) {
                        if let game = pendingDelete { delete(game) }
                    }
                } message: {
                    Text("This removes the game file \(AppConfiguration.appName) copied, its save data and save states from this device.")
                }
                .sheet(item: $selected, onDismiss: {
                    // Start the game only after the details sheet has fully gone away.
                    if let game = pendingPlay { pendingPlay = nil; playing = game }
                }) { game in
                    GameDetailView(game: game, model: model, onPlay: { pendingPlay = game }, onDelete: { pendingDelete = game })
                }
                .fullScreenCover(item: $playing) { game in
                    EmulatorView(game: game, storage: model.storage)
                }
                .sheet(isPresented: $showingSettings) { SettingsView() }
                .overlay {
                    if model.isImporting {
                        ProgressView("Importing…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if games.isEmpty {
            emptyState
        } else {
            let visible = model.visibleGames(games)
            ScrollView {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: model.searchText).padding(.top, 40)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(visible) { game in
                        Button {
                            InterfaceSound.shared.play(theme.sound)
                            selected = game
                        } label: {
                            GameCardView(game: game, artworkURL: model.artworkURL(game))
                                .padding(theme == .classic ? 0 : 10)
                                .background(theme == .classic ? Color.clear : theme.cardFill, in: .rect(cornerRadius: 20, style: .continuous))
                        }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library.game.\(game.gameCode)")
                            .contextMenu {
                                Button("Play", systemImage: "play.fill") { playing = game }
                                Button("Details", systemImage: "info.circle") { selected = game }
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = game }
                            }
                    }
                }
                .padding()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 32) {
            BrandHeader().padding(.top, 24)
            ContentUnavailableView {
                Label("No Games Yet", systemImage: "square.stack")
            } description: {
                Text("Import a Nintendo DS game (.nds) that you legally own. \(AppConfiguration.appName) does not include any games.")
            } actions: {
                Button { showingImporter = true } label: { Label("Import Game", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("library.import")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            .accessibilityIdentifier("library.sort")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingImporter = true } label: { Label("Import", systemImage: "plus") }
                .accessibilityIdentifier("library.toolbarImport")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                .accessibilityIdentifier("library.settings")
        }
    }

    private func delete(_ game: Game) {
        do {
            if selected?.id == game.id { selected = nil }
            try model.delete(game, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingDelete = nil
    }

    private func present<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
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
