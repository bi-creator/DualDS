// DualDS — Nintendo DS cartridge header and banner parsing (pure, no emulator involvement).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Layout reference: the documented NDS cartridge header (offsets below). The rules mirror what
// melonDS itself requires (NDSCart::ValidateROM) plus a header-checksum check, so a file that
// passes here is one the core will accept.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ROMHeader: Sendable, Equatable {
    enum UnitCode: UInt8, Sendable {
        case nds = 0, dsiEnhanced = 2, dsiExclusive = 3
    }

    var title: String          // 12-byte ASCII header title
    var gameCode: String       // 4 characters, "####" for some homebrew
    var makerCode: String      // 2 characters
    var unitCode: UInt8
    var arm9Offset: UInt32, arm9Size: UInt32
    var arm7Offset: UInt32, arm7Size: UInt32
    var bannerOffset: UInt32
    var headerCRC: UInt16

    static let minimumFileSize = 0x1000      // melonDS rejects smaller images
    static let maximumFileSize = 512 * 1024 * 1024
    static let headerSize = 0x200

    enum ParseError: Error, Equatable {
        case tooSmall
        case tooLarge
        case checksumMismatch(stored: UInt16, computed: UInt16)
        case badCodeSection(String)
        case dsiExclusive
    }

    /// Parses and validates a header. `header` must contain at least the first 0x200 bytes.
    static func parse(header: Data, fileSize: Int) throws -> ROMHeader {
        guard fileSize >= minimumFileSize, header.count >= headerSize else { throw ParseError.tooSmall }
        guard fileSize <= maximumFileSize else { throw ParseError.tooLarge }
        let bytes = [UInt8](header.prefix(headerSize))

        let stored = le16(bytes, 0x15E)
        let computed = crc16(bytes[0..<0x15E])
        guard stored == computed else { throw ParseError.checksumMismatch(stored: stored, computed: computed) }

        let h = ROMHeader(
            title: ascii(bytes[0x00..<0x0C]),
            gameCode: ascii(bytes[0x0C..<0x10]),
            makerCode: ascii(bytes[0x10..<0x12]),
            unitCode: bytes[0x12],
            arm9Offset: le32(bytes, 0x20), arm9Size: le32(bytes, 0x2C),
            arm7Offset: le32(bytes, 0x30), arm7Size: le32(bytes, 0x3C),
            bannerOffset: le32(bytes, 0x68),
            headerCRC: stored)

        let size = UInt64(fileSize)
        guard h.arm9Offset >= 0x200, UInt64(h.arm9Offset) + UInt64(h.arm9Size) <= size else {
            throw ParseError.badCodeSection("ARM9")
        }
        guard h.arm7Offset >= 0x200, UInt64(h.arm7Offset) + UInt64(h.arm7Size) <= size else {
            throw ParseError.badCodeSection("ARM7")
        }
        if h.unitCode == UnitCode.dsiExclusive.rawValue { throw ParseError.dsiExclusive }
        return h
    }

    /// CRC-16/MODBUS (poly 0xA001 reflected, init 0xFFFF), as used by the DS header checksum.
    static func crc16<C: Collection>(_ data: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }

    private static func le16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    private static func ascii(_ s: ArraySlice<UInt8>) -> String {
        let printable = s.prefix { $0 != 0 }.filter { $0 >= 0x20 && $0 < 0x7F }
        return String(decoding: printable, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}

/// The game's own banner (icon + localised titles), read from the user's ROM at import time.
struct ROMBanner: Sendable, Equatable {
    static let size = 0x840            // version 1 banner
    var englishTitleLines: [String]    // usually [name, subtitle?, publisher]
    var iconPNG: Data?

    var name: String? { englishTitleLines.first }
    var publisher: String? { englishTitleLines.count > 1 ? englishTitleLines.last : nil }
    var subtitle: String? { englishTitleLines.count > 2 ? englishTitleLines[1] : nil }

    static func parse(_ data: Data) -> ROMBanner? {
        guard data.count >= size else { return nil }
        let b = [UInt8](data.prefix(size))
        // English title: 0x340, 128 UTF-16LE code units.
        var units: [UInt16] = []
        for i in stride(from: 0x340, to: 0x440, by: 2) {
            let u = UInt16(b[i]) | UInt16(b[i + 1]) << 8
            if u == 0 { break }
            units.append(u)
        }
        let lines = String(decoding: units, as: UTF16.self)
            .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ROMBanner(englishTitleLines: lines, iconPNG: decodeIcon(b))
    }

    /// 32×32, 4 bpp, 4×4 tiles of 8×8 at 0x20; 16-colour BGR555 palette at 0x220 (index 0 transparent).
    private static func decodeIcon(_ b: [UInt8]) -> Data? {
        var palette = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let c = UInt16(b[0x220 + i * 2]) | UInt16(b[0x221 + i * 2]) << 8
            let r = UInt32(c & 0x1F) * 255 / 31, g = UInt32((c >> 5) & 0x1F) * 255 / 31, bl = UInt32((c >> 10) & 0x1F) * 255 / 31
            palette[i] = i == 0 ? 0 : (r | g << 8 | bl << 16 | 0xFF00_0000) // RGBA little-endian
        }
        var rgba = [UInt32](repeating: 0, count: 32 * 32)
        for tile in 0..<16 {
            let tx = (tile % 4) * 8, ty = (tile / 4) * 8
            for p in 0..<64 {
                let byte = b[0x20 + tile * 32 + p / 2]
                let index = p % 2 == 0 ? byte & 0x0F : byte >> 4
                rgba[(ty + p / 8) * 32 + tx + p % 8] = palette[Int(index)]
            }
        }
        if rgba.allSatisfy({ $0 == 0 }) { return nil }
        return pngData(rgba: rgba, width: 32, height: 32)
    }

    static func pngData(rgba: [UInt32], width: Int, height: Int) -> Data? {
        let data = rgba.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
