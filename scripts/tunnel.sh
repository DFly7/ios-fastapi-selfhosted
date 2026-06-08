#!/usr/bin/env bash
# scripts/tunnel.sh — Expose the local backend via cloudflared tunnel.
#
# Use this instead of dev.sh when testing on a physical iPhone or accessing
# the backend from outside the local network. Exposes the backend via
# a cloudflared tunnel so any device can reach it.
#
# Prerequisites:
#   brew install cloudflare/warp/cloudflared
#
# Usage:
#   ./scripts/tunnel.sh              # start services + tunnel
#   ./scripts/tunnel.sh --no-ios     # services + tunnel only (skip iOS config)
#   ./scripts/tunnel.sh --help

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
NO_IOS=false

while [[ $# -gt 0 ]]; do
  case $1 in
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
BACKEND_PORT="${BACKEND_PORT:-8000}"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
  echo ""
  echo "==> Shutting down…"
  (cd "$REPO_ROOT" && docker compose down 2>/dev/null) || true
  echo "==> Done."
}
trap cleanup INT TERM EXIT

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
if ! command -v cloudflared &>/dev/null; then
  echo "Error: cloudflared not found."
  echo "Install with: brew install cloudflare/warp/cloudflared"
  exit 1
fi

# ---------------------------------------------------------------------------
# Start services
# ---------------------------------------------------------------------------
echo "==> Starting dev stack (PostgreSQL + FastAPI + Adminer)…"
cd "$REPO_ROOT"
docker compose up --build -d

echo "==> Running Alembic migrations…"
sleep 3
docker compose exec backend uv run alembic upgrade head

echo "==> Waiting for backend to be ready…"
max_attempts=30
attempt=0
BACKEND_HEALTHZ="http://127.0.0.1:${BACKEND_PORT}/healthz"
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
# Start tunnel in background
# ---------------------------------------------------------------------------
echo ""
echo "==> Starting cloudflared tunnel for backend port $BACKEND_PORT…"
cloudflared tunnel --url "http://localhost:${BACKEND_PORT}" &
TUNNEL_PID=$!

# Give the tunnel a moment to establish
sleep 2

echo ""
echo "  Backend is now accessible via the cloudflared tunnel."
echo "  You can access it from any network using the tunnel URL."
echo ""
echo "  Local:  http://localhost:${BACKEND_PORT}"
echo "  Tunnel: https://<your-tunnel-url> (check cloudflared output above)"
echo ""
echo "Press Ctrl+C to stop all services."

wait
