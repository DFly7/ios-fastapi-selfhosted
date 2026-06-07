# Agent guide — iOS-FastAPI-Supabase-AI

Use this file for repository context. **User instructions in chat and Cursor rules override this document** when they conflict.

**Cursor rules** (`.cursor/rules/`): **`monorepo.mdc`** applies everywhere. **`backend.mdc`** and **`ios.mdc`** attach when you work under **`backend/**/*.py`** or **`ios/**/*.swift`** — short reminders for Makefile targets and testing; this file stays the **source of truth** for full conventions.

## What this repo is

- **iOS app:** SwiftUI, Tuist-generated workspace under `ios/StarterApp/` (`StarterApp.xcworkspace`, scheme `StarterApp`).
- **Backend:** FastAPI in `backend/` (Python, `uv`, pytest).
- **Database / auth:** Supabase — migrations and config in `supabase/`.
- **API contracts:** Pydantic schemas in the backend; Swift models generated into `ios/StarterApp/StarterApp/Models/GeneratedModels.swift` (see `make sync-models` / `make check-models`).

## Skills (project)

Detailed playbooks live under **`.agents/skills/<name>/SKILL.md`**. When a task clearly matches a skill’s description, **read that `SKILL.md` first** (and any `references/` it points to) before implementing.

- **Process / workflow:** `using-superpowers`, `brainstorming`, `writing-plans`, `executing-plans`, `subagent-driven-development`, `dispatching-parallel-agents`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `receiving-code-review`, `requesting-code-review`, `finishing-a-development-branch`.
- **Tuist:** `generated-projects`, `debug-generated-project`.
- **Data / API:** `supabase-postgres-best-practices` (Postgres, RLS, performance).
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
| **Layout** | **`tests/conftest.py`** — shared **`client`** fixture (`TestClient` as context manager so lifespan teardown runs). **`tests/api/`** — HTTP/route tests (`test_*_routes.py`, `test_health.py`). **`tests/unit/`** — services/config; **`tests/unit/conftest.py`** autouse `isolate_settings_env`. **`tests/integration/`** — real Supabase; **`pytestmark = pytest.mark.integration`**. Config: **`pyproject.toml`** `[tool.pytest.ini_options]` (marker `integration`, `asyncio_mode = "auto"`). |
| **Conventions** | Files **`test_*.py`**. API tests: **`fastapi.testclient.TestClient`**; prefer shared **`client`** fixture. Integration needs **`SUPABASE_URL`**, **`SUPABASE_PUBLIC_ANON_KEY`**, **`SUPABASE_SERVICE_ROLE_KEY`** (e.g. from `supabase status -o env`). Run separately: `uv run pytest tests/integration/ -v -m integration` — see `.github/workflows/backend-integration.yml` and `tests/integration/` docstrings. |

### iOS (`ios/StarterApp/`)

| | |
|--|--|
| **Run** | Repo root: **`make ios-test`** — `xcodebuild test` on **`StarterApp.xcworkspace`**, scheme **`StarterApp`**, **`-only-testing:StarterAppTests`**, Simulator via **`SIM_ID`** (override: `make ios-test SIM_ID=<udid>`). Output piped through **`xcpretty`**. UI tests: **`make ios-test-ui`** ( **`StarterAppUITests`** ). **`make validate`** runs **`ios-test`** then **`ios-build`**; it does **not** run UI tests. |
| **Layout** | Tuist (**`Project.swift`**): **`StarterAppTests`** (`.unitTests`, `StarterAppTests/**/*.swift`), **`StarterAppUITests`** (`.uiTests`, `StarterAppUITests/**/*.swift`). |
| **Conventions** | **Unit:** **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import StarterApp`; use `@MainActor` on suites when app types require it. **UI:** **XCTest** (`XCUIApplication`, template-style tests). Scheme **`testAction`** currently lists only **`StarterAppTests`**; if **`make ios-test-ui`** misbehaves from CLI, add **`StarterAppUITests`** to the scheme’s Test action in **`Project.swift`**. |

## Supabase MCP (Cursor)

Wire the **Supabase MCP** to **this app’s** cloud project and/or the **local** stack so tool calls target the right database.

### Hosted (cloud project)

1. Open **Cursor Settings → Tools & MCP** and add or select a Supabase MCP server (official remote server).
2. Complete **authentication** when prompted (browser OAuth to Supabase). See [Supabase MCP](https://supabase.com/docs/guides/getting-started/mcp).
3. **Scope to this repo’s project** using `project_ref=<your-cloud-project-ref>` in the MCP URL (Dashboard → **Project Settings** → **General** → **Reference ID**). Prefer a **dev/staging** project, not production, per Supabase’s security guidance.
4. If you maintain MCP entries for **multiple** products, name this one distinctly (e.g. `supabase-cloud-starter`) so agents use the correct project when working in **this** repository — not another dashboard project.

Optional query flags (same docs): `read_only=true`, `features=database,docs`, etc.

### Local (`supabase start`)

With the Supabase CLI dev stack running, the **same** MCP protocol is served at **`http://127.0.0.1:54321/mcp`** (API port from `supabase/config.toml`). Use a **second** MCP server entry (e.g. `supabase-local`) pointing at that URL when you want agents to run tools against **local** Postgres/API. If that server is disconnected or `supabase` is stopped, tools will fail — fall back to the CLI: `supabase status`, `supabase db reset`, migrations under `supabase/migrations/`, `psql` on port **54322**, etc.

**Verify which environment is active** before destructive SQL: hosted MCP ≠ local unless the **local** MCP URL is selected and `supabase start` is up.

### Repo template

Copy **`.cursor/mcp.json.example`** → **`.cursor/mcp.json`**, replace `YOUR_CLOUD_PROJECT_REF`, and adjust server names. **`.cursor/mcp.json`** is gitignored so tokens or personal URLs are not committed. You can instead configure MCP only in the Cursor UI — the example is for a reproducible team baseline.

Local CLI label **`project_id`** in `supabase/config.toml` (`ios-fastapi-supabase-starter`) is **not** the cloud `project_ref`; it only identifies the local stack.

## Verification (run from repo root)

Prefer **`make validate`** before claiming work is ready to merge (lint, model sync check, backend tests, iOS unit tests, iOS build).

Useful targets:

- `make help` — list all Makefile targets with descriptions.
- `make backend-test` — backend unit tests (CI-like).
- `make ios-test` — iOS unit tests (`StarterAppTests`).
- `make lint` — backend Ruff/mypy + SwiftLint.

See `Makefile` for UI tests, Tuist generation, and local dev scripts.

## Agent-only docs (not GitHub Pages)

The **`docs/`** tree is for the **published site** (e.g. GitHub Pages). Do not put internal design specs or implementation plans there.

**Canonical path:** **`.agents/superpowers/plans/`** (scaffolded in-repo). Put all agent planning artifacts there:

- Implementation plans (writing-plans): `YYYY-MM-DD-<feature-name>.md`
- Design / spec documents (brainstorming): `YYYY-MM-DD-<topic>-design.md`

Do not add unrelated markdown unless the user asks. See **`.agents/superpowers/README.md`** for a quick reference.

## Git / completion

When closing out a branch, follow **`.agents/skills/finishing-a-development-branch/SKILL.md`** — it is tailored to this repo’s **`make validate`** (and related Makefile targets).
