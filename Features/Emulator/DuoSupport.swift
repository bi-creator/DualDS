// DualDS — iPhone Duo posture detection (hinge state + fold region) for the emulator screen.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

enum DuoLayoutMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic", always = "Always", off = "Off"
    var id: String { rawValue }
}

/// Hinge state as reported by the system; `.unavailable` on devices without a hinge or before iOS 27.1.
enum HingeState: Equatable {
    case unavailable, closed, partiallyOpen, fullyOpen
}

enum DuoPosture {
    /// The fold region inside `proxy`'s coordinate space, if the system reports a horizontal one.
    static func systemFold(in proxy: GeometryProxy) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: proxy.size)
        if #available(iOS 27.1, *) {
            let divisions = proxy.reservedRegions(kind: .division).map(\.frame)
            return DuoClamshellLayout.horizontalFold(in: bounds, divisions: divisions)
        }
        return nil
    }

    /// Decides where the clamshell split goes, or nil to use the regular layouts.
    static func fold(in proxy: GeometryProxy, mode: DuoLayoutMode, hinge: HingeState) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: proxy.size)
        let portrait = bounds.height > bounds.width
        #if DEBUG
        if ProcessInfo.processInfo.environment["DUALDS_SIMULATE_FOLD"] == "1" {
            return CGRect(x: 0, y: bounds.midY - 12, width: bounds.width, height: 24)
        }
        #endif
        switch mode {
        case .off:
            return nil
        case .always:
            return systemFold(in: proxy) ?? (portrait ? DuoClamshellLayout.middleFold(in: bounds) : nil)
        case .automatic:
            if let fold = systemFold(in: proxy) { return fold }       // folded like a laptop (~90°)
            // Open flat on the inner display: no division is reported, but the DS layout still fits
            // each half; only when the system says this is a hinged device.
            let aspect = bounds.height / max(bounds.width, 1)
            if hinge == .fullyOpen, portrait, aspect < 1.65 { return DuoClamshellLayout.middleFold(in: bounds) }
            return nil
        }
    }
}

/// Observes the hinge on iOS 27.1+ (no-op elsewhere).
struct HingeObserver: ViewModifier {
    @Binding var state: HingeState
    @Binding var angle: Double

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                guard let hinge = context.hinge else { state = .unavailable; return }
                angle = hinge.angle.degrees
                if hinge.status == .partiallyOpen { state = .partiallyOpen }
                else if hinge.status == .fullyOpen { state = .fullyOpen }
                else if hinge.status == .closed { state = .closed }
            }
        } else {
            content
        }
    }
}

/// Decorative speaker grille, as on the DS shell.
struct SpeakerGrille: View {
    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow { ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.18)).frame(width: 5, height: 5) } }
            }
        }
        .accessibilityHidden(true)
    }
}
