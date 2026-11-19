// DualDS — SwiftUI wrapper for the Metal dual-screen view.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

struct DSScreensView: UIViewRepresentable {
    let core: DSCore
    var layout: DSScreenLayout
    var explicitFrames: DSScreenLayout.Frames? = nil
    var filter: ScreenFilter
    var onTouch: (Int, Int, Bool) -> Void

    init(core: DSCore, layout: DSScreenLayout, explicitFrames: DSScreenLayout.Frames? = nil, filter: ScreenFilter,
         onTouch: @escaping (Int, Int, Bool) -> Void) {
        self.core = core
        self.layout = layout
        self.explicitFrames = explicitFrames
        self.filter = filter
        self.onTouch = onTouch
    }

    func makeUIView(context: Context) -> DSMetalView {
        let view = DSMetalView()
        view.core = core
        return view
    }

    func updateUIView(_ view: DSMetalView, context: Context) {
        view.layout = layout
        view.explicitFrames = explicitFrames
        view.filter = filter
        view.onTouch = onTouch
    }
}
