#!/usr/bin/env bash
# Regenerates Resources/Legal/THIRD_PARTY_NOTICES.txt from the license files that ship inside the
# pinned melonDS submodule, covering every third-party component compiled into DualDS's core
# (inventory: Documentation/THIRD_PARTY_LICENSES.md). Run after bumping the submodule.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="$ROOT/EmulatorCore/melonDS"
OUT="$ROOT/Resources/Legal/THIRD_PARTY_NOTICES.txt"
COMMIT="$(git -C "$M" rev-parse HEAD)"

section() { printf '\n\n==============================================================================\n%s\n==============================================================================\n\n' "$1"; }

{
  echo "DualDS third-party notices"
  echo "Generated from melonDS commit $COMMIT by Scripts/generate-notices.sh."
  echo "DualDS and melonDS are licensed under the GNU GPL v3 (see the GPL texts in About > Licenses)."
  echo "The components below are compiled into DualDS as part of the melonDS core."

  section "FreeBIOS (built-in DS BIOS replacement) - BSD license"
  cat "$M/freebios/drastic_bios_readme.txt"

  section "teakra (DSi DSP emulator) - MIT License"
  cat "$M/src/teakra/LICENSE"

  section "Blip_Buffer / blip-buf (audio resampling) - GNU LGPL v2.1"
  echo "Statically linked. Because DualDS publishes its complete corresponding source under the GPL v3,"
  echo "users can modify blip-buf and relink DualDS (LGPL v2.1 section 6)."
  echo
  cat "$M/src/blip-buf/license.txt"

  section "FatFs (FAT file system module) - FatFs license (BSD-style)"
  cat "$M/src/fatfs/LICENSE.txt"

  section "xxHash - BSD 2-Clause License"
  sed -n '1,/\*\//p' "$M/src/xxhash/xxhash.h"

  section "SHA-1 by Steve Reid - Public domain"
  grep -m3 -E 'SHA-1 in C|Steve Reid|Public Domain' "$M/src/sha1/sha1.c"

  section "tiny-AES-c - The Unlicense"
  cat "$M/src/tiny-AES-c/unlicense.txt"
} > "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
