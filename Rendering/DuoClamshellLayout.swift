// DualDS — "DS clamshell" layout for iPhone Duo: with the device folded like a laptop, the DS top
// screen fills the upper half and the touch screen plus controls fill the lower half, mirroring a
// real Nintendo DS. Pure geometry, unit-tested; the fold rectangle comes from the system
// (GeometryProxy.reservedRegions(kind: .division), iOS 27.1+).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import CoreGraphics

struct DuoClamshellLayout: Equatable, Sendable {
    /// Above / below the fold, in the emulator view's coordinates.
    var upperArea: CGRect
    var lowerArea: CGRect
    var toolbar: CGRect
    var topScreen: CGRect
    var bottomScreen: CGRect
    /// Columns either side of the touch screen for the D-pad (left) and face buttons (right).
    var leftColumn: CGRect
    var rightColumn: CGRect
    /// Scale for the on-screen controls so they fill the columns on any window size.
    var controlScale: CGFloat

    static let toolbarHeight: CGFloat = 40
    /// Width the standard control clusters (D-pad, ABXY) need at scale 1.
    static let baseColumnWidth: CGFloat = 170
    static let shoulderRowHeight: CGFloat = 44
    static let systemRowHeight: CGFloat = 40

    /// - Parameters:
    ///   - bounds: the emulator view.
    ///   - fold: the horizontal fold region (zero height for a flat, unfolded display split at its middle).
    ///   - scale: pixels per point, for pixel alignment.
    static func make(bounds: CGRect, fold: CGRect, scale: CGFloat) -> DuoClamshellLayout {
        let pad: CGFloat = 10
        let upper = CGRect(x: bounds.minX, y: bounds.minY,
                           width: bounds.width, height: max(0, fold.minY - bounds.minY))
        let lower = CGRect(x: bounds.minX, y: min(bounds.maxY, fold.maxY),
                           width: bounds.width, height: max(0, bounds.maxY - fold.maxY))

        let toolbar = CGRect(x: upper.minX + pad, y: upper.minY, width: max(0, upper.width - 2 * pad), height: toolbarHeight)
        let topSlot = CGRect(x: upper.minX + pad, y: upper.minY + toolbarHeight,
                             width: max(0, upper.width - 2 * pad), height: max(0, upper.height - toolbarHeight - pad))

        let column = min(baseColumnWidth * 1.2, max(0, lower.width * 0.27))
        let screenSlot = CGRect(x: lower.minX + column, y: lower.minY + pad,
                                width: max(0, lower.width - 2 * column),
                                height: max(0, lower.height - 2 * pad))
        return DuoClamshellLayout(
            upperArea: upper, lowerArea: lower, toolbar: toolbar,
            topScreen: fit(in: topSlot, scale: scale),
            bottomScreen: fit(in: screenSlot, scale: scale),
            leftColumn: CGRect(x: lower.minX, y: lower.minY, width: column, height: lower.height),
            rightColumn: CGRect(x: lower.maxX - column, y: lower.minY, width: column, height: lower.height),
            controlScale: min(1.2, max(0.55, column / baseColumnWidth)))
    }

    /// Picks the system fold to use, if any: a horizontal division crossing the view's middle band.
    static func horizontalFold(in bounds: CGRect, divisions: [CGRect]) -> CGRect? {
        divisions.first { r in
            r.width >= bounds.width * 0.5 && r.width > r.height
                && r.midY > bounds.minY + bounds.height * 0.2 && r.midY < bounds.maxY - bounds.height * 0.2
        }
    }

    /// A zero-height fold at the vertical middle (unfolded-flat display, or the user's "Always" choice).
    static func middleFold(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: 0)
    }

    /// Largest 4:3 rectangle centred in `slot`, pixel aligned.
    static func fit(in slot: CGRect, scale: CGFloat) -> CGRect {
        guard slot.width > 0, slot.height > 0 else { return CGRect(origin: slot.origin, size: .zero) }
        let s = min(slot.width / 256, slot.height / 192)
        let size = CGSize(width: 256 * s, height: 192 * s)
        let r = CGRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2, width: size.width, height: size.height)
        guard scale > 0 else { return r }
        func a(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        return CGRect(x: a(r.minX), y: a(r.minY), width: a(r.width), height: a(r.height))
    }
}
