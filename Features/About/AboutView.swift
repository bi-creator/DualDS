// DualDS — about, credits and license texts.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConfiguration.appName).font(.title2.bold())
                    Text("Version \(AppConfiguration.marketingVersion) (\(AppConfiguration.buildNumber))")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Credits") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("melonDS").font(.headline)
                    Text("Emulation core by Arisotura and the melonDS team, used unmodified under the GNU GPL v3.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Commit \(String(AppConfiguration.melonDSCommit.prefix(12)))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text("DualDS is not affiliated with or endorsed by Nintendo. Nintendo DS is a trademark of Nintendo. No games, BIOS or firmware are included.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Source Code") {
                if let url = AppConfiguration.sourceCodeURL {
                    Link("View the complete source code", destination: url)
                } else {
                    Text("Source code link is added before public release.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Licenses") {
                ForEach(AppConfiguration.legalDocuments, id: \.resource) { doc in
                    NavigationLink(doc.title) {
                        LegalTextView(title: doc.title, resource: doc.resource)
                    }
                }
            }
        }
        .navigationTitle("About")
        .accessibilityIdentifier("about.list")
    }
}

struct LegalTextView: View {
    let title: String
    let resource: String

    var body: some View {
        ScrollView {
            Text(AppConfiguration.legalText(resource) ?? "License text missing from the app bundle.")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
