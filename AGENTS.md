# Agent guide — iOS-FastAPI-Self-Hosted

Use this file for repository context. **User instructions in chat and Cursor rules override this document** when they conflict.

**Cursor rules** (`.cursor/rules/`): **`monorepo.mdc`** applies everywhere. **`backend.mdc`** and **`ios.mdc`** attach when you work under **`backend/**/*.py`** or **`ios/**/*.swift`** — short reminders for Makefile targets and testing; this file stays the **source of truth** for full conventions.

## What this repo is

- **iOS app:** SwiftUI, Tuist-generated workspace under `ios/StarterApp/` (`StarterApp.xcworkspace`, scheme `StarterApp`).
- **Backend:** FastAPI in `backend/` (Python, `uv`, pytest).
- **Database / auth:** Self-hosted FastAPI auth (bcrypt + HS256 JWT) + PostgreSQL 17 via Docker Compose. Alembic manages migrations.
- **API contracts:** Pydantic schemas in the backend; Swift models generated into `ios/StarterApp/StarterApp/Models/GeneratedModels.swift` (see `make sync-models` / `make check-models`).

## Skills (project)

Detailed playbooks live under **`.agents/skills/<name>/SKILL.md`**. When a task clearly matches a skill’s description, **read that `SKILL.md` first** (and any `references/` it points to) before implementing.

- **Process / workflow:** `using-superpowers`, `brainstorming`, `writing-plans`, `executing-plans`, `subagent-driven-development`, `dispatching-parallel-agents`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `receiving-code-review`, `requesting-code-review`, `finishing-a-development-branch`.
- **Tuist:** `generated-projects`, `debug-generated-project`.
- **Data / API:** Postgres best practices — use SQLAlchemy async queries, Alembic for migrations. No Supabase.
- **Analytics:** `posthog-integration-swift` (PostHog on iOS/macOS), `posthog-feature-flags-ios` (PostHog feature flags on iOS). This app uses **Tuist** — treat upstream `pbxproj` / raw SPM steps in those skills as patterns only; wire packages and settings in `ios/StarterApp/Project.swift` and `Tuist/Package.swift`.
- **Subscriptions:** `revenuecat` (in-app purchases / subscriptions).
- **Anthropic / agents / MCP:** `claude-api` (API/SDK patterns from Python and other runtimes), `doc-coauthoring` (structured co-written docs), `mcp-builder` (author MCP servers), `skill-creator` (package and evaluate skills — overlaps conceptually with Superpowers `writing-skills`; pick one workflow when authoring).
- **iOS / Swift:** Other folders under `.agents/skills/` (SwiftUI, StoreKit, networking, concurrency, etc.) — open the one that matches the feature or framework in scope.

Do not invent new top-level conventions that contradict existing patterns in this codebase.

## TDD and testing

### Test-driven development

- Use **`.agents/skills/test-driven-development/SKILL.md`** when implementing features or bugfixes: prefer a **failing test first**, then minimal production code, then refactor (unless the user explicitly opts out).
- Pair with **`.agents/skills/verification-before-completion/SKILL.md`**: do not claim tests pass without running the commands below in this repo.
- If chat instructions conflict with strict TDD, follow the user (**`.agents/skills/using-superpowers/SKILL.md`** instruction priority).

### Backend (`backend/`)

| | |
|--|--|
| **Run (CI parity)** | From repo root: **`make backend-test`** — `uv sync --frozen`, then `pytest` on `tests/` with `-m "not integration"`, coverage on `app`, then `coverage report`. Env: `ENVIRONMENT=ci`, `LOG_JSON=false`, `RATE_LIMIT_ENABLED=false`. Matches `.github/workflows/backend-ci.yml`. |
| **Layout** | **`tests/conftest.py`** — shared **`client`** fixture (`TestClient` as context manager so lifespan teardown runs). **`tests/api/`** — HTTP/route tests (`test_*_routes.py`, `test_health.py`). **`tests/unit/`** — services/config; **`tests/unit/conftest.py`** autouse `isolate_settings_env`. **`tests/integration/`** — real database (Docker Compose); **`pytestmark = pytest.mark.integration`**. Config: **`pyproject.toml`** `[tool.pytest.ini_options]` (marker `integration`, `asyncio_mode = "auto"`). |
| **Conventions** | Files **`test_*.py`**. API tests: **`fastapi.testclient.TestClient`**; prefer shared **`client`** fixture. Integration needs Docker Compose running (`make dev` or `docker compose up -d db`) and `DATABASE_URL` + `JWT_SECRET` env vars. Run separately: `make backend-integration-test` — see `.github/workflows/backend-integration.yml`. |

### iOS (`ios/StarterApp/`)

| | |
|--|--|
| **Run** | Repo root: **`make ios-test`** (alias for **`ios-test-real`**) — `build-for-testing` + `test-without-building` via **`scripts/ios-unit-test.sh`**, scheme **`StarterApp`**, **`-only-testing:StarterAppTests`**, Simulator via **`SIM_ID`** from **`scripts/session-sim.sh`** (override: `make ios-test-real SIM_ID=<udid>`). UI tests: **`make ios-test-ui`** (**`StarterAppUITests`**). **`make validate`** runs **`ios-test-real`** then **`ios-build`**; it does **not** run UI tests. |
| **Layout** | Tuist (**`Project.swift`**): **`StarterAppTests`** (`.unitTests`, `StarterAppTests/**/*.swift`), **`StarterAppUITests`** (`.uiTests`, `StarterAppUITests/**/*.swift`). |
| **Conventions** | **Unit:** **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import StarterApp`; use `@MainActor` on suites when app types require it. **UI:** **XCTest** (`XCUIApplication`, template-style tests). Scheme **`testAction`** currently lists only **`StarterAppTests`**; if **`make ios-test-ui`** misbehaves from CLI, add **`StarterAppUITests`** to the scheme’s Test action in **`Project.swift`**. |

## Verification (run from repo root)

Prefer **`make validate`** before claiming work is ready to merge (lint, model sync check, backend tests, iOS unit tests, iOS build). On **Cursor Cloud / Linux**, use **`make cloud-validate`** instead (no iOS).

Useful targets:

- `make help` — list all Makefile targets with descriptions.
- `make backend-test` — backend unit tests (CI-like).
- `make backend-lint` — backend Ruff/mypy only (safe on Linux / Cursor Cloud).
- `make cloud-validate` — models + backend lint/tests (no iOS). Default gate for Cursor Cloud agents.
- `make ios-build` — build the app for Simulator, no tests. The fast inner-loop gate.
- `make ios-test` / `make ios-test-real` — iOS unit tests (`StarterAppTests`).
- `make worktree-init` / `make worktree-clean` — seed a fresh git worktree; reclaim DerivedData + session sim.
- `make e2e-test` — local E2E UI test against running dev stack (`make dev` first). Not in CI or `validate`.
- `make lint` — backend Ruff/mypy + SwiftLint.

See `Makefile` for UI tests, Tuist generation, and local dev scripts.

## Cursor Cloud specific instructions

Cloud agents run on **Linux VMs** (see `.cursor/environment.json` + `.cursor/Dockerfile`). They are a
**backend + API-contract workstation**, not a Mac. iOS compile/sim/device stay on macOS CI or a
developer Mac.

### Environment layout

| Piece | How it gets there |
|---|---|
| Docker + Compose, `gh`, mise, Python 3.12, uv | `.cursor/Dockerfile` |
| Seeded `.env` / `backend/.env`, `uv sync --frozen` | `scripts/cloud-agent-install.sh` |
| Docker daemon + `postgres:17-alpine` on `:5432` | `scripts/cloud-agent-start.sh` |

### What to run

1. Default proof: **`make cloud-validate`** (`check-models` → `backend-lint` → `backend-test`).
2. With DB (start script should already have brought Postgres up): `make backend-integration-test`.
   Full API stack if needed: `docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d` then `make smoke-test`.
3. After Pydantic schema edits: **`make sync-models`** (Python; works in cloud). Leave Xcode compile to **iOS CI**.
4. Inspect iOS CI on the PR with **`gh`** — do not claim a green iOS build from Linux.

### Do not run on Cloud

- `make ios-build`, `make ios-test`, `make ios-device`, `make validate` (includes iOS), `make e2e-test`
- Tuist generate / Simulator / physical device / ngrok
- `alembic upgrade` against anything other than the local Compose Postgres

### iOS / SwiftUI work from Cloud

You may edit Swift and `Project.swift`. You **cannot** screenshot or compile.
For UI verification, open a PR and watch **iOS CI**, or hand off to a Mac agent.
Never invent “sim verified” without a Mac.

## iOS Simulator (agent mode)

Agents build, launch, screenshot, and tap the app from the terminal via **`scripts/ios-sim.sh`**, **`idb`**, or the **`ios-simulator` MCP** server. This section captures **roadblocks agents hit repeatedly** — read it before your first sim command in a session.

**NEVER pick the simulator with `simctl list devices booted`.** Several simulators may be booted at
once — one per worktree — and the "first booted" one is usually *not* the one the script installed
your build to.

`scripts/ios-sim.sh` prints `→ SIM_UDID=<udid>` and writes the same value to **`.sim-udid`** at the
repo root. That file is the only source of truth for which device holds your build:

```bash
UDID=$(cat .sim-udid)
idb ui describe-all --udid "$UDID"
xcrun simctl io "$UDID" screenshot /tmp/screen.png
```

Orchestrating a plan or worktree? Use `--session-sim` / `make` defaults (`SIM_ID` from
`scripts/session-sim.sh`); every agent shares one bundle id, so installing onto a sim another
agent is using **replaces their app with your build**.

### Quick reference

- **Boot first:** Run `./scripts/ios-sim.sh --headless` (with `--udid <UDID>` if another session owns the default sim) — `idb` commands **fail silently** against a shutdown device.
- **Launch headless:** `./scripts/ios-sim.sh --headless --clean-state --verify-launch 5 --screenshot /tmp/screen.png`
- **Read screen:** `idb ui describe-all --udid <UDID>`
- **Tap / type / swipe:** always pass `--udid <UDID>` when more than one sim is booted.
- **Screenshot:** then **Read the image** — don't infer pass from exit code alone.
- **MCP tools:** same boot/UDID rules as `idb`.

### Standard recipe

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T backend uv run alembic upgrade head
curl -sf http://127.0.0.1:8000/healthz

UDID=$(bash scripts/session-sim.sh)
./scripts/ios-sim.sh --udid "$UDID" --headless --verify-launch 5 --screenshot /tmp/screen.png
# Then Read /tmp/screen.png — do not claim UI pass without viewing it.
```

Simulator talks to **`http://127.0.0.1:8000`** (no tunnel). `scripts/dev.sh` writes `BACKEND_URL` into gitignored `ios/StarterApp/Config-Debug.xcconfig`.

### Roadblocks

| Symptom | Likely cause | Fix |
|--------|----------------|-----|
| `idb` tap/type does nothing, no error | Simulator **not booted**, or wrong **UDID** | Run `ios-sim.sh` first; pass `--udid` / use `.sim-udid` |
| API OK but UI empty / 404 on query paths | **Decode or URL bug** | Fractional ISO8601 → `APIDateCoding`; query strings must not use `URL.appending(path:)` |
| Routes missing, healthz OK | **Stale Docker image** | `docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d` |
| `make dev` then stack disappears | **`dev.sh` traps EXIT** and runs compose down | Keep `make dev` alive, or use detached compose recipe above |
| App swapped mid-run / wrong UI | **Another agent installed same bundle id** onto your sim | Use **session sim** (`scripts/session-sim.sh` / `--session-sim`) |
| `--verify-launch` flakes | **`launchctl` flaky** on newer iOS | Script prefers `pgrep`; check DiagnosticReports if still failing |
| `Error 65` / missing `.xctest` | Shared DerivedData after plain `ios-build` | Use `make ios-build-for-testing` / `ios-test-real` |

### Multi-agent / parallel sessions

Before your first build in a worktree: rely on `SIM_ID` from `session-sim.sh` (Makefile default).
When done: `make worktree-clean` to delete DerivedData + the session simulator.

### ngrok + Cursor agents

**Never start ngrok from an agent shell** — agent teardown kills the tunnel and breaks device
testing mid-session. Start ngrok from a **human Terminal** window; agents may inject an existing
URL via `BACKEND_URL` / `ios-device.sh --no-tunnel` patterns.

## iOS physical device (`make ios-device`)

`scripts/ios-device.sh` builds, signs, installs, and launches on a **paired iPhone** in one step:
ngrok tunnel → inject `BACKEND_URL` → `xcodebuild -destination generic/platform=iOS` →
`xcrun devicectl device install app` → `... process launch`.

- **Command:** `make ios-device` (or `./scripts/ios-device.sh --verify-launch 5 --console`).
- **Signing:** automatic. Team ID is auto-detected from the `Apple Development` keychain cert;
  override with `--team`/`IOS_DEVELOPMENT_TEAM`. **Do not commit a real team ID** — keep it in the
  gitignored `Config-Debug.xcconfig` or let the script detect it. Bundle id must be unique to the
  team (set `PRODUCT_BUNDLE_IDENTIFIER` in `Config-Debug.xcconfig`; the `com.example.*` placeholder
  won't register).
- **Tunnel:** ngrok, not `cloudflared` (some ISP resolvers NXDOMAIN `*.trycloudflare.com`). Needs an
  authtoken; use `--domain` for a stable reserved URL.
- **Entitlements:** dev builds use `StarterApp.dev.entitlements` (Sign In with Apple kept, Apple Pay
  dropped); `--full-entitlements` uses the real one for parity with Release.
- **Logs over Wi-Fi:** `--console` launches attached via `devicectl process launch --console` and
  streams stdout. DEBUG builds call `AppLog.startConsoleMirror()` so `[category] message` lines
  appear in the terminal without USB. Blocks until the app exits (Ctrl-C to stop).
- **Full syslog (USB):** `--logs` uses `idevicesyslog` and needs a cable; over Wi-Fi it is
  flaky/unavailable. Detached launch (`--verify-launch`) is also more reliable over USB.
- **Flags:** `--no-tunnel`, `--device-id`, `--regen`, `--stop-tunnel`, `--console`, `--logs`.

## Docs layout — product docs vs. agent planning

The **`docs/`** tree is for the **published site** (e.g. GitHub Pages waitlist) and any
**product + reference** docs you choose to keep there. It is **not** where agent planning goes.

**Agent planning goes in `.agents/superpowers/`.** See
**[`.agents/superpowers/README.md`](.agents/superpowers/README.md)** for layout and conventions.

- Implementation plans (writing-plans): `plans/YYYY-MM-DD-<feature-name>.md`
- Design / spec documents (brainstorming): `plans/YYYY-MM-DD-<topic>-design.md`
- Legacy specs: **`.agents/superpowers/specs/`** (write new designs in `plans/`)
- Completed / superseded plans + specs: **`.agents/archive/plans/`** and **`.agents/archive/specs/`**

Do not add unrelated markdown unless the user asks.

`CLAUDE.md` is a stub that points here — keep conventions in this file only.

## Cursor CLI as a sub-agent

When dispatching `cursor-agent` (or similar) as a background worker from this repo:

- Prefer **`--yolo`** (or the non-interactive equivalent) so it can run tools without blocking on approvals you will not see.
- **Always background** the process; never busy-wait a long agent run in the foreground.
- Do **not** arbitrarily cap the run with a short timeout — wait for completion or a clear failure.
- The brief must include a **verification contract** (which `make` targets / tests prove done).

## Git / completion

When closing out a branch, follow **`.agents/skills/finishing-a-development-branch/SKILL.md`** — it is tailored to this repo’s **`make validate`** / **`make cloud-validate`** (and related Makefile targets).
