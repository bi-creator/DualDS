// DualDS — audio pipeline tests: real core → SPSC ring → render callback / AVAudioEngine.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest
@testable import DualDS

@MainActor
final class AudioRendererTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func loadedCore() throws -> DSCore {
        let rom = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dualds-test", withExtension: "nds"))
        let core = DSCore()
        try core.loadGame(at: rom, save: tmp.appendingPathComponent("t.sav"))
        return core
    }

    func testRenderCapsLatencyThenPadsSilenceWhenDrained() throws {
        let core = try loadedCore()
        core.runFramesBlocking(30)            // ~24 000 frames produced; ring keeps the newest 250 ms
        let pipe = AudioPipe(core: core, maxLatency: 0.05)  // 2 400 frames
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
        defer { left.deallocate(); right.deallocate() }

        pipe.render(left: left, right: right, frames: 512)
        var s = pipe.snapshot
        XCTAssertEqual(s.fromCore, 512)
        XCTAssertGreaterThan(s.discarded, 5_000, "excess latency is discarded")
        XCTAssertLessThanOrEqual(core.audioFramesAvailable, 2_400, "latency capped")

        // Drain whatever is left, then render again: the output must be silence, not garbage.
        while core.audioFramesAvailable > 0 { pipe.render(left: left, right: right, frames: 1024) }
        for i in 0..<256 { left[i] = 99; right[i] = 99 }
        pipe.render(left: left, right: right, frames: 256)
        s = pipe.snapshot
        XCTAssertGreaterThanOrEqual(s.silent, 256)
        XCTAssertTrue((0..<256).allSatisfy { left[$0] == 0 && right[$0] == 0 })
    }

    func testAudioFlowsFromRunningCoreToTheOutputDevice() async throws {
        let core = try loadedCore()
        try core.start()
        defer { core.stop() }
        let audio = AudioRenderer(core: core)
        do { try audio.start() } catch {
            throw XCTSkip("No audio output available in this environment: \(error)")
        }
        try await Task.sleep(for: .seconds(2))
        let s = audio.stats
        let total = s.fromCore + s.silent
        XCTAssertGreaterThan(total, 60_000, "the engine pulled ~2 s of audio")
        XCTAssertGreaterThan(s.fromCore, 60_000, "the samples came from the emulated SPU")
        XCTAssertLessThan(Double(s.silent) / Double(max(total, 1)), 0.2, "few underruns: \(s)")

        audio.pause()
        try await Task.sleep(for: .milliseconds(300))
        let paused = audio.stats.fromCore + audio.stats.silent
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(audio.stats.fromCore + audio.stats.silent, paused, "no rendering while paused")
        audio.stop()
    }
}
