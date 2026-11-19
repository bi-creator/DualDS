#!/usr/bin/env bash
# Apple Silicon iOS Simulator (arm64) core build. See build-core.sh.
exec "$(dirname "$0")/build-core.sh" iphonesimulator "${1:-Release}"
