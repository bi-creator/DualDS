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

# Keep the Mac awake (no idle or system sleep) while the runner is up, so long unattended
# sessions (e.g. overnight game builds) don't stall. Ends with the runner.
if command -v caffeinate >/dev/null; then caffeinate -dimsu -w $$ & fi

# A step that runs longer than this is stopped so one hang can't block the queue (seconds).
STEP_TIMEOUT="${DUALDS_STEP_TIMEOUT:-3600}"

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
    sim-info)    Scripts/ci.sh sim-info ;;
    device-build) Scripts/ci.sh device-build ;;
    testflight)  Scripts/ci.sh testflight ;;
    privacy-site) Scripts/ci.sh privacy-site ;;
    games)       Scripts/ci.sh games ;;
    ci)          # Any step defined in Scripts/ci.sh, named on the first line of Build/requests/ci-step.txt
                 # (ci.sh refuses names it doesn't define). Lets new ci.sh steps run without a restart.
                 Scripts/ci.sh "$(head -n1 "$REQ/ci-step.txt" | tr -cd 'a-z0-9-')" ;;
    push)        git push -u origin HEAD ;;
    publish)     # Create the public GitHub repo (needs the GitHub CLI, logged in) and push main.
                 command -v gh >/dev/null || { echo "gh not installed: brew install gh && gh auth login"; return 69; }
                 gh auth status && \
                 gh repo create DualDS --public --source . --remote origin --push \
                   --description "Nintendo DS emulator for iPhone and iPad, built on melonDS (GPL-3.0)" && \
                 git remote -v ;;
    commit)      # message comes from Build/requests/commit-message.txt
                 git add -A && git commit -F "$REQ/commit-message.txt" && git log --oneline -1 ;;
    status)      git status --short; git log --oneline -5 ;;
    crash-logs)  # Copy the newest DualDS crash reports (Simulator and device) into Build/logs/crashes.
                 mkdir -p "$LOGDIR/crashes" && \
                 ls -t "$HOME"/Library/Logs/DiagnosticReports/DualDS*.ips 2>/dev/null | head -3 | while read -r f; do cp "$f" "$LOGDIR/crashes/"; echo "$f"; done ;;
    metal-toolchain) xcodebuild -downloadComponent MetalToolchain ;;
    *)           echo "refused: '$1' is not an allowed step"; return 64 ;;
  esac
}

echo "DualDS runner watching $REQ (allowed: bootstrap phase1 core host-tests core-ios licenses xcodegen sim-build sim-test sim-run sim-info device-build testflight privacy-site games ci push publish crash-logs commit status)"
while true; do
  for f in "$REQ"/*.req; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .req)"
    step="$(head -n1 "$f" | tr -cd 'a-z0-9-')"
    mv "$f" "$REQ/done/$id.req"
    echo "[$(date '+%H:%M:%S')] $id: $step"
    start=$(date +%s)
    run_step "$step" > "$LOGDIR/runner-$id.log" 2>&1 &
    pid=$!
    ( sleep "$STEP_TIMEOUT"; if kill -0 "$pid" 2>/dev/null; then echo "timeout after ${STEP_TIMEOUT}s" >> "$LOGDIR/runner-$id.log"; pkill -TERM -P "$pid"; kill -TERM "$pid"; fi ) 2>/dev/null &
    watchdog=$!
    wait "$pid"
    rc=$?
    kill "$watchdog" 2>/dev/null
    echo "$rc $(( $(date +%s) - start ))s $step" > "$LOGDIR/runner-$id.done"
    echo "[$(date '+%H:%M:%S')] $id: $step -> exit $rc"
  done
  sleep 2
done
