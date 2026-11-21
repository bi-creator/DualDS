// DualDS — the in-game screen: both DS screens, on-screen controls and a minimal toolbar.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftData
import SwiftUI

struct EmulatorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var model: EmulatorViewModel
    @State private var showingDisplaySettings = false
    @State private var showingSaveStates = false
    @State private var showingSoundtrack = false
    @State private var soundtrack = SoundtrackPlayer.shared
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.classic

    @AppStorage("display.arrangement") private var arrangement = DSScreenLayout.Arrangement.vertical
    @AppStorage("display.scaling") private var scaling = DSScreenLayout.Scaling.aspectFit
    @AppStorage("display.filter") private var filter = ScreenFilter.nearest
    @AppStorage("display.gap") private var gap = 0.0
    @AppStorage("display.swap") private var swapScreens = false
    @AppStorage("controls.visible") private var controlsVisible = true
    @AppStorage("audio.volume") private var volume = 1.0
    @AppStorage("audio.muted") private var muted = false
    @AppStorage("display.shellTheme") private var shellTheme = ShellTheme.lilac
    @AppStorage("controls.style") private var controllerStyle = ControllerStyle.clamshell
    @AppStorage("display.duoLayout") private var duoMode = DuoLayoutMode.automatic
    @State private var hinge: HingeState = .unavailable
    @State private var hingeAngle = 0.0

    init(game: Game, storage: GameStorage) {
        _model = State(initialValue: EmulatorViewModel(game: game, storage: storage))
    }

    /// An era theme colours every controller style; Classic keeps each style's own look.
    private var palette: ShellPalette { theme.palette ?? controllerStyle.palette(clamshellTheme: shellTheme) }

    private var layout: DSScreenLayout {
        DSScreenLayout(arrangement: arrangement, scaling: scaling, gap: gap, swapScreens: swapScreens)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                palette.shell.ignoresSafeArea()
                if let fold = DuoPosture.fold(in: geo, mode: duoMode, hinge: hinge) {
                    clamshellBody(DuoClamshellLayout.make(bounds: CGRect(origin: .zero, size: geo.size), fold: fold,
                                                          scale: displayScale))
                } else if landscape {
                    landscapeBody
                } else {
                    portraitBody
                }
                overlay
            }
        }
        .modifier(HingeObserver(state: $hinge, angle: $hingeAngle))
        .environment(\.shellPalette, palette)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            model.setAudio(volume: volume, muted: muted)
            await model.start(context: context)
        }
        .onChange(of: volume) { _, v in model.setAudio(volume: v, muted: muted) }
        .onChange(of: muted) { _, m in model.setAudio(volume: volume, muted: m) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appBecameActive() } else { model.appBecameInactive() }
        }
        .sheet(isPresented: $showingDisplaySettings) { displaySettings }
        .sheet(isPresented: $showingSaveStates, onDismiss: { model.resumeAfterMenu() }) {
            SaveStatesView(model: model).onAppear { model.pauseForMenu() }
        }
        .sheet(isPresented: $showingSoundtrack, onDismiss: { model.resumeAfterMenu() }) {
            SoundtrackView().onAppear { model.pauseForMenu() }
        }
        .alert("Save States", isPresented: Binding(get: { model.stateError != nil && !showingSaveStates },
                                                  set: { if !$0 { model.stateError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.stateError ?? "") }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: .capsule).padding(.top, 48)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("emulator.toast")
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
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
                    if controllerStyle.hasShoulderButtons {
                        HStack {
                            ShoulderButton(title: "L", button: .L, style: controllerStyle, onChange: press)
                            Spacer()
                            ShoulderButton(title: "R", button: .R, style: controllerStyle, onChange: press)
                        }
                    }
                    HStack { DirectionalControl(style: controllerStyle, onChange: press); Spacer(); FaceControl(style: controllerStyle, onChange: press) }
                    HStack(spacing: 24) { SystemButton(title: "SELECT", button: .select, onChange: press); SystemButton(title: "START", button: .start, onChange: press) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    /// iPhone Duo folded like a laptop: top screen above the fold; touch screen and controls below.
    private func clamshellBody(_ c: DuoClamshellLayout) -> some View {
        ZStack(alignment: .topLeading) {
            // Hinge band across the crease.
            Rectangle().fill(palette.shellEdge)
                .frame(width: c.upperArea.width + 400, height: max(10, c.lowerArea.minY - c.upperArea.maxY + 10))
                .position(x: c.upperArea.midX, y: (c.upperArea.maxY + c.lowerArea.minY) / 2)
            ScreenBezel(rect: c.topScreen)
            ScreenBezel(rect: c.bottomScreen)
            DSScreensView(core: model.core, layout: layout,
                          explicitFrames: .init(top: c.topScreen, bottom: c.bottomScreen), filter: filter) { x, y, touching in
                model.touch(x: x, y: y, touching: touching)
            }
            .accessibilityIdentifier("emulator.screens")

            toolbar.frame(width: c.toolbar.width, height: c.toolbar.height)
                .position(x: c.toolbar.midX, y: c.toolbar.midY)

            if c.topScreen.minX - c.upperArea.minX > 44 {
                SpeakerGrille().position(x: (c.upperArea.minX + c.topScreen.minX) / 2, y: c.topScreen.midY)
                SpeakerGrille().position(x: (c.topScreen.maxX + c.upperArea.maxX) / 2, y: c.topScreen.midY)
            }

            if controlsVisible {
                let s = c.controlScale
                let shoulderY = c.lowerArea.minY + DuoClamshellLayout.shoulderRowHeight / 2 + 2
                if controllerStyle.hasShoulderButtons {
                    ShoulderButton(title: "L", button: .L, style: controllerStyle, onChange: press).scaleEffect(min(s, 1.1))
                        .position(x: c.leftColumn.midX, y: shoulderY)
                    ShoulderButton(title: "R", button: .R, style: controllerStyle, onChange: press).scaleEffect(min(s, 1.1))
                        .position(x: c.rightColumn.midX, y: shoulderY)
                }
                DirectionalControl(style: controllerStyle, onChange: press).scaleEffect(s)
                    .position(x: c.leftColumn.midX, y: c.clusterCentreY)
                FaceControl(style: controllerStyle, onChange: press).scaleEffect(s)
                    .position(x: c.rightColumn.midX, y: c.clusterCentreY)
                HStack(spacing: 18) {
                    SystemButton(title: "SELECT", button: .select, onChange: press)
                    SystemButton(title: "START", button: .start, onChange: press)
                }
                .scaleEffect(min(1, max(0.8, s)))
                .position(x: c.systemRow.midX, y: c.systemRow.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            if controlsVisible {
                VStack(spacing: 18) {
                    if controllerStyle.hasShoulderButtons { ShoulderButton(title: "L", button: .L, style: controllerStyle, onChange: press) }
                    Spacer()
                    DirectionalControl(style: controllerStyle, onChange: press)
                    Spacer()
                    SystemButton(title: "SELECT", button: .select, onChange: press)
                }
                .padding(.vertical, 12).padding(.leading, 12)
            }
            VStack(spacing: 0) { toolbar.padding(.horizontal, 8); screens }
            if controlsVisible {
                VStack(spacing: 18) {
                    if controllerStyle.hasShoulderButtons { ShoulderButton(title: "R", button: .R, style: controllerStyle, onChange: press) }
                    Spacer()
                    FaceControl(style: controllerStyle, onChange: press)
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
            Button { showingSoundtrack = true } label: {
                Image(systemName: soundtrack.isPlaying ? "music.note.list" : "music.note")
            }
            .accessibilityIdentifier("emulator.soundtrack")
            .accessibilityLabel("Soundtrack")
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(model.phase == .running ? String(format: "%.0f fps", model.core.measuredFPS) : "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.chrome.opacity(0.6))
                    .accessibilityIdentifier("emulator.fps")
            }
            Menu {
                Button("Quick Save", systemImage: "square.and.arrow.down") { Task { await model.quickSave(context: context) } }
                Button("Quick Load", systemImage: "square.and.arrow.up") { Task { await model.quickLoad(context: context) } }
                Button("Save States…", systemImage: "square.stack.3d.up") { showingSaveStates = true }
                Divider()
                Button("Reset Game", systemImage: "arrow.counterclockwise") { model.reset() }
                Button("Display…", systemImage: "rectangle.split.1x2") { showingDisplaySettings = true }
                Picker("Controller Layout", selection: $controllerStyle) {
                    ForEach(ControllerStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Button("Soundtrack…", systemImage: "music.note") { showingSoundtrack = true }
                if soundtrack.hasQueue {
                    Button(soundtrack.isPlaying ? "Pause Music" : "Play Music", systemImage: soundtrack.isPlaying ? "pause" : "play") {
                        Task { await soundtrack.togglePlayPause() }
                    }
                    Button("Next Song", systemImage: "forward") { Task { await soundtrack.next() } }
                }
                Toggle("Show Controls", isOn: $controlsVisible)
                Toggle("Mute Sound", isOn: $muted)
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityIdentifier("emulator.menu")
        }
        .font(.title3)
        .foregroundStyle(palette.chrome)
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
            if let audioError = model.audioError {
                VStack {
                    Spacer()
                    Label(audioError, systemImage: "speaker.slash").font(.caption).padding(8)
                        .background(.ultraThinMaterial, in: .capsule).foregroundStyle(.white)
                }
                .allowsHitTesting(false)
                .accessibilityIdentifier("emulator.audioError")
            }
        }
    }

    private var displaySettings: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Controller Layout", selection: $controllerStyle) {
                        ForEach(ControllerStyle.allCases) { style in
                            VStack(alignment: .leading) { Text(style.rawValue); Text(style.summary).font(.caption).foregroundStyle(.secondary) }
                                .tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    Picker("Theme", selection: $theme) { ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) } }
                    if controllerStyle == .clamshell && theme == .classic {
                        Picker("Colour", selection: $shellTheme) { ForEach(ShellTheme.allCases) { Text($0.rawValue).tag($0) } }
                    }
                }
                Picker("Arrangement", selection: $arrangement) { ForEach(DSScreenLayout.Arrangement.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Scaling", selection: $scaling) { ForEach(DSScreenLayout.Scaling.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Filter", selection: $filter) { ForEach(ScreenFilter.allCases) { Text($0.rawValue).tag($0) } }
                VStack(alignment: .leading) {
                    Text("Game Volume: \(Int(volume * 100))%")
                    Slider(value: $volume, in: 0...1)
                }
                Picker("iPhone Duo Fold Layout", selection: $duoMode) { ForEach(DuoLayoutMode.allCases) { Text($0.rawValue).tag($0) } }
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
        .presentationDetents([.medium, .large])
    }

    private func press(_ button: DSButton, _ pressed: Bool) { model.setButton(button, pressed: pressed) }

    private func close() {
        model.finish(context: context)
        dismiss()
    }
}
