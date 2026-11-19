#!/usr/bin/env bash
# Builds the core for the host (macOS or Linux) and runs the headless emulator tests against the
# original DualDS test ROM. Rebuilds the ROM first if arm-none-eabi binutils are installed.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
host_tests() {
  if command -v arm-none-eabi-as >/dev/null; then python3 -I "$ROOT/Tests/Fixtures/testrom/make_testrom.py"; fi
  local lto=ON; [ "$(uname)" = Linux ] && lto=OFF   # GNU ld cannot read clang LTO objects
  cmake -S "$ROOT/EmulatorCore" -B "$ROOT/Build/core-host" -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_LTO_RELEASE=$lto
  cmake --build "$ROOT/Build/core-host" --target dualds_core_tests
  "$ROOT/Build/core-host/dualds_core_tests" "$ROOT/Tests/Fixtures/testrom/dualds-test.nds"
}
run_logged core-host-tests host_tests
