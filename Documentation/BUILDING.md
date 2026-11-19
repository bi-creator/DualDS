# Building DualDS

## Requirements

* Apple Silicon Mac, Xcode 16 or newer with an iOS 17+ simulator runtime
* Homebrew packages: `brew install cmake ninja xcodegen`
* Optional, to rebuild the test ROM: `brew install arm-none-eabi-binutils` (the prebuilt ROM is committed)

## First-time setup

```sh
git clone --recursive <repo-url> DualDS && cd DualDS
Scripts/bootstrap.sh            # checks tools, fetches melonDS, generates DualDS.xcodeproj
cp Config/Signing.template.xcconfig Config/Signing.local.xcconfig   # then fill in your Team ID + bundle ID
```

`Config/Signing.local.xcconfig` is git-ignored. Without it, Simulator builds still work (they are unsigned).

## Build and test

| Command | What it does |
|---|---|
| `Scripts/ci.sh phase1` | licence checks → generate project → build app for Simulator → unit + UI tests |
| `Scripts/test-core-host.sh` | builds melonDS + DualDSCore for the Mac and runs the headless emulator tests |
| `Scripts/build-core.sh all` | builds `Build/DualDSCore.xcframework` (iOS arm64 + Simulator arm64) |
| `Scripts/verify-licenses.sh` | licence/notice/content compliance checks |

Every step writes `Build/logs/<step>.log` and `Build/logs/<step>.status` (`PASS` / `FAIL <code>`).

## Installing a modified build on your own iPhone (GPL-3.0 §6)

1. Open `DualDS.xcodeproj` in Xcode and sign in with any Apple ID (Xcode → Settings → Accounts; a free account works).
2. Set your team and a unique bundle ID in `Config/Signing.local.xcconfig`.
3. Connect the iPhone, enable Developer Mode (Settings → Privacy & Security), choose it as the run destination and press Run.

Free-account builds expire after 7 days and must be re-installed. That is an Apple limitation, not a DualDS one.

## Core build flags

melonDS is built with `ENABLE_JIT=OFF ENABLE_OGLRENDERER=OFF ENABLE_GDBSTUB=OFF BUILD_QT_SDL=OFF`,
and LTO on for iOS release builds. The device and Simulator slices are separate arm64 builds;
Intel simulators are not supported.
