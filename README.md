

# iOS · FastAPI · Supabase Starter

**Production-ready template for shipping authenticated iOS apps with a FastAPI backend and Supabase — without the weeks of boilerplate.**

[Backend CI](https://github.com/DFly7/iOS-FastAPI-Supabase-AI/actions/workflows/backend-ci.yml)
[Integration Tests](https://github.com/DFly7/iOS-FastAPI-Supabase-AI/actions/workflows/backend-integration.yml)
[iOS CI](https://github.com/DFly7/iOS-FastAPI-Supabase-AI/actions/workflows/ios-ci.yml)
[Migrations](https://github.com/DFly7/iOS-FastAPI-Supabase-AI/actions/workflows/supabase-migrations.yml)

Python
FastAPI
Swift
Supabase
Docker
License



---

## What this gives you

Spinning up an authenticated iOS app with a custom backend and a real database typically takes days of glue work. This template collapses it to `**make dev`** from the repo root.


| Layer           | Technology                    | What's wired up                                                                                                                                              |
| --------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **iOS**         | SwiftUI + supabase-swift      | Auth (sign up / sign in / sign out), JWT forwarded to backend, `BackendAPIService`, Tuist project generation                                                 |
| **Backend**     | FastAPI + uv + Docker         | JWT verification via Supabase JWKS, per-user profile endpoint, rate limiting, structured JSON logging, Sentry, Prometheus metrics, Resend email              |
| **Database**    | Supabase (Postgres 17)        | `profiles` table, Row-Level Security policies, `handle_new_user` trigger, seed hooks                                                                         |
| **Local infra** | Supabase CLI + Docker Compose | Full Supabase stack locally (API · Studio · Auth · Storage · Realtime), backend on port 8000, HTTPS tunnels for physical device testing                      |
| **CI/CD**       | GitHub Actions                | Backend unit tests, Docker image push to GHCR, integration tests against live local Supabase, iOS build + test on macOS, automated production migration push |


---

## Architecture

```
iPhone (or Simulator)
        │ SUPABASE_URL (tunnel or localhost)
        │ BACKEND_URL  (tunnel or localhost)
        ▼
┌─ instatunnel / ngrok / cloudflared ─┐
│  HTTPS → localhost:54321 (Supabase) │
│  HTTPS → localhost:8000  (FastAPI)  │
└─────────────────────────────────────┘
        │
        ▼
┌─── Mac (localhost) ─────────────────────────┐
│                                             │
│  Supabase CLI   (:54321)                    │
│  ├─ Postgres 17  (:5432)                    │
│  ├─ PostgREST    (:54321/rest/v1)           │
│  ├─ GoTrue Auth  (:54321/auth/v1)           │
│  └─ Supabase Studio (:54323) ←── browser   │
│                                             │
│  FastAPI (Docker Compose)  (:8000)          │
│  └─ reaches Supabase via                   │
│     host.docker.internal:54321             │
│     (no tunnel required)                   │
└─────────────────────────────────────────────┘
```

---

## What's already built

### SwiftUI iOS App

- **Auth flow** — Sign up, sign in, sign out with supabase-swift; session persisted across launches
- **Authenticated API calls** — `BackendAPIService` attaches the Supabase JWT to every request
- **Config via xcconfig** — `SUPABASE_URL`, `BACKEND_URL`, and `SUPABASE_ANON_KEY` injected at build time; no secrets in source
- **Tuist** — `Project.swift` defines the target, dependencies (Supabase, PostHog), URL scheme, and entitlements; generated `.xcodeproj` / `.xcworkspace` are gitignored — run `make ios-gen` and open `StarterApp.xcworkspace` in Xcode
- **Deep link auth redirect** — `com.example.starter://` URL scheme wired to Supabase auth

### FastAPI Backend

- **JWKS JWT verification** — validates Supabase-issued tokens without a shared secret; HTTP client reused across requests
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
- `**GET /api/v1/ping**` — open ping
- `**GET /api/v1/secure-test**` — requires valid JWT
- `**GET /api/v1/me/profile**` — returns the authenticated user's profile from Postgres

### Supabase

- `**profiles` table** — auto-created for every new user via `handle_new_user` trigger on `auth.users`
- **Row-Level Security** — users can only read and update their own profile
- **Seed file** — `supabase/seed.sql` runs on every `supabase start` for local dev
- **Local Studio** — full Supabase dashboard at `http://127.0.0.1:54323`

### Testing

- **Unit tests** — pytest with async support; services and auth helpers tested in isolation
- **Integration tests** — spin up a real local Supabase instance via `supabase start`; test the full auth → backend → DB round trip
- **iOS tests** — Swift Testing unit tests + XCUITest UI tests scaffolded and running in CI

### CI / CD (GitHub Actions)

- `backend-ci.yml` — lint, test, build Docker image, push to GHCR on `main`
- `backend-integration.yml` — install Supabase CLI, `supabase start`, run integration tests against it
- `ios-ci.yml` — `tuist generate`, `xcodebuild test` on macOS-15 (Xcode 16.4 pinned; matches bundled simulators)
- `distribute.yml` — signed Release archive → TestFlight, triggered on `v*` tags (see [Path to TestFlight](#path-to-testflight))
- `supabase-migrations.yml` — push migrations to your hosted Supabase project when `supabase/migrations/`** changes on `main`

---

## Getting started

> Full step-by-step instructions, tunnel options (instatunnel / ngrok / Cloudflare), and environment variable reference are in **[local-setup.md](local-setup.md)**.

### 0. Rename the project (first-time template users only)

Before anything else, replace every occurrence of `StarterApp`, `com.example.StarterApp`, and `Starter API` with your own app's names:

```sh
# Run from the repo root (or anywhere inside the repo — the script finds the root automatically)
./scripts/rename-project.sh
```

The script prompts for four values (all others are derived automatically):

| Prompt | Example | What it replaces |
|---|---|---|
| App name (PascalCase) | `TaskFlow` | `StarterApp` everywhere |
| Bundle ID | `com.acme.taskflow` | `com.example.StarterApp` |
| API name | `TaskFlow API` | `Starter API` |
| Supabase local project ID | `task-flow` *(auto-derived)* | `ios-fastapi-supabase-starter` |

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
# mise manages Python, uv, Tuist, and the Supabase CLI at pinned versions
curl https://mise.run | sh
mise install   # run from repo root
```

Also install **[Docker Desktop](https://www.docker.com/products/docker-desktop/)**.

### 2. Configure environment

```sh
# Backend
cp backend/.env.example backend/.env
# Fill in SUPABASE_PUBLIC_ANON_KEY after step 3

# iOS
cp ios/StarterApp/Config.example.xcconfig ios/StarterApp/Config-Debug.xcconfig
cp ios/StarterApp/Config.example.xcconfig ios/StarterApp/Config-Release.xcconfig
# Edit both: set DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER, SUPABASE_ANON_KEY, URLs
```

### 3. Start everything

```sh
make dev
```

This runs `**scripts/dev.sh**`: starts Supabase, brings up FastAPI via Docker Compose, syncs `backend/.env` and iOS `Config-Debug.xcconfig` with local URLs and keys, runs `tuist generate`, then builds and launches the app in the **iOS Simulator** (no tunnel required on the Simulator). **Ctrl+C stops everything cleanly.**

```
Services:
  Supabase Studio → http://127.0.0.1:54323
  FastAPI docs    → http://127.0.0.1:8000/docs
```

For a physical device you still need HTTPS tunnel URLs in xcconfig; see **[local-setup.md](local-setup.md)**. Extra flags: `make dev ARGS="--regen"` (tuist install + generate), `ARGS="--no-ios"` (services only), `ARGS="--sim-logs"`.

### 4. Open the iOS project in Xcode (optional)

If you used `**make dev`** with the default flow, Tuist already ran and the Simulator may already have the app. To work in Xcode manually (or after `**make dev ARGS="--no-ios"**`):

```sh
make ios-gen
open ios/StarterApp/StarterApp.xcworkspace
```

Tuist writes `StarterApp.xcodeproj` and `StarterApp.xcworkspace` under `ios/StarterApp/`; both are generated and gitignored. **Open the `.xcworkspace`** (same as CI and `make ios-test`). Opening only an old or copied `.xcodeproj` can show stale targets and package resolution. If you change Swift package dependencies, run `cd ios/StarterApp && tuist install` before `make ios-gen` (see **Customising**).

Build and run on the Simulator or a physical device (device builds need valid signing and tunnel URLs — see **local-setup.md**).

---

## Repo layout

```
.
├── ios/StarterApp/          # SwiftUI app (Tuist)
├── backend/                 # FastAPI (uv + Docker)
│   ├── app/
│   │   ├── api/v1/          # Route handlers
│   │   ├── core/            # Config, auth (JWKS), rate limiting
│   │   ├── middleware/      # Request ID, auth context, access log
│   │   ├── repositories/    # Data access layer
│   │   ├── schemas/         # Pydantic models
│   │   └── services/        # Business logic, email
│   └── tests/               # Unit + integration tests
├── supabase/                # Supabase CLI project
│   └── migrations/          # SQL migrations (versioned)
├── .github/workflows/       # CI/CD pipelines
├── .mise.toml               # Pinned tool versions (Python, uv, Tuist, Supabase CLI)
├── Makefile                 # make dev → scripts/dev.sh; make ios-gen, sync-models, etc.
├── scripts/
│   ├── dev.sh               # Full local stack: Supabase + Docker backend + Tuist + Simulator
│   ├── dev-logs.sh          # Same stack with tmux log panes (make dev-logs)
│   ├── ios-sim.sh           # Build / launch Simulator (used by dev.sh)
│   ├── tunnel.sh            # Optional HTTPS forwarding for physical devices
│   ├── sync_models.py       # Pydantic → Swift Codable (make sync-models / check-models)
│   ├── setup-dist.sh        # Distribution wizard (make setup-dist → TestFlight)
│   └── _lib.sh              # Shared helpers for bash scripts
└── local-setup.md           # Full local dev runbook (tunnels, physical device, manual tabs)
```

---

## Tool versions

All versions are pinned in `.mise.toml` and kept in sync with CI:


| Tool         | Version |
| ------------ | ------- |
| Python       | 3.12    |
| uv           | 0.11.2  |
| Tuist        | 4.44.3  |
| Supabase CLI | 2.84.2  |


---

## Local ports


| Service          | Port  | URL                      |
| ---------------- | ----- | ------------------------ |
| Supabase API     | 54321 | `http://127.0.0.1:54321` |
| Supabase Studio  | 54323 | `http://127.0.0.1:54323` |
| Inbucket (email) | 54324 | `http://127.0.0.1:54324` |
| FastAPI backend  | 8000  | `http://127.0.0.1:8000`  |


---

## Email (Resend + Supabase Auth)

This template uses **Resend** for all outbound email. There are two separate email paths:

| Path | What sends it | Emails |
| --- | --- | --- |
| **Supabase auth** | Supabase's GoTrue service | Confirmation links, magic links, password resets |
| **App-level transactional** | FastAPI via Resend SDK | Anything you send from your own backend routes |

### Local dev

All Supabase auth emails are captured by **Inbucket** — nothing is sent to a real inbox. View them at:

```
http://127.0.0.1:54324
```

No configuration is needed; Inbucket runs automatically as part of `make dev`.

### Production: wire Supabase auth to Resend

Supabase's default email service is rate-limited to ~3 emails/hour. To remove that limit, configure Resend as a custom SMTP relay:

**One-time setup:**

1. Sign up at [resend.com](https://resend.com), add and verify your sending domain, and create an API key with Sending access.
2. In the [Supabase dashboard](https://supabase.com/dashboard) → your project → **Project Settings → Auth → SMTP Settings**, enable custom SMTP and enter:

| Field | Value |
| --- | --- |
| Sender name | Your app name |
| Sender email | `you@yourdomain.com` |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | Your Resend API key (`re_...`) |

This is a dashboard-only change — nothing to commit.

> The same `RESEND_API_KEY` in `backend/.env` is used both here (as the SMTP password) and by the FastAPI Resend SDK for app-level transactional email.

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
| `SUPABASE_URL`                      | Production Supabase project URL                        |
| `SUPABASE_ANON_KEY`                 | Production Supabase anon key                           |
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

- **Rename the app** — update `PRODUCT_BUNDLE_IDENTIFIER` in xcconfig, `CFBundleURLSchemes` in `Project.swift`, and `additional_redirect_urls` in `supabase/config.toml`
- **Add a migration** — create a file in `supabase/migrations/` following the timestamp naming convention; it runs automatically on `supabase start` and in CI
- **Add a backend route** — add a handler in `backend/app/api/v1/`, register it in `router.py`
- **Add a Swift dependency** — add it to `Tuist/Package.swift`, run `cd ios/StarterApp && tuist install`, then `make ios-gen` from the repo root
- **Configure Sentry / Resend** — uncomment the relevant lines in `backend/.env` and fill in your keys

---

## Waitlist page

The `docs/` folder contains a ready-to-ship GitHub Pages waitlist page. Send the URL to potential users before you launch — they drop their email (and optionally their phone number), and the signup lands straight in your Supabase `waitlist` table.

### Quick setup

**1. Configure the page** — edit the `CONFIG` block at the top of [`docs/index.html`](docs/index.html):

```js
const CONFIG = {
  APP_NAME:        "Your App",
  APP_TAGLINE:     "Something great is on its way.",
  APP_DESCRIPTION: "We're building something you'll love. ...",
  BRAND_COLOR:     "#6366f1",
  BRAND_COLOR_DARK:"#4f46e5",

  SUPABASE_URL:      "https://YOUR_PROJECT_REF.supabase.co",
  SUPABASE_ANON_KEY: "YOUR_ANON_KEY",   // ← see critical warning below

  PHONE_ENABLED:   true,
};
```

**2. Run the migration** — the `waitlist` table is created automatically when you run `supabase db push` (or `supabase start` locally):

```
supabase/migrations/20260403000000_create_waitlist.sql
```

**3. Enable GitHub Pages** — in your GitHub repo go to **Settings → Pages → Source: Deploy from a branch → Branch: `main` / folder: `docs`**. Your page will be live at `https://<your-username>.github.io/<repo-name>/` within a minute.

---

> [!CAUTION]
> **CRITICAL — Always use `SUPABASE_ANON_KEY`, never `SUPABASE_SERVICE_ROLE_KEY`.**
>
> The anon key is designed to be embedded in public client-side code. It is safe to commit and expose. Row Level Security (RLS) controls exactly what it can do — in this case, INSERT into `waitlist` only.
>
> The service role key **bypasses all RLS policies**. If you accidentally put it in `docs/index.html`, anyone who views your page source gains unrestricted read/write/delete access to your entire database.
>
> Your anon key is in the Supabase dashboard under **Project Settings → API → Project API keys → `anon` `public`**.

---

### How it's hardened

| Layer | Where | What it does |
| --- | --- | --- |
| **RLS policy** | Supabase | Anon role can `INSERT` only — no `SELECT`, `UPDATE`, or `DELETE` |
| **Rate-limit trigger** | Postgres | Max 5 sign-ups per IP per hour (adjust the constant in the migration) |
| **Honeypot field** | Browser | A hidden field bots fill in; JS silently drops the request without calling Supabase |

### Viewing signups

Query your waitlist from the Supabase dashboard or with the service role key (server-side only):

```sql
select email, phone, created_at from waitlist order by created_at desc;
```

---



Built to skip the setup. Start building features.

