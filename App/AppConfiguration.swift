// DualDS — static app metadata.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import Foundation
import UniformTypeIdentifiers

enum AppConfiguration {
    /// User-facing name (App Store and home screen). "DualDS" remains the project/code name.
    static let appName = "FoldPlay"

    /// Upstream melonDS commit the bundled core is built from (EmulatorCore/melonDS submodule).
    /// Scripts/verify-licenses.sh checks that this matches the submodule.
    static let melonDSCommit = "361ffa9501b631d53d7150fe57dec40a8341f664"
    static let melonDSVersion = "1.1"

    /// Where the corresponding source for each release is published (GPL-3.0 §6).
    /// Each release must also be tagged there (see Documentation/LICENSING_REPORT.md).
    static let sourceCodeURL: URL? = URL(string: "https://github.com/bi-creator/DualDS")

    /// Privacy policy page (repo bi-creator/foldplay-privacy, deployed on Vercel). The same URL goes
    /// into App Store Connect, App Privacy, Privacy Policy URL.
    static let privacyPolicyURL: URL? = URL(string: "https://foldplay-privacy.vercel.app/privacy")

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Bundled license texts shown in About → Licenses.
    static let legalDocuments: [(title: String, resource: String)] = [
        ("DualDS (GPL-3.0)", "LICENSE-DualDS"),
        ("melonDS (GPL-3.0)", "LICENSE-melonDS"),
        ("Third-party notices", "THIRD_PARTY_NOTICES"),
    ]

    static func legalText(_ resource: String) -> String? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

extension UTType {
    /// Nintendo DS ROM image (.nds). Declared as an imported type in Info.plist.
    static let ndsROM = UTType(importedAs: "com.dualds.nds-rom", conformingTo: .data)
}
