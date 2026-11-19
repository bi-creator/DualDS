# Third-party licence inventory

Generated from what is actually **compiled into** the DualDS core (object files of the `core`
target with `ENABLE_JIT=OFF ENABLE_OGLRENDERER=OFF ENABLE_GDBSTUB=OFF BUILD_QT_SDL=OFF`),
not just what sits in the melonDS repository. Full texts ship in the app:
`Resources/Legal/THIRD_PARTY_NOTICES.txt` (regenerate with `Scripts/generate-notices.sh`).

melonDS commit: `361ffa9501b631d53d7150fe57dec40a8341f664` (melonDS 1.1)

| Component | Path in melonDS | Licence | In binary |
|---|---|---|---|
| melonDS | `src/` | GPL-3.0-or-later | yes |
| FreeBIOS | `src/FreeBIOS*` (from `freebios/`) | BSD-style, © 2013 Gilead Kutnick | yes |
| teakra | `src/teakra` | MIT, © 2018 Weiyi Wang | yes |
| blip-buf | `src/blip-buf` | LGPL-2.1 | yes |
| FatFs | `src/fatfs` | FatFs licence (BSD-style), ChaN | yes |
| xxHash | `src/xxhash` | BSD-2-Clause, Yann Collet | yes |
| SHA-1 | `src/sha1` | Public domain, Steve Reid | yes |
| tiny-AES-c | `src/tiny-AES-c` | The Unlicense | yes |
| Dolphin emitter code | `src/dolphin` | GPL-2.0+ | **no** (JIT only; JIT disabled) |
| Qt/SDL frontend, glad, duckstation | `src/frontend` | various | **no** |

DualDS-owned assets: the app icon and `DualScreenGlyph` are original artwork (GPL-3.0-or-later,
with the rest of DualDS). The test ROM in `Tests/Fixtures/testrom` is original DualDS code.

Build-time tools (not distributed): CMake, Ninja, XcodeGen, Xcode, GNU binutils for ARM
(test-ROM assembly only).
