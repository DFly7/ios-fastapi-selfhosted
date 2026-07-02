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
| **Run** | Repo root: **`make ios-test`** — `xcodebuild test` on **`StarterApp.xcworkspace`**, scheme **`StarterApp`**, **`-only-testing:StarterAppTests`**, Simulator via **`SIM_ID`** (override: `make ios-test SIM_ID=<udid>`). Output piped through **`xcpretty`**. UI tests: **`make ios-test-ui`** ( **`StarterAppUITests`** ). **`make validate`** runs **`ios-test`** then **`ios-build`**; it does **not** run UI tests. |
| **Layout** | Tuist (**`Project.swift`**): **`StarterAppTests`** (`.unitTests`, `StarterAppTests/**/*.swift`), **`StarterAppUITests`** (`.uiTests`, `StarterAppUITests/**/*.swift`). |
| **Conventions** | **Unit:** **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import StarterApp`; use `@MainActor` on suites when app types require it. **UI:** **XCTest** (`XCUIApplication`, template-style tests). Scheme **`testAction`** currently lists only **`StarterAppTests`**; if **`make ios-test-ui`** misbehaves from CLI, add **`StarterAppUITests`** to the scheme’s Test action in **`Project.swift`**. |

## Verification (run from repo root)

Prefer **`make validate`** before claiming work is ready to merge (lint, model sync check, backend tests, iOS unit tests, iOS build).

Useful targets:

- `make help` — list all Makefile targets with descriptions.
- `make backend-test` — backend unit tests (CI-like).
- `make ios-test` — iOS unit tests (`StarterAppTests`).
- `make lint` — backend Ruff/mypy + SwiftLint.

See `Makefile` for UI tests, Tuist generation, and local dev scripts.

## iOS Simulator (agent mode)

The agent can build, launch, screenshot, read, and interact with the iOS app from the terminal using `idb` (Facebook iOS Development Bridge) or the `ios-simulator` MCP server.

- **Launch headless:** `./scripts/ios-sim.sh --headless --clean-state --verify-launch 5 --screenshot /tmp/screen.png`
- **Read screen (accessibility tree):** `idb ui describe-all --udid <UDID>` — returns JSON with every label, button, frame
- **Tap / type / swipe:** `idb ui tap <x> <y>`, `idb ui text "string"`, `idb ui swipe <x1> <y1> <x2> <y2>`
- **Screenshot:** `idb screenshot /tmp/screen.png` — then view the image to verify visually
- **MCP tools:** The `ios-simulator` MCP server (`.cursor/mcp.json`, `.claude/settings.json`) exposes `ui_describe_all`, `ui_tap`, `ui_type`, `screenshot` as native tool calls

## iOS physical device (`make ios-device`)

`scripts/ios-device.sh` builds, signs, installs, and launches on a **paired iPhone** in one step:
ngrok tunnel → inject `BACKEND_URL` → `xcodebuild -destination generic/platform=iOS` →
`xcrun devicectl device install app` → `... process launch`.

- **Command:** `make ios-device` (or `./scripts/ios-device.sh --verify-launch 5 --logs`).
- **Signing:** automatic. Team ID is auto-detected from the `Apple Development` keychain cert;
  override with `--team`/`IOS_DEVELOPMENT_TEAM`. **Do not commit a real team ID** — keep it in the
  gitignored `Config-Debug.xcconfig` or let the script detect it. Bundle id must be unique to the
  team (set `PRODUCT_BUNDLE_IDENTIFIER` in `Config-Debug.xcconfig`; the `com.example.*` placeholder
  won't register).
- **Tunnel:** ngrok, not `cloudflared` (some ISP resolvers NXDOMAIN `*.trycloudflare.com`). Needs an
  authtoken; use `--domain` for a stable reserved URL.
- **Entitlements:** dev builds use `StarterApp.dev.entitlements` (Sign In with Apple kept, Apple Pay
  dropped); `--full-entitlements` uses the real one for parity with Release.
- **USB recommended:** over Wi-Fi, `devicectl` *launch* and `idevicesyslog` (`--logs`) are flaky;
  build/install still work. Flags: `--no-tunnel`, `--device-id`, `--regen`, `--stop-tunnel`.

## Agent-only docs (not GitHub Pages)

The **`docs/`** tree is for the **published site** (e.g. GitHub Pages). Do not put internal design specs or implementation plans there.

**Canonical path:** **`.agents/superpowers/plans/`** (scaffolded in-repo). Put all agent planning artifacts there:

- Implementation plans (writing-plans): `YYYY-MM-DD-<feature-name>.md`
- Design / spec documents (brainstorming): `YYYY-MM-DD-<topic>-design.md`

Do not add unrelated markdown unless the user asks. See **`.agents/superpowers/README.md`** for a quick reference.

## Git / completion

When closing out a branch, follow **`.agents/skills/finishing-a-development-branch/SKILL.md`** — it is tailored to this repo’s **`make validate`** (and related Makefile targets).
