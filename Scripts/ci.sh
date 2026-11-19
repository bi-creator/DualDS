#!/usr/bin/env bash
# Build-and-test entry point. Each step logs to Build/logs/<step>.log with a .status file.
#   Scripts/ci.sh phase1     generate project, build app for Simulator, run unit + UI tests
#   Scripts/ci.sh core       host core tests + iOS/Simulator core libraries
#   Scripts/ci.sh sim-build | sim-test | sim-run   (individual Simulator steps)
#   Scripts/ci.sh all
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
STEP="${1:-all}"
DERIVED="$ROOT/Build/DerivedData"

sim_dest() {
  local sim; sim="$(pick_simulator)" || { echo "No iPhone simulator found. Install one in Xcode > Settings > Components." >&2; exit 1; }
  echo "$sim" > "$LOGDIR/simulator.txt"
  echo "$sim"
}

# Fails if the compiler warned about any DualDS source file (Xcode's own tool notices are ignored).
no_source_warnings() {
  local hits
  hits="$(grep -E "^$ROOT/(App|Features|Models|Services|Rendering|EmulatorBridge|Tests)/.*: warning:" "$LOGDIR/$1.log" | sort -u || true)"
  if [ -n "$hits" ]; then echo "$hits"; echo "error: compiler warnings in DualDS sources (see above)"; return 1; fi
  echo "no compiler warnings in DualDS sources"
}

sim_build() {
  run_logged xcodegen xcodegen generate --spec project.yml
  run_logged app-build-sim xcodebuild -project DualDS.xcodeproj -scheme DualDS -configuration Debug \
    -destination "id=$(sim_dest)" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO clean build
  run_logged warnings-sim no_source_warnings app-build-sim
}

sim_test() {
  run_logged xcodegen xcodegen generate --spec project.yml   # pick up new source files
  rm -rf "$ROOT/Build/logs/app-test-sim.xcresult"
  TEST_RUNNER_DUALDS_SCREENSHOT_DIR="$LOGDIR" \
  run_logged app-test-sim xcodebuild -project DualDS.xcodeproj -scheme DualDS -configuration Debug \
    -destination "id=$(sim_dest)" -derivedDataPath "$DERIVED" -resultBundlePath "$ROOT/Build/logs/app-test-sim.xcresult" \
    CODE_SIGNING_ALLOWED=NO test
}

# Boots the simulator, installs and launches the last Debug build, saves Build/logs/sim-screenshot.png.
sim_run_impl() {
  local sim; sim="$(sim_dest)"
  local app="$DERIVED/Build/Products/Debug-iphonesimulator/DualDS.app"
  [ -d "$app" ] || { echo "no app at $app; run sim-build first" >&2; return 1; }
  xcrun simctl boot "$sim" 2>/dev/null || true
  xcrun simctl bootstatus "$sim" -b
  xcrun simctl install "$sim" "$app"
  local bid; bid="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")"
  xcrun simctl terminate "$sim" "$bid" 2>/dev/null || true
  xcrun simctl launch "$sim" "$bid"
  sleep 4
  rm -f "$LOGDIR"/sim-screenshot*.png
  # Multi-display devices (e.g. foldables) need --display; capture every display that exists.
  if ! xcrun simctl io "$sim" screenshot "$LOGDIR/sim-screenshot.png" 2>/dev/null; then
    local n ok=0
    for n in 1 2 3 4 5 6; do
      xcrun simctl io "$sim" screenshot --display=$n "$LOGDIR/sim-screenshot-display$n.png" 2>/dev/null && ok=1
    done
    [ "$ok" = 1 ]
  fi
  ls -la "$LOGDIR"/sim-screenshot*.png
}

# Signed Release build for a generic iOS device: proves device compilation, linking and signing
# without hardware attached. Uses DEVELOPMENT_TEAM from Config/Signing.local.xcconfig.
device_build() {
  # 1) Unsigned arm64 device build: proves the app, bridge and core compile and link for hardware.
  run_logged device-compile xcodebuild -project DualDS.xcodeproj -scheme DualDS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
  run_logged warnings-device no_source_warnings device-compile
  # 2) Signed build (needs the team's Apple account in Xcode > Settings > Accounts).
  run_logged device-build xcodebuild -project DualDS.xcodeproj -scheme DualDS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" -allowProvisioningUpdates build
}

sim_info_impl() {
  xcrun simctl list runtimes
  xcrun simctl list devicetypes
  xcrun simctl list devices available
  echo "--- json ---"
  xcrun simctl list devices available -j
}
sim_info() { run_logged sim-info sim_info_impl; }
sim_run() { run_logged sim-run sim_run_impl; }

phase1() {
  run_logged licenses "$ROOT/Scripts/verify-licenses.sh"
  sim_build
  sim_test
  sim_run
}

core() {
  "$ROOT/Scripts/test-core-host.sh"
  "$ROOT/Scripts/build-core.sh" all Release
}

case "$STEP" in
  phase1) phase1 ;;
  sim-build) sim_build ;;
  sim-test) sim_test ;;
  sim-run) sim_run ;;
  sim-info) sim_info ;;
  device-build) device_build ;;
  core) core ;;
  all) phase1; core ;;
  *) echo "usage: $0 [phase1|core|sim-build|sim-test|sim-run|sim-info|device-build|all]" >&2; exit 2 ;;
esac
echo "All requested steps passed."
