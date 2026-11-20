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
  # Compiler warnings in app/test sources and runtime warnings reported against test files.
  run_logged warnings-test no_source_warnings app-test-sim
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
  # Games you own placed in Build/import/ (git-ignored) go into the app's Files folder; DualDS
  # imports them on launch.
  if compgen -G "$ROOT/Build/import/*.nds" >/dev/null; then
    local docs; docs="$(xcrun simctl get_app_container "$sim" "$bid" data)/Documents"
    mkdir -p "$docs"
    cp "$ROOT"/Build/import/*.nds "$docs/"
    echo "copied into $docs:"; ls "$docs"
  fi
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

# Release archive -> upload to App Store Connect (TestFlight), then tag the source in git.
# Needs: the team's Apple ID signed in under Xcode > Settings > Accounts, and an App Store Connect
# app record for the bundle ID. Build numbers are timestamps so every upload is unique.
testflight() {
  local team bundle build version archive opts tag
  team="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$ROOT/Config/Signing.local.xcconfig" | tr -d ' ')"
  bundle="$(sed -n 's/^DUALDS_BUNDLE_ID *= *//p' "$ROOT/Config/Signing.local.xcconfig" | tr -d ' ')"
  [ -n "$team" ] && [ -n "$bundle" ] || { echo "error: set DEVELOPMENT_TEAM and DUALDS_BUNDLE_ID in Config/Signing.local.xcconfig" >&2; return 1; }
  [ -z "$(git status --porcelain)" ] || { echo "error: commit your changes first, so the uploaded build matches a public source tag" >&2; return 1; }
  build="$(date +%Y%m%d%H%M)"
  version="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}/\1/p' "$ROOT/project.yml" | head -1)"
  archive="$ROOT/Build/DualDS-$build.xcarchive"
  opts="$ROOT/Build/ExportOptions.plist"
  cat > "$opts" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
  run_logged licenses "$ROOT/Scripts/verify-licenses.sh"
  run_logged xcodegen xcodegen generate --spec project.yml
  # Archive unsigned: development signing would need a registered test device. The export step
  # signs the app for App Store distribution (automatic signing, distribution certificate).
  run_logged archive xcodebuild -project DualDS.xcodeproj -scheme DualDS -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" \
    CURRENT_PROJECT_VERSION="$build" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive
  run_logged upload xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$opts" \
    -exportPath "$ROOT/Build/export-$build" -allowProvisioningUpdates
  # GPL-3.0 corresponding source: tag exactly what was uploaded and publish the tag.
  tag="v$version-build.$build"
  git tag -a "$tag" -m "TestFlight build $version ($build)"
  run_logged push-tag git push origin "$tag"
  echo "Uploaded DualDS $version ($build); source tag $tag"
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

# Commit and push the FoldPlay privacy site (sibling folder ../foldplay-privacy). Creates the public
# GitHub repo bi-creator/foldplay-privacy on first run (needs the GitHub CLI, logged in).
privacy_site() {
  local site; site="$(cd "$ROOT/.." && pwd)/foldplay-privacy"
  [ -f "$site/privacy.html" ] || { echo "missing $site/privacy.html" >&2; return 66; }
  command -v gh >/dev/null || { echo "gh not installed: brew install gh && gh auth login" >&2; return 69; }
  cd "$site"
  [ -d .git ] || git init -b main
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "FoldPlay app page and privacy policy (20 November 2026)" \
      -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XA6WVmMX3pDCBHDgGvdHVV"
  fi
  if git remote get-url origin >/dev/null 2>&1; then
    git push -u origin main
  elif gh repo view bi-creator/foldplay-privacy >/dev/null 2>&1; then
    git remote add origin https://github.com/bi-creator/foldplay-privacy.git
    git push -u origin main
  else
    gh repo create foldplay-privacy --public --source . --remote origin --push \
      --description "FoldPlay app page and privacy policy (static site for Vercel)"
  fi
  git log --oneline -1
  git remote -v
  cd "$ROOT"
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
  testflight) testflight ;;
  privacy-site) privacy_site ;;
  core) core ;;
  all) phase1; core ;;
  *) echo "usage: $0 [phase1|core|sim-build|sim-test|sim-run|sim-info|device-build|testflight|privacy-site|all]" >&2; exit 2 ;;
esac
echo "All requested steps passed."
