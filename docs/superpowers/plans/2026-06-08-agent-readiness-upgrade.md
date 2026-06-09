# Agent-Readiness Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ios-fastapi-selfhosted repo 100% agent-executable from the terminal — an AI agent can bootstrap the environment, build/test/deploy the full stack, and verify results without any GUI interaction.

**Architecture:** Eight tasks across workspace metadata (CLAUDE.md, AGENTS.md), verification scripts (full-stack, smoke test), MCP configuration (Postgres, fetch for both Claude Code and Cursor), simulator automation (headless, screenshots, state cleanup), API contract hardening (auth schemas moved to discoverable package, iOS decoder fix), and developer bootstrap automation (single `make bootstrap` command).

**Tech Stack:** Bash, Python 3.12, FastAPI, Pydantic, Swift/SwiftUI, Tuist, Docker Compose, xcrun simctl, MCP (Postgres + fetch servers), Make.

---

## File Map

### Created
- `CLAUDE.md` — Claude Code workspace rules (separate from AGENTS.md)
- `scripts/verify-full-stack.sh` — unified test orchestrator (docker + migrate + test + teardown)
- `scripts/smoke-test.sh` — curl-based happy-path verification
- `.claude/settings.json` — Claude Code MCP server config
- `.cursor/mcp.json` — Cursor MCP server config (from updated example)
- `backend/app/schemas/auth.py` — auth request/response schemas (moved from auth route)

### Modified
- `AGENTS.md` — remove 7 Supabase references, update stack description
- `.cursor/rules/monorepo.mdc` — remove Supabase MCP rule
- `.cursor/rules/backend.mdc` — remove Supabase integration test reference
- `.cursor/mcp.json.example` — replace Supabase MCP with Postgres + fetch
- `scripts/ios-sim.sh` — add `--headless`, `--clean-state`, `--screenshot`, `--verify-launch`
- `backend/app/api/v1/auth.py` — import schemas from `schemas.auth` instead of inline
- `backend/app/schemas/__init__.py` — export auth schemas
- `scripts/sync_models.py` — add `SKIP_SCHEMAS` entries for request-only types
- `ios/StarterApp/StarterApp/Services/AuthService.swift` — fix JSONDecoder to use `.iso8601`
- `Makefile` — add `bootstrap`, `validate-full`, `smoke-test` targets; reorder `validate` steps

---

## Task 1: Fix AGENTS.md — remove stale Supabase references

**Files:**
- Modify: `AGENTS.md`
- Modify: `.cursor/rules/monorepo.mdc`
- Modify: `.cursor/rules/backend.mdc`

- [ ] **Step 1: Update AGENTS.md title and "What this repo is" section**

Replace lines 1-13 of `AGENTS.md`:

```markdown
# Agent guide — iOS-FastAPI-Self-Hosted

Use this file for repository context. **User instructions in chat and Cursor rules override this document** when they conflict.

**Cursor rules** (`.cursor/rules/`): **`monorepo.mdc`** applies everywhere. **`backend.mdc`** and **`ios.mdc`** attach when you work under **`backend/**/*.py`** or **`ios/**/*.swift`** — short reminders for Makefile targets and testing; this file stays the **source of truth** for full conventions.

## What this repo is

- **iOS app:** SwiftUI, Tuist-generated workspace under `ios/StarterApp/` (`StarterApp.xcworkspace`, scheme `StarterApp`).
- **Backend:** FastAPI in `backend/` (Python, `uv`, pytest).
- **Database / auth:** Self-hosted FastAPI auth (bcrypt + HS256 JWT) + PostgreSQL 17 via Docker Compose. Alembic manages migrations.
- **API contracts:** Pydantic schemas in the backend; Swift models generated into `ios/StarterApp/StarterApp/Models/GeneratedModels.swift` (see `make sync-models` / `make check-models`).
```

- [ ] **Step 2: Update skills listing — replace supabase skill reference**

In the Skills section, replace:
```
- **Data / API:** `supabase-postgres-best-practices` (Postgres, RLS, performance).
```
With:
```
- **Data / API:** Postgres best practices — use SQLAlchemy async queries, Alembic for migrations. No Supabase.
```

- [ ] **Step 3: Update backend testing conventions — remove Supabase env vars**

In the Backend testing table, replace the Conventions row content. Change:
```
Integration needs **`SUPABASE_URL`**, **`SUPABASE_PUBLIC_ANON_KEY`**, **`SUPABASE_SERVICE_ROLE_KEY`** (e.g. from `supabase status -o env`). Run separately: `uv run pytest tests/integration/ -v -m integration` — see `.github/workflows/backend-integration.yml` and `tests/integration/` docstrings.
```
With:
```
Integration needs Docker Compose running (`make dev` or `docker compose up -d db`) and `DATABASE_URL` + `JWT_SECRET` env vars. Run separately: `make backend-integration-test` — see `.github/workflows/backend-integration.yml`.
```

- [ ] **Step 4: Delete the entire "Supabase MCP (Cursor)" section**

Remove everything from `## Supabase MCP (Cursor)` through the line `Local CLI label **project_id**...` (lines 52-75 of current AGENTS.md). This is approximately 23 lines.

- [ ] **Step 5: Update .cursor/rules/monorepo.mdc — remove Supabase rule**

Replace line 12 of `monorepo.mdc`:
```
- **Supabase:** For **hosted** vs **local** MCP and CLI, follow **`AGENTS.md`** (Supabase MCP section). Do not assume MCP `execute_sql` hits **local** DB unless the active MCP server is the **local** URL and `supabase start` is running.
```
With:
```
- **Database:** PostgreSQL via Docker Compose. Alembic for migrations (`make db-migrate`). Never run `alembic upgrade head` against production without confirming `DATABASE_URL`.
```

- [ ] **Step 6: Update .cursor/rules/backend.mdc — remove Supabase integration reference**

In `backend.mdc`, replace:
```
Integration: **`tests/integration/`** with `integration` marker and Supabase env — see workflows and test docstrings, not the default `make` target.
```
With:
```
Integration: **`tests/integration/`** with `integration` marker — needs Docker Compose running and `DATABASE_URL` + `JWT_SECRET` env vars. See `make backend-integration-test`.
```

- [ ] **Step 7: Commit**

```bash
git add AGENTS.md .cursor/rules/monorepo.mdc .cursor/rules/backend.mdc
git commit -m "chore: remove all Supabase references from AGENTS.md and cursor rules"
```

---

## Task 2: Create CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Create `CLAUDE.md` at repo root**

```markdown
# CLAUDE.md — Workspace rules for Claude Code

This file is read by Claude Code at session start. For Cursor/Copilot, see `AGENTS.md`.

## Stack

| Layer | Technology |
|---|---|
| iOS | SwiftUI + Tuist (`ios/StarterApp/`) |
| Backend | FastAPI + Python 3.12 (`backend/`) |
| Database | PostgreSQL 17 (Docker Compose) |
| Auth | FastAPI-native (bcrypt + HS256 JWT) |
| ORM | SQLAlchemy 2 (async) + Alembic |
| API contracts | Pydantic schemas → `make sync-models` → `GeneratedModels.swift` |
| Deployment | Docker Compose (Raspberry Pi target via GitHub Actions) |

## Bootstrap (first time)

```bash
make bootstrap   # copies .env files, generates JWT_SECRET, installs tools + deps
make dev         # starts Postgres + backend + Adminer + iOS Simulator
```

Or step by step:
```bash
cp .env.example .env && cp backend/.env.example backend/.env
# Set JWT_SECRET in .env: openssl rand -hex 32
mise install && cd backend && uv sync && cd ..
make dev
```

## Verification

**Always run before claiming work is done:**

```bash
make validate       # lint → check-models → backend-test → ios-test → ios-build
make validate-full  # validate + docker + integration tests + smoke test
```

Useful targets: `make help` for the full list.

## Key conventions

- **Makefile is the entry point** for all operations. Prefer `make <target>` over raw commands.
- **iOS project is Tuist-generated.** Edit `Project.swift`, `Tuist/Package.swift`, `.xcconfig` — never `*.pbxproj`.
- **API models:** After changing Pydantic schemas in `backend/app/schemas/`, run `make sync-models`. CI enforces sync via `make check-models`.
- **Two .env files:** Root `.env` (Docker Compose vars), `backend/.env` (app config for `uv run` local dev). Both have `.example` templates.
- **Tests:** Backend uses pytest (`make backend-test`). iOS uses Swift Testing (`make ios-test`). Integration tests need Docker (`make backend-integration-test`).

## Migration safety

- **Never** run `alembic upgrade head` without confirming `DATABASE_URL` points to the correct database.
- **Review** autogenerated migrations for destructive operations (`DROP TABLE`, `DROP COLUMN`) before applying.
- **Local dev DB** is `localhost:5432` via Docker Compose. Production DB on Raspberry Pi is accessed only via GitHub Actions deploy workflow.
- Prefer `make db-migrate` (runs inside Docker container) over bare `alembic` commands.

## Deployment (Raspberry Pi)

Target: Raspberry Pi running Docker (linux/arm64). Deployment is via GitHub Actions — not from the local machine.

- Build multi-arch images: `docker buildx build --platform linux/arm64`
- Pi details are configured in GitHub Actions secrets (not in repo)
- **Never** push directly to the Pi from a local terminal session

## Skills

Detailed playbooks: `.agents/skills/<name>/SKILL.md`. Read the relevant skill before implementing when a task matches.

## Files to never edit manually

- `ios/StarterApp/StarterApp/Models/GeneratedModels.swift` — use `make sync-models`
- `*.pbxproj` — use Tuist (`make ios-gen`)
- `backend/uv.lock` — use `uv add/remove` then `uv sync`
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md workspace rules for Claude Code"
```

---

## Task 3: Move auth schemas to discoverable package

**Files:**
- Create: `backend/app/schemas/auth.py`
- Modify: `backend/app/api/v1/auth.py`
- Modify: `backend/app/schemas/__init__.py`
- Modify: `scripts/sync_models.py`
- Modify: `ios/StarterApp/StarterApp/Services/AuthService.swift`

- [ ] **Step 1: Create `backend/app/schemas/auth.py`**

```python
from pydantic import BaseModel


class RegisterRequest(BaseModel):
    """POST /auth/register request body."""

    email: str
    password: str
    display_name: str | None = None


class LoginRequest(BaseModel):
    """POST /auth/token request body."""

    email: str
    password: str


class RefreshRequest(BaseModel):
    """POST /auth/refresh request body."""

    refresh_token: str


class TokenResponse(BaseModel):
    """Auth token pair returned by register, login, and refresh endpoints."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
```

- [ ] **Step 2: Update `backend/app/api/v1/auth.py` — import from schemas**

Replace the inline class definitions (lines 28-46) with an import. Remove:

```python
class RegisterRequest(BaseModel):
    email: str
    password: str
    display_name: str | None = None


class LoginRequest(BaseModel):
    email: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
```

Add this import near the top (after the existing `from pydantic import BaseModel` line — which can be removed since it's no longer used directly):

```python
from app.schemas.auth import LoginRequest, RefreshRequest, RegisterRequest, TokenResponse
```

Also remove the now-unused `from pydantic import BaseModel` import.

- [ ] **Step 3: Update `backend/app/schemas/__init__.py`**

```python
# Pydantic request/response models for API layers.

from app.schemas.auth import LoginRequest, RefreshRequest, RegisterRequest, TokenResponse
from app.schemas.notes import NoteIn, NoteOut, NoteUpdate
from app.schemas.profile import ProfileOut, ProfileUpdate
```

- [ ] **Step 4: Add request-only types to SKIP_SCHEMAS in `scripts/sync_models.py`**

The `RegisterRequest`, `LoginRequest`, and `RefreshRequest` schemas are request-only — they should not be generated as Swift structs because they are never decoded on the iOS side. `TokenResponse` SHOULD be generated.

In `sync_models.py`, update the `SKIP_SCHEMAS` set (around line 43):

```python
SKIP_SCHEMAS: set[str] = {
    "HTTPValidationError",
    "ValidationError",
    "RegisterRequest",
    "LoginRequest",
    "RefreshRequest",
}
```

- [ ] **Step 5: Run `make sync-models` and verify**

Run: `make sync-models`

Expected: `GeneratedModels.swift` now includes a `TokenResponse` struct with `accessToken`, `refreshToken`, `tokenType` and CodingKeys mapping `access_token`, `refresh_token`, `token_type`.

Run: `make check-models`

Expected: exit 0 (in sync).

- [ ] **Step 6: Fix iOS `AuthService.swift` — use `.iso8601` decoder and generated `TokenResponse`**

The `AuthService` currently has a private `TokenResponse` struct (lines 170-177) and uses a bare `JSONDecoder()` without `.iso8601` date strategy. Now that `TokenResponse` is generated in `GeneratedModels.swift`, we need to:

1. Remove the private `TokenResponse` struct
2. Use an ISO 8601 decoder

In `ios/StarterApp/StarterApp/Services/AuthService.swift`, remove lines 170-177:

```swift
private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
```

Then update the `post` helper method (around line 118). Replace:

```swift
    private func post<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.detail
            throw AuthError.server(http.statusCode, msg ?? "Unknown error")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
```

With:

```swift
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func post<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.detail
            throw AuthError.server(http.statusCode, msg ?? "Unknown error")
        }
        return try Self.decoder.decode(R.self, from: data)
    }
```

- [ ] **Step 7: Verify backend tests still pass**

Run: `make backend-test`

Expected: all PASS — the route behavior is unchanged, only the import location moved.

- [ ] **Step 8: Verify iOS builds**

Run: `make ios-build`

Expected: build succeeds. The generated `TokenResponse` struct from `GeneratedModels.swift` is now used instead of the private one.

- [ ] **Step 9: Commit**

```bash
git add backend/app/schemas/auth.py backend/app/schemas/__init__.py backend/app/api/v1/auth.py scripts/sync_models.py ios/StarterApp/StarterApp/Services/AuthService.swift ios/StarterApp/StarterApp/Models/GeneratedModels.swift
git commit -m "refactor: move auth schemas to discoverable package, fix iOS decoder for iso8601"
```

---

## Task 4: Add `make bootstrap` target

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add `bootstrap` target to Makefile**

Add after the `check-deps` target (before the Help section):

```makefile
# ── Bootstrap ────────────────────────────────────────────────────────────────

bootstrap: ## First-time setup: copy .env files, generate JWT_SECRET, install tools + deps
	@echo "\n── Bootstrapping project ──────────────────────────────────────"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		JWT=$$(openssl rand -hex 32); \
		sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/$$JWT/" .env; \
		echo "  ✓ Created .env with generated JWT_SECRET"; \
	else \
		echo "  · .env already exists — skipping"; \
	fi
	@if [ ! -f backend/.env ]; then \
		cp backend/.env.example backend/.env; \
		JWT=$$(grep '^JWT_SECRET=' .env | cut -d= -f2); \
		sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/$$JWT/" backend/.env; \
		echo "  ✓ Created backend/.env (JWT_SECRET synced from root)"; \
	else \
		echo "  · backend/.env already exists — skipping"; \
	fi
	@echo "\n── Installing tools (mise) ────────────────────────────────────"
	@if command -v mise >/dev/null 2>&1; then \
		mise install; \
	else \
		echo "  ⚠  mise not found — install from https://mise.jdx.dev then re-run"; \
	fi
	@echo "\n── Installing Python dependencies ─────────────────────────────"
	cd backend && uv sync
	@echo "\n── Checking all dependencies ──────────────────────────────────"
	@bash scripts/check-deps.sh
	@echo "\n✓  Bootstrap complete. Run 'make dev' to start the stack."
```

- [ ] **Step 2: Reorder `validate` — move check-models before lint**

Replace the current `validate` target:

```makefile
validate: ## Run all checks in sequence: model-sync → lint → backend tests → iOS tests → iOS build
	@echo "\n── 1/5  model-sync check ───────────────────────────────────────"
	@$(MAKE) check-models
	@echo "\n── 2/5  lint & type-check ──────────────────────────────────────"
	@$(MAKE) lint
	@echo "\n── 3/5  backend unit tests ─────────────────────────────────────"
	@$(MAKE) backend-test
	@echo "\n── 4/5  iOS unit tests ─────────────────────────────────────────"
	@$(MAKE) ios-test
	@echo "\n── 5/5  iOS build check ────────────────────────────────────────"
	@$(MAKE) ios-build
	@echo "\n✓  All checks passed — safe to push."
```

- [ ] **Step 3: Add `validate-full` and `smoke-test` targets**

Add after the `validate` target:

```makefile
validate-full: validate ## Full validation: validate + integration tests + smoke test
	@echo "\n── 6/7  backend integration tests ──────────────────────────────"
	@$(MAKE) backend-integration-test
	@echo "\n── 7/7  smoke test ─────────────────────────────────────────────"
	@bash scripts/smoke-test.sh
	@echo "\n✓  Full validation passed."

smoke-test: ## Run curl-based happy-path smoke test against running backend
	@bash scripts/smoke-test.sh
```

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add make bootstrap, validate-full, smoke-test targets; reorder validate"
```

---

## Task 5: Create smoke test and full-stack verification scripts

**Files:**
- Create: `scripts/smoke-test.sh`
- Create: `scripts/verify-full-stack.sh`

- [ ] **Step 1: Create `scripts/smoke-test.sh`**

```bash
#!/usr/bin/env bash
# scripts/smoke-test.sh — Curl-based happy-path verification against a running backend.
#
# Assumes backend is running at http://localhost:8000. Does NOT start Docker.
# Registers a test user, logs in, creates a note, reads profile, cleans up.
#
# Usage:
#   bash scripts/smoke-test.sh              # default: localhost:8000
#   BACKEND_URL=http://pi.local:8000 bash scripts/smoke-test.sh

set -euo pipefail

BASE="${BACKEND_URL:-http://localhost:8000}"
API="${BASE}/api/v1"
EMAIL="smoke-test-$(date +%s)@example.com"
PASSWORD="SmokeTest123!"
PASS=0
FAIL=0

fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  OK:   $1"; PASS=$((PASS + 1)); }

echo "==> Smoke test against ${BASE}"
echo ""

# ── Health check ──────────────────────────────────────────────────────────
echo "── Health ──"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/healthz" 2>/dev/null || echo "000")
if [[ "$STATUS" == "200" ]]; then pass "/healthz → 200"; else fail "/healthz → ${STATUS} (expected 200)"; fi

# ── Register ──────────────────────────────────────────────────────────────
echo "── Register ──"
REGISTER=$(curl -s -X POST "${API}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}")
ACCESS=$(echo "$REGISTER" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
REFRESH=$(echo "$REGISTER" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null || echo "")

if [[ -n "$ACCESS" && -n "$REFRESH" ]]; then
  pass "Register → got tokens"
else
  fail "Register → no tokens returned"
  echo "  Response: ${REGISTER}"
  echo ""
  echo "RESULT: ${PASS} passed, ${FAIL} failed (aborted early)"
  exit 1
fi

AUTH="Authorization: Bearer ${ACCESS}"

# ── Profile ───────────────────────────────────────────────────────────────
echo "── Profile ──"
PROFILE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${API}/me/profile" -H "${AUTH}")
if [[ "$PROFILE_STATUS" == "200" ]]; then pass "GET /me/profile → 200"; else fail "GET /me/profile → ${PROFILE_STATUS}"; fi

# ── Notes CRUD ────────────────────────────────────────────────────────────
echo "── Notes ──"
CREATE=$(curl -s -X POST "${API}/me/notes" \
  -H "${AUTH}" -H "Content-Type: application/json" \
  -d '{"title":"Smoke test note","body":"Created by smoke-test.sh"}')
NOTE_ID=$(echo "$CREATE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

if [[ -n "$NOTE_ID" ]]; then pass "POST /me/notes → created (${NOTE_ID})"; else fail "POST /me/notes → no id"; fi

LIST_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${API}/me/notes" -H "${AUTH}")
if [[ "$LIST_STATUS" == "200" ]]; then pass "GET /me/notes → 200"; else fail "GET /me/notes → ${LIST_STATUS}"; fi

if [[ -n "$NOTE_ID" ]]; then
  DEL_STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "${API}/me/notes/${NOTE_ID}" -H "${AUTH}")
  if [[ "$DEL_STATUS" == "204" ]]; then pass "DELETE /me/notes/${NOTE_ID} → 204"; else fail "DELETE → ${DEL_STATUS}"; fi
fi

# ── Refresh ───────────────────────────────────────────────────────────────
echo "── Refresh ──"
REFRESH_RESP=$(curl -s -X POST "${API}/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"${REFRESH}\"}")
NEW_ACCESS=$(echo "$REFRESH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
if [[ -n "$NEW_ACCESS" ]]; then pass "POST /auth/refresh → new token"; else fail "POST /auth/refresh → no token"; fi

# ── Logout ────────────────────────────────────────────────────────────────
echo "── Logout ──"
NEW_REFRESH=$(echo "$REFRESH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null || echo "")
if [[ -n "$NEW_REFRESH" ]]; then
  LOGOUT_STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${API}/auth/logout" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\":\"${NEW_REFRESH}\"}")
  if [[ "$LOGOUT_STATUS" == "204" ]]; then pass "POST /auth/logout → 204"; else fail "POST /auth/logout → ${LOGOUT_STATUS}"; fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "RESULT: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
```

Run: `chmod +x scripts/smoke-test.sh`

- [ ] **Step 2: Create `scripts/verify-full-stack.sh`**

```bash
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
```

Run: `chmod +x scripts/verify-full-stack.sh`

- [ ] **Step 3: Verify smoke test works against running stack**

Run:
```bash
docker compose up -d
sleep 5
docker compose exec backend uv run alembic upgrade head
bash scripts/smoke-test.sh
docker compose down
```

Expected: All checks pass (8+ OK lines, 0 FAIL).

- [ ] **Step 4: Commit**

```bash
git add scripts/smoke-test.sh scripts/verify-full-stack.sh
git commit -m "feat: add smoke-test.sh and verify-full-stack.sh for agent verification"
```

---

## Task 6: Upgrade ios-sim.sh with agent automation flags

**Files:**
- Modify: `scripts/ios-sim.sh`

- [ ] **Step 1: Add new flag parsing**

In the argument parsing block (lines 20-29), replace the entire `while` loop:

```bash
REGEN=false
LOGS=false
HEADLESS=false
CLEAN_STATE=false
SCREENSHOT=""
VERIFY_LAUNCH=0
TARGET_UDID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --regen)          REGEN=true;          shift ;;
    --logs)           LOGS=true;           shift ;;
    --headless)       HEADLESS=true;       shift ;;
    --clean-state)    CLEAN_STATE=true;    shift ;;
    --screenshot)     SCREENSHOT="$2";     shift 2 ;;
    --verify-launch)  VERIFY_LAUNCH="${2:-5}"; shift 2 ;;
    --udid)           TARGET_UDID="$2";    shift 2 ;;
    -h|--help)
      sed -n '/^# Usage/,/^$/p' "$0" | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1  (try --help)"; exit 1 ;;
  esac
done
```

- [ ] **Step 2: Add clean-state support (before boot)**

Insert after the simulator selection block (after line `echo "→ Simulator: ${SIM_NAME} (${TARGET_UDID})"`):

```bash
# ---------------------------------------------------------------------------
# Clean state — erase simulator to clear Keychain, caches, app data
# ---------------------------------------------------------------------------
if $CLEAN_STATE; then
  echo "→ Erasing simulator state…"
  xcrun simctl shutdown "$TARGET_UDID" 2>/dev/null || true
  xcrun simctl erase "$TARGET_UDID"
  echo "  Simulator erased."
fi
```

- [ ] **Step 3: Make simulator boot conditional on --headless**

Replace lines 142-144:
```bash
echo "→ Booting simulator…"
xcrun simctl boot "$TARGET_UDID" 2>/dev/null || true   # already-booted is fine
open -a Simulator --args -CurrentDeviceUDID "$TARGET_UDID"
```

With:
```bash
echo "→ Booting simulator…"
xcrun simctl boot "$TARGET_UDID" 2>/dev/null || true   # already-booted is fine
if ! $HEADLESS; then
  open -a Simulator --args -CurrentDeviceUDID "$TARGET_UDID"
fi
```

- [ ] **Step 4: Add screenshot capture after launch**

Insert after the launch block (after the `fi` that closes the `if $LOGS` block):

```bash
# ---------------------------------------------------------------------------
# Screenshot — capture simulator screen to file
# ---------------------------------------------------------------------------
if [[ -n "$SCREENSHOT" ]]; then
  sleep 2  # give app time to render
  echo "→ Capturing screenshot to ${SCREENSHOT}…"
  xcrun simctl io "$TARGET_UDID" screenshot "$SCREENSHOT"
  echo "  ✓ Screenshot saved."
fi
```

- [ ] **Step 5: Add launch verification**

Insert after the screenshot block:

```bash
# ---------------------------------------------------------------------------
# Verify launch — poll for app process, fail if it crashed
# ---------------------------------------------------------------------------
if [[ "$VERIFY_LAUNCH" -gt 0 ]]; then
  echo "→ Verifying app stayed alive for ${VERIFY_LAUNCH}s…"
  sleep "$VERIFY_LAUNCH"
  if xcrun simctl spawn "$TARGET_UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "  ✓ App is running."
  else
    echo "  ✗ App is NOT running — may have crashed on launch."
    echo "  Recent crash logs:"
    find ~/Library/Logs/DiagnosticReports -name "StarterApp*" -newer "$APP_PATH" 2>/dev/null | head -3
    exit 1
  fi
fi
```

- [ ] **Step 6: Update the script header comment**

Replace lines 2-8:
```bash
# scripts/ios-sim.sh — Build StarterApp and launch it on an iOS Simulator.
#
# Usage:
#   ./scripts/ios-sim.sh                  # auto-picks newest iPhone sim
#   ./scripts/ios-sim.sh --regen          # tuist install + generate first
#   ./scripts/ios-sim.sh --udid <UDID>    # target a specific simulator
#   ./scripts/ios-sim.sh --logs           # stream console after launch
#   ./scripts/ios-sim.sh --regen --logs   # combine flags
```

With:
```bash
# scripts/ios-sim.sh — Build StarterApp and launch it on an iOS Simulator.
#
# Usage:
#   ./scripts/ios-sim.sh                        # auto-picks newest iPhone sim
#   ./scripts/ios-sim.sh --regen                # tuist install + generate first
#   ./scripts/ios-sim.sh --udid <UDID>          # target a specific simulator
#   ./scripts/ios-sim.sh --logs                 # stream console after launch
#   ./scripts/ios-sim.sh --headless             # no Simulator.app GUI (agent mode)
#   ./scripts/ios-sim.sh --clean-state          # erase sim before run (clears Keychain)
#   ./scripts/ios-sim.sh --screenshot out.png   # capture screenshot after launch
#   ./scripts/ios-sim.sh --verify-launch 5      # fail if app crashes within 5s
#   ./scripts/ios-sim.sh --headless --clean-state --verify-launch 5  # full agent mode
```

- [ ] **Step 7: Test the new flags**

Run:
```bash
./scripts/ios-sim.sh --headless --verify-launch 5 --screenshot /tmp/smoke-screenshot.png
```

Expected: Build succeeds, simulator boots without GUI, app launches, stays alive for 5s, screenshot saved to `/tmp/smoke-screenshot.png`.

- [ ] **Step 8: Commit**

```bash
git add scripts/ios-sim.sh
git commit -m "feat: add --headless, --clean-state, --screenshot, --verify-launch to ios-sim.sh"
```

---

## Task 7: Add MCP configuration for Claude Code and Cursor

**Files:**
- Create: `.claude/settings.json`
- Modify: `.cursor/mcp.json.example`

- [ ] **Step 1: Create `.claude/settings.json` with MCP servers**

```bash
mkdir -p .claude
```

```json
{
  "permissions": {
    "allow": [],
    "deny": []
  },
  "mcpServers": {
    "postgres-local": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic-ai/mcp-server-postgres",
        "postgresql://postgres:postgres@localhost:5432/postgres"
      ]
    },
    "fetch": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic-ai/mcp-server-fetch"
      ]
    }
  }
}
```

- [ ] **Step 2: Update `.cursor/mcp.json.example`**

Replace the entire file:

```json
{
  "mcpServers": {
    "postgres-local": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic-ai/mcp-server-postgres",
        "postgresql://postgres:postgres@localhost:5432/postgres"
      ]
    },
    "fetch": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic-ai/mcp-server-fetch"
      ]
    }
  }
}
```

- [ ] **Step 3: Create `.cursor/mcp.json` from example (gitignored)**

```bash
cp .cursor/mcp.json.example .cursor/mcp.json
```

Verify `.cursor/mcp.json` is in `.gitignore` (it already should be).

- [ ] **Step 4: Verify MCP servers start**

For Claude Code, restart the session. The MCP servers should appear in the tool list.

For Cursor, go to Settings → Tools & MCP and verify `postgres-local` and `fetch` are listed.

- [ ] **Step 5: Commit**

```bash
git add .claude/settings.json .cursor/mcp.json.example
git commit -m "feat: add Postgres and fetch MCP servers for Claude Code and Cursor"
```

---

## Task 8: Delete placeholder schema file

**Files:**
- Delete: `backend/app/schemas/placeholder.py`

- [ ] **Step 1: Delete the placeholder file**

The `placeholder.py` file says "DELETE THIS FILE once you have created your first real schema module." We now have `auth.py`, `notes.py`, and `profile.py`.

```bash
rm backend/app/schemas/placeholder.py
```

- [ ] **Step 2: Verify no imports break**

Run: `make backend-test`

Expected: all PASS. Nothing imports `placeholder.py`.

- [ ] **Step 3: Verify sync-models still works**

Run: `make check-models`

Expected: exit 0. The placeholder file had no BaseModel subclasses so removing it changes nothing.

- [ ] **Step 4: Commit**

```bash
git rm backend/app/schemas/placeholder.py
git commit -m "chore: delete placeholder schema file (real schemas exist now)"
```

---

## Verification Checklist

After all tasks are complete, run from repo root:

- [ ] `make bootstrap` — succeeds on a fresh checkout (copies .env, generates secret, installs deps)
- [ ] `make validate` — all 5 steps pass (check-models now runs first)
- [ ] `make smoke-test` — all checks pass against running backend
- [ ] `make validate-full` — full stack passes including integration + smoke
- [ ] `bash scripts/verify-full-stack.sh` — starts Docker, runs everything, tears down cleanly
- [ ] `./scripts/ios-sim.sh --headless --verify-launch 5` — builds and verifies app without GUI
- [ ] `grep -ri supabase AGENTS.md .cursor/rules/` — returns zero matches
- [ ] `cat CLAUDE.md` — exists with correct stack table, bootstrap, migration safety rules
- [ ] `make sync-models && make check-models` — TokenResponse appears in GeneratedModels.swift
- [ ] `.claude/settings.json` — has postgres-local and fetch MCP servers
- [ ] `.cursor/mcp.json.example` — has postgres-local and fetch MCP servers (no Supabase)
