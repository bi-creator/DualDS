#!/usr/bin/env bash
# One-time setup on a Mac: checks the toolchain, fetches the pinned melonDS submodule and
# generates DualDS.xcodeproj from project.yml.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

env_report() {
  sw_vers || true
  uname -m
  xcodebuild -version
  xcode-select -p
  swift --version 2>&1 | head -1
  clang --version | head -1
  cmake --version | head -1
  ninja --version
  git --version
  xcodegen --version
  xcrun simctl list runtimes | grep -i ios || true
}

need xcodebuild "Install Xcode from the App Store and run: sudo xcode-select -s /Applications/Xcode.app"
need cmake "Install with: brew install cmake"
need ninja "Install with: brew install ninja"
need git ""
need xcodegen "Install with: brew install xcodegen"

run_logged environment env_report
run_logged submodule git submodule update --init --recursive EmulatorCore/melonDS
run_logged xcodegen xcodegen generate --spec project.yml
echo "Bootstrap complete. Next: Scripts/ci.sh phase1"
