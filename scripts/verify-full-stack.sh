#!/usr/bin/env bash
# scripts/verify-full-stack.sh — Start Docker, migrate, run ALL tests, smoke test, tear down.
#
# This is the single command an agent calls to verify everything works end-to-end.
# It always tears down Docker on exit (success or failure).
#
# Usage:
#   bash scripts/verify-full-stack.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BACKEND_HEALTHZ="http://127.0.0.1:8000/healthz"

# ── Cleanup on exit ───────────────────────────────────────────────────────
cleanup() {
  echo ""
  echo "==> Tearing down Docker…"
  docker compose down 2>/dev/null || true
}
trap cleanup EXIT

# ── 1. Start Docker ──────────────────────────────────────────────────────
echo "==> Starting Docker stack…"
docker compose up --build -d

# ── 2. Wait for backend health ───────────────────────────────────────────
echo "==> Waiting for backend…"
max_attempts=30
attempt=0
while ! curl -s "$BACKEND_HEALTHZ" &>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $max_attempts ]]; then
    echo "ERROR: Backend not ready after ${max_attempts}s"
    docker compose logs backend
    exit 1
  fi
  sleep 1
done
echo "  Backend ready."

# ── 3. Run migrations ───────────────────────────────────────────────────
echo "==> Running Alembic migrations…"
docker compose exec backend uv run alembic upgrade head

# ── 4. Backend unit tests ────────────────────────────────────────────────
echo ""
echo "==> Backend unit tests…"
cd backend && \
  ENVIRONMENT=ci LOG_JSON=false RATE_LIMIT_ENABLED=false \
  uv run pytest tests/ -v --tb=short -m "not integration" \
    --cov=app --cov-report=term-missing:skip-covered
cd "$REPO_ROOT"

# ── 5. Backend integration tests ────────────────────────────────────────
echo ""
echo "==> Backend integration tests…"
cd backend && \
  ENVIRONMENT=ci LOG_JSON=false RATE_LIMIT_ENABLED=false \
  DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres \
  JWT_SECRET=$(grep '^JWT_SECRET=' "$REPO_ROOT/.env" | cut -d= -f2) \
  uv run pytest tests/integration/ -v -m integration --tb=short
cd "$REPO_ROOT"

# ── 6. Smoke test ────────────────────────────────────────────────────────
echo ""
echo "==> Smoke test…"
bash scripts/smoke-test.sh

# ── 7. iOS (if simulator available) ─────────────────────────────────────
SIM_ID=$(xcrun simctl list devices available 2>/dev/null | grep -i iphone | tail -1 | grep -oEi '[0-9A-F-]{36}' || true)
if [[ -n "$SIM_ID" ]]; then
  echo ""
  echo "==> iOS build check (SIM_ID=${SIM_ID})…"
  make ios-build SIM_ID="$SIM_ID"
else
  echo ""
  echo "==> Skipping iOS build (no simulator available)"
fi

echo ""
echo "✓  Full stack verification passed."
