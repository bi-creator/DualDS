# Development status

Last updated: 2026-11-19

| Phase | Status |
|---|---|
| 0. Investigation (melonDS, eDuo, licensing) | ✅ Done. See Documentation/LICENSING_REPORT.md, ARCHITECTURE.md |
| 1. Project foundation | ✅ Builds and passes all tests on the iOS Simulator (Xcode 27.2) |
| 2. melonDS core integration | 🟡 Tested in the Simulator; Release **device build compiles and links** (arm64, 0 warnings); signed build needs the Apple account in Xcode; no test device yet |
| 3. Game import and library | ✅ Import, validation, dedupe, library, search/sort, details, artwork, delete; tests pass |
| 4. Graphics and dual-screen rendering | ✅ Metal renderer, layouts, scaling, filters, emulator screen; end-to-end pixel test passes |
| 5. Input | 🟡 On-screen controls + touch screen work; controller support, editing, sizing pending |
| 6–15 | ⬜ Not started |

## Phase 0: investigation

* melonDS @ `361ffa95` (v1.1, 18 Nov 2026): GPL-3.0-or-later. The core builds standalone with
  JIT, OpenGL, GDB stub and Qt off; no desktop dependencies remain.
* eDuo (GPL-3.0, unmodified melonDS, TestFlight) and Delta (AGPL-3.0, App Store) are the reference
  points. Both publish full source.
* Outcome: DualDS is GPL-3.0-or-later open source; melonDS stays an unmodified submodule.

## Phase 1: project foundation

Created: `project.yml` (XcodeGen), `Config/*.xcconfig`, `App/`, `Features/{Library,Settings,About}`,
`Resources/` (original icon, accent colour, bundled licence texts), `Tests/DualDSTests`,
`Tests/AppUITests`, `Scripts/{bootstrap,ci,lib,verify-licenses,generate-notices}.sh`, docs,
`.gitignore`, `LICENSE`.

* Build status (2026-11-19, Mac mini M5 Pro, Xcode 27.2 / build 27B52, iOS 27.2 Simulator,
  device **iPhone Duo**): `** BUILD SUCCEEDED **` with 0 compiler errors or warnings (warnings are errors);
  4/4 unit tests and 2/2 UI tests pass (`Build/logs/app-test-sim.log`). The app launches and
  `sim-run` captured both Duo displays; the library renders on display 1 (1398×2034), display 3
  (2007×2853) was dark at capture time.
* Tests written: 4 unit tests (UTType declaration, bundled licences, GPL text, commit SHA) and
  2 UI tests (first launch shows branding/import/settings; Settings → About → melonDS licence).
* `verify-licenses.sh`: all 8 checks pass.

## Phase 2 (started early because it can be verified without a Mac)

* `EmulatorCore/DualDSCore`: `DSSession` (lifecycle, paced emulation thread, input, frames,
  audio ring, battery saves, save states) plus a full melonDS `Platform::` implementation.
* `Tests/Fixtures/testrom`: an original ARM9/ARM7 test ROM assembled from source.
* `Tests/EmulatorCoreTests/core_tests.cpp`: 39 checks against real emulation. **All pass**
  (3 consecutive runs, Linux x86-64):
  * load errors (missing file, garbage, no ROM)
  * boot; top screen pixel-exact red, bottom screen pixel-exact blue
  * A button changes the picture, both synchronously and from another thread into the running core
  * SPU output at 802 frames per video frame (48 kHz); ring capped, overflow counted
  * save state round-trip is byte-identical; corrupt and missing states are rejected without
    breaking emulation
  * reset re-boots the ROM
  * threaded pacing at 59.77 fps; pause holds, resume continues; fast-forward runs faster
* Warnings in DualDS code: 0 (`-Wall -Wextra`).
* Mac host run (Apple clang, M5 Pro): all core checks pass; paced 59.82 fps; fast-forward 978 fps
  on the trivial test ROM.
* `Build/DualDSCore.xcframework` (ios-arm64 + ios-arm64-simulator, static, LTO off) built by
  `Scripts/build-core.sh` in ~13 s.
* `EmulatorBridge/DSCoreBridge.{h,mm}`: Objective-C API (`DSCore` in Swift) over DSSession. It does
  type and error conversion only; callbacks are atomic properties.
* `Tests/DualDSTests/EmulatorBridgeTests.swift`: 8 integration tests running the real core in the
  iOS Simulator app process (iPhone Duo, iOS 27.2). **All pass**: rejects bad files, boots,
  pixel-exact screens, A button, 48 kHz audio, exact save-state round-trip, corrupt-state
  recovery, threaded pacing (55–63 fps window), pause/resume.
* Full suite: 12 unit + 2 UI tests, `** TEST SUCCEEDED **`.
* Remaining for Phase 2: run the same tests on a physical device (needs DEVELOPMENT_TEAM and a
  connected iPhone/iPad).

## Phase 3: game import and library

* `Services/ROMHeader.swift`: header parse and validate (header CRC-16, ARM9/ARM7 ranges like
  melonDS's `ValidateROM`, size limits, DSi-exclusive rejected); banner English title and
  32×32 icon decoded from the user's ROM.
* `Services/GameImportService.swift`: security-scoped read, streaming SHA-256, duplicate
  rejection, free-space check, copy via temp file then move (no partial files), typed errors.
* `Services/GameStorage.swift`: Application Support/DualDS/{Games,Saves,States,Artwork}.
* `Models/Game.swift` (SwiftData); `Features/Library/*`: grid, search (title/code), sort
  (title/last played/recently imported), details (code, maker, size, imported, last played,
  play time, save data), custom artwork via PhotosPicker, delete (ROM, save, states, artwork).
* Works offline; no artwork is downloaded or bundled.
* Tests: 25 unit (`ROMHeaderTests` 7, `GameLibraryTests` 6, `EmulatorBridgeTests` 8, config 4)
  and 3 UI (first launch ×2, library import → details → delete). **All pass**, iPhone Duo
  simulator, iOS 27.2.
* Not yet tracked: last played and play time are stored but only updated once games can be
  launched (Phase 4).

## Phase 4: graphics and dual-screen rendering

* `Rendering/MetalRenderer.swift` (`DSMetalView`): MTKView subclass. Each refresh, the core copies
  the latest frame into a shared MTLBuffer (3-deep ring guarded by a semaphore; no per-frame
  allocation), a GPU blit fills two private textures, and two draws go into per-screen viewports.
  Nearest or linear sampling. Shared/buffer-backed textures were tried first and crashed in the
  iOS Simulator (unsupported there), hence the blit.
* Shaders compile at runtime (`ShaderLibrary.swift`), so no Metal Toolchain download is needed.
* `Rendering/DSScreenLayout.swift`: vertical / side-by-side, aspect-fit / integer (pixel
  perfect) / stretch, configurable gap, screen swap, pixel alignment, touch mapping.
* `Features/Emulator`: emulator screen launched from the library's Play button (details sheet or
  context menu). Portrait and landscape control layouts, pause/resume, fast-forward, reset, FPS,
  display settings (persisted), auto-pause plus save flush when backgrounded, play time and last
  played recorded.
* Touch screen: single-touch tracking on the bottom-screen frame, clamped at the edges.
* Concurrency: callbacks invoked off the main thread (Metal completion, core stop) are built in
  `nonisolated` helpers so they never inherit main-actor isolation.
* CI now fails on any compiler warning in DualDS sources (`warnings-sim` step).
* Tests: 32 unit (7 new layout/touch) and 4 UI. The new `EmulatorUITests` imports the test ROM,
  presses Play and samples the live Metal-rendered screens (top red, bottom blue). **All pass.**

## Repository

Published (GPL-3.0) at https://github.com/bi-creator/DualDS, branch `main`. About → Source Code links there.

## Outstanding issues

See KNOWN_ISSUES.md. Owner decisions are listed in LICENSING_REPORT.md §6.

## Next steps

1. Signed device build: sign in to the team's Apple account in Xcode > Settings > Accounts; physical-device tests once hardware is available.
2. Phase 5: input polish (Game Controller framework, remapping, layout editor, sizing, opacity).
3. Phase 6: audio (AVAudioEngine).
