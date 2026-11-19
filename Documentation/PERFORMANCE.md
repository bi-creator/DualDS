# Performance

No physical-device measurements exist yet. The numbers below come from a development VM and say
nothing about iPhone performance. They are kept only as a regression baseline for the headless tests.

| Date | Machine | Build | Workload | Result |
|---|---|---|---|---|
| 2026-11-19 | Linux VM, 2 vCPU x86-64 | clang Release, no LTO, interpreter | DualDS test ROM (2D only, trivial) | paced 59.77 fps (target 59.83); fast-forward ≈ 414 fps |

Known costs to measure on device (Phase 11, with Instruments):
* Interpreter only (no JIT on the App Store). Demanding 3D games are the expected bottleneck.
* Two 192 KiB frame copies per frame today (core → shared buffer → renderer). Phase 4 targets one.
* Software 3D rasteriser runs threaded (`SessionConfig::threaded3D`).
