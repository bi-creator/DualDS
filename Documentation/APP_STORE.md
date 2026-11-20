# Release checklist: TestFlight and App Store

Store name: **FoldPlay** · Bundle ID: `com.bicreator.dualds` · Team: individual account
Project/code name: DualDS · Source: https://github.com/bi-creator/DualDS (GPL-3.0)

## TestFlight (internal testing)

| Step | Status |
|---|---|
| Apple Developer Program membership, Paid Apps agreement, tax and banking | ✅ (account holder) |
| Bundle ID `com.bicreator.dualds` registered (Certificates, IDs & Profiles) | ⏳ |
| App Store Connect app record "FoldPlay" | ⏳ |
| Apple ID signed in under Xcode → Settings → Accounts (for signing and upload) | ⏳ |
| App icon 1024×1024, no alpha | ✅ |
| `ITSAppUsesNonExemptEncryption = NO` (export compliance) | ✅ |
| Privacy manifest `Resources/PrivacyInfo.xcprivacy` (no tracking, no data collected; UserDefaults CA92.1, disk space E174.1, system boot time 35F9.1) | ✅ |
| No ROMs, BIOS, firmware or third-party games inside the app (`Scripts/verify-licenses.sh`) | ✅ |
| Upload: `Scripts/ci.sh testflight`. Release archive, timestamp build number, upload, then git tag `v<version>-build.<n>` pushed (GPL corresponding source) | ready |

Internal testers (up to 100 App Store Connect users) need no Beta App Review. Installing needs a
physical iPhone/iPad with the TestFlight app; the Simulator can't install TestFlight builds.

## External TestFlight / public App Store (later)

* Beta App Review / App Review: emulators are allowed (guideline 4.7); the app must not offer or
  link to game downloads (FoldPlay only imports files the user supplies). Notes for review: explain
  that no games are included, and how to test with a legally obtained homebrew file.
* Privacy policy URL (required). Content: no data collected, games stay on device. Privacy
  "nutrition label": Data Not Collected.
* Age rating questionnaire. Category: Games or Utilities (decide).
* Screenshots: 6.9" iPhone, plus iPhone Duo if App Store Connect offers a size for it. Use only
  homebrew or original content in screenshots, never commercial game imagery.
* Description must not use Nintendo trademarks except descriptively ("plays Nintendo DS
  homebrew and games you own"), and must state there is no affiliation.
* GPL: the description or support URL links to the source; every build is tagged (done by the
  script). Decide whether to contact the melonDS team first (LICENSING_REPORT.md §4).
* Version bump: `MARKETING_VERSION` in `project.yml`.
