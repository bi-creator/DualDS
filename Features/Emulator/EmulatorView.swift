// DualDS — the in-game screen: both DS screens, on-screen controls and a minimal toolbar.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftData
import SwiftUI

struct EmulatorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: EmulatorViewModel
    @State private var showingDisplaySettings = false

    @AppStorage("display.arrangement") private var arrangement = DSScreenLayout.Arrangement.vertical
    @AppStorage("display.scaling") private var scaling = DSScreenLayout.Scaling.aspectFit
    @AppStorage("display.filter") private var filter = ScreenFilter.nearest
    @AppStorage("display.gap") private var gap = 0.0
    @AppStorage("display.swap") private var swapScreens = false
    @AppStorage("controls.visible") private var controlsVisible = true

    init(game: Game, storage: GameStorage) {
        _model = State(initialValue: EmulatorViewModel(game: game, storage: storage))
    }

    private var layout: DSScreenLayout {
        DSScreenLayout(arrangement: arrangement, scaling: scaling, gap: gap, swapScreens: swapScreens)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape { landscapeBody } else { portraitBody }
                overlay
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await model.start(context: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appBecameActive() } else { model.appBecameInactive() }
        }
        .sheet(isPresented: $showingDisplaySettings) { displaySettings }
    }

    private var screens: some View {
        DSScreensView(core: model.core, layout: layout, filter: filter) { x, y, touching in
            model.touch(x: x, y: y, touching: touching)
        }
        .accessibilityIdentifier("emulator.screens")
    }

    private var portraitBody: some View {
        VStack(spacing: 0) {
            toolbar.padding(.horizontal)
            screens
            if controlsVisible {
                VStack(spacing: 12) {
                    HStack { ShoulderButton(title: "L", button: .L, onChange: press); Spacer(); ShoulderButton(title: "R", button: .R, onChange: press) }
                    HStack { DPadView(onChange: press); Spacer(); FaceButtonsView(onChange: press) }
                    HStack(spacing: 24) { SystemButton(title: "SELECT", button: .select, onChange: press); SystemButton(title: "START", button: .start, onChange: press) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            if controlsVisible {
                VStack(spacing: 18) {
                    ShoulderButton(title: "L", button: .L, onChange: press)
                    Spacer()
                    DPadView(onChange: press)
                    Spacer()
                    SystemButton(title: "SELECT", button: .select, onChange: press)
                }
                .padding(.vertical, 12).padding(.leading, 12)
            }
            VStack(spacing: 0) { toolbar.padding(.horizontal, 8); screens }
            if controlsVisible {
                VStack(spacing: 18) {
                    ShoulderButton(title: "R", button: .R, onChange: press)
                    Spacer()
                    FaceButtonsView(onChange: press)
                    Spacer()
                    SystemButton(title: "START", button: .start, onChange: press)
                }
                .padding(.vertical, 12).padding(.trailing, 12)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            Button { close() } label: { Image(systemName: "xmark") }
                .accessibilityIdentifier("emulator.close")
                .accessibilityLabel("Close game")
            Button { model.togglePause() } label: {
                Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill")
            }
            .accessibilityIdentifier("emulator.pause")
            .accessibilityLabel(model.phase == .paused ? "Resume" : "Pause")
            Button { model.setFastForward(!model.isFastForward) } label: {
                Image(systemName: model.isFastForward ? "forward.fill" : "forward")
            }
            .accessibilityIdentifier("emulator.fastForward")
            .accessibilityLabel("Fast forward")
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(model.phase == .running ? String(format: "%.0f fps", model.core.measuredFPS) : "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityIdentifier("emulator.fps")
            }
            Menu {
                Button("Reset Game", systemImage: "arrow.counterclockwise") { model.reset() }
                Button("Display…", systemImage: "rectangle.split.1x2") { showingDisplaySettings = true }
                Toggle("Show Controls", isOn: $controlsVisible)
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityIdentifier("emulator.menu")
        }
        .font(.title3)
        .foregroundStyle(.white)
        .frame(height: 40)
    }

    @ViewBuilder private var overlay: some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(.white)
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text(message).multilineTextAlignment(.center)
                Button("Close") { close() }.buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .padding(24)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            .padding()
            .accessibilityIdentifier("emulator.error")
        case .paused:
            Text("Paused").font(.headline).padding(10).background(.ultraThinMaterial, in: .capsule)
                .foregroundStyle(.white).allowsHitTesting(false)
        case .running:
            EmptyView()
        }
    }

    private var displaySettings: some View {
        NavigationStack {
            Form {
                Picker("Arrangement", selection: $arrangement) { ForEach(DSScreenLayout.Arrangement.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Scaling", selection: $scaling) { ForEach(DSScreenLayout.Scaling.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Filter", selection: $filter) { ForEach(ScreenFilter.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Touch Screen First", isOn: $swapScreens)
                VStack(alignment: .leading) {
                    Text("Screen Gap: \(Int(gap)) pt")
                    Slider(value: $gap, in: 0...64, step: 2)
                }
            }
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDisplaySettings = false } } }
        }
        .presentationDetents([.medium])
    }

    private func press(_ button: DSButton, _ pressed: Bool) { model.setButton(button, pressed: pressed) }

    private func close() {
        model.finish(context: context)
        dismiss()
    }
}
