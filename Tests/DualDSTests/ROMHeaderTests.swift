// DualDS — unit tests for NDS header/banner parsing.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import UIKit
import XCTest
@testable import DualDS

final class ROMHeaderTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dualds-test", withExtension: "nds"))
        return try Data(contentsOf: url)
    }

    func testParsesTheTestROMHeader() throws {
        let rom = try fixture()
        let h = try ROMHeader.parse(header: rom, fileSize: rom.count)
        XCTAssertEqual(h.title, "DUALDSTEST")
        XCTAssertEqual(h.gameCode, "DDST")
        XCTAssertEqual(h.makerCode, "00")
        XCTAssertEqual(h.unitCode, 0)
        XCTAssertEqual(h.arm9Offset, 0x200)
        XCTAssertEqual(h.bannerOffset, 0, "test ROM has no banner")
    }

    func testCRC16MatchesKnownVector() {
        // CRC-16/MODBUS check value for "123456789" is 0x4B37.
        XCTAssertEqual(ROMHeader.crc16(Array("123456789".utf8)), 0x4B37)
    }

    func testCorruptedHeaderIsRejected() throws {
        var rom = try fixture()
        rom[0x05] ^= 0xFF
        XCTAssertThrowsError(try ROMHeader.parse(header: rom, fileSize: rom.count)) { error in
            guard case ROMHeader.ParseError.checksumMismatch = error else { return XCTFail("\(error)") }
        }
    }

    /// Rewrites the header checksum after editing header bytes.
    private func fixCRC(_ rom: inout Data) {
        let crc = ROMHeader.crc16(rom[0..<0x15E])
        rom[0x15E] = UInt8(crc & 0xFF); rom[0x15F] = UInt8(crc >> 8)
    }

    func testTooSmallAndOutOfRangeCodeAreRejected() throws {
        let rom = try fixture()
        XCTAssertThrowsError(try ROMHeader.parse(header: rom, fileSize: 0x800)) {
            XCTAssertEqual($0 as? ROMHeader.ParseError, .tooSmall)
        }
        // Header claims ARM7 code beyond the end of the file (truncated/corrupt dump).
        var bad = rom
        let offset = UInt32(rom.count + 0x1000)
        for i in 0..<4 { bad[0x30 + i] = UInt8((offset >> (8 * UInt32(i))) & 0xFF) }
        fixCRC(&bad)
        XCTAssertThrowsError(try ROMHeader.parse(header: bad, fileSize: bad.count)) {
            XCTAssertEqual($0 as? ROMHeader.ParseError, .badCodeSection("ARM7"))
        }
    }

    func testDSiExclusiveIsRejected() throws {
        var rom = try fixture()
        rom[0x12] = ROMHeader.UnitCode.dsiExclusive.rawValue
        fixCRC(&rom)
        XCTAssertThrowsError(try ROMHeader.parse(header: rom, fileSize: rom.count)) {
            XCTAssertEqual($0 as? ROMHeader.ParseError, .dsiExclusive)
        }
    }

    func testBannerTitleAndIconDecode() throws {
        var banner = Data(count: ROMBanner.size)
        banner[0] = 1
        let title = Array("Sample Game\nSecond Line\nDualDS Tests".utf16)
        for (i, u) in title.enumerated() {
            banner[0x340 + i * 2] = UInt8(u & 0xFF); banner[0x341 + i * 2] = UInt8(u >> 8)
        }
        banner[0x222] = 0x1F; banner[0x223] = 0x00          // palette[1] = red
        for i in 0..<512 { banner[0x20 + i] = 0x11 }       // every pixel uses palette[1]
        let parsed = try XCTUnwrap(ROMBanner.parse(banner))
        XCTAssertEqual(parsed.name, "Sample Game")
        XCTAssertEqual(parsed.subtitle, "Second Line")
        XCTAssertEqual(parsed.publisher, "DualDS Tests")
        let png = try XCTUnwrap(parsed.iconPNG)
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(image.size, CGSize(width: 32, height: 32))
    }

    func testBlankIconYieldsNoPNG() throws {
        let parsed = try XCTUnwrap(ROMBanner.parse(Data(count: ROMBanner.size)))
        XCTAssertNil(parsed.iconPNG)
        XCTAssertNil(parsed.name)
    }
}
