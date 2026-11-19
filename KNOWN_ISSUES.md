# Known issues and limitations

| Area | Status |
|---|---|
| In-app emulator screen | Core and bridge work in the app process (tested), but there is no emulator UI yet (Phase 4). |
| Core LTO | Static core libraries are built without LTO (bitcode breaks `-create-xcframework`). Re-evaluate in Phase 11. |
| Physical device | Not yet run on hardware. |
| Audio sync | Clock-paced with a 120 ms latency cap. Long sessions may occasionally drop or pad a few ms to stay in sync (no time-stretching yet). Untested on hardware. |
| Controllers | Bluetooth controllers not yet supported (Phase 5). |
| JIT | Compiled out. App Store apps cannot use JIT, so the interpreter's performance is the ceiling. |
| BIOS / firmware | FreeBIOS + generated firmware only. Direct boot always; no firmware menu. Firmware settings (nickname, language) are not persisted yet. |
| DSi mode | Not offered (needs real DSi BIOS/NAND). |
| Microphone | Not implemented. Games hear silence (Phase 8). |
| Local wireless / Wi-Fi | Not implemented. The core sees no other consoles and no network. |
| GBA slot / add-ons | Not implemented. |
| RTC | Seeded from the device clock at load; in-game clock changes are not saved. |
| Save state screenshots | melonDS states do not contain rendered frames; screenshots will be captured separately (Phase 7). |
| melonDS logs on load | `ROM entry not found for gamecode …` is expected for homebrew (not in melonDS's ROM database). `ROM header verification failed` means the file was rejected as a ROM. |
