# Known issues and limitations

| Area | Status |
|---|---|
| ObjC++ bridge / in-app emulation | Not started (Phase 2). |
| Game import | Button and file picker only; importing is Phase 3. |
| JIT | Compiled out. App Store apps cannot use JIT, so the interpreter's performance is the ceiling. |
| BIOS / firmware | FreeBIOS + generated firmware only. Direct boot always; no firmware menu. Firmware settings (nickname, language) are not persisted yet. |
| DSi mode | Not offered (needs real DSi BIOS/NAND). |
| Microphone | Not implemented. Games hear silence (Phase 8). |
| Local wireless / Wi-Fi | Not implemented. The core sees no other consoles and no network. |
| GBA slot / add-ons | Not implemented. |
| RTC | Seeded from the device clock at load; in-game clock changes are not saved. |
| Save state screenshots | melonDS states do not contain rendered frames; screenshots will be captured separately (Phase 7). |
| melonDS logs on load | `ROM entry not found for gamecode …` is expected for homebrew (not in melonDS's ROM database). `ROM header verification failed` means the file was rejected as a ROM. |
