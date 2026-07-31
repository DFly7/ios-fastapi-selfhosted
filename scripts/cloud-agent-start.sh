#!/usr/bin/env bash
# Cursor Cloud Agent start step — Docker daemon + Postgres for this repo.
# Idempotent; safe if services are already running.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Cloud agent start (Docker + Postgres)"

# Start dockerd when missing (DinD / nested Docker).
if ! docker info >/dev/null 2>&1; then
  if command -v service >/dev/null 2>&1; then
    sudo service docker start || true
  fi
  if ! docker info >/dev/null 2>&1; then
    sudo dockerd >/tmp/dockerd.log 2>&1 &
    # Wait for the socket
    for _ in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "⚠  Docker daemon failed to start — see /tmp/dockerd.log"
  echo "   Backend unit tests still work; integration tests need Postgres."
  exit 0
fi

docker pull postgres:17-alpine >/dev/null || true

# Root compose only — do not bring up any extra services unless asked.
docker compose up -d db

echo "  → waiting for Postgres health"
for _ in $(seq 1 40); do
  if docker compose exec -T db pg_isready -U postgres >/dev/null 2>&1; then
    echo "✓ Postgres ready on localhost:5432"
    exit 0
  fi
  sleep 1
done

echo "⚠  Postgres did not become ready in time"
exit 0
