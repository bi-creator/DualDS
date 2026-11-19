# Shared helpers for DualDS scripts. Source, don't execute.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="$ROOT/Build/logs"
mkdir -p "$LOGDIR"

# run_logged <name> <command...>: runs the command, tees output to Build/logs/<name>.log and writes
# Build/logs/<name>.status as "PASS" or "FAIL <exit code>", so results can be read without a terminal.
run_logged() {
  local name="$1"; shift
  local log="$LOGDIR/$name.log"
  echo "==> $name: $*" | tee "$log"
  set +e
  "$@" 2>&1 | tee -a "$log"
  local rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -eq 0 ]; then echo "PASS" > "$LOGDIR/$name.status"; else echo "FAIL $rc" > "$LOGDIR/$name.status"; fi
  echo "==> $name: $(cat "$LOGDIR/$name.status")  (log: Build/logs/$name.log)"
  return "$rc"
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found. $2" >&2; return 1; }; }

# First available iPhone simulator UDID (newest runtime first).
pick_simulator() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
for runtime in sorted(data, reverse=True):
    if "iOS" not in runtime: continue
    for d in data[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit(0)
sys.exit(1)'
}
