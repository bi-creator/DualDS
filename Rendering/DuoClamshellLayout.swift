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
    /// Columns either side of the touch screen for the directional control (left) and face buttons (right).
    var leftColumn: CGRect
    var rightColumn: CGRect
    /// Row under the touch screen for Start / Select.
    var systemRow: CGRect
    /// Scale for the on-screen controls so they fill the columns on any window size.
    var controlScale: CGFloat

    static let toolbarHeight: CGFloat = 40
    /// Width / height of the larger control cluster (face buttons) at scale 1.
    static let clusterSize: CGFloat = 164
    static let shoulderRowHeight: CGFloat = 44
    static let systemRowHeight: CGFloat = 40
    /// Share of the lower half's width given to the touch screen (DS Lite proportions).
    static let touchScreenWidthShare: CGFloat = 0.54

    /// - Parameters:
    ///   - bounds: the emulator view.
    ///   - fold: the horizontal fold region (zero height for a flat, unfolded display split at its middle).
    ///   - scale: pixels per point, for pixel alignment.
    static func make(bounds: CGRect, fold: CGRect, scale: CGFloat) -> DuoClamshellLayout {
        let pad: CGFloat = 10
        let hingeClearance: CGFloat = 22   // keeps screen bezels off the hinge band
        let upper = CGRect(x: bounds.minX, y: bounds.minY,
                           width: bounds.width, height: max(0, fold.minY - bounds.minY))
        let lower = CGRect(x: bounds.minX, y: min(bounds.maxY, fold.maxY),
                           width: bounds.width, height: max(0, bounds.maxY - fold.maxY))

        let toolbar = CGRect(x: upper.minX + pad, y: upper.minY, width: max(0, upper.width - 2 * pad), height: toolbarHeight)
        let topSlot = CGRect(x: upper.minX + pad, y: upper.minY + toolbarHeight,
                             width: max(0, upper.width - 2 * pad), height: max(0, upper.height - toolbarHeight - hingeClearance))

        // Touch screen: as wide as the DS proportions allow, leaving a row for Start/Select below it.
        let screenSlotWidth = max(0, lower.width * touchScreenWidthShare)
        let screenSlotHeight = max(0, lower.height - hingeClearance - (systemRowHeight + 4) - pad)
        let fitted = fit(in: CGRect(x: 0, y: 0, width: screenSlotWidth, height: screenSlotHeight), scale: scale).size
        // Centre the touch screen + Start/Select row vertically in the space below the hinge.
        let spare = max(0, screenSlotHeight - fitted.height)
        let bottomScreen = pixelAligned(CGRect(x: lower.midX - fitted.width / 2, y: lower.minY + hingeClearance + spare / 2,
                                               width: fitted.width, height: fitted.height), scale: scale)

        let gutter: CGFloat = 6
        let left = CGRect(x: lower.minX, y: lower.minY,
                          width: max(0, bottomScreen.minX - gutter - lower.minX), height: lower.height)
        let right = CGRect(x: bottomScreen.maxX + gutter, y: lower.minY,
                           width: max(0, lower.maxX - bottomScreen.maxX - gutter), height: lower.height)
        let systemRow = CGRect(x: bottomScreen.minX, y: bottomScreen.maxY + 4,
                               width: bottomScreen.width, height: systemRowHeight)

        // Controls scale with their column, capped so they also fit under the shoulder row.
        let byWidth = (left.width - 8) / clusterSize
        let byHeight = (lower.height - shoulderRowHeight - pad) / clusterSize
        let controlScale = min(1.35, max(0.55, min(byWidth, byHeight)))

        return DuoClamshellLayout(
            upperArea: upper, lowerArea: lower, toolbar: toolbar,
            topScreen: fit(in: topSlot, scale: scale), bottomScreen: bottomScreen,
            leftColumn: left, rightColumn: right, systemRow: systemRow, controlScale: controlScale)
    }

    /// Vertical centre for the control clusters: level with the touch screen, but never under the shoulders.
    var clusterCentreY: CGFloat {
        max(bottomScreen.midY, lowerArea.minY + Self.shoulderRowHeight + Self.clusterSize * controlScale / 2)
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
        return pixelAligned(CGRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2,
                                   width: size.width, height: size.height), scale: scale)
    }

    static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0 else { return r }
        func a(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        return CGRect(x: a(r.minX), y: a(r.minY), width: a(r.width), height: a(r.height))
    }
}
