#!/usr/bin/env bash
# scripts/dev.sh — One-command local dev: Docker Compose + FastAPI + iOS Simulator.
#
# No tunnels needed — the iOS Simulator runs on this Mac and can reach
# 127.0.0.1 directly.
#
# What it does:
#   1.  docker compose up     (PostgreSQL + FastAPI + Adminer)
#   2.  Runs alembic          migrate database schema
#   3.  Writes backend/.env   DATABASE_URL + JWT_SECRET
#   4.  Waits for /healthz    to confirm the backend is ready
#   5.  Writes iOS Config-Debug.xcconfig  BACKEND_URL
#   6.  tuist generate        (always — keeps Xcode project in sync with file system)
#   7.  Builds + launches     iOS Simulator (auto-picks newest iPhone)
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
BACKEND_DIR="$REPO_ROOT/backend"
BACKEND_HEALTHZ="http://127.0.0.1:8000/healthz"
XCCONFIG="$REPO_ROOT/ios/StarterApp/Config-Debug.xcconfig"
XCCONFIG_EXAMPLE="$REPO_ROOT/ios/StarterApp/Config.example.xcconfig"
IOS_DIR="$REPO_ROOT/ios/StarterApp"
IOS_SIM="$REPO_ROOT/scripts/ios-sim.sh"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
# Base stack + local-dev overlay (bind-mounts backend source, runs uvicorn --reload).
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.dev.yml)

cleanup() {
  echo ""
  echo "==> Shutting down…"
  (cd "$REPO_ROOT" && "${COMPOSE[@]}" down 2>/dev/null) || true
  echo "==> Done."
}
trap cleanup INT TERM EXIT

# ---------------------------------------------------------------------------
# 1–2. Docker Compose + Migrations
# ---------------------------------------------------------------------------
echo "==> Starting dev stack (PostgreSQL + FastAPI + Adminer)… backend hot-reloads on edit"
cd "$REPO_ROOT"
"${COMPOSE[@]}" up --build -d

echo "==> Running Alembic migrations…"
sleep 3
"${COMPOSE[@]}" exec backend uv run alembic upgrade head

# ---------------------------------------------------------------------------
# 3. Wait for backend
# ---------------------------------------------------------------------------
echo "==> Waiting for backend to be ready…"
max_attempts=30
attempt=0
while ! curl -s "$BACKEND_HEALTHZ" &>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $max_attempts ]]; then
    echo "ERROR: Backend did not become ready after ${max_attempts} attempts"
    exit 1
  fi
  echo "  (waiting… ${attempt}/${max_attempts})"
  sleep 1
done
echo "✓ Backend is ready"

# ---------------------------------------------------------------------------
# 4. iOS xcconfig
# ---------------------------------------------------------------------------
echo "==> Configuring iOS…"
if [[ ! -f "$XCCONFIG" ]]; then
  cp "$XCCONFIG_EXAMPLE" "$XCCONFIG"
fi

# Write BACKEND_URL (escape // so xcconfig doesn't treat it as a comment — same as ios-device.sh)
python3 - "$XCCONFIG" "http://127.0.0.1:8000" <<'EOF'
import re, sys
path, url = sys.argv[1], sys.argv[2]
scheme, rest = url.split("://", 1)
escaped = f"{scheme}:/$()/{rest}"
line = f"BACKEND_URL = {escaped}\n"
try:
    text = open(path).read()
except FileNotFoundError:
    text = open(path.replace("Config-Debug.xcconfig", "Config.example.xcconfig")).read()
if re.search(r'^\s*BACKEND_URL\s*=', text, re.M):
    text = re.sub(r'^\s*BACKEND_URL\s*=.*$', line.rstrip("\n"), text, count=1, flags=re.M)
else:
    text = text.rstrip("\n") + "\n" + line
open(path, "w").write(text)
EOF

# ---------------------------------------------------------------------------
# 5. Tuist + iOS Simulator
# ---------------------------------------------------------------------------
if $NO_IOS; then
  echo ""
  echo "==> Services running (--no-ios: skipping simulator)."
  echo ""
  echo "  API              → http://localhost:8000"
  echo "  API docs         → http://localhost:8000/docs"
  echo "  Adminer DB admin → http://localhost:8080"
  echo ""
  echo "Press Ctrl+C to stop everything."
  wait
else
  if $REGEN; then
    echo "==> Running tuist install + generate (--regen)…"
    (cd "$IOS_DIR" && tuist install && tuist generate)
  else
    echo "==> Running tuist generate…"
    (cd "$IOS_DIR" && tuist generate)
  fi

  echo "==> Building and launching iOS Simulator…"
  SIM_ARGS=""
  $SIM_LOGS && SIM_ARGS="$SIM_ARGS --logs"

  echo ""
  echo "  API              → http://localhost:8000"
  echo "  API docs         → http://localhost:8000/docs"
  echo "  Adminer DB admin → http://localhost:8080"
  echo ""

  # shellcheck disable=SC2086
  "$IOS_SIM" $SIM_ARGS

  echo ""
  echo "Simulator launched. Press Ctrl+C to stop all services."
  wait
fi
