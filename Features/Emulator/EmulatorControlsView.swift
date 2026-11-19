// DualDS — on-screen DS controls and the switchable controller styles.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Styles are original designs that evoke classic controller families (dual-screen handheld,
// pocket handheld, arcade panel, modern gamepad). They deliberately do not reproduce any
// manufacturer's product design, colours, symbols or logos.

import SwiftUI
import UIKit

enum ControllerStyle: String, CaseIterable, Identifiable {
    case clamshell = "Clamshell", pocket = "Pocket", arcade = "Arcade", proPad = "Pro Pad"
    var id: String { rawValue }

    var summary: String {
        switch self {
        case .clamshell: "Dual-screen handheld: cross D-pad, diamond buttons"
        case .pocket: "Pocket handheld: two big diagonal buttons"
        case .arcade: "Arcade panel: 8-way stick, six buttons"
        case .proPad: "Modern gamepad: triggers, colour-coded buttons"
        }
    }

    /// Clamshell follows the user's colour theme; the others have their own look.
    func palette(clamshellTheme: ShellTheme) -> ShellPalette {
        switch self {
        case .clamshell:
            return clamshellTheme.palette
        case .pocket:
            var p = ShellPalette(shell: Color(red: 0.83, green: 0.81, blue: 0.75), shellEdge: Color(red: 0.70, green: 0.68, blue: 0.62),
                                 bezel: Color(red: 0.34, green: 0.35, blue: 0.41), button: Color(red: 0.24, green: 0.24, blue: 0.27),
                                 buttonPressed: Color(red: 0.12, green: 0.12, blue: 0.14), label: Color(red: 0.90, green: 0.89, blue: 0.86),
                                 chrome: Color(red: 0.30, green: 0.30, blue: 0.34))
            let plum = Color(red: 0.56, green: 0.20, blue: 0.40)
            p.faceTints = [.A: plum, .B: plum]
            return p
        case .arcade:
            var p = ShellPalette(shell: Color(red: 0.09, green: 0.09, blue: 0.11), shellEdge: Color(red: 0.20, green: 0.20, blue: 0.24),
                                 bezel: Color(red: 0.02, green: 0.02, blue: 0.03), button: Color(red: 0.24, green: 0.24, blue: 0.28),
                                 buttonPressed: Color(red: 0.40, green: 0.40, blue: 0.46), label: .white, chrome: .white)
            p.faceTints = [.A: Color(red: 0.88, green: 0.20, blue: 0.22), .B: Color(red: 0.96, green: 0.76, blue: 0.16),
                           .X: Color(red: 0.20, green: 0.48, blue: 0.92), .Y: Color(red: 0.22, green: 0.70, blue: 0.36),
                           .L: Color(red: 0.95, green: 0.50, blue: 0.16), .R: Color(red: 0.58, green: 0.34, blue: 0.86)]
            return p
        case .proPad:
            var p = ShellPalette(shell: Color(red: 0.16, green: 0.17, blue: 0.19), shellEdge: Color(red: 0.25, green: 0.26, blue: 0.29),
                                 bezel: Color(red: 0.05, green: 0.05, blue: 0.06), button: Color(red: 0.30, green: 0.31, blue: 0.34),
                                 buttonPressed: Color(red: 0.46, green: 0.47, blue: 0.52), label: Color(red: 0.92, green: 0.92, blue: 0.94),
                                 chrome: Color(red: 0.86, green: 0.86, blue: 0.90))
            p.faceTints = [.A: Color(red: 0.96, green: 0.45, blue: 0.40), .B: Color(red: 0.98, green: 0.76, blue: 0.28),
                           .X: Color(red: 0.30, green: 0.80, blue: 0.74), .Y: Color(red: 0.66, green: 0.55, blue: 0.98)]
            p.tintLabelsOnly = true
            return p
        }
    }

    /// Arcade's six-button panel already includes L and R.
    var hasShoulderButtons: Bool { self != .arcade }
}

// MARK: - Buttons

struct ControlButton: View {
    let title: String
    let button: DSButton
    var size: CGSize = CGSize(width: 56, height: 56)
    var shape: AnyShape = AnyShape(Circle())
    let onChange: (DSButton, Bool) -> Void

    @State private var pressed = false
    @Environment(\.shellPalette) private var palette
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        let tint = palette.faceTints[button]
        let fill = (tint != nil && !palette.tintLabelsOnly) ? tint! : palette.button
        let labelColor = (tint != nil && palette.tintLabelsOnly) ? tint! : palette.label
        // The drawn button is inset 4 pt inside its frame, so the touch target is larger than the art.
        ZStack {
            shape.fill(pressed ? palette.buttonPressed : fill)
                .shadow(color: .black.opacity(pressed ? 0 : 0.25), radius: pressed ? 0 : 2, y: pressed ? 0 : 1.5)
                .overlay(shape.stroke(palette.label.opacity(0.18), lineWidth: 1))
                .padding(4)
            Text(title)
                .font(.system(size: min(size.width, size.height) * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(labelColor)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    haptic.impactOccurred()
                    onChange(button, true)
                }
                .onEnded { _ in
                    pressed = false
                    onChange(button, false)
                }
        )
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityIdentifier("control.\(title)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Directional controls

/// Maps a touch offset from a control's centre to the D-pad directions it presses (8-way).
enum DirectionalInput {
    static func directions(dx: CGFloat, dy: CGFloat, deadZone: CGFloat) -> Set<DSButton> {
        guard hypot(dx, dy) > deadZone else { return [] }
        var angle = atan2(-dy, dx)                        // 0 = right, counter-clockwise
        if angle < 0 { angle += 2 * .pi }
        let sector = Int((angle + .pi / 8) / (.pi / 4)) % 8
        switch sector {
        case 0: return [.right]
        case 1: return [.right, .up]
        case 2: return [.up]
        case 3: return [.up, .left]
        case 4: return [.left]
        case 5: return [.left, .down]
        case 6: return [.down]
        default: return [.down, .right]
        }
    }
}

/// Tracks which directions are held so only changes are sent to the core.
private struct DirectionalGesture: ViewModifier {
    let size: CGFloat
    let deadZone: CGFloat
    @Binding var active: Set<DSButton>
    @Binding var offset: CGSize
    let onChange: (DSButton, Bool) -> Void
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let dx = v.location.x - size / 2, dy = v.location.y - size / 2
                    update(DirectionalInput.directions(dx: dx, dy: dy, deadZone: deadZone))
                    let r = hypot(dx, dy), maxR = size * 0.28
                    offset = r > maxR ? CGSize(width: dx / r * maxR, height: dy / r * maxR) : CGSize(width: dx, height: dy)
                }
                .onEnded { _ in update([]); offset = .zero }
        )
    }

    private func update(_ next: Set<DSButton>) {
        for b in active.subtracting(next) { onChange(b, false) }
        let added = next.subtracting(active)
        for b in added { onChange(b, true) }
        if !added.isEmpty { haptic.impactOccurred() }
        active = next
    }
}

/// One-piece cross D-pad: press or slide anywhere on it, diagonals included.
struct DPadView: View {
    let onChange: (DSButton, Bool) -> Void
    var size: CGFloat = 150
    @Environment(\.shellPalette) private var palette
    @State private var active: Set<DSButton> = []
    @State private var offset: CGSize = .zero

    var body: some View {
        let arm = size / 3
        ZStack {
            Group {
                RoundedRectangle(cornerRadius: 7, style: .continuous).frame(width: size - 8, height: arm)
                RoundedRectangle(cornerRadius: 7, style: .continuous).frame(width: arm, height: size - 8)
            }
            .foregroundStyle(palette.button)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1.5)
            ForEach([DSButton.up, .down, .left, .right], id: \.self) { b in
                let o = Self.armOffset(b, arm: arm)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active.contains(b) ? palette.buttonPressed : .clear)
                    .frame(width: arm - 6, height: arm - 6)
                    .offset(o)
                Image(systemName: Self.symbol(b)).font(.system(size: arm * 0.32, weight: .bold))
                    .foregroundStyle(palette.label.opacity(0.75)).offset(o)
            }
            Circle().fill(palette.label.opacity(0.12)).frame(width: arm * 0.45)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .modifier(DirectionalGesture(size: size, deadZone: size * 0.1, active: $active, offset: $offset, onChange: onChange))
        .accessibilityElement()
        .accessibilityLabel("D-pad")
        .accessibilityIdentifier("control.dpad")
    }

    static func armOffset(_ b: DSButton, arm: CGFloat) -> CGSize {
        switch b {
        case .up: CGSize(width: 0, height: -arm)
        case .down: CGSize(width: 0, height: arm)
        case .left: CGSize(width: -arm, height: 0)
        default: CGSize(width: arm, height: 0)
        }
    }

    static func symbol(_ b: DSButton) -> String {
        switch b {
        case .up: "triangle.fill"
        case .down: "arrowtriangle.down.fill"
        case .left: "arrowtriangle.left.fill"
        default: "arrowtriangle.right.fill"
        }
    }
}

/// Round 8-way arcade stick.
struct StickPad: View {
    let onChange: (DSButton, Bool) -> Void
    var size: CGFloat = 150
    @Environment(\.shellPalette) private var palette
    @State private var active: Set<DSButton> = []
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(palette.button).overlay(Circle().stroke(palette.label.opacity(0.15), lineWidth: 2))
            Circle().stroke(palette.label.opacity(0.10), lineWidth: 1).padding(size * 0.18)
            Circle()
                .fill(RadialGradient(colors: [palette.faceTints[.A] ?? palette.buttonPressed, .black.opacity(0.6)],
                                     center: .topLeading, startRadius: 2, endRadius: size * 0.3))
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .offset(offset)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .modifier(DirectionalGesture(size: size, deadZone: size * 0.12, active: $active, offset: $offset, onChange: onChange))
        .accessibilityElement()
        .accessibilityLabel("Joystick")
        .accessibilityIdentifier("control.dpad")
    }
}

struct DirectionalControl: View {
    let style: ControllerStyle
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        if style == .arcade { StickPad(onChange: onChange) } else { DPadView(onChange: onChange) }
    }
}

// MARK: - Face buttons

/// X top, Y left, A right, B bottom (DS order).
struct DiamondFace: View {
    let onChange: (DSButton, Bool) -> Void
    private let d: CGFloat = 56
    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow { Color.clear.frame(width: d, height: d); b("X", .X); Color.clear.frame(width: d, height: d) }
            GridRow { b("Y", .Y); Color.clear.frame(width: d, height: d); b("A", .A) }
            GridRow { Color.clear.frame(width: d, height: d); b("B", .B); Color.clear.frame(width: d, height: d) }
        }
    }
    private func b(_ t: String, _ k: DSButton) -> some View {
        ControlButton(title: t, button: k, size: CGSize(width: d, height: d), onChange: onChange)
    }
}

/// Two big diagonal buttons (B lower-left, A upper-right) with small X / Y above them.
struct PocketFace: View {
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        ZStack {
            ControlButton(title: "Y", button: .Y, size: CGSize(width: 44, height: 44), onChange: onChange).offset(x: -42, y: -56)
            ControlButton(title: "X", button: .X, size: CGSize(width: 44, height: 44), onChange: onChange).offset(x: 14, y: -72)
            ControlButton(title: "B", button: .B, size: CGSize(width: 66, height: 66), onChange: onChange).offset(x: -36, y: 26)
            ControlButton(title: "A", button: .A, size: CGSize(width: 66, height: 66), onChange: onChange).offset(x: 40, y: -8)
        }
        .frame(width: 164, height: 164)
    }
}

/// Six-button arcade panel: Y X L on top, B A R below, offset like a classic cabinet.
struct ArcadePanel: View {
    let onChange: (DSButton, Bool) -> Void
    private let d: CGFloat = 52
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) { b("Y", .Y); b("X", .X); b("L", .L) }
            HStack(spacing: 2) { b("B", .B); b("A", .A); b("R", .R) }.padding(.leading, 16)
        }
        .frame(width: 164, height: 164)
    }
    private func b(_ t: String, _ k: DSButton) -> some View {
        ControlButton(title: t, button: k, size: CGSize(width: d, height: d), onChange: onChange)
    }
}

struct FaceControl: View {
    let style: ControllerStyle
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        switch style {
        case .clamshell, .proPad: DiamondFace(onChange: onChange)
        case .pocket: PocketFace(onChange: onChange)
        case .arcade: ArcadePanel(onChange: onChange)
        }
    }
}

// MARK: - Shoulders and system buttons

struct ShoulderButton: View {
    let title: String
    let button: DSButton
    var style: ControllerStyle = .clamshell
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        if style == .proPad {
            let leading = button == .L
            ControlButton(title: title, button: button, size: CGSize(width: 96, height: 40),
                          shape: AnyShape(UnevenRoundedRectangle(topLeadingRadius: leading ? 18 : 6, bottomLeadingRadius: 6,
                                                                 bottomTrailingRadius: 6, topTrailingRadius: leading ? 6 : 18,
                                                                 style: .continuous)),
                          onChange: onChange)
        } else {
            ControlButton(title: title, button: button, size: CGSize(width: 84, height: 38), shape: AnyShape(Capsule()), onChange: onChange)
        }
    }
}

struct SystemButton: View {
    let title: String
    let button: DSButton
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        ControlButton(title: title, button: button, size: CGSize(width: 76, height: 32), shape: AnyShape(Capsule()), onChange: onChange)
    }
}
