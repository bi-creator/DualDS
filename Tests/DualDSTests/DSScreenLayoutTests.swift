// DualDS — unit tests for dual-screen layout and touch mapping.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import XCTest
@testable import DualDS

final class DSScreenLayoutTests: XCTestCase {
    func testVerticalAspectFitFillsWidthAndStacks() {
        let f = DSScreenLayout().frames(in: CGRect(x: 0, y: 0, width: 512, height: 1000), scale: 1)
        XCTAssertEqual(f.top.size, CGSize(width: 512, height: 384))
        XCTAssertEqual(f.bottom.size, f.top.size)
        XCTAssertEqual(f.bottom.minY, f.top.maxY, "no gap by default")
        XCTAssertEqual(f.top.midX, 256)
        XCTAssertEqual(f.top.minY, (1000 - 768) / 2, "group is centred")
    }

    func testHorizontalArrangementWithGap() {
        let layout = DSScreenLayout(arrangement: .horizontal, gap: 20)
        let f = layout.frames(in: CGRect(x: 0, y: 0, width: 1044, height: 400), scale: 1)
        XCTAssertEqual(f.top.size, CGSize(width: 512, height: 384))
        XCTAssertEqual(f.bottom.minX - f.top.maxX, 20)
        XCTAssertEqual(f.top.midY, f.bottom.midY)
    }

    func testIntegerScalingUsesWholePixelMultiples() {
        let layout = DSScreenLayout(scaling: .integer)
        // 390 pt wide at 3x = 1170 px -> 4x (1024 px) fits, 5x (1280) doesn't.
        let f = layout.frames(in: CGRect(x: 0, y: 0, width: 390, height: 844), scale: 3)
        XCTAssertEqual(f.top.width * 3, 1024, accuracy: 0.01)
        XCTAssertEqual(f.top.height * 3, 768, accuracy: 0.01)
    }

    func testStretchFillsEachHalf() {
        let f = DSScreenLayout(scaling: .stretch).frames(in: CGRect(x: 0, y: 0, width: 300, height: 1000), scale: 1)
        XCTAssertEqual(f.top, CGRect(x: 0, y: 0, width: 300, height: 500))
        XCTAssertEqual(f.bottom, CGRect(x: 0, y: 500, width: 300, height: 500))
    }

    func testSwapPutsTouchScreenFirst() {
        let normal = DSScreenLayout().frames(in: CGRect(x: 0, y: 0, width: 256, height: 384), scale: 1)
        let swapped = DSScreenLayout(swapScreens: true).frames(in: CGRect(x: 0, y: 0, width: 256, height: 384), scale: 1)
        XCTAssertEqual(swapped.top, normal.bottom)
        XCTAssertEqual(swapped.bottom, normal.top)
    }

    func testEmptyBoundsDoNotProduceNegativeSizes() {
        let f = DSScreenLayout(gap: 40).frames(in: .zero, scale: 2)
        XCTAssertGreaterThanOrEqual(f.top.width, 0)
        XCTAssertGreaterThanOrEqual(f.top.height, 0)
    }

    func testTouchMappingCornersAndOutside() {
        let bottom = CGRect(x: 10, y: 400, width: 512, height: 384)
        XCTAssertEqual(DSScreenLayout.touchCoordinates(of: CGPoint(x: 10, y: 400), in: bottom)?.x, 0)
        let far = DSScreenLayout.touchCoordinates(of: CGPoint(x: 521.99, y: 783.99), in: bottom)
        XCTAssertEqual(far?.x, 255)
        XCTAssertEqual(far?.y, 191)
        let mid = DSScreenLayout.touchCoordinates(of: CGPoint(x: 10 + 256, y: 400 + 192), in: bottom)
        XCTAssertEqual(mid?.x, 128)
        XCTAssertEqual(mid?.y, 96)
        XCTAssertNil(DSScreenLayout.touchCoordinates(of: CGPoint(x: 5, y: 500), in: bottom))
    }
}
