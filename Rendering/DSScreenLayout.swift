// DualDS — where the two DS screens go inside a view. Pure geometry, unit-tested.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import CoreGraphics

struct DSScreenLayout: Equatable, Sendable {
    enum Arrangement: String, CaseIterable, Identifiable, Sendable {
        case vertical = "Vertical", horizontal = "Side by Side"
        var id: String { rawValue }
    }

    enum Scaling: String, CaseIterable, Identifiable, Sendable {
        case aspectFit = "Aspect Fit", integer = "Integer (Pixel Perfect)", stretch = "Stretch"
        var id: String { rawValue }
    }

    static let screenSize = CGSize(width: 256, height: 192)

    var arrangement: Arrangement = .vertical
    var scaling: Scaling = .aspectFit
    /// Space between the two screens, in points.
    var gap: CGFloat = 0
    /// Show the bottom (touch) screen first.
    var swapScreens = false

    struct Frames: Equatable {
        var top: CGRect     // the DS top screen
        var bottom: CGRect  // the DS bottom (touch) screen
    }

    /// Frames in points inside `bounds`. `scale` is the display's pixels per point (for integer scaling
    /// and pixel alignment).
    func frames(in bounds: CGRect, scale: CGFloat) -> Frames {
        let s = Self.screenSize
        let gap = max(0, gap)
        let vertical = arrangement == .vertical
        let slot = CGSize(width: max(0, vertical ? bounds.width : (bounds.width - gap) / 2),
                          height: max(0, vertical ? (bounds.height - gap) / 2 : bounds.height))

        var size: CGSize
        switch scaling {
        case .stretch:
            size = slot
        case .aspectFit, .integer:
            let fit = min(slot.width / s.width, slot.height / s.height)
            size = CGSize(width: s.width * fit, height: s.height * fit)
            if scaling == .integer, scale > 0 {
                let pixels = (min(slot.width * scale / s.width, slot.height * scale / s.height)).rounded(.down)
                if pixels >= 1 { size = CGSize(width: s.width * pixels / scale, height: s.height * pixels / scale) }
            }
        }

        let group = vertical ? CGSize(width: size.width, height: size.height * 2 + gap)
                             : CGSize(width: size.width * 2 + gap, height: size.height)
        let origin = CGPoint(x: bounds.minX + (bounds.width - group.width) / 2,
                             y: bounds.minY + (bounds.height - group.height) / 2)
        let first = CGRect(origin: origin, size: size)
        let second = vertical ? first.offsetBy(dx: 0, dy: size.height + gap) : first.offsetBy(dx: size.width + gap, dy: 0)
        let a = Self.pixelAligned(first, scale: scale), b = Self.pixelAligned(second, scale: scale)
        return swapScreens ? Frames(top: b, bottom: a) : Frames(top: a, bottom: b)
    }

    /// Converts a point inside the bottom screen's frame to DS touch coordinates (0…255, 0…191).
    static func touchCoordinates(of point: CGPoint, in bottom: CGRect) -> (x: Int, y: Int)? {
        guard bottom.width > 0, bottom.height > 0, bottom.contains(point) else { return nil }
        let x = Int(((point.x - bottom.minX) / bottom.width * screenSize.width).rounded(.down))
        let y = Int(((point.y - bottom.minY) / bottom.height * screenSize.height).rounded(.down))
        return (min(max(x, 0), 255), min(max(y, 0), 191))
    }

    private static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0 else { return r }
        func a(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        return CGRect(x: a(r.minX), y: a(r.minY), width: a(r.width), height: a(r.height))
    }
}
