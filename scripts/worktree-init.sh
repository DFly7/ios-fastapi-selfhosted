#!/usr/bin/env bash
# Make a fresh git worktree buildable.
#
# The files needed to run *any* verification gate are all gitignored, so a new worktree starts
# unable to lint, test, or build — each failing with an error that points at the code rather than
# at the missing config:
#
#   make backend-test  → Pydantic "jwt_secret — Field required"   (.env / backend/.env absent)
#   make lint          → "Config files are not trusted"           (.mise.toml untrusted at new path)
#   tuist generate     → generic Tuist failure                    (Config-Debug.xcconfig absent)
#   make ios-build     → "workspace not found"                    (no .xcworkspace yet)
#
# This script fixes all four. It is idempotent — safe to re-run.
#
# Secrets are copied from the main checkout when it has them, so every worktree talks to the same
# local database with the same JWT_SECRET. Only if the main checkout has no .env do we generate one.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# In a worktree, --git-common-dir points at <main>/.git; its parent is the main checkout.
GIT_COMMON="$(git rev-parse --git-common-dir)"
MAIN_ROOT="$(cd "$(dirname "$(cd "$GIT_COMMON" && pwd)")" && pwd)"

if [[ "$MAIN_ROOT" == "$REPO_ROOT" ]]; then
  echo "==> Main checkout (not a worktree) — seeding config in place."
else
  echo "==> Worktree: $REPO_ROOT"
  echo "    Main checkout: $MAIN_ROOT"
fi

# ---------------------------------------------------------------------------
# 1. Root .env  (Docker Compose vars, incl. JWT_SECRET)
# ---------------------------------------------------------------------------
if [[ -f .env ]]; then
  echo "  · .env already present"
elif [[ -f "$MAIN_ROOT/.env" ]]; then
  cp "$MAIN_ROOT/.env" .env
  echo "  ✓ .env copied from main checkout (shared JWT_SECRET + DB)"
else
  cp .env.example .env
  JWT="$(openssl rand -hex 32)"
  sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/$JWT/" .env
  echo "  ✓ .env created from example (generated JWT_SECRET)"
fi

# ---------------------------------------------------------------------------
# 2. backend/.env  (app config for `uv run` local dev)
# ---------------------------------------------------------------------------
if [[ -f backend/.env ]]; then
  echo "  · backend/.env already present"
elif [[ -f "$MAIN_ROOT/backend/.env" ]]; then
  cp "$MAIN_ROOT/backend/.env" backend/.env
  echo "  ✓ backend/.env copied from main checkout"
else
  cp backend/.env.example backend/.env
  JWT="$(grep '^JWT_SECRET=' .env | cut -d= -f2)"
  sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/$JWT/" backend/.env
  echo "  ✓ backend/.env created from example (JWT_SECRET synced from root .env)"
fi

# ---------------------------------------------------------------------------
# 3. iOS xcconfig  (gitignored: holds the dev team id + bundle id)
# ---------------------------------------------------------------------------
IOS_DIR="ios/StarterApp"
for cfg in Config-Debug Config-Release; do
  if [[ -f "$IOS_DIR/$cfg.xcconfig" ]]; then
    echo "  · $cfg.xcconfig already present"
  elif [[ -f "$MAIN_ROOT/$IOS_DIR/$cfg.xcconfig" ]]; then
    cp "$MAIN_ROOT/$IOS_DIR/$cfg.xcconfig" "$IOS_DIR/$cfg.xcconfig"
    echo "  ✓ $cfg.xcconfig copied from main checkout (keeps your real team id)"
  else
    cp "$IOS_DIR/Config.example.xcconfig" "$IOS_DIR/$cfg.xcconfig"
    echo "  ✓ $cfg.xcconfig created from example (placeholder team id — fine for Simulator)"
  fi
done

# ---------------------------------------------------------------------------
# 4. mise trust  (config is untrusted at every new path)
# ---------------------------------------------------------------------------
if command -v mise >/dev/null 2>&1; then
  mise trust --quiet 2>/dev/null || mise trust >/dev/null
  echo "  ✓ mise config trusted"
else
  echo "  ⚠  mise not found — skipping trust (lint may fail)"
fi

# ---------------------------------------------------------------------------
# 5. Xcode project  (Tuist-generated, gitignored)
# ---------------------------------------------------------------------------
if [[ -d "$IOS_DIR/StarterApp.xcworkspace" ]]; then
  echo "  · StarterApp.xcworkspace already generated"
else
  echo "==> Generating Xcode project (tuist install + generate)…"
  (cd "$IOS_DIR" && tuist install && tuist generate --no-open)
  echo "  ✓ StarterApp.xcworkspace generated"
fi

echo ""
echo "✓  Worktree ready. Verification gates should now run:"
echo "     make lint  ·  make backend-test  ·  make ios-build  ·  make ios-test-real"
