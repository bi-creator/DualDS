// DualDS — UI tests for the game library (import via DEBUG launch hook, details, delete).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest

final class LibraryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testImportedGameAppearsShowsDetailsAndCanBeDeleted() throws {
        let rom = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "dualds-test", ofType: "nds"))
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launchEnvironment["DUALDS_UITEST_IMPORT"] = rom
        app.launch()

        let alert = app.alerts["Import"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()

        let card = app.buttons["library.game.DDST"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.staticTexts["DDST"].waitForExistence(timeout: 5), "detail shows the game code")
        let delete = app.buttons["detail.delete"]
        // Form rows load lazily below the fold; scroll the sheet's list, not the window.
        let list = app.collectionViews.firstMatch
        for _ in 0..<12 where !(delete.exists && delete.isHittable) {
            if list.exists { list.swipeUp(velocity: .slow) } else { app.swipeUp() }
        }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        let confirm = app.buttons["Delete Game, Saves and States"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No Games Yet"].waitForExistence(timeout: 5))
    }
}
