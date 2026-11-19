# Compatibility

Only results that were actually measured are listed. **No commercial game has been tested yet.**
Real-device testing starts after Phase 2 (core running in the iOS app).

| Title | Game code | Emulator | Platform | Boot | Graphics | Audio | Input | Save | Save state | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| DualDS test ROM (original, in repo) | DDST | melonDS 1.1 @361ffa95, interpreter | Linux x86-64 host (headless) | ✅ | ✅ 2D VRAM + backdrop, pixel-exact | ✅ SPU 802 frames/video frame | ✅ A button | n/a (homebrew, no save memory) | ✅ byte-identical round-trip | Automated: `Scripts/test-core-host.sh` |

Planned test categories (Phase 12): 2D, 3D, touch-heavy, microphone, unusual save types (EEPROM, FLASH, NAND, IR), demanding 3D, audio-stream games.
