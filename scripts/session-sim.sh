#!/usr/bin/env bash
# Print the UDID of this worktree's own simulator, creating it if it does not exist yet.
#
# Every agent reaches for "an iPhone simulator", and they all share one bundle id. Falling back to
# "the last available iPhone" therefore lands on whichever device *another* worktree is using:
# installing onto it replaces that agent's app, which then dies with `Library not loaded`. A device
# named for the worktree is unambiguous, and its state (a signed-in session, in-progress work)
# survives between runs.
#
# The UDID is cached in .sim-udid at the repo root — the same file scripts/ios-sim.sh writes, so
# make and the sim script always agree on which device holds this worktree's build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_NAME="StarterApp-$(basename "$REPO_ROOT")"
UDID_FILE="$REPO_ROOT/.sim-udid"

device_exists() {
  [[ -n "${1:-}" ]] && xcrun simctl list devices -j | python3 -c "
import json, sys
udid = sys.argv[1]
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['udid'] == udid and d.get('isAvailable', True):
            raise SystemExit(0)
raise SystemExit(1)
" "$1" 2>/dev/null
}

# 1. Cached UDID, if it still names a real device (a deleted sim leaves a stale .sim-udid behind).
if [[ -f "$UDID_FILE" ]]; then
  CACHED="$(tr -d '[:space:]' < "$UDID_FILE")"
  if device_exists "$CACHED"; then echo "$CACHED"; exit 0; fi
fi

# 2. An existing device with this worktree's name.
UDID=$(xcrun simctl list devices -j | python3 -c "
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == name and d.get('isAvailable', True):
            print(d['udid'])
            raise SystemExit
" "$SESSION_NAME")

# 3. Otherwise create it. Clone the device type + runtime of an existing available iPhone rather
#    than pairing the newest of each: not every device type runs on every runtime, and simctl
#    rejects the mismatch with a bare "Incompatible device".
if [[ -z "$UDID" ]]; then
  echo "→ Creating session simulator '${SESSION_NAME}'…" >&2
  read -r DEVICE_TYPE RUNTIME <<<"$(xcrun simctl list devices available -j | python3 -c "
import json, sys

best = None
for runtime, devices in json.load(sys.stdin)['devices'].items():
    if 'iOS' not in runtime:
        continue
    version = [int(p) for p in runtime.split('iOS-')[-1].split('-')]
    for d in devices:
        if d.get('isAvailable') and 'iPhone' in d['name'] and d.get('deviceTypeIdentifier'):
            key = (version, d['name'])
            if best is None or key > best[0]:
                best = (key, d['deviceTypeIdentifier'], runtime)

if best:
    print(best[1], best[2])
")"
  if [[ -z "${DEVICE_TYPE:-}" || -z "${RUNTIME:-}" ]]; then
    echo "Error: no available iPhone simulator to model the session simulator on." >&2
    echo "       Open Xcode → Settings → Platforms and install an iOS simulator runtime." >&2
    exit 1
  fi
  UDID=$(xcrun simctl create "$SESSION_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi

printf '%s' "$UDID" > "$UDID_FILE"
echo "$UDID"
