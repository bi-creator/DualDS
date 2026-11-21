// DualDS — UI tests for first launch.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest

final class FirstLaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLibraryShowsBrandingImportAndSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["brand.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["brand.title"].label, "FoldPlay")
        XCTAssertTrue(app.staticTexts["No Games Yet"].exists)
        XCTAssertTrue(app.buttons["library.import"].exists)
        XCTAssertTrue(app.buttons["library.settings"].exists)
    }

    @MainActor
    func testSettingsOpensAboutWithLicenses() {
        let app = XCUIApplication()
        app.launchEnvironment["DUALDS_UITEST_FRESH"] = "1"
        app.launch()

        app.buttons["library.settings"].tap()
        let about = app.buttons["settings.about"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !about.isHittable { app.swipeUp() }   // About sits below Appearance and Sound
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        let privacy = app.descendants(matching: .any)["about.privacyPolicy"].firstMatch
        let melonLicense = app.buttons["melonDS (GPL-3.0)"]
        // The list only builds rows that are on screen, so scroll down to reach them.
        for _ in 0..<6 where !(privacy.exists && melonLicense.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(privacy.exists, "About must link to the privacy policy")
        XCTAssertTrue(melonLicense.waitForExistence(timeout: 5))
        melonLicense.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "GNU GENERAL PUBLIC LICENSE")).firstMatch
            .waitForExistence(timeout: 5))
    }
}
