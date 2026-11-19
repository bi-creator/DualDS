# DualDS architecture

```
┌──────────────────────────────────────────────────────────────┐
│ SwiftUI / UIKit  (App/, Features/)          main thread      │
│   Views ── ViewModels (MVVM, @Observable)                    │
├──────────────────────────────────────────────────────────────┤
│ Rendering/  Metal: MTKView draws latest frame (display link) │
│ Audio:      AVAudioEngine + AVAudioSourceNode (render thread)│
├──────────────────────────────────────────────────────────────┤
│ EmulatorBridge/  Objective-C++  (DSCoreBridge)    [Phase 2]  │
│   Swift-visible NSObject API; converts types, no logic       │
├──────────────────────────────────────────────────────────────┤
│ EmulatorCore/DualDSCore  portable C++20       emulation thread│
│   DSSession: lifecycle, pacing, input, frames, audio ring,   │
│   battery saves, save states.  DSPlatform: melonDS Platform::│
├──────────────────────────────────────────────────────────────┤
│ EmulatorCore/melonDS  (git submodule, unmodified upstream)   │
└──────────────────────────────────────────────────────────────┘
```

## Rules

* SwiftUI never sees C++. Swift talks only to `DSCoreBridge` (Objective-C interface, `.mm` implementation).
* `DSSession`'s header exposes no melonDS types, so the bridge stays thin and the core can be upgraded without touching Swift.
* Everything below the bridge is plain C++/POSIX and is tested headless on macOS or Linux (`Scripts/test-core-host.sh`), with real emulation of an original test ROM.
* No emulation, rendering or audio work on the main thread.

## Why a C++ session layer in addition to the Objective-C++ bridge

The spec asks for an Objective-C++ bridge. DualDS keeps that bridge, but puts threading, pacing,
buffering and save logic one layer lower in portable C++. That code can then run in CI against
the real core without a simulator, and the Objective-C++ layer contains only type conversion.
This is the one intentional deviation from the suggested folder structure.

## Threads and data flow

| Data | Producer → consumer | Mechanism |
|---|---|---|
| Buttons, touch, lid, fast-forward | any thread → emulation thread | atomics, applied before each `RunFrame()` |
| Frames (2 × 256×192 BGRA) | emulation → render thread | copied under a small mutex after each frame; renderer copies out the latest (Phase 4 will upload straight into a Metal texture) |
| Audio (s16 stereo, 48 kHz) | emulation → audio render thread | lock-free SPSC ring, 250 ms; overflow drops, underrun pads silence; both counted in `stats()` |
| Battery save | melonDS `WriteNDSSave` → disk | whole image buffered, written after 1 s of quiet and always on pause/stop; `tmp` + `rename()` so a crash never truncates a save |
| Save states | any thread ↔ core | melonDS `DoSavestate` under the core mutex; loading backs up the current state and restores it if the file is rejected |
| Lifecycle (load/reset/state ops) | any non-emulation thread | core mutex, held for at most one frame by the emulation thread |

Pacing: the emulation thread sleeps to the native 59.826 Hz frame period with `steady_clock` and
resets its schedule instead of sprinting after a stall (for example after app suspension).
Fast-forward removes the sleep and drops audio.

## melonDS integration (actual upstream APIs)

| DualDS operation | melonDS API |
|---|---|
| initialize / loadGame | `NDSCart::ParseROM` → `new NDS(NDSArgs{FreeBIOS, generated firmware, JIT off})` → `SetRenderer(SoftRenderer)` → `SetNDSCart` → `Reset` → `SetupDirectBoot` → `RTC.SetDateTime` → `Start` |
| run frame | `NDS::RunFrame()` |
| input | `NDS::SetKeyMask` (active-low, 12 bits), `TouchScreen` / `ReleaseScreen`, `SetLidClosed` |
| framebuffers | `GPU::GetFramebuffers(&top, &bottom)` (soft renderer, BGRA8) |
| audio | `SPU::GetOutputSize` / `SPU::ReadOutput` |
| game save | `Platform::WriteNDSSave` callback; initial save passed via `NDSCartArgs::SRAM` |
| save / load state | `Savestate` + `NDS::DoSavestate` |
| stop | `NDS::Stop(StopReason::External)`; core-initiated stops arrive via `Platform::SignalStop` |

Direct boot is mandatory: FreeBIOS cannot run the DS firmware menu. JIT is compiled out because
App Store apps cannot allocate writable+executable memory.

## Features stubbed honestly in the Platform layer

Local wireless and Wi-Fi (`MP_*`, `Net_*`) report no packets. The microphone reports no samples
(silence). DSi camera and AAC are not offered. Slot-2 add-ons are absent. None of these are
advertised in the UI. See KNOWN_ISSUES.md.
