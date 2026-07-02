#!/usr/bin/env bash
# scripts/mcp-postgres-local.sh — Start postgres-local MCP only when Postgres is reachable.
# Requires: make dev (or docker compose up -d db) so localhost:5432 accepts connections.

set -euo pipefail

if ! command -v pg_isready &>/dev/null; then
  echo "postgres-local MCP: pg_isready not found (install PostgreSQL client tools)." >&2
  echo "Start the database first: make dev  OR  docker compose up -d db" >&2
  exit 1
fi

if ! pg_isready -h localhost -p 5432 -q; then
  echo "postgres-local MCP: PostgreSQL is not ready on localhost:5432." >&2
  echo "Start the database first: make dev  OR  docker compose up -d db" >&2
  exit 1
fi

exec npx -y @modelcontextprotocol/server-postgres \
  "postgresql://postgres:postgres@localhost:5432/postgres"
