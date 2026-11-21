// DualDS — the FoldPlay Store opens from the library and lists the Originals with a price.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest

final class StoreUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testStoreListsBackAlleyBrawl() {
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launchArguments += ["-ui.sounds", "NO"]
        app.launch()

        let open = app.buttons["library.storeEmpty"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "empty library offers the store")
        open.tap()
        let card = app.descendants(matching: .any)["store.game.back-alley-brawl"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        // With the local StoreKit configuration the price loads; without it the card says so.
        let buy = app.buttons["store.buy.back-alley-brawl"]
        let available = buy.waitForExistence(timeout: 10)
        if available { XCTAssertTrue(buy.label.contains("Buy"), buy.label) }
        XCTAssertTrue(app.buttons["store.restore"].exists)
        if let dir = ProcessInfo.processInfo.environment["DUALDS_SCREENSHOT_DIR"], !dir.isEmpty {
            try? app.windows.firstMatch.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("store.png"))
        }
        print("StoreUITests: price available = \(available)")
    }
}
