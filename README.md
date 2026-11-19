# DualDS

A native Nintendo DS emulator for iPhone and iPad, built on the [melonDS](https://melonds.kuribo64.net)
emulation core, with a SwiftUI frontend and Metal rendering.

> **Status: early development.** The emulator core layer runs and passes its tests headless.
> The iOS app shell builds and passes its tests on the Simulator; the core is not yet wired into the app. See [DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md).

DualDS includes **no games, BIOS or firmware**. You import `.nds` files that you legally own.
DualDS is not affiliated with Nintendo.

## Technology

Swift 5 / SwiftUI / UIKit (MVVM) · Objective-C++ bridge · C++20 session layer · melonDS 1.1
(interpreter, software renderer, FreeBIOS) · Metal · AVAudioEngine · XcodeGen · CMake + Ninja · XCTest/XCUITest

## Quick start

```sh
brew install cmake ninja xcodegen
git clone --recursive <repo-url> && cd DualDS
Scripts/bootstrap.sh
Scripts/ci.sh phase1          # build + test the app on the Simulator
Scripts/test-core-host.sh     # headless emulator tests on the Mac
```

Details: [Documentation/BUILDING.md](Documentation/BUILDING.md).

## Importing games

Use **Import Game** (or **+**) in the Library and choose one or more `.nds` files from Files. DualDS checks each
header, rejects duplicates and DSi-exclusive titles, and copies the file into its own storage; the
original is left untouched. Delete a game from its details sheet or with a long press.

## Documentation

* [Architecture](Documentation/ARCHITECTURE.md): layers, threads, how DualDS calls melonDS
* [Building](Documentation/BUILDING.md), including installing modified builds on your own device
* [Compatibility](Documentation/COMPATIBILITY.md): only measured results
* [Performance](Documentation/PERFORMANCE.md)
* [Licensing report](Documentation/LICENSING_REPORT.md) and [third-party licences](Documentation/THIRD_PARTY_LICENSES.md)
* [Known issues](KNOWN_ISSUES.md)

## Testing

* `Scripts/test-core-host.sh`: real emulation of the original test ROM (`Tests/Fixtures/testrom`)
* `Scripts/ci.sh phase1`: XCTest unit tests and XCUITest UI tests on the Simulator
* `Scripts/verify-licenses.sh`: licence, notice and "no bundled ROMs/BIOS" checks

## Licence

DualDS is free software under the **GNU General Public License v3.0 or later** (see [LICENSE](LICENSE)),
as required by melonDS. melonDS is © Arisotura and the melonDS team, and is used unmodified.
Third-party components inside melonDS are listed in
[Documentation/THIRD_PARTY_LICENSES.md](Documentation/THIRD_PARTY_LICENSES.md).
