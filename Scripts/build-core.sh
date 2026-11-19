#!/usr/bin/env bash
# Builds the DualDS emulator core (melonDS + session layer) as static libraries for iOS devices
# (arm64) and the Apple Silicon iOS Simulator (arm64), then packages Build/DualDSCore.xcframework.
#   Scripts/build-core.sh [iphoneos|iphonesimulator|all] [Release|Debug]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
WHICH="${1:-all}"
CONFIG="${2:-Release}"
DEPLOY=17.0

build_sdk() {
  local sdk="$1"
  local bdir="$ROOT/Build/core-$sdk"
  local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cmake -S "$ROOT/EmulatorCore" -B "$bdir" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOY \
    -DCMAKE_BUILD_TYPE="$CONFIG" \
    -DCMAKE_C_COMPILER="$(xcrun --sdk "$sdk" -f clang)" \
    -DCMAKE_CXX_COMPILER="$(xcrun --sdk "$sdk" -f clang++)" \
    -DENABLE_LTO_RELEASE=ON \
    "-DCMAKE_C_FLAGS=-ffile-prefix-map=$ROOT=DualDS" \
    "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$ROOT=DualDS"
  cmake --build "$bdir" --target dualdscore core teakra
  mkdir -p "$bdir/merged"
  libtool -static -o "$bdir/merged/libDualDSCore.a" \
    "$bdir/libdualdscore.a" "$bdir/melonDS/src/libcore.a" "$bdir/melonDS/src/teakra/src/libteakra.a"
  # Sanity check: the library must target the right platform (2 = iOS, 7 = iOS Simulator).
  xcrun vtool -show-build "$bdir/merged/libDualDSCore.a" 2>/dev/null | grep -m1 -E 'platform' || true
}

package() {
  local out="$ROOT/Build/DualDSCore.xcframework"
  rm -rf "$out"
  local args=()
  for sdk in iphoneos iphonesimulator; do
    [ -f "$ROOT/Build/core-$sdk/merged/libDualDSCore.a" ] || continue
    args+=(-library "$ROOT/Build/core-$sdk/merged/libDualDSCore.a" -headers "$ROOT/EmulatorCore/DualDSCore/include")
  done
  xcodebuild -create-xcframework "${args[@]}" -output "$out"
}

case "$WHICH" in
  iphoneos|iphonesimulator) run_logged "core-$WHICH" build_sdk "$WHICH" ;;
  all) run_logged core-iphoneos build_sdk iphoneos && run_logged core-iphonesimulator build_sdk iphonesimulator ;;
  *) echo "usage: $0 [iphoneos|iphonesimulator|all] [Release|Debug]" >&2; exit 2 ;;
esac
run_logged core-xcframework package
