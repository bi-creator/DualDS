// DualDS — one play session: loads the game into the core, runs it, tracks play time.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class EmulatorViewModel {
    enum Phase: Equatable { case loading, running, paused, failed(String) }

    let core = DSCore()
    let audio: AudioRenderer
    /// Set if audio could not start; the game keeps running silently.
    private(set) var audioError: String?
    let game: Game
    let storage: GameStorage
    let saveStates: SaveStateStore
    /// Short confirmation shown over the game ("Saved to Slot 2").
    private(set) var toast: String?
    /// Error from the last save-state operation, shown as an alert.
    var stateError: String?
    private(set) var isWorkingOnState = false
    private(set) var phase: Phase = .loading
    private(set) var isFastForward = false
    /// Paused by the user (as opposed to by the app going to the background).
    private var userPaused = false
    private var runningSince: Date?

    init(game: Game, storage: GameStorage) {
        self.game = game
        self.storage = storage
        self.audio = AudioRenderer(core: core)
        self.saveStates = SaveStateStore(storage: storage)
    }

    // MARK: Save states

    func saveState(slot: Int, context: ModelContext) async {
        guard !isWorkingOnState else { return }
        isWorkingOnState = true
        defer { isWorkingOnState = false }
        do {
            let state = try await saveStates.save(core: core, game: game, slot: slot, context: context)
            show("Saved to \(state.name)")
        } catch {
            stateError = "Could not save: \(Self.message(for: error))"
        }
    }

    /// Returns true if the state was restored.
    @discardableResult
    func loadState(_ state: SaveState) async -> Bool {
        guard !isWorkingOnState else { return false }
        isWorkingOnState = true
        defer { isWorkingOnState = false }
        do {
            try await saveStates.load(state, into: core, game: game)
            show("Loaded \(state.name)")
            return true
        } catch {
            var message = "Could not load \(state.name): \(Self.message(for: error))"
            if state.coreVersion != DSCore.melonDSVersion {
                message += " It was saved with melonDS \(state.coreVersion); this is \(DSCore.melonDSVersion)."
            }
            stateError = message + " The game continues where it was."
            return false
        }
    }

    func quickSave(context: ModelContext) async { await saveState(slot: SaveStateStore.quickSlot, context: context) }

    func quickLoad(context: ModelContext) async {
        guard let state = saveStates.state(for: game, slot: SaveStateStore.quickSlot, context: context) else {
            stateError = "There is no Quick Save for this game yet."
            return
        }
        await loadState(state)
    }

    /// Pause while a menu covers the game; `resumeAfterMenu` restores the previous state.
    func pauseForMenu() { appBecameInactive() }
    func resumeAfterMenu() { appBecameActive() }

    private static var toastDuration: Duration {
        #if DEBUG
        // UI tests poll about once a second after the app goes idle; keep confirmations around longer.
        if ProcessInfo.processInfo.environment["DUALDS_UITEST_FRESH"] == "1" { return .seconds(8) }
        #endif
        return .milliseconds(2500)
    }

    private func show(_ message: String) {
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.toastDuration)
            if self?.toast == message { self?.toast = nil }
        }
    }

    func start(context: ModelContext) async {
        let rom = storage.romURL(fileName: game.fileName)
        let save = storage.saveURL(gameID: game.id)
        let core = self.core
        do {
            try storage.createDirectories()
            // Reading a ROM (up to 512 MB) and building the console happens off the main thread.
            try await Task.detached(priority: .userInitiated) {
                try core.loadGame(at: rom, save: save)
                try core.start()
            }.value
        } catch {
            phase = .failed(Self.message(for: error))
            return
        }
        core.onStopped = Self.stopHandler(for: self)
        game.lastPlayedAt = .now
        try? context.save()
        do { try await audio.start() } catch { audioError = "Sound is unavailable: \(error.localizedDescription)" }
        runningSince = .now
        phase = .running
    }

    func togglePause() {
        if phase == .running { userPaused = true; pauseCore() }
        else if phase == .paused { userPaused = false; resumeCore() }
    }

    /// App moved to background / inactive: pause and flush the save; resume only if the user hadn't paused.
    func appBecameInactive() { if phase == .running { pauseCore() } }
    func appBecameActive() { if phase == .paused && !userPaused { resumeCore() } }

    func reset() {
        do { try core.reset() } catch { phase = .failed(Self.message(for: error)) }
    }

    func setFastForward(_ on: Bool) {
        isFastForward = on
        core.setFastForward(on)
    }

    func setAudio(volume: Double, muted: Bool) {
        audio.volume = Float(volume)
        audio.isMuted = muted
    }

    func setButton(_ button: DSButton, pressed: Bool) { core.setButton(button, pressed: pressed) }
    func touch(x: Int, y: Int, touching: Bool) { core.setTouch(x: x, y: y, touching: touching) }

    /// Stops emulation, flushes the battery save and records play time.
    func finish(context: ModelContext) {
        accumulatePlayTime()
        core.onStopped = nil
        audio.stop()
        core.stop()
        try? context.save()
    }

    private func pauseCore() {
        core.pause()
        audio.pause()
        accumulatePlayTime()
        phase = .paused
    }

    private func resumeCore() {
        core.resume()
        audio.resume()
        runningSince = .now
        phase = .running
    }

    private func accumulatePlayTime() {
        if let since = runningSince { game.playTime += Date.now.timeIntervalSince(since) }
        runningSince = nil
    }

    /// The core calls this on its emulation thread, so the closure must not be main-actor isolated.
    nonisolated private static func stopHandler(for model: EmulatorViewModel) -> (String) -> Void {
        { [weak model] reason in
            Task { @MainActor in model?.coreStopped(reason) }
        }
    }

    private func coreStopped(_ reason: String) {
        accumulatePlayTime()
        audio.pause()
        phase = .failed(reason)
    }

    static func message(for error: Error) -> String {
        let ns = error as NSError
        if let reason = ns.localizedFailureReason { return "\(ns.localizedDescription) (\(reason))" }
        return ns.localizedDescription
    }
}
