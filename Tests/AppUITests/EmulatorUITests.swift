// DualDS — end-to-end: import → Play → the real core renders through Metal → read the pixels.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest

final class EmulatorUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Average colour of the centre region of an element's screenshot.
    @MainActor
    private func centreColour(of element: XCUIElement) throws -> (r: Double, g: Double, b: Double) {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let w = 8, h = 8
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cw = image.width / 4, ch = image.height / 4
        let centre = try XCTUnwrap(image.cropping(to: CGRect(x: (image.width - cw) / 2, y: (image.height - ch) / 2, width: cw, height: ch)))
        ctx.draw(centre, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = (0.0, 0.0, 0.0)
        for i in stride(from: 0, to: px.count, by: 4) { sum.0 += Double(px[i]); sum.1 += Double(px[i + 1]); sum.2 += Double(px[i + 2]) }
        let n = Double(w * h)
        return (sum.0 / n, sum.1 / n, sum.2 / n)
    }

    /// Imports the test ROM in a fresh app, presses Play, waits for frames. Optional extra launch arguments.
    @MainActor
    private func launchIntoGame(arguments: [String] = [], fold: Bool) throws -> XCUIApplication {
        let rom = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "dualds-test", ofType: "nds"))
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launchEnvironment["DUALDS_UITEST_IMPORT"] = rom
        if fold { app.launchEnvironment["DUALDS_SIMULATE_FOLD"] = "1" }
        app.launchArguments += arguments
        app.launch()
        let alert = app.alerts["Import"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        app.buttons["library.game.DDST"].tap()
        let play = app.buttons["detail.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.descendants(matching: .any)["emulator.topScreen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["emulator.fps"].waitForExistence(timeout: 10))
        sleep(2)
        return app
    }

    @MainActor
    func testSaveAndLoadAStateFromTheMenu() throws {
        let app = try launchIntoGame(fold: false)
        app.buttons["emulator.menu"].tap()
        app.buttons["Save States…"].tap()

        let save = app.buttons["slot.1.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["slot.1.date"].label, "Empty")
        save.tap()
        let date = app.staticTexts["slot.1.date"]
        wait(for: [expectation(for: NSPredicate(format: "label != 'Empty'"), evaluatedWith: date)], timeout: 10)  // timestamp after saving

        app.buttons["slot.1.load"].tap()
        XCTAssertTrue(app.staticTexts["emulator.toast"].waitForExistence(timeout: 10), "confirmation after loading")
        XCTAssertTrue(app.staticTexts["emulator.toast"].label.contains("Loaded Slot 1"))

        // Quick Save, confirmed through the Save States list (not just the transient message).
        app.buttons["emulator.menu"].tap()
        app.buttons["Quick Save"].tap()
        let toast = app.staticTexts["emulator.toast"]
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'Saved to Quick Save'"), evaluatedWith: toast)], timeout: 10)
        app.buttons["emulator.menu"].tap()
        app.buttons["Save States…"].tap()
        let quickDate = app.staticTexts["slot.0.date"]
        XCTAssertTrue(quickDate.waitForExistence(timeout: 5))
        XCTAssertNotEqual(quickDate.label, "Empty", "Quick Save slot is filled")
        app.buttons["Done"].tap()

        app.buttons["emulator.menu"].tap()
        app.buttons["Quick Load"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'Loaded Quick Save'"), evaluatedWith: toast)], timeout: 10)
    }

    @MainActor
    func testEveryControllerStyleLaysOutAroundTheTouchScreen() throws {
        for style in ["Clamshell", "Pocket", "Arcade", "Pro Pad"] {
            let app = try launchIntoGame(arguments: ["-controls.style", style], fold: true)
            let bottom = app.descendants(matching: .any)["emulator.bottomScreen"].frame
            let dir = app.descendants(matching: .any)["control.dpad"]
            XCTAssertTrue(dir.exists, "\(style): directional control")
            XCTAssertLessThan(dir.frame.maxX, bottom.minX + 1, "\(style): directional control left of the touch screen")
            for name in ["A", "B", "X", "Y"] {
                let b = app.buttons["control.\(name)"]
                XCTAssertTrue(b.exists, "\(style): \(name)")
                XCTAssertGreaterThan(b.frame.minX, bottom.maxX - 1, "\(style): \(name) right of the touch screen")
            }
            XCTAssertTrue(app.buttons["control.L"].exists && app.buttons["control.R"].exists, "\(style): L and R")
            XCTAssertTrue(app.buttons["control.START"].exists && app.buttons["control.SELECT"].exists, "\(style): Start/Select")
            if let dirPath = ProcessInfo.processInfo.environment["DUALDS_SCREENSHOT_DIR"], !dirPath.isEmpty {
                let file = "emulator-style-\(style.replacingOccurrences(of: " ", with: "")).png"
                try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dirPath).appendingPathComponent(file))
            }
            app.terminate()
        }
    }

    @MainActor
    func testFoldedDuoShowsTopScreenAboveFoldAndControlsBelow() throws {
        let rom = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "dualds-test", ofType: "nds"))
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launchEnvironment["DUALDS_UITEST_IMPORT"] = rom
        app.launchEnvironment["DUALDS_SIMULATE_FOLD"] = "1"   // DEBUG: fold at the middle of the window
        app.launch()

        let alert = app.alerts["Import"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        app.buttons["library.game.DDST"].tap()
        let play = app.buttons["detail.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()

        let top = app.descendants(matching: .any)["emulator.topScreen"]
        let bottom = app.descendants(matching: .any)["emulator.bottomScreen"]
        XCTAssertTrue(top.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["emulator.fps"].waitForExistence(timeout: 10))
        sleep(2)

        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(top.frame.maxY, window.midY, "top screen above the fold")
        XCTAssertGreaterThan(bottom.frame.minY, window.midY, "touch screen below the fold")
        let dpad = app.descendants(matching: .any)["control.dpad"].frame, a = app.buttons["control.A"].frame
        XCTAssertLessThan(dpad.maxX, bottom.frame.minX, "D-pad left of the touch screen")
        XCTAssertGreaterThan(a.minX, bottom.frame.maxX, "face buttons right of the touch screen")
        XCTAssertGreaterThan(dpad.minY, window.midY)

        let t = try centreColour(of: top), b = try centreColour(of: bottom)
        XCTAssertGreaterThan(t.r, 180, "top screen red: \(t)")
        XCTAssertGreaterThan(b.b, 180, "bottom screen blue: \(b)")

        if let dir = ProcessInfo.processInfo.environment["DUALDS_SCREENSHOT_DIR"], !dir.isEmpty {
            try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("emulator-duo-folded.png"))
        }
        app.buttons["emulator.close"].tap()
    }

    @MainActor
    func testPlayingTheTestROMRendersBothScreens() throws {
        let rom = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "dualds-test", ofType: "nds"))
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launchEnvironment["DUALDS_UITEST_IMPORT"] = rom
        app.launch()

        let alert = app.alerts["Import"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        app.buttons["library.game.DDST"].tap()
        let play = app.buttons["detail.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()

        let top = app.descendants(matching: .any)["emulator.topScreen"]
        let bottom = app.descendants(matching: .any)["emulator.bottomScreen"]
        XCTAssertTrue(top.waitForExistence(timeout: 10))
        XCTAssertTrue(bottom.exists)
        XCTAssertGreaterThan(top.frame.width, 100)

        // Allow the core to boot and the renderer to present a few frames.
        let fps = app.staticTexts["emulator.fps"]
        XCTAssertTrue(fps.waitForExistence(timeout: 10))
        sleep(2)

        let t = try centreColour(of: top), b = try centreColour(of: bottom)
        XCTAssertGreaterThan(t.r, 180, "top screen should be red: \(t)")
        XCTAssertLessThan(t.g, 60); XCTAssertLessThan(t.b, 60)
        XCTAssertGreaterThan(b.b, 180, "bottom screen should be blue: \(b)")
        XCTAssertLessThan(b.r, 60); XCTAssertLessThan(b.g, 60)

        // Optional: save what the player sees (CI sets TEST_RUNNER_DUALDS_SCREENSHOT_DIR).
        if let dir = ProcessInfo.processInfo.environment["DUALDS_SCREENSHOT_DIR"], !dir.isEmpty {
            try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("emulator-portrait.png"))
        }

        // Exercise the on-screen A button (press and release). Pixel-level input checks live in
        // EmulatorBridgeTests; XCUITest cannot sample the screen while a press is held.
        let a = app.buttons["control.A"]
        XCTAssertTrue(a.exists)
        let start = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 2.0, thenDragTo: start)   // hold, then release on the same spot

        app.buttons["emulator.close"].tap()
        XCTAssertTrue(app.buttons["library.game.DDST"].waitForExistence(timeout: 5))
    }
}
