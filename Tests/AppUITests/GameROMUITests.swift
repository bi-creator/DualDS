// DualDS — plays a FoldPlay Games ROM (built in ../FoldPlayGames) end to end and saves screenshots.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// CI passes the ROM path in DUALDS_GAME_ROM; without it the test is skipped.

import XCTest

final class GameROMUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testBrawlerStartsAndResponds() throws {
        let env = ProcessInfo.processInfo.environment
        guard let rom = env["DUALDS_GAME_ROM"], FileManager.default.fileExists(atPath: rom) else {
            throw XCTSkip("No game ROM (DUALDS_GAME_ROM)")
        }
        let dir = env["DUALDS_SCREENSHOT_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        func shot(_ app: XCUIApplication, _ name: String) {
            if let dir { try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("game-\(name).png")) }
        }

        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launchEnvironment["DUALDS_UITEST_IMPORT"] = rom
        app.launchEnvironment["DUALDS_SIMULATE_FOLD"] = "1"
        app.launchArguments += ["-ui.sounds", "NO"]
        app.launch()
        let alert = app.alerts["Import"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.game.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        app.buttons["detail.play"].tap()
        XCTAssertTrue(app.staticTexts["emulator.fps"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "1-title")

        // Start from the title by tapping the touch screen.
        let bottom = app.descendants(matching: .any)["emulator.bottomScreen"]
        XCTAssertTrue(bottom.waitForExistence(timeout: 5))
        bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        sleep(2)
        shot(app, "2-fight-start")

        // Walk right, then punch and kick as enemies arrive.
        let dpad = app.descendants(matching: .any)["control.dpad"]
        let right = dpad.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        right.press(forDuration: 1.2)
        let a = app.descendants(matching: .any)["control.A"]
        let y = app.descendants(matching: .any)["control.Y"]
        for i in 0..<12 {
            a.tap()
            if i % 3 == 2 { y.tap() }
            usleep(150_000)
        }
        shot(app, "3-fighting")
        sleep(3)
        for _ in 0..<15 { a.tap(); usleep(120_000) }
        shot(app, "4-later")
        app.buttons["emulator.close"].tap()
    }
}
