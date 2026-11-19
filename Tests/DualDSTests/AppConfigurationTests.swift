// DualDS — unit tests for app configuration and bundled legal material.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import UniformTypeIdentifiers
import XCTest
@testable import DualDS

final class AppConfigurationTests: XCTestCase {
    func testNDSTypeIsDeclaredForTheNdsExtension() {
        XCTAssertTrue(UTType.ndsROM.conforms(to: .data))
        XCTAssertEqual(UTType(filenameExtension: "nds"), .ndsROM,
                       "Info.plist must declare com.dualds.nds-rom for the .nds extension")
    }

    func testEveryLegalDocumentIsBundledAndNonEmpty() {
        for doc in AppConfiguration.legalDocuments {
            let text = AppConfiguration.legalText(doc.resource)
            XCTAssertNotNil(text, "\(doc.resource).txt missing from the app bundle")
            XCTAssertGreaterThan(text?.count ?? 0, 200, "\(doc.resource).txt looks truncated")
        }
    }

    func testGPLTextIsTheRealLicense() throws {
        let gpl = try XCTUnwrap(AppConfiguration.legalText("LICENSE-DualDS"))
        XCTAssertTrue(gpl.contains("GNU GENERAL PUBLIC LICENSE"))
        XCTAssertTrue(gpl.contains("Version 3, 29 June 2007"))
    }

    func testMelonDSCommitIsAFullSHA() {
        XCTAssertEqual(AppConfiguration.melonDSCommit.count, 40)
        XCTAssertTrue(AppConfiguration.melonDSCommit.allSatisfy(\.isHexDigit))
    }
}
