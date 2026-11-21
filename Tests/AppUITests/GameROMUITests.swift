// DualDS — plays FoldPlay Games ROMs (built in ../FoldPlayGames) end to end and saves screenshots.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// CI passes the ROM path in DUALDS_GAME_ROM and test-only stage variants in DUALDS_GAME_TEST_DIR;
// without them the tests are skipped.

import XCTest

final class GameROMUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = env["DUALDS_SCREENSHOT_DIR"], !dir.isEmpty else { return }
        try? app.windows.firstMatch.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("game-\(name).png"))
    }

    /// Imports one ROM in a fresh app on the folded layout and opens it.
    @MainActor
    private func launch(rom: String) -> XCUIApplication {
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
        return app
    }

    @MainActor
    private func tapTouchScreen(_ app: XCUIApplication) {
        let bottom = app.descendants(matching: .any)["emulator.bottomScreen"]
        XCTAssertTrue(bottom.waitForExistence(timeout: 5))
        bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
    }

    /// Walk right a bit and throw punches and kicks.
    @MainActor
    private func brawl(_ app: XCUIApplication, rounds: Int) {
        let dpad = app.descendants(matching: .any)["control.dpad"]
        let a = app.descendants(matching: .any)["control.A"]
        let y = app.descendants(matching: .any)["control.Y"]
        for r in 0..<rounds {
            dpad.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).press(forDuration: 0.6)
            for i in 0..<8 {
                a.tap()
                if (i + r) % 3 == 2 { y.tap() }
                usleep(120_000)
            }
        }
    }

    @MainActor
    func testBrawlerStartsAndResponds() throws {
        guard let rom = env["DUALDS_GAME_ROM"], FileManager.default.fileExists(atPath: rom) else {
            throw XCTSkip("No game ROM (DUALDS_GAME_ROM)")
        }
        let app = launch(rom: rom)
        shot(app, "1-title")
        tapTouchScreen(app)
        sleep(2)
        shot(app, "2-stage1-start")
        brawl(app, rounds: 3)
        shot(app, "3-stage1-fighting")
        brawl(app, rounds: 4)
        shot(app, "4-stage1-later")
        app.buttons["emulator.close"].tap()
    }

    @MainActor
    func testLaterStagesLoad() throws {
        guard let dir = env["DUALDS_GAME_TEST_DIR"] else { throw XCTSkip("No test ROMs (DUALDS_GAME_TEST_DIR)") }
        for n in [2, 3] {
            let rom = "\(dir)/brawler_stage\(n).nds"
            guard FileManager.default.fileExists(atPath: rom) else { throw XCTSkip("Missing \(rom)") }
            let app = launch(rom: rom)
            tapTouchScreen(app)
            sleep(2)
            shot(app, "5-stage\(n)-start")
            brawl(app, rounds: 2)
            shot(app, "6-stage\(n)-fighting")
            app.buttons["emulator.close"].tap()
            app.terminate()
        }
    }
}
