#!/usr/bin/env bash
# Idempotent Cursor Cloud Agent install step (runs from repo root after checkout).
# Seeds gitignored .env files, syncs backend deps, pre-pulls Postgres.
# Does NOT install Tuist/Xcode — iOS builds belong to macOS CI / Remote Control.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

sed_inplace() {
  local expr="$1"
  local file="$2"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$expr" "$file"
  else
    sed -i "$expr" "$file"
  fi
}

set_env_key() {
  # set_env_key FILE KEY VALUE — create or replace KEY= in FILE
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed_inplace "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

echo "==> Cloud agent install"

# ---------------------------------------------------------------------------
# 1. Root .env + backend/.env
# ---------------------------------------------------------------------------
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "  ✓ Created .env from example"
else
  echo "  · .env already present"
fi

if [[ ! -f backend/.env ]]; then
  cp backend/.env.example backend/.env
  echo "  ✓ Created backend/.env from example"
else
  echo "  · backend/.env already present"
fi

# Prefer Cursor dashboard secrets when present; otherwise generate a local JWT.
if [[ -n "${JWT_SECRET:-}" ]]; then
  set_env_key .env JWT_SECRET "$JWT_SECRET"
  set_env_key backend/.env JWT_SECRET "$JWT_SECRET"
  echo "  ✓ JWT_SECRET synced from environment secret"
elif grep -q 'change-me-generate-with-openssl-rand-hex-32' .env 2>/dev/null; then
  JWT="$(openssl rand -hex 32)"
  set_env_key .env JWT_SECRET "$JWT"
  set_env_key backend/.env JWT_SECRET "$JWT"
  echo "  ✓ Generated JWT_SECRET"
fi

# Keep app config pointed at Compose Postgres on localhost (agent host → published 5432).
set_env_key backend/.env DATABASE_URL \
  "postgresql+asyncpg://postgres:${POSTGRES_PASSWORD:-postgres}@localhost:5432/postgres"
set_env_key backend/.env ENVIRONMENT development

# ---------------------------------------------------------------------------
# 2. Tooling — python + uv only (skip Tuist / SwiftLint on Linux)
# ---------------------------------------------------------------------------
if command -v mise >/dev/null 2>&1; then
  mise trust "$REPO_ROOT/.mise.toml" >/dev/null 2>&1 || true
  mise install python uv
  echo "  ✓ mise: python + uv ready"
else
  echo "  · mise not found — relying on image PATH for python/uv"
fi

# ---------------------------------------------------------------------------
# 3. Backend dependencies (cached across boots when install is slow)
# ---------------------------------------------------------------------------
echo "  → uv sync --frozen"
(cd backend && uv sync --frozen)
echo "  ✓ backend deps synced"

# ---------------------------------------------------------------------------
# 4. Warm Docker images (daemon may not be up yet — best effort)
# ---------------------------------------------------------------------------
if docker info >/dev/null 2>&1; then
  docker pull postgres:17-alpine >/dev/null
  echo "  ✓ postgres:17-alpine pulled"
else
  echo "  · docker daemon not running yet — start step will pull Postgres"
fi

echo "✓ Cloud agent install complete"
echo "  Verify with: make cloud-validate"
echo "  Integration: docker compose up -d db && make backend-integration-test"
echo "  Do NOT run: make ios-build / ios-test / validate (needs macOS)"
