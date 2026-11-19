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
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Text(title)
            .font(.system(size: min(size.width, size.height) * 0.36, weight: .semibold, design: .rounded))
            .frame(width: size.width, height: size.height)
            .background(shape.fill(.white.opacity(pressed ? 0.45 : 0.18)))
            .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 1))
            .foregroundStyle(.white)
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
    private let s = CGSize(width: 48, height: 48)

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                Color.clear.frame(width: s.width, height: s.height)
                ControlButton(title: "▲", button: .up, size: s, shape: AnyShape(RoundedRectangle(cornerRadius: 8)), onChange: onChange)
                Color.clear.frame(width: s.width, height: s.height)
            }
            GridRow {
                ControlButton(title: "◀", button: .left, size: s, shape: AnyShape(RoundedRectangle(cornerRadius: 8)), onChange: onChange)
                Color.clear.frame(width: s.width, height: s.height)
                ControlButton(title: "▶", button: .right, size: s, shape: AnyShape(RoundedRectangle(cornerRadius: 8)), onChange: onChange)
            }
            GridRow {
                Color.clear.frame(width: s.width, height: s.height)
                ControlButton(title: "▼", button: .down, size: s, shape: AnyShape(RoundedRectangle(cornerRadius: 8)), onChange: onChange)
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
