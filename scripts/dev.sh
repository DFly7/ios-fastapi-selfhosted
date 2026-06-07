#!/usr/bin/env bash
# scripts/dev.sh — One-command local dev: Supabase + FastAPI + iOS Simulator.
#
# No tunnels needed — the iOS Simulator runs on this Mac and can reach
# 127.0.0.1 directly.
#
# What it does:
#   1.  supabase start        (local Postgres / Auth / Storage / Studio)
#   2.  Reads anon key from   supabase status
#   3.  Writes backend/.env   SUPABASE_URL + SUPABASE_PUBLIC_ANON_KEY
#   4.  Starts FastAPI        docker compose up  (port 8000)
#   5.  Waits for /healthz    to confirm the backend is ready
#   6.  Writes ios Config-Debug.xcconfig  BACKEND_URL + SUPABASE_URL + SUPABASE_ANON_KEY
#   7.  tuist generate        (always — keeps Xcode project in sync with file system)
#   8.  Builds + launches     iOS Simulator (auto-picks newest iPhone)
#
# Usage:
#   ./scripts/dev.sh                  # full stack, auto-pick sim
#   ./scripts/dev.sh --regen          # run tuist install + generate before iOS build
#   ./scripts/dev.sh --no-ios         # services only (skip iOS build/launch)
#   ./scripts/dev.sh --sim-logs       # stream simulator console after launch

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
REGEN=false
NO_IOS=false
SIM_LOGS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --regen)    REGEN=true;    shift ;;
    --no-ios)   NO_IOS=true;   shift ;;
    --sim-logs) SIM_LOGS=true; shift ;;
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
# 3. Backend .env
# ---------------------------------------------------------------------------
configure_backend_env

# ---------------------------------------------------------------------------
# 4–5. FastAPI
# ---------------------------------------------------------------------------
echo "==> Starting FastAPI backend (docker compose)…"
(cd "$BACKEND_DIR" && docker compose up --build) &
DOCKER_PID=$!

wait_for_backend

# ---------------------------------------------------------------------------
# 6. iOS xcconfig
# ---------------------------------------------------------------------------
configure_ios_xcconfig

# ---------------------------------------------------------------------------
# 6b. Config summary
# ---------------------------------------------------------------------------
check_config_files

# ---------------------------------------------------------------------------
# 7–8. Tuist + iOS Simulator
# ---------------------------------------------------------------------------
if $NO_IOS; then
  echo ""
  echo "==> Services running (--no-ios: skipping simulator)."
  echo "    Supabase Studio → http://127.0.0.1:54323"
  echo "    FastAPI docs    → http://127.0.0.1:8000/docs"
  echo ""
  echo "Press Ctrl+C to stop everything."
  wait
else
  run_tuist "$REGEN"

  echo "==> Building and launching iOS Simulator…"
  SIM_ARGS=""
  $SIM_LOGS && SIM_ARGS="$SIM_ARGS --logs"

  echo ""
  echo "Services:"
  echo "  Supabase Studio → http://127.0.0.1:54323"
  echo "  FastAPI docs    → http://127.0.0.1:8000/docs"
  echo ""

  # shellcheck disable=SC2086
  "$IOS_SIM" $SIM_ARGS

  echo ""
  echo "Simulator launched. Press Ctrl+C to stop all services."
  wait
fi
