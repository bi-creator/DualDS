# Development status

Last updated: 2026-11-19

| Phase | Status |
|---|---|
| 0. Investigation (melonDS, eDuo, licensing) | ✅ Done. See Documentation/LICENSING_REPORT.md, ARCHITECTURE.md |
| 1. Project foundation | 🟡 Written; **blocked on first Xcode build** (needs the Mac) |
| 2. melonDS core integration | 🟡 Portable core layer done and tested headless; iOS libraries scripted, not built; ObjC++ bridge not started |
| 3–15 | ⬜ Not started |

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

* Build status: **not yet built**. The dev VM has no Xcode or Swift. Next step is
  `Scripts/bootstrap.sh && Scripts/ci.sh phase1` on the Mac.
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
* Not done: iOS/Simulator library build (`Scripts/build-core.sh`, unrun), `DSCoreBridge` (ObjC++),
  loading a game inside the app.

## Outstanding issues

See KNOWN_ISSUES.md. Owner decisions are listed in LICENSING_REPORT.md §6.

## Next steps

1. On the Mac: `Scripts/bootstrap.sh`, `Scripts/ci.sh phase1`; fix anything Xcode reports; commit.
2. `Scripts/ci.sh core`: host tests with Apple clang plus the iOS/Simulator xcframework.
3. Phase 2 bridge: `DSCoreBridge` (ObjC++) over `DSSession`, then boot the test ROM inside the
   Simulator and on a device.
