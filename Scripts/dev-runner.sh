#!/usr/bin/env bash
# DualDS development runner. Start it yourself in Terminal:   Scripts/dev-runner.sh
#
# It lets a remote collaborator (e.g. an AI assistant editing files in this folder) request build
# and test steps WITHOUT typing into your terminal. It only ever runs the fixed steps listed in
# `run_step` below — never arbitrary commands from the request. Each request is a file
# Build/requests/<id>.req whose first line is a step name; results go to Build/logs/.
# Stop it any time with Ctrl-C.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
REQ="$ROOT/Build/requests"
mkdir -p "$REQ/done"

run_step() {
  case "$1" in
    bootstrap)   Scripts/bootstrap.sh ;;
    phase1)      Scripts/ci.sh phase1 ;;
    core)        Scripts/ci.sh core ;;
    host-tests)  Scripts/test-core-host.sh ;;
    core-ios)    Scripts/build-core.sh all Release ;;
    licenses)    Scripts/verify-licenses.sh ;;
    xcodegen)    xcodegen generate --spec project.yml ;;
    sim-build)   Scripts/ci.sh sim-build ;;
    sim-test)    Scripts/ci.sh sim-test ;;
    sim-run)     Scripts/ci.sh sim-run ;;
    commit)      # message comes from Build/requests/commit-message.txt
                 git add -A && git commit -F "$REQ/commit-message.txt" && git log --oneline -1 ;;
    status)      git status --short; git log --oneline -5 ;;
    *)           echo "refused: '$1' is not an allowed step"; return 64 ;;
  esac
}

echo "DualDS runner watching $REQ (allowed: bootstrap phase1 core host-tests core-ios licenses xcodegen sim-build sim-test sim-run commit status)"
while true; do
  for f in "$REQ"/*.req; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .req)"
    step="$(head -n1 "$f" | tr -cd 'a-z0-9-')"
    mv "$f" "$REQ/done/$id.req"
    echo "[$(date '+%H:%M:%S')] $id: $step"
    start=$(date +%s)
    run_step "$step" > "$LOGDIR/runner-$id.log" 2>&1
    rc=$?
    echo "$rc $(( $(date +%s) - start ))s $step" > "$LOGDIR/runner-$id.done"
    echo "[$(date '+%H:%M:%S')] $id: $step -> exit $rc"
  done
  sleep 2
done
