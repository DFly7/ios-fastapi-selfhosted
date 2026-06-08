#!/usr/bin/env bash
# scripts/ios-sim.sh — Build StarterApp and launch it on an iOS Simulator.
#
# Usage:
#   ./scripts/ios-sim.sh                        # auto-picks newest iPhone sim
#   ./scripts/ios-sim.sh --regen                # tuist install + generate first
#   ./scripts/ios-sim.sh --udid <UDID>          # target a specific simulator
#   ./scripts/ios-sim.sh --logs                 # stream console after launch
#   ./scripts/ios-sim.sh --headless             # no Simulator.app GUI (agent mode)
#   ./scripts/ios-sim.sh --clean-state          # erase sim before run (clears Keychain)
#   ./scripts/ios-sim.sh --screenshot out.png   # capture screenshot after launch
#   ./scripts/ios-sim.sh --verify-launch 5      # fail if app crashes within 5s
#   ./scripts/ios-sim.sh --headless --clean-state --verify-launch 5  # full agent mode

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
REGEN=false
LOGS=false
HEADLESS=false
CLEAN_STATE=false
SCREENSHOT=""
VERIFY_LAUNCH=0
TARGET_UDID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --regen)          REGEN=true;          shift ;;
    --logs)           LOGS=true;           shift ;;
    --headless)       HEADLESS=true;       shift ;;
    --clean-state)    CLEAN_STATE=true;    shift ;;
    --screenshot)     SCREENSHOT="$2";     shift 2 ;;
    --verify-launch)  VERIFY_LAUNCH="${2:-5}"; shift 2 ;;
    --udid)           TARGET_UDID="$2";    shift 2 ;;
    -h|--help)
      sed -n '/^# Usage/,/^$/p' "$0" | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1  (try --help)"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Paths — always resolve relative to this script, so it can be called from anywhere
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$REPO_ROOT/ios/StarterApp"
cd "$IOS_DIR"

WORKSPACE="StarterApp.xcworkspace"
SCHEME="StarterApp"
DERIVED_DATA="./DerivedDataRun"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/StarterApp.app"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for cmd in xcodebuild xcrun python3; do
  command -v "$cmd" &>/dev/null || { echo "Error: '$cmd' not found."; exit 1; }
done

# ---------------------------------------------------------------------------
# Tuist — regenerate if explicitly requested or workspace is missing
# ---------------------------------------------------------------------------
if $REGEN || [[ ! -d "$WORKSPACE" ]]; then
  command -v tuist &>/dev/null || {
    echo "Error: 'tuist' not found. Install from https://docs.tuist.dev"
    exit 1
  }
  echo "→ tuist install…"
  tuist install
  echo "→ tuist generate…"
  tuist generate --no-open
fi

[[ -d "$WORKSPACE" ]] || {
  echo "Error: $WORKSPACE not found."
  echo "       Run with --regen to generate it first."
  exit 1
}

# ---------------------------------------------------------------------------
# Pick simulator — auto-selects the newest available iPhone if --udid not given
# ---------------------------------------------------------------------------
if [[ -z "$TARGET_UDID" ]]; then
  echo "→ Picking newest available iPhone simulator…"
  TARGET_UDID=$(python3 - <<'EOF'
import json, subprocess, sys

raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
data = json.loads(raw)

candidates = []
for runtime, devices in data["devices"].items():
    if "iOS" not in runtime:
        continue
    # runtime string: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
    ver = runtime.split("iOS-")[-1].replace("-", ".")
    for d in devices:
        if d.get("isAvailable") and "iPhone" in d["name"]:
            candidates.append((ver, d["udid"], d["name"]))

if not candidates:
    sys.exit(0)

candidates.sort(reverse=True)
print(candidates[0][1])
EOF
  )
fi

[[ -n "$TARGET_UDID" ]] || {
  echo "Error: No available iPhone simulator found."
  echo "       Open Xcode → Settings → Platforms and install an iOS simulator runtime."
  exit 1
}

SIM_NAME=$(xcrun simctl list devices available | grep "$TARGET_UDID" | sed 's/ (.*//' | xargs)
echo "→ Simulator: ${SIM_NAME} (${TARGET_UDID})"

# ---------------------------------------------------------------------------
# Clean state — erase simulator to clear Keychain, caches, app data
# ---------------------------------------------------------------------------
if $CLEAN_STATE; then
  echo "→ Erasing simulator state…"
  xcrun simctl shutdown "$TARGET_UDID" 2>/dev/null || true
  xcrun simctl erase "$TARGET_UDID"
  echo "  Simulator erased."
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "→ Building ${SCHEME} (Debug)…"
xcodebuild build \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$TARGET_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet

[[ -d "$APP_PATH" ]] || {
  echo "Error: Build succeeded but .app not found at expected path:"
  echo "       $APP_PATH"
  exit 1
}

# ---------------------------------------------------------------------------
# Bundle ID — read from the built .app so it never drifts from the xcconfig
# ---------------------------------------------------------------------------
BUNDLE_ID=$(defaults read "$(pwd)/$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || true)
[[ -n "$BUNDLE_ID" ]] || {
  echo "Error: Could not read CFBundleIdentifier from $APP_PATH/Info.plist"
  echo "       Set PRODUCT_BUNDLE_IDENTIFIER in Config-Debug.xcconfig."
  exit 1
}

# ---------------------------------------------------------------------------
# Boot simulator → install → launch
# ---------------------------------------------------------------------------
echo "→ Booting simulator…"
xcrun simctl boot "$TARGET_UDID" 2>/dev/null || true   # already-booted is fine
if ! $HEADLESS; then
  open -a Simulator --args -CurrentDeviceUDID "$TARGET_UDID"
fi

echo "→ Installing ${BUNDLE_ID}…"
xcrun simctl install "$TARGET_UDID" "$APP_PATH"

if $LOGS; then
  echo "→ Launching with console logs (Ctrl-C to stop)…"
  xcrun simctl launch --console-pty "$TARGET_UDID" "$BUNDLE_ID"
else
  echo "→ Launching…"
  xcrun simctl launch "$TARGET_UDID" "$BUNDLE_ID"
  echo ""
  echo "✓ ${BUNDLE_ID} running on ${SIM_NAME}"
fi

# ---------------------------------------------------------------------------
# Screenshot — capture simulator screen to file
# ---------------------------------------------------------------------------
if [[ -n "$SCREENSHOT" ]]; then
  sleep 2  # give app time to render
  echo "→ Capturing screenshot to ${SCREENSHOT}…"
  xcrun simctl io "$TARGET_UDID" screenshot "$SCREENSHOT"
  echo "  ✓ Screenshot saved."
fi

# ---------------------------------------------------------------------------
# Verify launch — poll for app process, fail if it crashed
# ---------------------------------------------------------------------------
if [[ "$VERIFY_LAUNCH" -gt 0 ]]; then
  echo "→ Verifying app stayed alive for ${VERIFY_LAUNCH}s…"
  sleep "$VERIFY_LAUNCH"
  if xcrun simctl spawn "$TARGET_UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "  ✓ App is running."
  else
    echo "  ✗ App is NOT running — may have crashed on launch."
    echo "  Recent crash logs:"
    find ~/Library/Logs/DiagnosticReports -name "StarterApp*" -newer "$APP_PATH" 2>/dev/null | head -3
    exit 1
  fi
fi
