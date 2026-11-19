// DualDS — on-screen DS controls. Each control is its own multi-touch gesture, so buttons
// can be held together (e.g. D-pad + A). Phase 5 adds layout editing, sizing and opacity.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI
import UIKit

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
        Text(title)
            .font(.system(size: min(size.width, size.height) * 0.36, weight: .semibold, design: .rounded))
            .frame(width: size.width, height: size.height)
            .background(shape.fill(pressed ? palette.buttonPressed : palette.button)
                .shadow(color: .black.opacity(pressed ? 0 : 0.22), radius: pressed ? 0 : 2, y: pressed ? 0 : 1.5))
            .overlay(shape.stroke(palette.label.opacity(0.18), lineWidth: 1))
            .foregroundStyle(palette.label)
            .contentShape(shape)
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
            .accessibilityLabel(title)
            .accessibilityIdentifier("control.\(title)")
            .accessibilityAddTraits(.isButton)
    }
}

struct DPadView: View {
    let onChange: (DSButton, Bool) -> Void
    @Environment(\.shellPalette) private var palette
    private let s = CGSize(width: 46, height: 46)

    var body: some View {
        let arm = AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Color.clear.frame(width: s.width, height: s.height)
                ControlButton(title: "▲", button: .up, size: s, shape: arm, onChange: onChange)
                Color.clear.frame(width: s.width, height: s.height)
            }
            GridRow {
                ControlButton(title: "◀", button: .left, size: s, shape: arm, onChange: onChange)
                Rectangle().fill(palette.button).frame(width: s.width, height: s.height)
                    .overlay(Circle().fill(palette.label.opacity(0.12)).padding(14))
                ControlButton(title: "▶", button: .right, size: s, shape: arm, onChange: onChange)
            }
            GridRow {
                Color.clear.frame(width: s.width, height: s.height)
                ControlButton(title: "▼", button: .down, size: s, shape: arm, onChange: onChange)
                Color.clear.frame(width: s.width, height: s.height)
            }
        }
    }
}

struct FaceButtonsView: View {
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow { Color.clear.frame(width: 52, height: 52); ControlButton(title: "X", button: .X, size: .init(width: 52, height: 52), onChange: onChange); Color.clear.frame(width: 52, height: 52) }
            GridRow { ControlButton(title: "Y", button: .Y, size: .init(width: 52, height: 52), onChange: onChange); Color.clear.frame(width: 52, height: 52); ControlButton(title: "A", button: .A, size: .init(width: 52, height: 52), onChange: onChange) }
            GridRow { Color.clear.frame(width: 52, height: 52); ControlButton(title: "B", button: .B, size: .init(width: 52, height: 52), onChange: onChange); Color.clear.frame(width: 52, height: 52) }
        }
    }
}

struct ShoulderButton: View {
    let title: String
    let button: DSButton
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        ControlButton(title: title, button: button, size: CGSize(width: 76, height: 34),
                      shape: AnyShape(Capsule()), onChange: onChange)
    }
}

struct SystemButton: View {
    let title: String
    let button: DSButton
    let onChange: (DSButton, Bool) -> Void
    var body: some View {
        ControlButton(title: title, button: button, size: CGSize(width: 64, height: 26),
                      shape: AnyShape(Capsule()), onChange: onChange)
    }
}
