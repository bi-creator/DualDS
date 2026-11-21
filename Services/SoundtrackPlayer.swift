// DualDS — background music from the player's own Apple Music, via MusicKit.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// FoldPlay never stores or streams music itself: Apple Music plays the songs under the user's
// Apple Account (full songs need an Apple Music subscription). FoldPlay only keeps the list of
// songs the user picked, on this device.

import Foundation
@preconcurrency import MusicKit
import Observation

@MainActor
@Observable
final class SoundtrackPlayer {
    static let shared = SoundtrackPlayer()
    static let songsKey = "soundtrack.songs"

    /// Songs a player can add in one tap (title and artist, searched in Apple Music).
    nonisolated static let starterList: [String] = [
        "Sweet Dreams (Are Made of This) Eurythmics",
        "Eye of the Tiger Survivor",
        "Numb Linkin Park",
        "In the End Linkin Park",
        "Thunderstruck AC/DC",
        "The Final Countdown Europe",
        "Sweet Child O' Mine Guns N' Roses",
        "Where Is My Mind? Pixies",
    ]

    enum Access: Equatable { case unknown, notDetermined, denied, restricted, authorized }

    private(set) var access: Access = .unknown
    private(set) var canPlayCatalog = false
    private(set) var canSubscribe = false
    private(set) var songs: [Song] = []
    private(set) var results: [Song] = []
    private(set) var isSearching = false
    private(set) var isPlaying = false
    private(set) var nowPlaying: String?
    var shuffle = false { didSet { player.state.shuffleMode = shuffle ? .songs : .off } }
    var message: String?

    private let player = ApplicationMusicPlayer.shared

    private init() {
        songs = Self.loadSongs()
        access = Self.map(MusicAuthorization.currentStatus)
    }

    var hasQueue: Bool { player.queue.currentEntry != nil }

    // MARK: Access

    func refreshAccess() async {
        access = Self.map(MusicAuthorization.currentStatus)
        guard access == .authorized else { return }
        do {
            let subscription = try await MusicSubscription.current
            canPlayCatalog = subscription.canPlayCatalogContent
            canSubscribe = subscription.canBecomeSubscriber
        } catch {
            message = "Couldn't check Apple Music: \(error.localizedDescription)"
        }
    }

    func requestAccess() async {
        access = Self.map(await MusicAuthorization.request())
        await refreshAccess()
    }

    // MARK: Search and the saved list

    func search(_ term: String) async {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, access == .authorized else { results = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await Self.firstSongs(for: trimmed, limit: 15)
        } catch {
            results = []
            message = "Apple Music search failed: \(error.localizedDescription)"
        }
    }

    func add(_ song: Song) {
        guard !songs.contains(where: { $0.id == song.id }) else { return }
        songs.append(song)
        save()
    }

    func remove(at offsets: IndexSet) {
        songs.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        songs.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Searches each starter song and adds the best match. Returns how many were added.
    @discardableResult
    func addStarterList() async -> Int {
        guard access == .authorized else { return 0 }
        var added = 0
        for term in Self.starterList {
            if let song = try? await Self.firstSongs(for: term, limit: 1).first, !songs.contains(where: { $0.id == song.id }) {
                songs.append(song)
                added += 1
            }
        }
        save()
        return added
    }

    // MARK: Playback

    func play(startingAt song: Song? = nil) async {
        guard !songs.isEmpty else { return }
        guard canPlayCatalog else {
            message = "Playing full songs needs an Apple Music subscription."
            return
        }
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: song)
            player.state.shuffleMode = shuffle ? .songs : .off
            try await player.play()
            update()
        } catch {
            message = "Couldn't play: \(error.localizedDescription)"
        }
    }

    func togglePlayPause() async {
        if isPlaying {
            player.pause()
        } else if hasQueue {
            try? await player.play()
        } else {
            await play()
        }
        update()
    }

    func next() async {
        guard hasQueue else { return }
        try? await player.skipToNextEntry()
        update()
    }

    func stop() {
        player.stop()
        update()
    }

    /// Re-reads the player's state (call after actions and when the soundtrack screen appears).
    func update() {
        isPlaying = player.state.playbackStatus == .playing
        nowPlaying = player.queue.currentEntry.map { entry in
            [entry.title, entry.subtitle].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: Helpers

    private static func firstSongs(for term: String, limit: Int) async throws -> [Song] {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = limit
        let response = try await request.response()
        return Array(response.songs)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(songs) { UserDefaults.standard.set(data, forKey: Self.songsKey) }
    }

    private static func loadSongs() -> [Song] {
        guard let data = UserDefaults.standard.data(forKey: songsKey) else { return [] }
        return (try? JSONDecoder().decode([Song].self, from: data)) ?? []
    }

    private static func map(_ status: MusicAuthorization.Status) -> Access {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }
}
