#!/usr/bin/env bash
# Licence and content compliance checks (run in CI and before every release build).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

M=EmulatorCore/melonDS
check "melonDS submodule present" "[ -f $M/LICENSE ]"
check "DualDS LICENSE is GPL-3.0" "grep -q 'Version 3, 29 June 2007' LICENSE"
check "bundled DualDS licence matches LICENSE" "cmp -s LICENSE Resources/Legal/LICENSE-DualDS.txt"
check "bundled melonDS licence matches upstream" "cmp -s $M/LICENSE Resources/Legal/LICENSE-melonDS.txt"

pinned="$(git -C $M rev-parse HEAD 2>/dev/null)"
check "AppConfiguration.melonDSCommit matches submodule ($pinned)" \
  "grep -q \"melonDSCommit = \\\"$pinned\\\"\" App/AppConfiguration.swift"

tmp="$(mktemp)"; cp Resources/Legal/THIRD_PARTY_NOTICES.txt "$tmp"
Scripts/generate-notices.sh >/dev/null
check "THIRD_PARTY_NOTICES.txt is up to date with the submodule" \
  "diff -q <(tail -n +3 \"$tmp\") <(tail -n +3 Resources/Legal/THIRD_PARTY_NOTICES.txt) >/dev/null"
rm -f "$tmp"

forbidden="$(git ls-files | grep -iE '\.(nds|dsi|srl|sav)$|(^|/)bios[79]\.bin$|(^|/)firmware\.bin$|dsi_?nand' \
             | grep -v '^Tests/Fixtures/testrom/dualds-test.nds$' || true)"
check "no ROMs, BIOS, firmware or saves are tracked" "[ -z \"$forbidden\" ]"
[ -n "$forbidden" ] && echo "$forbidden"

missing="$(git ls-files 'App/*.swift' 'Features/*.swift' 'EmulatorBridge/*' 'Rendering/*.swift' 'Services/*.swift' \
             'Models/*.swift' 'EmulatorCore/DualDSCore/*' 'Tests/*.swift' 'Tests/*.cpp' 2>/dev/null \
           | while read -r f; do grep -q 'GPL-3.0-or-later' "$f" || echo "$f"; done)"
check "every DualDS source file carries a GPL-3.0-or-later header" "[ -z \"$missing\" ]"
[ -n "$missing" ] && echo "$missing"

exit $fail
