#!/usr/bin/env bash
# Device (arm64) core build. See build-core.sh.
exec "$(dirname "$0")/build-core.sh" iphoneos "${1:-Release}"
