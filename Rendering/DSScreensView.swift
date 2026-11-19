// DualDS — SwiftUI wrapper for the Metal dual-screen view.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

struct DSScreensView: UIViewRepresentable {
    let core: DSCore
    var layout: DSScreenLayout
    var filter: ScreenFilter
    var onTouch: (Int, Int, Bool) -> Void

    func makeUIView(context: Context) -> DSMetalView {
        let view = DSMetalView()
        view.core = core
        return view
    }

    func updateUIView(_ view: DSMetalView, context: Context) {
        view.layout = layout
        view.filter = filter
        view.onTouch = onTouch
    }
}
