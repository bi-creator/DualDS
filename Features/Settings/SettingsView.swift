// DualDS — settings.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.classic
    @AppStorage(InterfaceSound.enabledKey) private var interfaceSounds = true
    @AppStorage(AudioSessionPolicy.mixKey) private var mixWithOthers = true
    @State private var showingSoundtrack = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        LabeledContent("Theme", value: theme.rawValue)
                    }
                    .accessibilityIdentifier("settings.theme")
                }
                Section {
                    Toggle("Interface Sounds", isOn: $interfaceSounds)
                    Toggle("Keep Other Music Playing", isOn: $mixWithOthers)
                        .accessibilityIdentifier("settings.mixWithOthers")
                    Button("Soundtrack (Apple Music)…") { showingSoundtrack = true }
                        .accessibilityIdentifier("settings.soundtrack")
                } header: {
                    Text("Sound")
                } footer: {
                    Text("With Keep Other Music Playing on, music from Spotify, YouTube Music or any music app keeps playing while you game.")
                }
                Section("Emulation") {
                    LabeledContent("Core", value: "melonDS \(AppConfiguration.melonDSVersion)")
                    LabeledContent("CPU", value: "Interpreter")
                    LabeledContent("3D renderer", value: "Software")
                }
                Section {
                    NavigationLink("About \(AppConfiguration.appName)") {
                        AboutView()
                    }
                    .accessibilityIdentifier("settings.about")
                }
            }
            .sheet(isPresented: $showingSoundtrack) { SoundtrackView() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
