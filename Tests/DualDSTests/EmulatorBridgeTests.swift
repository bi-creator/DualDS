// DualDS — integration tests: the real melonDS core, through the Objective-C++ bridge,
// running the original DualDS test ROM inside the iOS app process. No mocks.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest
@testable import DualDS

final class EmulatorBridgeTests: XCTestCase {
    private var tmp: URL!
    /// The fixture repaints VRAM from uncached RAM (~1.5 frames per pass); let input settle.
    private let settleFrames = 10

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func testROM() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dualds-test", withExtension: "nds"),
                      "dualds-test.nds missing from the test bundle")
    }

    private var pixelCount: Int { DSCore.screenWidth * DSCore.screenHeight }

    private func loadedCore() throws -> DSCore {
        let core = DSCore()
        try core.loadGame(at: testROM(), save: tmp.appendingPathComponent("test.sav"))
        return core
    }

    private func frame(_ core: DSCore) -> (top: [UInt32], bottom: [UInt32], number: UInt64)? {
        var top = [UInt32](repeating: 0, count: pixelCount)
        var bottom = [UInt32](repeating: 0, count: pixelCount)
        var number: UInt64 = 0
        let ok = top.withUnsafeMutableBufferPointer { t in
            bottom.withUnsafeMutableBufferPointer { b in
                core.copyFramebuffer(top: t.baseAddress, bottom: b.baseAddress, frameNumber: &number)
            }
        }
        return ok ? (top, bottom, number) : nil
    }

    private enum Colour { case red, green, blue, mixed }

    /// Every pixel must be the same pure colour; BGRA little-endian.
    private func colour(_ pixels: [UInt32]) -> Colour {
        func classify(_ p: UInt32) -> Colour {
            let r = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF
            if r > 200 && g < 40 && b < 40 { return .red }
            if g > 200 && r < 40 && b < 40 { return .green }
            if b > 200 && r < 40 && g < 40 { return .blue }
            return .mixed
        }
        guard let first = pixels.first.map(classify), first != .mixed else { return .mixed }
        return pixels.allSatisfy { classify($0) == first } ? first : .mixed
    }

    func testReportsMelonDSVersion() {
        XCTAssertEqual(DSCore.melonDSVersion, AppConfiguration.melonDSVersion)
    }

    func testMissingAndInvalidFilesAreRejected() throws {
        let core = DSCore()
        XCTAssertThrowsError(try core.loadGame(at: tmp.appendingPathComponent("missing.nds"),
                                               save: tmp.appendingPathComponent("x.sav"))) { error in
            XCTAssertEqual((error as? DSCoreError)?.code, .fileNotFound)
        }
        let junk = tmp.appendingPathComponent("junk.nds")
        try Data(repeating: 0x7F, count: 0x2000).write(to: junk)
        XCTAssertThrowsError(try core.loadGame(at: junk, save: tmp.appendingPathComponent("x.sav"))) { error in
            XCTAssertEqual((error as? DSCoreError)?.code, .invalidROM)
        }
        XCTAssertThrowsError(try core.start()) { error in
            XCTAssertEqual((error as? DSCoreError)?.code, .noROMLoaded)
        }
    }

    func testBootsTestROMAndRendersBothScreens() throws {
        let core = try loadedCore()
        XCTAssertNil(frame(core), "no frame before emulation")
        XCTAssertEqual(core.runFramesBlocking(60), 60)
        let f = try XCTUnwrap(frame(core))
        XCTAssertEqual(f.number, 60)
        XCTAssertEqual(colour(f.top), .red, "top screen: ARM9 program drew VRAM display")
        XCTAssertEqual(colour(f.bottom), .blue, "bottom screen: engine B backdrop")
    }

    func testButtonInputReachesTheEmulatedConsole() throws {
        let core = try loadedCore()
        core.runFramesBlocking(30)
        core.setButton(.A, pressed: true)
        core.runFramesBlocking(settleFrames)
        XCTAssertEqual(colour(try XCTUnwrap(frame(core)).top), .green)
        core.setButton(.A, pressed: false)
        core.runFramesBlocking(settleFrames)
        XCTAssertEqual(colour(try XCTUnwrap(frame(core)).top), .red)
    }

    func testAudioIsProducedAt48kHz() throws {
        let core = try loadedCore()
        core.runFramesBlocking(5)
        var sink = [Int16](repeating: 0, count: 16_384 * 2)
        _ = sink.withUnsafeMutableBufferPointer { core.readAudio(into: $0.baseAddress!, frames: 16_384) }
        XCTAssertEqual(core.audioFramesAvailable, 0)
        core.runFramesBlocking(1)
        let perFrame = core.audioFramesAvailable
        XCTAssertGreaterThan(perFrame, 760)
        XCTAssertLessThan(perFrame, 840, "48000 / 59.83 ≈ 802 stereo frames per video frame")
        XCTAssertEqual(core.audioSampleRate, 48_000)
    }

    func testSaveStateRoundTripIsExact() throws {
        let core = try loadedCore()
        core.runFramesBlocking(30)
        let slot = tmp.appendingPathComponent("slot1.mln")
        try core.saveState(to: slot)

        core.setButton(.A, pressed: true)
        core.runFramesBlocking(settleFrames)
        XCTAssertEqual(colour(try XCTUnwrap(frame(core)).top), .green, "state diverged after saving")
        core.setButton(.A, pressed: false)

        try core.loadState(from: slot)
        let again = tmp.appendingPathComponent("slot1-again.mln")
        try core.saveState(to: again)
        XCTAssertEqual(try Data(contentsOf: slot), try Data(contentsOf: again),
                       "restored console state must be byte-identical to the saved one")
    }

    func testCorruptSaveStateIsRejectedAndEmulationContinues() throws {
        let core = try loadedCore()
        core.runFramesBlocking(10)
        let bad = tmp.appendingPathComponent("bad.mln")
        try Data(count: 4096).write(to: bad)
        XCTAssertThrowsError(try core.loadState(from: bad)) { error in
            XCTAssertEqual((error as? DSCoreError)?.code, .stateIncompatible)
        }
        XCTAssertEqual(core.runFramesBlocking(settleFrames), settleFrames)
        XCTAssertEqual(colour(try XCTUnwrap(frame(core)).top), .red)
    }

    func testThreadedEmulationIsPacedAndPausable() throws {
        let core = try loadedCore()
        let framesArrived = expectation(description: "onFrame called")
        framesArrived.expectedFulfillmentCount = 30
        framesArrived.assertForOverFulfill = false
        core.onFrame = { _ in framesArrived.fulfill() }

        try core.start()
        XCTAssertEqual(core.runState, .running)
        wait(for: [framesArrived], timeout: 5)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertGreaterThan(core.measuredFPS, 55)
        XCTAssertLessThan(core.measuredFPS, 63)

        core.pause()
        Thread.sleep(forTimeInterval: 0.2)
        let paused = core.framesEmulated
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(core.framesEmulated, paused, "no frames while paused")
        XCTAssertEqual(core.runState, .paused)

        core.resume()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertGreaterThan(core.framesEmulated, paused)
        core.onFrame = nil
        core.stop()
        XCTAssertEqual(core.runState, .stopped)
    }
}
