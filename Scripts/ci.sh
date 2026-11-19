#!/usr/bin/env bash
# Build-and-test entry point. Each step logs to Build/logs/<step>.log with a .status file.
#   Scripts/ci.sh phase1     generate project, build app for Simulator, run unit + UI tests
#   Scripts/ci.sh core       host core tests + iOS/Simulator core libraries
#   Scripts/ci.sh all
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
STEP="${1:-all}"
DERIVED="$ROOT/Build/DerivedData"

phase1() {
  run_logged licenses "$ROOT/Scripts/verify-licenses.sh"
  run_logged xcodegen xcodegen generate --spec project.yml
  local sim; sim="$(pick_simulator)" || { echo "No iPhone simulator found. Install one in Xcode > Settings > Components." >&2; exit 1; }
  echo "Using simulator $sim" | tee "$LOGDIR/simulator.txt"
  run_logged app-build-sim xcodebuild -project DualDS.xcodeproj -scheme DualDS -configuration Debug \
    -destination "id=$sim" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
  run_logged app-test-sim xcodebuild -project DualDS.xcodeproj -scheme DualDS -configuration Debug \
    -destination "id=$sim" -derivedDataPath "$DERIVED" -resultBundlePath "$ROOT/Build/logs/app-test-sim.xcresult" \
    CODE_SIGNING_ALLOWED=NO test
}

core() {
  "$ROOT/Scripts/test-core-host.sh"
  "$ROOT/Scripts/build-core.sh" all Release
}

rm -rf "$ROOT/Build/logs/app-test-sim.xcresult"
case "$STEP" in
  phase1) phase1 ;;
  core) core ;;
  all) phase1; core ;;
  *) echo "usage: $0 [phase1|core|all]" >&2; exit 2 ;;
esac
echo "All requested steps passed."
