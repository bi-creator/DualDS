// DualDS — settings (Phase 1 shell).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
