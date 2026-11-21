// DualDS — pick and control background music from Apple Music.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import MusicKit
import SwiftUI

struct SoundtrackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = SoundtrackPlayer.shared
    @State private var query = ""
    @State private var showingOffer = false
    @State private var addingStarters = false
    @AppStorage(AudioSessionPolicy.mixKey) private var mixWithOthers = true

    var body: some View {
        NavigationStack {
            List {
                otherAppsSection
                switch player.access {
                case .authorized: authorizedSections
                case .denied, .restricted: deniedSection
                case .notDetermined, .unknown: connectSection
                }
            }
            .navigationTitle("Soundtrack")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search Apple Music")
            .onSubmit(of: .search) { Task { await player.search(query) } }
            .onChange(of: query) { _, q in if q.isEmpty { Task { await player.search("") } } }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await player.refreshAccess(); player.update() }
            .musicSubscriptionOffer(isPresented: $showingOffer)
            .alert("Soundtrack", isPresented: Binding(get: { player.message != nil }, set: { if !$0 { player.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(player.message ?? "") }
        }
        .accessibilityIdentifier("soundtrack.view")
    }

    private var otherAppsSection: some View {
        Section {
            Toggle("Keep other music playing", isOn: $mixWithOthers)
                .accessibilityIdentifier("soundtrack.mixToggle")
        } footer: {
            Text("Start a song in Spotify, YouTube Music, Apple Music or any music app, then open your game: it keeps playing under the game sound. Turn the game volume down in Display if you want the music louder.")
        }
    }

    private var connectSection: some View {
        Section {
            Button { Task { await player.requestAccess() } } label: {
                Label("Connect Apple Music", systemImage: "music.note")
            }
            .accessibilityIdentifier("soundtrack.connect")
        } header: {
            Text("Apple Music in FoldPlay")
        } footer: {
            Text("Build a playlist here and it plays while you game. Full songs need an Apple Music subscription. FoldPlay only keeps your song list on this device.")
        }
    }

    private var deniedSection: some View {
        Section("Apple Music in FoldPlay") {
            Text("FoldPlay doesn't have access to Apple Music. You can allow it in Settings, Apps, FoldPlay.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var authorizedSections: some View {
        if !player.canPlayCatalog && player.canSubscribe {
            Section {
                Button("Get Apple Music") { showingOffer = true }
            } footer: { Text("You can build your list now; playing full songs needs a subscription.") }
        }
        if !player.results.isEmpty || player.isSearching {
            Section("Results") {
                if player.isSearching { ProgressView() }
                ForEach(player.results, id: \.id) { song in
                    HStack {
                        SongRow(song: song)
                        Spacer()
                        let added = player.songs.contains { $0.id == song.id }
                        Button { player.add(song) } label: {
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                        }
                        .disabled(added)
                        .accessibilityLabel(added ? "Added" : "Add \(song.title)")
                    }
                }
            }
        }
        Section {
            if let now = player.nowPlaying {
                HStack {
                    Image(systemName: player.isPlaying ? "waveform" : "pause")
                    Text(now).lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                Button { Task { await player.togglePlayPause() } } label: {
                    Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(player.songs.isEmpty)
                .accessibilityIdentifier("soundtrack.playPause")
                Button { Task { await player.next() } } label: { Label("Next", systemImage: "forward.fill") }
                    .disabled(!player.hasQueue)
                Spacer()
                Toggle(isOn: $player.shuffle) { Image(systemName: "shuffle") }
                    .toggleStyle(.button)
                    .accessibilityLabel("Shuffle")
            }
            .buttonStyle(.borderless)
            ForEach(player.songs, id: \.id) { song in
                Button { Task { await player.play(startingAt: song) } } label: { SongRow(song: song) }
                    .buttonStyle(.plain)
            }
            .onDelete { player.remove(at: $0) }
            .onMove { player.move(from: $0, to: $1) }
            if player.songs.isEmpty {
                Button {
                    addingStarters = true
                    Task { await player.addStarterList(); addingStarters = false }
                } label: {
                    if addingStarters { ProgressView() } else { Label("Add the rock classics starter list", systemImage: "guitars") }
                }
                .disabled(addingStarters)
                .accessibilityIdentifier("soundtrack.starters")
            }
        } header: {
            Text("Your Soundtrack")
        } footer: {
            Text("Search above to add songs. Swipe a song to remove it.")
        }
    }
}

private struct SongRow: View {
    let song: Song
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 40, height: 40).clipShape(.rect(cornerRadius: 6))
            } else {
                Image(systemName: "music.note").frame(width: 40, height: 40)
            }
            VStack(alignment: .leading) {
                Text(song.title).lineLimit(1)
                Text(song.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
