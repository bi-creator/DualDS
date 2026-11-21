// DualDS — every theme opens the library and a game; screenshots each for review.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest

final class ThemeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private static let themes = ["Classic", "Neon Maze", "Vector Void", "Pixel Kingdom", "Dungeon Map", "Block Rain",
                                 "Pocket Green", "Speed Zone", "Street Brawl", "Polygon Rally", "Fog Town"]

    @MainActor
    func testEveryThemeShowsTheLibraryAndAFoldedGame() throws {
        let rom = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "dualds-test", ofType: "nds"))
        let dir = ProcessInfo.processInfo.environment["DUALDS_SCREENSHOT_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        for theme in Self.themes {
            let app = XCUIApplication()
            app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
            app.launchEnvironment["DUALDS_UITEST_IMPORT"] = rom
            app.launchEnvironment["DUALDS_SIMULATE_FOLD"] = "1"
            app.launchArguments += ["-app.theme", theme, "-ui.sounds", "NO"]
            app.launch()
            let alert = app.alerts["Import"]
            XCTAssertTrue(alert.waitForExistence(timeout: 10), theme)
            alert.buttons["OK"].tap()
            let card = app.buttons["library.game.DDST"]
            XCTAssertTrue(card.waitForExistence(timeout: 5), theme)
            let slug = theme.lowercased().replacingOccurrences(of: " ", with: "-")
            if let dir { try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("theme-\(slug)-library.png")) }

            card.tap()
            let play = app.buttons["detail.play"]
            XCTAssertTrue(play.waitForExistence(timeout: 5), theme)
            play.tap()
            XCTAssertTrue(app.staticTexts["emulator.fps"].waitForExistence(timeout: 10), theme)
            XCTAssertTrue(app.buttons["emulator.soundtrack"].exists, "\(theme): soundtrack button")
            sleep(1)
            if let dir { try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("theme-\(slug)-game.png")) }
            app.buttons["emulator.close"].tap()
            app.terminate()
        }
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DUALDS_SCREENSHOT_DIR"], !dir.isEmpty else { return }
        try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("theme-\(name).png"))
    }

    /// Back to the previous screen: the Back button when it is exposed, otherwise the edge swipe.
    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists { back.tap(); return }
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
    }

    @MainActor
    func testThemePickerSwitchesTheTheme() {
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launchArguments += ["-ui.sounds", "NO"]
        app.launch()
        app.buttons["library.settings"].tap()
        let themeRow = app.buttons["settings.theme"]
        XCTAssertTrue(themeRow.waitForExistence(timeout: 5))
        themeRow.tap()
        let fog = app.buttons["theme.Fog Town"]
        XCTAssertTrue(fog.waitForExistence(timeout: 5))
        fog.tap()
        sleep(1)
        snap(app, "picker-after-tap")
        goBack(app)
        snap(app, "picker-after-back")
        XCTAssertTrue(themeRow.waitForExistence(timeout: 5))
        XCTAssertTrue(themeRow.label.contains("Fog Town"), "Settings shows the new theme: \(themeRow.label)")
    }
}
