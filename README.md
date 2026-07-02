

# iOS · FastAPI · Self-Hosted Starter

**Production-ready template for shipping authenticated iOS apps with a FastAPI backend and self-hosted PostgreSQL — without the weeks of boilerplate.**

[Backend CI](https://github.com/DFly7/iOS-FastAPI-Supabase-AI/actions/workflows/backend-ci.yml)
[Integration Tests](https://github.com/DFly7/iOS-FastAPI-Supabase-AI/actions/workflows/backend-integration.yml)
[iOS CI](https://github.com/DFly7/iOS-FastAPI-Supabase-AI/actions/workflows/ios-ci.yml)

Python
FastAPI
Swift
PostgreSQL
Docker
License



---

## What this gives you

Spinning up an authenticated iOS app with a custom backend and a real database typically takes days of glue work. This template collapses it to `**make dev`** from the repo root.


| Layer           | Technology                    | What's wired up                                                                                                                                              |
| --------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **iOS**         | SwiftUI + URLSession + Keychain | Auth (sign up / sign in / sign out), JWT forwarded to backend, `BackendAPIService`, Tuist project generation                                                 |
| **Backend**     | FastAPI + uv + Docker         | JWT verification via HS256, per-user profile endpoint, rate limiting, structured JSON logging, Sentry, Prometheus metrics, Resend email                    |
| **Database**    | PostgreSQL 17                 | `profiles` table, alembic migrations, seed SQL, no RLS required (app logic handles access)                                                                  |
| **Local infra** | Docker Compose                | Full local stack (Postgres + backend + Adminer), backend on port 8000, migrations via Alembic, optional HTTPS tunnels for physical device testing          |
| **CI/CD**       | GitHub Actions                | Backend unit tests, Docker image push to GHCR, integration tests against live local Postgres, iOS build + test on macOS, automated migrations              |


---

## Architecture

```
iPhone (or Simulator)
        │ BACKEND_URL (tunnel or localhost)
        ▼
┌─ Optional tunnel (cloudflared / ngrok) ─┐
│  HTTPS → localhost:8000 (FastAPI)      │
└─────────────────────────────────────────┘
        │
        ▼
┌─── Mac (localhost) ────────────────────────────┐
│                                                │
│  Docker Compose:                               │
│  ├─ PostgreSQL 17 (:5432)                     │
│  ├─ FastAPI (:8000)  /api/v1/*               │
│  │  └─ reads/writes via SQLAlchemy (async)   │
│  └─ Adminer (browser DB admin) (:8080)       │
│                                                │
│  Auth flow: bcrypt + HS256 JWT                │
│  (no external service required)               │
└────────────────────────────────────────────────┘
```

---

## What's already built

### SwiftUI iOS App

- **Auth flow** — Sign up, sign in, sign out via `/auth/register` and `/auth/token` endpoints; session persisted in Keychain
- **Authenticated API calls** — `BackendAPIService` attaches the JWT (from Keychain) to every request
- **Config via xcconfig** — `BACKEND_URL` injected at build time; no secrets in source
- **Tuist** — `Project.swift` defines the target, dependencies (PostHog), URL scheme, and entitlements; generated `.xcodeproj` / `.xcworkspace` are gitignored — run `make ios-gen` and open `StarterApp.xcworkspace` in Xcode
- **Deep link support** — `com.example.starter://` URL scheme available for future integrations

### FastAPI Backend

- **HS256 JWT verification** — validates self-issued tokens with a shared secret from `.env`; HTTP client reused across requests
- **Auth middleware** — `AuthContextMiddleware` extracts `user_id` and attaches it to every request's context
- **Request ID middleware** — every request gets a unique `X-Request-ID` for tracing
- **Structured logging** — `structlog` with JSON output in production, human-readable in dev; log level auto-set per environment
- **Rate limiting** — `slowapi` with configurable default rate; exempt `GET /healthz`
- **Prometheus metrics** — opt-in `/metrics` endpoint for scraping
- **Sentry** — opt-in error tracking with Starlette + FastAPI integrations
- **Resend email** — helper service ready to send transactional email
- **CORS** — correctly handles `allow_credentials` with explicit origins
- **Environment-aware config** — single `Settings` class via `pydantic-settings`; sensible defaults, all overridable via env vars
- `**GET /healthz`** — unauthenticated health check
- `**POST /api/v1/auth/register**` — create a new user account
- `**POST /api/v1/auth/token**` — exchange email + password for a JWT token
- `**GET /api/v1/me/profile**` — returns the authenticated user's profile from Postgres

### PostgreSQL & Migrations

- **`profiles` table** — auto-created via Alembic migration for every user (app logic triggers on signup)
- **Alembic versioning** — all schema changes tracked in `backend/alembic/versions/`; migrations run on `make dev`
- **Seed file** — `backend/seed_db.sql` runs on Postgres startup (set via `docker-compose.yml`)
- **Adminer browser UI** — full database admin at `http://localhost:8080` (login: server=db, user=postgres, pass=postgres)

### Testing

- **Unit tests** — pytest with async support; services and auth helpers tested in isolation
- **Integration tests** — spin up a real local Postgres instance via Docker Compose; test the full auth → backend → DB round trip
- **iOS tests** — Swift Testing unit tests + XCUITest UI tests scaffolded and running in CI

### CI / CD (GitHub Actions)

- `backend-ci.yml` — lint, test, build Docker image, push to GHCR on `main`
- `backend-integration.yml` — run Docker Compose with Postgres, run integration tests against it
- `ios-ci.yml` — `tuist generate`, `xcodebuild test` on macOS-15 (Xcode 16.4 pinned; matches bundled simulators)
- `distribute.yml` — signed Release archive → TestFlight, triggered on `v*` tags (see [Path to TestFlight](#path-to-testflight))

---

## Quick Start

### Prerequisites
- Docker + Docker Compose
- Xcode 16+
- [mise](https://mise.jdx.dev/)

### Local dev

```bash
cp .env.example .env
# Set JWT_SECRET in .env: openssl rand -hex 32

make dev          # starts Postgres + backend + Adminer
make db-migrate   # runs Alembic migrations

# API:     http://localhost:8000/api/v1/
# Adminer: http://localhost:8080 (server=db, user=postgres, pass=postgres)
```

Register your first user:
```bash
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"yourpassword"}'
```

In iOS: set `BACKEND_URL = http://localhost:8000` in `Config-Debug.xcconfig`.

---

## Getting started

> Full step-by-step instructions, tunnel options (cloudflared / ngrok), and environment variable reference are in **[local-setup.md](local-setup.md)**.

### 0. Rename the project (first-time template users only)

Before anything else, replace every occurrence of `StarterApp`, `com.example.StarterApp`, and `Starter API` with your own app's names:

```sh
# Run from the repo root (or anywhere inside the repo — the script finds the root automatically)
./scripts/rename-project.sh
```

The script prompts for three values (all others are derived automatically):

| Prompt | Example | What it replaces |
|---|---|---|
| App name (PascalCase) | `TaskFlow` | `StarterApp` everywhere |
| Bundle ID | `com.acme.taskflow` | `com.example.StarterApp` |
| API name | `TaskFlow API` | `Starter API` |

Preview without changing anything:

```sh
./scripts/rename-project.sh --dry-run --app-name TaskFlow --bundle-id com.acme.taskflow
```

What it changes: file contents (all tracked text files via `git ls-files`), directory names (`ios/StarterApp/` → `ios/YourApp/`), and file names (`StarterAppApp.swift`, `StarterApp.entitlements`). It also removes stale Tuist-generated artifacts so the next `tuist generate` starts clean.

**Requirements:** working directory must be clean (`git status` shows nothing) so you can `git reset --hard` if needed.

Once you are happy with the result, remove the one-time script:

```sh
git rm scripts/rename-project.sh && git commit -m "chore: remove template rename script"
```

---

### 1. Install tools

```sh
# mise manages Python, uv, Tuist, and SwiftLint at pinned versions
curl https://mise.run | sh
mise install   # run from repo root
```

Also install **[Docker Desktop](https://www.docker.com/products/docker-desktop/)**.

### 2. Configure environment

```sh
# Backend
cp backend/.env.example backend/.env
# Fill in JWT_SECRET with: openssl rand -hex 32

# iOS
cp ios/StarterApp/Config.example.xcconfig ios/StarterApp/Config-Debug.xcconfig
cp ios/StarterApp/Config.example.xcconfig ios/StarterApp/Config-Release.xcconfig
# Edit both: set DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER, and BACKEND_URL
```

### 3. Start everything

```sh
make dev
```

This runs `**scripts/dev.sh**`: brings up PostgreSQL and FastAPI via Docker Compose, runs Alembic migrations, syncs `backend/.env` and iOS `Config-Debug.xcconfig` with local URLs, runs `tuist generate`, then builds and launches the app in the **iOS Simulator** (no tunnel required on the Simulator). **Ctrl+C stops everything cleanly.**

```
Services:
  FastAPI docs → http://127.0.0.1:8000/docs
  Adminer DB   → http://127.0.0.1:8080
```

For a **physical iPhone**, use `make ios-device` (one command: ngrok tunnel → inject `BACKEND_URL` → build → sign → install → launch). It auto-detects your signing team from the keychain; set a unique `PRODUCT_BUNDLE_IDENTIFIER` in your gitignored `Config-Debug.xcconfig` first, and run `ngrok config add-authtoken <token>` once. Stream DEBUG logs over Wi-Fi with `make ios-device ARGS="--console"`; use `--logs` for full USB syslog. Extra `make dev` flags: `ARGS="--regen"` (tuist install + generate), `ARGS="--no-ios"` (services only), `ARGS="--sim-logs"`.

### 4. Open the iOS project in Xcode (optional)

If you used `**make dev`** with the default flow, Tuist already ran and the Simulator may already have the app. To work in Xcode manually (or after `**make dev ARGS="--no-ios"**`):

```sh
make ios-gen
open ios/StarterApp/StarterApp.xcworkspace
```

Tuist writes `StarterApp.xcodeproj` and `StarterApp.xcworkspace` under `ios/StarterApp/`; both are generated and gitignored. **Open the `.xcworkspace`** (same as CI and `make ios-test`). Opening only an old or copied `.xcodeproj` can show stale targets and package resolution. If you change Swift package dependencies, run `cd ios/StarterApp && tuist install` before `make ios-gen` (see **Customising**).

Build and run on the Simulator (`make ios-run`) or a **physical device** (`make ios-device` — handles signing + tunnel automatically; see the [CLAUDE.md](CLAUDE.md) "iOS physical device" section).

---

## Repo layout

```
.
├── ios/StarterApp/          # SwiftUI app (Tuist)
├── backend/                 # FastAPI (uv + Docker)
│   ├── app/
│   │   ├── api/v1/          # Route handlers
│   │   ├── core/            # Config, auth (JWT), rate limiting
│   │   ├── middleware/      # Request ID, auth context, access log
│   │   ├── repositories/    # Data access layer (SQLAlchemy)
│   │   ├── schemas/         # Pydantic models
│   │   └── services/        # Business logic, email
│   ├── alembic/             # Database migrations
│   │   └── versions/        # Versioned SQL migrations
│   └── tests/               # Unit + integration tests
├── .github/workflows/       # CI/CD pipelines
├── .mise.toml               # Pinned tool versions (Python, uv, Tuist)
├── docker-compose.yml       # Postgres + FastAPI + Adminer
├── Makefile                 # make dev → scripts/dev.sh; make ios-gen, sync-models, etc.
├── scripts/
│   ├── dev.sh               # Full local stack: Docker + backend + Tuist + Simulator
│   ├── dev-logs.sh          # Same stack with tmux log panes (make dev-logs)
│   ├── ios-sim.sh           # Build / launch Simulator (used by dev.sh)
│   ├── tunnel.sh            # Optional HTTPS forwarding for physical devices
│   ├── sync_models.py       # Pydantic → Swift Codable (make sync-models / check-models)
│   ├── setup-dist.sh        # Distribution wizard (make setup-dist → TestFlight)
│   └── check-deps.sh        # Validate prerequisite tools
└── local-setup.md           # Full local dev runbook (tunnels, physical device, manual tabs)
```

---

## Tool versions

All versions are pinned in `.mise.toml` and kept in sync with CI:


| Tool    | Version |
| ------- | ------- |
| Python  | 3.12    |
| uv      | 0.11.2  |
| Tuist   | 4.44.3  |
| Docker  | 4.x+    |


---

## Local ports


| Service         | Port  | URL                     |
| --------------- | ----- | ----------------------- |
| PostgreSQL      | 5432  | `localhost:5432`        |
| FastAPI backend | 8000  | `http://127.0.0.1:8000` |
| Adminer (DB UI) | 8080  | `http://127.0.0.1:8080` |


---

## Email (Resend)

This template uses **Resend** for all outbound email sent from your FastAPI backend.

### Local dev

No email configuration needed for local development. Leave `RESEND_API_KEY` and `RESEND_FROM_EMAIL` empty in `.env` and emails will not be sent (useful for testing).

### Production: enable Resend

**One-time setup:**

1. Sign up at [resend.com](https://resend.com), add and verify your sending domain, and create an API key with Sending access.
2. Set `RESEND_API_KEY` and `RESEND_FROM_EMAIL` in your production backend `.env`.

### Sending email from FastAPI

`backend/app/services/resend_email.py` is already wired up. Set `RESEND_API_KEY` and `RESEND_FROM_EMAIL` in `backend/.env` and call the service from any route handler.

---

## Path to TestFlight

> `make setup-dist` handles all of the one-time setup. You do not need to manually click "New App" in the portal or manage certificates by hand.
>
> Full step-by-step guide for getting every key and secret: **[distribution-setup.md](distribution-setup.md)**

### Prerequisites (do these once in the browser)

1. **Create a private GitHub repo** for certificates — leave it completely empty (e.g. `github.com/yourorg/yourapp-certs`). Fastlane match will populate it.
2. **Download an App Store Connect API key** (`.p8`) from [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api). Note the Key ID and Issuer ID.

### One-time local setup

```sh
make setup-dist
```

The wizard will:

- Validate your `Project.swift` is clean, your `.p8` key is readable, and your credentials resolve (smoke test — fails fast before writing anything)
- Fill in `Config-Release.xcconfig` and `fastlane/Appfile` / `fastlane/Matchfile` with your values
- Run `fastlane produce` to create the App Store Connect record and register the App ID (idempotent — safe to re-run)
- Run `fastlane match appstore` to generate certificates and provisioning profiles and push them to your private certs repo
- Print the exact GitHub Secrets to add

> **Important:** `make setup-dist` must be run locally before the first tag push. CI pulls certs from the private repo — if the repo is empty, the build will fail.

### Add GitHub Secrets

After the wizard finishes, add the printed values to your repo:  
**GitHub → Settings → Secrets and variables → Actions**


| Secret                              | Description                                            |
| ----------------------------------- | ------------------------------------------------------ |
| `DEVELOPMENT_TEAM`                  | 10-character Apple Team ID                             |
| `APP_BUNDLE_ID`                     | e.g. `com.yourcompany.yourapp`                         |
| `APP_NAME`                          | Display name for App Store Connect                     |
| `APPLE_ID`                          | Your Apple ID email                                    |
| `PRODUCTION_BACKEND_URL`            | Public HTTPS base URL of deployed FastAPI (release)  |
| `POSTHOG_API_KEY`                   | PostHog key (leave empty to disable)                   |
| `MATCH_GIT_URL`                     | URL of your private certs repo                         |
| `MATCH_PASSWORD`                    | Encryption password set during `match init`            |
| `GIT_BASIC_AUTH`                    | `base64(github_username:PAT)` — PAT needs `repo` scope |
| `APP_STORE_CONNECT_API_KEY_ID`      | 10-character key ID from App Store Connect             |
| `APP_STORE_CONNECT_API_ISSUER_ID`   | UUID issuer ID from App Store Connect                  |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Full contents of your `.p8` key file                   |


### Ship a build

```sh
git tag v0.1.0 && git push --tags
```

This triggers the **Distribute to TestFlight** GitHub Action. The build appears in TestFlight within ~15 minutes of the workflow completing.

### Useful commands


| Command           | What it does                                    |
| ----------------- | ----------------------------------------------- |
| `make setup-dist` | Full one-time setup wizard                      |
| `make create-app` | Re-create App Store Connect record (idempotent) |
| `make beta`       | Build + upload to TestFlight locally            |
| `make release`    | Build + submit to App Store locally             |


---

## Customising

- **Rename the app** — use `./scripts/rename-project.sh` (see [Rename the project](#0-rename-the-project-first-time-template-users-only) above)
- **Add a migration** — create a file in `backend/alembic/versions/` following the timestamp naming convention (e.g. `20240101120000_add_new_table.py`); it runs automatically on `make dev` and in CI via `make db-migrate`
- **Add a backend route** — add a handler in `backend/app/api/v1/`, register it in `router.py`
- **Add a Swift dependency** — add it to `Tuist/Package.swift`, run `cd ios/StarterApp && tuist install`, then `make ios-gen` from the repo root
- **Configure Sentry / Resend** — uncomment the relevant lines in `backend/.env` and fill in your keys

---

## Waitlist page (optional)

The `docs/` folder contains a ready-to-ship GitHub Pages waitlist page. However, it requires a backend endpoint to capture signups. You can wire the page to your FastAPI backend or use a third-party service like Supabase, Firebase, or Airtable.

To enable GitHub Pages, go to **Settings → Pages → Source: Deploy from a branch → Branch: `main` / folder: `docs`**. Your page will be live at `https://<your-username>.github.io/<repo-name>/` within a minute.

---



Built to skip the setup. Start building features.

