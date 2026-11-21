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
| 10. iPhone Duo / foldable adaptation | 🟡 DS clamshell layout for the folded (~90°) Duo, plus flat-open split; verified with a simulated fold. Pending: real fold in Simulator/device |
| 6. Audio | ✅ AVAudioEngine output, latency cap, interruptions and route changes, mute/volume; tests pass (Simulator) |
| 7. Saves and save states | ✅ Battery saves (auto, atomic); save-state slots with screenshots, rename/delete, Quick Save/Load; tests pass |
| 8–9, 11–15 | ⬜ Not started (Bluetooth controllers deferred by owner) |

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

## Phase 10 (started early, owner priority: iPhone Duo)

* **DS clamshell layout**: with the Duo folded like a laptop, the DS top screen fills the upper
  half; below the crease sit the touch screen (centre), D-pad (left), ABXY (right), L/R (top
  corners) and Start/Select (bottom right).
* Fold detection uses Apple's iOS 27.1 APIs: `GeometryProxy.reservedRegions(kind: .division)`
  for the crease frame and `onHingeChange` for hinge status and angle, behind `#available`.
  Only a horizontal crease across the middle band is used. A vertical (book-posture) crease falls
  back to the regular layouts.
* Fully open flat on the inner display (no crease reported, hinge `fullyOpen`, portrait): the
  same layout, split at the middle.
* Display settings → "iPhone Duo Fold Layout": Automatic / Always / Off.
* Handheld shell themes (`Features/Emulator/ShellTheme.swift`, original designs): Lilac
  (default), Blush, Silver and Midnight. Shell body, screen bezels, a hinge band at the crease,
  speaker grilles, a one-piece cross D-pad and themed buttons. The Metal view is transparent
  outside the screens so the shell shows through.
* `Rendering/DuoClamshellLayout.swift` (pure geometry; 6 unit tests) and
  `Features/Emulator/DuoSupport.swift`.
* UI test `testFoldedDuoShowsTopScreenAboveFoldAndControlsBelow` (DEBUG fold at mid-window): top
  screen above the fold, touch screen below, D-pad left and face buttons right of it, pixels
  red/blue. **Passes.** Not yet exercised: a real crease from the Simulator's fold control or a device.

## Phase 6: audio

* `Rendering/AudioRenderer.swift`: `AVAudioSourceNode` render block (built `nonisolated`, runs on
  the real-time thread) pulls the core's 48 kHz stereo s16 ring through a preallocated scratch
  buffer and converts it to float. Buffered audio above 120 ms is discarded to cap latency;
  underruns output silence. Stats are counted under an unfair lock.
* Audio session `.playback` with a 5 ms preferred IO buffer. Restarts after interruptions (calls,
  Siri), `AVAudioEngineConfigurationChange` (headphones, Bluetooth, route or sample-rate
  changes) and media-services resets.
* Audio pauses and resumes with the emulator (including on backgrounding) and stops on close.
  Fast-forward is silent. Mute and volume are in the emulator menu and display settings, and are
  persisted. If audio cannot start, the game keeps running and shows a "Sound is unavailable"
  notice.
* A/V sync: video and audio share the emulation clock, and the latency cap bounds drift. No time
  stretching yet.
* Tests: `AudioRendererTests` (latency cap and silence padding; live AVAudioEngine output: >60k
  SPU frames in 2 s, <20% silence, nothing rendered while paused). **Both pass on the Simulator.**
  Full suite: 40 unit + 5 UI.

## Fold layout tuning and controller styles (owner request, 2026-11-19)

* Lower half: the touch screen takes ~54% of the width (DS Lite proportions). The touch screen
  and Start/Select row are centred vertically below the hinge, with the controls level with the
  screen and scaled to their columns. Hit areas are 4 pt larger than the drawn buttons.
* D-pad is now one control: press or slide anywhere on it, diagonals included (8-way).
* Switchable controller layouts (`ControllerStyle`, in-game menu → Controller Layout, or Display
  settings). All are original designs that evoke classic families without copying any product:
  * Clamshell: cross D-pad, diamond ABXY, follows the colour theme
  * Pocket: warm-grey body, two big diagonal A/B, small X/Y
  * Arcade: 8-way stick, six-button panel (Y X L / B A R)
  * Pro Pad: graphite body, wide L/R triggers, colour-coded face letters
* UI test `testEveryControllerStyleLaysOutAroundTheTouchScreen` checks each style's layout
  (directional control left of the touch screen, ABXY right, L/R and Start/Select present) and
  saves a screenshot of each.

## Phase 7: saves and save states

* Battery saves: written by the core after 1 s of quiet and on pause/stop, via tmp + rename
  (Phase 2); shown as "Save data" in game details.
* Save states (`Models/SaveState.swift`, `Services/SaveStateStore.swift`,
  `Features/SaveStates/SaveStateView.swift`): Quick slot plus 8 manual slots per game. Each
  stores the melonDS state file, a 256×384 screenshot of both screens, a timestamp, a renameable
  name and the core version. Saving or loading runs off the main thread. A slot is replaced only
  after the new state is written. Loading checks the game and that the file exists, and the core
  rolls back if a file is rejected. Errors are shown with a version hint, and the game continues.
* Emulator menu: Quick Save, Quick Load, Save States… (the game pauses while the sheet is open).
  Deleting a game removes its states.
* Tests: `SaveStateStoreTests` (5, real core and files) and `testSaveAndLoadAStateFromTheMenu`
  (slot save/load and Quick Save/Load end to end). **All pass.**

## Release preparation (2026-11-20)

* Store name **FoldPlay** (display name and in-app brand; DualDS stays the project name). Version 1.0.
* App ID `com.bicreator.dualds` registered (team T429AK4VVK); App Store Connect app "FoldPlay"
  created (Apple ID 6837318848, SKU dualds).
* `Resources/PrivacyInfo.xcprivacy`: no tracking, no data collected; required-reason APIs declared.
* `Scripts/ci.sh testflight`: unsigned Release archive, then App Store export signed with automatic
  distribution signing and uploaded; timestamp build numbers; pushes the git tag
  `v<version>-build.<n>` for GPL corresponding source. Checklist: Documentation/APP_STORE.md.
* No games are bundled. Test games (homebrew the owner downloaded) are loaded into the Simulator
  only, from `Build/import/` (git-ignored).

## Themes and music (owner request, 2026-11-21)

* **10 era themes + Classic** (`Features/Themes`): Neon Maze (1980 arcade mazes), Vector Void (1981
  vector shooters), Pixel Kingdom (1985 platformers), Dungeon Map (1986 dungeon quests), Block Rain
  (1989 falling blocks), Pocket Green (1989 monochrome handhelds), Speed Zone (1991 16-bit speed),
  Street Brawl (1991 arcade fighters), Polygon Rally (1997 early 3D racing), Fog Town (1999 survival
  horror). Each sets accent, light/dark, font design, a procedural backdrop (drawn in code), the
  controller colours for every controller style, and a synthesized tap sound. All original: no game
  names, characters, logos, music or art. Picker in Settings → Theme, and in the game menu.
  Contrast of button labels ≥ 3:1 is unit-tested; `ThemeUITests` screenshots every theme.
* **Music while playing.** (A) `AudioSessionPolicy`: the library uses `.ambient`; games use
  `.playback` with `.mixWithOthers` (default on, Settings → Keep Other Music Playing), so Spotify,
  YouTube Music or Apple Music keep playing under the game. (B) `SoundtrackPlayer` +
  `SoundtrackView`: MusicKit search, a saved song list, play/pause/next/shuffle, a one-tap starter
  list of the owner's eight songs, subscription offer. Opened from the game toolbar (♪) and Settings.
  YouTube playback was rejected: its API terms forbid audio-only or background play.
* Not verifiable in the Simulator: MusicKit playback (needs a device, an Apple Music subscription and
  the MusicKit App Service on the App ID).

## FoldPlay Store and FoldPlay Originals (owner request, 2026-11-21)

* First Original: **Back Alley Brawl** (private repo bi-creator/FoldPlayGames, BlocksDS). Three
  stages (night street, harbor docks, neon rooftops), three named bosses, breakable cans with food,
  original PSG chiptune music per stage, touch-screen HUD. `GameROMUITests` plays it on the folded
  layout and loads stages 2 and 3 from test-only ROM variants.
* StoreKit 2 purchase flow: `StoreService` (products, entitlements, Transaction.updates, restore),
  `StoreView` (bag button in the library), `OriginalsInstaller` (unpacks the bundled game into the
  library). Games ship as scrambled packages in `Build/Originals` (gitignored; built by the `games`
  step via `Scripts/package-originals.py`); `testflight` refuses to upload without them.
* In-app purchase `com.bicreator.dualds.backalleybrawl` (Apple ID 6837720558), non-consumable,
  ₹99 base (India) / US$0.99. Must be submitted together with the next app version.
* Tests: `StoreTests` (SKTestSession: product, purchase, refund, package round trip, real package
  install), `StoreUITests`. Local StoreKit config: `Config/FoldPlay.storekit` (also the Run scheme's).

## Repository

Published (GPL-3.0) at https://github.com/bi-creator/DualDS, branch `main`. About → Source Code links there.

## Outstanding issues

See KNOWN_ISSUES.md. Owner decisions are listed in LICENSING_REPORT.md §6.

## Next steps

1. Signed device build: sign in to the team's Apple account in Xcode > Settings > Accounts; physical-device tests once hardware is available.
2. Phase 5: input polish (Game Controller framework, remapping, layout editor, sizing, opacity).
3. Phase 6: audio (AVAudioEngine).
