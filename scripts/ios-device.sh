#!/usr/bin/env bash
# scripts/ios-device.sh — Build StarterApp and install+launch it on a PHYSICAL iPhone.
#
# Simulator counterpart lives in scripts/ios-sim.sh. This script targets a real,
# paired device via `xcrun devicectl` (Xcode 15+), with automatic code signing.
#
# Prerequisites:
#   • An iPhone paired to this Mac (USB or wireless). Check: xcrun devicectl list devices
#   • An Apple Development signing identity in the login keychain.
#   • A DEVELOPMENT_TEAM (10-char Team ID) — see resolution order below.
#   • BACKEND_URL in Config-Debug.xcconfig must be reachable FROM THE PHONE
#     (localhost will NOT work — use scripts/tunnel.sh to expose the backend).
#
# Team ID resolution (first match wins):
#   1. --team <ID>
#   2. IOS_DEVELOPMENT_TEAM env var
#   3. DEVELOPMENT_TEAM in Config-Debug.xcconfig
#   4. Auto-detected from the "Apple Development" cert in the login keychain
#
# Tunnel: a physical phone can't reach http://localhost. When Config-Debug's
# BACKEND_URL is a loopback address, this script starts (or reuses) an ngrok
# tunnel to the backend, writes the public URL into Config-Debug.xcconfig, then
# builds. The tunnel is left running after the script exits (the app on the
# phone keeps needing it). Stop it with `./scripts/ios-device.sh --stop-tunnel`.
#
# ngrok is used because *.trycloudflare.com quick tunnels are NXDOMAIN'd by some
# ISP resolvers. Requires an authtoken: `ngrok config add-authtoken <token>`.
# For a stable URL, reserve a domain and pass --domain <name>.ngrok-free.dev
# (or set NGROK_DOMAIN) so it never changes between runs.
#
# Usage:
#   ./scripts/ios-device.sh                         # first paired iPhone, auto team, auto tunnel
#   ./scripts/ios-device.sh --team V8S6S975CD       # explicit team (else auto-detected)
#   ./scripts/ios-device.sh --device-id <UDID>      # target a specific device
#   ./scripts/ios-device.sh --regen                 # tuist install + generate first
#   ./scripts/ios-device.sh --verify-launch 5       # fail if app dies within 5s
#   ./scripts/ios-device.sh --console               # launch attached & stream os_log over Wi-Fi (DEBUG mirrors AppLog to stdout)
#   ./scripts/ios-device.sh --logs                  # stream full device syslog (needs USB + libimobiledevice)
#   ./scripts/ios-device.sh --allow-device-registration  # let Xcode register a new device
#   ./scripts/ios-device.sh --no-tunnel             # skip tunnel (BACKEND_URL is already reachable)
#   ./scripts/ios-device.sh --tunnel                # force tunnel even if BACKEND_URL isn't loopback
#   ./scripts/ios-device.sh --tunnel-port 9000      # tunnel a non-default backend port
#   ./scripts/ios-device.sh --domain api.ngrok-free.dev  # use a reserved (stable) ngrok domain
#   ./scripts/ios-device.sh --stop-tunnel           # tear down the running ngrok tunnel and exit

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
REGEN=false
VERIFY_LAUNCH=0
LOGS=false
CONSOLE=false
DEVICE_ID="${IOS_DEVICE_ID:-}"
TEAM="${IOS_DEVELOPMENT_TEAM:-}"
ALLOW_DEVICE_REGISTRATION=false
TUNNEL=""            # "" = auto (on when BACKEND_URL is loopback), true, false
TUNNEL_PORT="${BACKEND_PORT:-8000}"
NGROK_DOMAIN="${NGROK_DOMAIN:-}"
STOP_TUNNEL=false
# Dev device builds use a stripped entitlements file (no Sign In with Apple /
# Apple Pay, which need App ID capabilities). --full-entitlements uses the
# project's real StarterApp.entitlements instead.
DEV_ENTITLEMENTS="StarterApp.dev.entitlements"

while [[ $# -gt 0 ]]; do
  case $1 in
    --regen)                     REGEN=true;                    shift ;;
    --device-id)                 DEVICE_ID="$2";                shift 2 ;;
    --team)                      TEAM="$2";                     shift 2 ;;
    --verify-launch)             VERIFY_LAUNCH="${2:-5}";       shift 2 ;;
    --logs)                      LOGS=true;                     shift ;;
    --console)                   CONSOLE=true;                  shift ;;
    --allow-device-registration) ALLOW_DEVICE_REGISTRATION=true; shift ;;
    --tunnel)                    TUNNEL=true;                   shift ;;
    --no-tunnel)                 TUNNEL=false;                  shift ;;
    --tunnel-port)               TUNNEL_PORT="$2";              shift 2 ;;
    --domain)                    NGROK_DOMAIN="$2";             shift 2 ;;
    --entitlements)              DEV_ENTITLEMENTS="$2";         shift 2 ;;
    --full-entitlements)         DEV_ENTITLEMENTS="";           shift ;;
    --stop-tunnel)               STOP_TUNNEL=true;              shift ;;
    -h|--help)
      sed -n '/^# Usage/,/^$/p' "$0" | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1  (try --help)"; exit 1 ;;
  esac
done

if $CONSOLE && $LOGS; then
  echo "Error: --console and --logs are mutually exclusive."
  echo "       --console streams AppLog over Wi-Fi (devicectl attach); --logs needs USB + libimobiledevice."
  exit 1
fi

# ---------------------------------------------------------------------------
# Tunnel state — ngrok runs one background agent with a local API on :4040.
# The log/pid live in a machine-local dir so the agent outlives this script.
# ---------------------------------------------------------------------------
TUNNEL_STATE_DIR="${TMPDIR:-/tmp}"
TUNNEL_LOG="${TUNNEL_STATE_DIR}/starterapp-ngrok.log"
TUNNEL_PIDFILE="${TUNNEL_STATE_DIR}/starterapp-ngrok.pid"
NGROK_API="http://127.0.0.1:4040/api/tunnels"

# Print the https public_url of the running agent's tunnel for our port, if any.
ngrok_current_url() {
  local port="$1"
  curl -s -m 5 "$NGROK_API" 2>/dev/null | python3 -c "
import sys, json
try:
    tunnels = json.load(sys.stdin).get('tunnels', [])
except Exception:
    sys.exit(0)
port = sys.argv[1]
for t in tunnels:
    if t.get('public_url','').startswith('https') and t.get('config',{}).get('addr','').endswith(':'+port):
        print(t['public_url']); break
" "$port" 2>/dev/null || true
}

stop_tunnel() {
  if [[ -f "$TUNNEL_PIDFILE" ]] && kill -0 "$(cat "$TUNNEL_PIDFILE")" 2>/dev/null; then
    kill "$(cat "$TUNNEL_PIDFILE")" 2>/dev/null || true
    echo "→ Stopped ngrok tunnel (pid $(cat "$TUNNEL_PIDFILE"))."
  else
    pkill -f "ngrok http" 2>/dev/null && echo "→ Stopped stray ngrok agent." || echo "→ No running ngrok tunnel found."
  fi
  rm -f "$TUNNEL_PIDFILE"
}

if $STOP_TUNNEL; then
  stop_tunnel
  exit 0
fi

# ---------------------------------------------------------------------------
# Paths — resolve relative to this script so it can be called from anywhere
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$REPO_ROOT/ios/StarterApp"
cd "$IOS_DIR"

WORKSPACE="StarterApp.xcworkspace"
SCHEME="StarterApp"
DERIVED_DATA="./DerivedDataDevice"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/StarterApp.app"
DEBUG_XCCONFIG="Config-Debug.xcconfig"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for cmd in xcodebuild xcrun python3 security; do
  command -v "$cmd" &>/dev/null || { echo "Error: '$cmd' not found."; exit 1; }
done

# ---------------------------------------------------------------------------
# Resolve DEVELOPMENT_TEAM
# ---------------------------------------------------------------------------
if [[ -z "$TEAM" && -f "$DEBUG_XCCONFIG" ]]; then
  TEAM=$(grep -E '^\s*DEVELOPMENT_TEAM\s*=' "$DEBUG_XCCONFIG" 2>/dev/null \
           | tail -1 | cut -d= -f2 | xargs || true)
fi
if [[ -z "$TEAM" ]]; then
  # OU field of the "Apple Development" certificate = Team ID
  TEAM=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
           | openssl x509 -noout -subject 2>/dev/null \
           | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2 || true)
fi
[[ -n "$TEAM" ]] || {
  echo "Error: Could not resolve a DEVELOPMENT_TEAM."
  echo "       Pass --team <ID>, set IOS_DEVELOPMENT_TEAM, or add DEVELOPMENT_TEAM to $DEBUG_XCCONFIG."
  exit 1
}
echo "→ Development team: $TEAM"

# ---------------------------------------------------------------------------
# Tuist — regenerate if requested or workspace missing
# ---------------------------------------------------------------------------
if $REGEN || [[ ! -d "$WORKSPACE" ]]; then
  command -v tuist &>/dev/null || {
    echo "Error: 'tuist' not found. Install from https://docs.tuist.dev"; exit 1; }
  echo "→ tuist install…"; tuist install
  echo "→ tuist generate…"; tuist generate --no-open
fi
[[ -d "$WORKSPACE" ]] || { echo "Error: $WORKSPACE not found. Run with --regen."; exit 1; }

# ---------------------------------------------------------------------------
# Select a paired physical device
# ---------------------------------------------------------------------------
echo "→ Locating paired iPhone…"
DEV_JSON="$(mktemp -t ios-device-XXXX).json"
xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null 2>&1 || {
  echo "Error: 'xcrun devicectl list devices' failed. Is a device paired?"; exit 1; }

read -r DEVICE_ID DEVICE_NAME < <(python3 - "$DEV_JSON" "$DEVICE_ID" <<'EOF'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
data = json.load(open(path))
best = None
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("platform") != "iOS":
        continue
    if conn.get("pairingState") != "paired":
        continue
    udid = hw.get("udid", "")
    name = d.get("deviceProperties", {}).get("name", "?")
    if wanted:
        if udid == wanted:
            best = (udid, name); break
    else:
        # Prefer a connected device; otherwise take the first paired one.
        connected = conn.get("tunnelState") in ("connected", "available") \
            or hw.get("deviceType") == "iPhone"
        if best is None or connected:
            best = (udid, name)
            if connected:
                break
if best:
    print(best[0], best[1])
EOF
)

[[ -n "${DEVICE_ID:-}" ]] || {
  echo "Error: No paired iPhone found."
  echo "       Connect via USB (trust the Mac) or enable wireless debugging in Xcode ▸ Devices."
  echo "       Seen devices:"; xcrun devicectl list devices 2>/dev/null | sed 's/^/         /'
  exit 1
}
echo "→ Device: ${DEVICE_NAME} (${DEVICE_ID})"

# ---------------------------------------------------------------------------
# Tunnel — expose the local backend so the phone can reach it, then bake the
# public URL into Config-Debug.xcconfig before building.
# ---------------------------------------------------------------------------
current_backend_url() {
  # Read BACKEND_URL from the xcconfig, undoing the `https:/$()/` comment-escape.
  grep -E '^\s*BACKEND_URL\s*=' "$DEBUG_XCCONFIG" 2>/dev/null \
    | tail -1 | cut -d= -f2- | sed 's/\$()//g' | xargs || true
}

# Auto-decide: tunnel on when the configured BACKEND_URL is loopback.
if [[ -z "$TUNNEL" ]]; then
  case "$(current_backend_url)" in
    *localhost*|*127.0.0.1*|*"0.0.0.0"*) TUNNEL=true ;;
    *)                                    TUNNEL=false ;;
  esac
fi

if $TUNNEL; then
  command -v ngrok &>/dev/null || {
    echo "Error: ngrok not found. Install: brew install ngrok"
    echo "       (or pass --no-tunnel if BACKEND_URL is already reachable from the phone)"
    exit 1; }

  # Backend must be up locally before we tunnel to it.
  if ! curl -sf -m 5 "http://localhost:${TUNNEL_PORT}/healthz" >/dev/null 2>&1; then
    echo "Error: backend not responding at http://localhost:${TUNNEL_PORT}/healthz"
    echo "       Start it first (e.g. 'make dev' or 'docker compose up -d')."
    exit 1
  fi

  # Reuse the running ngrok agent's tunnel for this port if one is already up.
  TUNNEL_URL="$(ngrok_current_url "$TUNNEL_PORT")"
  if [[ -n "$TUNNEL_URL" ]]; then
    echo "→ Reusing ngrok tunnel: $TUNNEL_URL"
  else
    echo "→ Starting ngrok tunnel to localhost:${TUNNEL_PORT}…"
    : > "$TUNNEL_LOG"
    NGROK_ARGS=(http "$TUNNEL_PORT" --log=stdout)
    [[ -n "$NGROK_DOMAIN" ]] && NGROK_ARGS+=(--domain="$NGROK_DOMAIN")
    nohup ngrok "${NGROK_ARGS[@]}" >"$TUNNEL_LOG" 2>&1 &
    echo $! > "$TUNNEL_PIDFILE"
    for _ in $(seq 1 20); do
      TUNNEL_URL="$(ngrok_current_url "$TUNNEL_PORT")"
      [[ -n "$TUNNEL_URL" ]] && break
      sleep 1
    done
    [[ -n "$TUNNEL_URL" ]] || {
      echo "Error: ngrok URL never appeared. Log: $TUNNEL_LOG"; tail -20 "$TUNNEL_LOG"; exit 1; }
    if curl -sf -m 10 "${TUNNEL_URL}/healthz" >/dev/null 2>&1; then
      echo "  ✓ Tunnel routing: $TUNNEL_URL (pid $(cat "$TUNNEL_PIDFILE"))."
    else
      echo "  ⚠ Tunnel up ($TUNNEL_URL) but /healthz not verified — continuing."
    fi
  fi

  # Bake the URL into Config-Debug.xcconfig (escape // so xcconfig doesn't treat it as a comment).
  python3 - "$DEBUG_XCCONFIG" "$TUNNEL_URL" <<'EOF'
import re, sys
path, url = sys.argv[1], sys.argv[2]
scheme, rest = url.split("://", 1)
escaped = f"{scheme}:/$()/{rest}"          # e.g. https:/$()/xxxx.trycloudflare.com
line = f"BACKEND_URL = {escaped}\n"
try:
    text = open(path).read()
except FileNotFoundError:
    text = ""
if re.search(r'^\s*BACKEND_URL\s*=', text, re.M):
    text = re.sub(r'^\s*BACKEND_URL\s*=.*$', line.rstrip("\n"), text, count=1, flags=re.M)
else:
    text = text.rstrip("\n") + "\n" + line
open(path, "w").write(text)
print(f"  ✓ Config-Debug.xcconfig BACKEND_URL -> {url}")
EOF
fi

# ---------------------------------------------------------------------------
# Build for a generic iOS device (lets automatic signing resolve the profile)
# ---------------------------------------------------------------------------
echo "→ Building ${SCHEME} (Debug, device)…"
EXTRA_ARGS=()
if $ALLOW_DEVICE_REGISTRATION; then
  EXTRA_ARGS+=(-allowProvisioningDeviceRegistration)
fi
if [[ -n "$DEV_ENTITLEMENTS" && -f "$DEV_ENTITLEMENTS" ]]; then
  echo "→ Using dev entitlements: $DEV_ENTITLEMENTS (Sign In with Apple kept, Apple Pay dropped)"
  # Absolute path: the setting applies to every target (incl. SPM deps), and a
  # relative path resolves against each target's own project dir. Frameworks
  # ignore entitlements, so an empty plist is harmless for them.
  EXTRA_ARGS+=(CODE_SIGN_ENTITLEMENTS="$PWD/$DEV_ENTITLEMENTS")
fi
xcodebuild build \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM" \
  -quiet

[[ -d "$APP_PATH" ]] || {
  echo "Error: Build succeeded but .app not found at:"; echo "       $APP_PATH"; exit 1; }

# ---------------------------------------------------------------------------
# Bundle ID — read from the built .app so it never drifts from the xcconfig
# ---------------------------------------------------------------------------
BUNDLE_ID=$(defaults read "$(pwd)/$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || true)
[[ -n "$BUNDLE_ID" ]] || { echo "Error: Could not read CFBundleIdentifier from the built app."; exit 1; }
# Executable name is what shows up in the device process list (bundle id doesn't).
EXEC_NAME=$(defaults read "$(pwd)/$APP_PATH/Info.plist" CFBundleExecutable 2>/dev/null || echo "StarterApp")

# ---------------------------------------------------------------------------
# Install → launch
# ---------------------------------------------------------------------------
echo "→ Installing ${BUNDLE_ID} on ${DEVICE_NAME}…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

if $CONSOLE; then
  echo "→ Launching attached (--console) — streaming os_log over the tunnel. Ctrl-C to stop."
  echo "  (unlock ${DEVICE_NAME} and keep it awake; DEBUG builds mirror AppLog to stdout)"
  if $TUNNEL && [[ -n "${TUNNEL_URL:-}" ]]; then
    echo "  Backend tunnel: ${TUNNEL_URL} (stop later with: $0 --stop-tunnel)"
  fi
  exec xcrun devicectl device process launch --console --terminate-existing \
    --device "$DEVICE_ID" "$BUNDLE_ID"
fi

echo "→ Launching… (unlock ${DEVICE_NAME} and keep the screen on)"
launched=false
for attempt in $(seq 1 18); do
  if launch_out=$(xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1); then
    launched=true
    break
  fi
  # Retry on transient conditions: locked device, or a flaky wireless connection
  # (error 4000 "disconnected immediately", timeouts). Fail fast on anything else.
  if grep -qiE "unlock|disconnect|error 4000|timed out|not.*connect" <<<"$launch_out"; then
    case $attempt in
      1) echo "  ⏳ Waiting for device — unlock it / keep it awake (retrying ~90s)…" ;;
    esac
    sleep 5
    continue
  fi
  echo "$launch_out"
  echo "Error: launch failed (non-transient — see above)."
  exit 1
done
if ! $launched; then
  echo "  ✗ Could not launch after retries (device stayed locked/disconnected)."
  echo "    The app is installed — unlock the phone and just tap the app icon,"
  echo "    or plug in via USB for a stable connection and re-run."
  exit 1
fi
echo ""
echo "✓ ${BUNDLE_ID} running on ${DEVICE_NAME}"
if $TUNNEL && [[ -n "${TUNNEL_URL:-}" ]]; then
  echo "  Backend tunnel: ${TUNNEL_URL} (left running; stop with: $0 --stop-tunnel)"
fi

# ---------------------------------------------------------------------------
# Verify launch — poll the device process list, fail if the app is gone
# ---------------------------------------------------------------------------
if [[ "$VERIFY_LAUNCH" -gt 0 ]]; then
  echo "→ Verifying app stayed alive for ${VERIFY_LAUNCH}s…"
  sleep "$VERIFY_LAUNCH"
  # The process query is flaky over Wi-Fi (empty/timeout even when the app runs),
  # so poll a few times and only fail if we get a valid list that lacks the app.
  alive=false
  for _ in $(seq 1 6); do
    procs=$(xcrun devicectl device info processes --device "$DEVICE_ID" 2>/dev/null || true)
    if grep -q "/${EXEC_NAME}.app/${EXEC_NAME}" <<<"$procs"; then alive=true; break; fi
    sleep 2
  done
  if $alive; then
    echo "  ✓ App is running."
  elif find ~/Library/Logs/CrashReporter -iname "*${EXEC_NAME}*" -newermt "-2 minutes" 2>/dev/null | grep -q .; then
    echo "  ✗ App crashed — recent crash report found:"
    find ~/Library/Logs/CrashReporter -iname "*${EXEC_NAME}*" -newermt "-2 minutes" 2>/dev/null | head -1 | sed 's/^/    /'
    exit 1
  else
    echo "  ⚠ Could not confirm via Wi-Fi (no crash report seen — app is likely running)."
    echo "    Verify manually: xcrun devicectl device info processes --device $DEVICE_ID | grep ${EXEC_NAME}"
  fi
fi

# ---------------------------------------------------------------------------
# Stream device logs (needs libimobiledevice + a USB connection)
# ---------------------------------------------------------------------------
if $LOGS; then
  if ! command -v idevicesyslog &>/dev/null; then
    echo "→ --logs needs libimobiledevice: brew install libimobiledevice"
  elif ! idevice_id -l 2>/dev/null | grep -q .; then
    echo "→ --logs needs a USB connection (libimobiledevice can't see the device over Wi-Fi)."
    echo "  Connect ${DEVICE_NAME} via cable, then: idevicesyslog -u ${DEVICE_ID} | grep -i ${EXEC_NAME}"
  else
    echo "→ Streaming device logs for ${EXEC_NAME} (Ctrl-C to stop)…"
    exec idevicesyslog -u "$DEVICE_ID" -p "$EXEC_NAME"
  fi
fi
