// DualDS — unit tests for the iPhone Duo clamshell layout.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest
@testable import DualDS

final class DuoClamshellLayoutTests: XCTestCase {
    // Inner display in portrait, roughly iPhone Duo proportions, folded with a 24 pt crease.
    private let bounds = CGRect(x: 0, y: 0, width: 669, height: 951)
    private var fold: CGRect { CGRect(x: 0, y: 463, width: 669, height: 24) }

    func testScreensSitOnEitherSideOfTheFold() {
        let c = DuoClamshellLayout.make(bounds: bounds, fold: fold, scale: 3)
        XCTAssertLessThanOrEqual(c.topScreen.maxY, fold.minY)
        XCTAssertGreaterThanOrEqual(c.bottomScreen.minY, fold.maxY)
        XCTAssertTrue(c.upperArea.contains(c.topScreen))
        XCTAssertTrue(c.lowerArea.contains(c.bottomScreen))
    }

    func testBothScreensKeepTheDSAspectRatio() {
        let c = DuoClamshellLayout.make(bounds: bounds, fold: fold, scale: 3)
        XCTAssertEqual(c.topScreen.width / c.topScreen.height, 4.0 / 3.0, accuracy: 0.02)
        XCTAssertEqual(c.bottomScreen.width / c.bottomScreen.height, 4.0 / 3.0, accuracy: 0.02)
        XCTAssertGreaterThan(c.topScreen.width, bounds.width * 0.75, "top screen uses most of the upper half")
    }

    func testControlsFlankTheTouchScreenWithoutOverlap() {
        let c = DuoClamshellLayout.make(bounds: bounds, fold: fold, scale: 3)
        XCTAssertLessThanOrEqual(c.leftColumn.maxX, c.bottomScreen.minX + 0.5)
        XCTAssertGreaterThanOrEqual(c.rightColumn.minX, c.bottomScreen.maxX - 0.5)
        XCTAssertEqual(c.bottomScreen.midX, bounds.midX, accuracy: 1)
        XCTAssertGreaterThan(c.controlScale, 0.8)
        XCTAssertGreaterThanOrEqual(c.bottomScreen.width, bounds.width * 0.5, "touch screen gets about half the width")
        XCTAssertGreaterThanOrEqual(c.bottomScreen.minY, fold.maxY + 22 - 0.5, "touch screen clears the hinge")
        let above = c.bottomScreen.minY - (fold.maxY + 22), below = c.lowerArea.maxY - 10 - c.systemRow.maxY
        XCTAssertEqual(above, below, accuracy: 2, "touch screen and Start/Select are centred in the lower half")
        XCTAssertGreaterThanOrEqual(c.systemRow.minY, c.bottomScreen.maxY, "Start/Select below the touch screen")
        XCTAssertLessThanOrEqual(c.systemRow.maxY, c.lowerArea.maxY)
    }

    func testToolbarStaysInTheUpperHalf() {
        let c = DuoClamshellLayout.make(bounds: bounds, fold: fold, scale: 3)
        XCTAssertTrue(c.upperArea.contains(c.toolbar))
        XCTAssertFalse(c.toolbar.intersects(c.topScreen))
    }

    func testFoldSelection() {
        // Horizontal crease across the middle is accepted; vertical (book posture) and edge regions are not.
        XCTAssertEqual(DuoClamshellLayout.horizontalFold(in: bounds, divisions: [fold]), fold)
        XCTAssertNil(DuoClamshellLayout.horizontalFold(in: bounds, divisions: [CGRect(x: 322, y: 0, width: 24, height: 951)]))
        XCTAssertNil(DuoClamshellLayout.horizontalFold(in: bounds, divisions: [CGRect(x: 0, y: 20, width: 669, height: 24)]))
        XCTAssertNil(DuoClamshellLayout.horizontalFold(in: bounds, divisions: []))
    }

    func testFlatMiddleSplitAndDegenerateBounds() {
        let flat = DuoClamshellLayout.make(bounds: bounds, fold: DuoClamshellLayout.middleFold(in: bounds), scale: 3)
        XCTAssertLessThanOrEqual(flat.topScreen.maxY, bounds.midY)
        XCTAssertGreaterThanOrEqual(flat.bottomScreen.minY, bounds.midY)
        let tiny = DuoClamshellLayout.make(bounds: .zero, fold: .zero, scale: 3)
        XCTAssertEqual(tiny.topScreen.size, .zero)
    }
}
