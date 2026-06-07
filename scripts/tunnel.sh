#!/usr/bin/env bash
# scripts/tunnel.sh — Supabase + FastAPI + instatunnel for real device or remote access.
#
# Use this instead of dev.sh when testing on a physical iPhone or sharing
# the backend externally. Exposes both services via instatunnel.dev subdomains
# so any device on any network can reach them.
#
# After tunnels are up, you will be prompted to override Config-Debug.xcconfig
# with the tunnel URLs. If you confirm, the Xcode project is regenerated and
# the iOS Simulator is built and launched with the new config baked in.
#
# Usage:
#   ./scripts/tunnel.sh              # start services + tunnels + prompt + build
#   ./scripts/tunnel.sh --build      # rebuild Docker image first
#   ./scripts/tunnel.sh --regen      # run tuist install + generate before iOS build
#   ./scripts/tunnel.sh --no-ios     # skip iOS config prompts and build

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
BUILD=false
REGEN=false
NO_IOS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --build)   BUILD=true;   shift ;;
    --regen)   REGEN=true;   shift ;;
    --no-ios)  NO_IOS=true;  shift ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1  (try --help)"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$REPO_ROOT/scripts/_lib.sh"

# ---------------------------------------------------------------------------
# Config — edit these once
# ---------------------------------------------------------------------------
SUPA_SUBDOMAIN="my-supa-api"
BACKEND_SUBDOMAIN="my-backend-api"

SUPA_TUNNEL_URL="https://${SUPA_SUBDOMAIN}.instatunnel.dev"
BACKEND_TUNNEL_URL="https://${BACKEND_SUBDOMAIN}.instatunnel.dev"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
  echo ""
  echo "==> Shutting down…"
  (cd "$BACKEND_DIR" && docker compose down 2>/dev/null) || true
  supabase stop --no-backup 2>/dev/null || true
  kill "$DOCKER_PID" 2>/dev/null || true
  echo "==> Done."
}
DOCKER_PID=""
trap cleanup INT TERM EXIT

# ---------------------------------------------------------------------------
# 1–2. Supabase
# ---------------------------------------------------------------------------
start_supabase

# ---------------------------------------------------------------------------
# 3. Backend .env (Docker container still talks to Supabase via host.docker.internal)
# ---------------------------------------------------------------------------
configure_backend_env

# ---------------------------------------------------------------------------
# 4–5. FastAPI
# ---------------------------------------------------------------------------
echo "==> Starting FastAPI backend (docker compose)…"
if $BUILD; then
  (cd "$BACKEND_DIR" && docker compose up --build) &
else
  (cd "$BACKEND_DIR" && docker compose up) &
fi
DOCKER_PID=$!

wait_for_backend

# ---------------------------------------------------------------------------
# 6. Tunnels
# ---------------------------------------------------------------------------
echo "==> Starting tunnels…"
instatunnel 54321 --subdomain "$SUPA_SUBDOMAIN" &
instatunnel 8000  --subdomain "$BACKEND_SUBDOMAIN" &

echo ""
printf '  %-14s →  %s\n' "Supabase API"  "$SUPA_TUNNEL_URL"
printf '  %-14s →  %s\n' "Backend API"   "$BACKEND_TUNNEL_URL"
printf '  %-14s →  %s\n' "Supabase UI"   "http://127.0.0.1:54323 (local only)"
echo ""

# ---------------------------------------------------------------------------
# 7. iOS xcconfig — prompt to override with tunnel URLs
# ---------------------------------------------------------------------------
if ! $NO_IOS; then
  if [[ ! -f "$XCCONFIG" ]]; then
    cp "$XCCONFIG_EXAMPLE" "$XCCONFIG"
    echo "    created Config-Debug.xcconfig from example"
  fi

  # Decode xcconfig-safe URL escaping back to a readable URL for display
  decode_xcurl() { echo "$1" | sed 's|:/\$()/|://|g'; }
  current_backend=$(decode_xcurl "$(grep "^BACKEND_URL = "  "$XCCONFIG" 2>/dev/null | sed 's/^BACKEND_URL = //'  || true)")
  current_supa=$(decode_xcurl    "$(grep "^SUPABASE_URL = " "$XCCONFIG" 2>/dev/null | sed 's/^SUPABASE_URL = //' || true)")

  echo "==> Update Config-Debug.xcconfig with tunnel URLs?"
  echo ""

  yn_backend="n"
  [[ -n "$current_backend" ]] && printf "    BACKEND_URL  set to: %s\n" "$current_backend"
  printf "    Override with %s? [y/N] " "$BACKEND_TUNNEL_URL"
  read -r yn_backend

  echo ""

  yn_supa="n"
  [[ -n "$current_supa" ]] && printf "    SUPABASE_URL set to: %s\n" "$current_supa"
  printf "    Override with %s? [y/N] " "$SUPA_TUNNEL_URL"
  read -r yn_supa

  echo ""

  FINAL_BACKEND_URL=$( [[ "${yn_backend,,}" == "y" ]] && echo "$BACKEND_TUNNEL_URL" || echo "$BACKEND_LOCAL_URL" )
  FINAL_SUPA_URL=$(    [[ "${yn_supa,,}" == "y"    ]] && echo "$SUPA_TUNNEL_URL"    || echo "$SUPA_LOCAL_URL"    )

  echo "==> Writing Config-Debug.xcconfig…"
  upsert_xcconfig "$XCCONFIG" "BACKEND_URL"       "$(xcconfig_url "$FINAL_BACKEND_URL")"
  upsert_xcconfig "$XCCONFIG" "SUPABASE_URL"      "$(xcconfig_url "$FINAL_SUPA_URL")"
  upsert_xcconfig "$XCCONFIG" "SUPABASE_ANON_KEY" "$SUPA_ANON_KEY"

  # ---------------------------------------------------------------------------
  # 8. Tuist + build
  # ---------------------------------------------------------------------------
  run_tuist "$REGEN"

  echo "==> Building and launching iOS Simulator…"
  "$IOS_SIM"

  echo ""
  echo "┌─────────────────────────────────────────────────────────────────┐"
  echo "│  ✓ Tunnels live — run the app on your device now.              │"
  echo "│                                                                  │"
  printf "│  Supabase  →  %-50s│\n" "$SUPA_TUNNEL_URL"
  printf "│  Backend   →  %-50s│\n" "$BACKEND_TUNNEL_URL"
  echo "│                                                                  │"
  echo "│  To build for a physical device: open Xcode, select your        │"
  echo "│  device, and hit Run — the xcconfig is already configured.      │"
  echo "│                                                                  │"
  echo "│  Ctrl+C to stop all services.                                   │"
  echo "└─────────────────────────────────────────────────────────────────┘"
  echo ""
fi

wait
