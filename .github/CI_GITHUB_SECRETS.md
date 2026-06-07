# GitHub Actions — secrets for CI

Add secrets under **GitHub → your repository → Settings → Secrets and variables → Actions**.  
Use **repository secrets** unless you rely on [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment) (this repo uses an environment only for production migrations).

| Secret | Required | Used by |
|--------|----------|---------|
| `SUPABASE_ACCESS_TOKEN` | Yes, for hosted DB migrations | [supabase-migrations.yml](workflows/supabase-migrations.yml) |
| `SUPABASE_PROJECT_ID` | Yes, for hosted DB migrations | supabase-migrations |
| `SUPABASE_DB_PASSWORD` | Yes, for hosted DB migrations | supabase-migrations |
| `PRODUCTION_BACKEND_URL` | **Yes, for TestFlight distribution** | [distribute.yml](workflows/distribute.yml) — written as `BACKEND_URL` in `Config-Release.xcconfig`; the workflow hard-fails if absent |
| `SUPABASE_URL` | Yes, for TestFlight distribution | distribute.yml — written into `Config-Release.xcconfig` |
| `SUPABASE_ANON_KEY` | Yes, for TestFlight distribution | distribute.yml — written into `Config-Release.xcconfig` |
| `DEVELOPMENT_TEAM` | Yes, for TestFlight distribution | distribute.yml — Apple Developer Team ID |
| `APP_BUNDLE_ID` | Yes, for TestFlight distribution | distribute.yml — e.g. `com.example.StarterApp` |
| `APPLE_ID` | Yes, for TestFlight distribution | distribute.yml — Apple ID email for App Store Connect |
| `MATCH_GIT_URL` | Yes, for TestFlight distribution | distribute.yml — HTTPS URL of the Fastlane Match certs repo |
| `MATCH_PASSWORD` | Yes, for TestFlight distribution | distribute.yml — encryption passphrase for the Match repo |
| `GIT_BASIC_AUTH` | Yes, for TestFlight distribution | distribute.yml — `user:token` for cloning the Match repo |
| `APP_STORE_CONNECT_API_KEY_ID` | Yes, for TestFlight distribution | distribute.yml |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Yes, for TestFlight distribution | distribute.yml |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Yes, for TestFlight distribution | distribute.yml — base64-encoded `.p8` key content |
| `POSTHOG_API_KEY` | Optional | distribute.yml — PostHog is disabled when empty |

Secrets are **not** available to workflows triggered from forks on `pull_request`; keep default CI jobs passing without real credentials (as in `backend-ci.yml` today).

---

## Required: TestFlight distribution (`distribute.yml`)

Triggered by a version tag (`git tag v1.0.0 && git push --tags`) or `workflow_dispatch`. Run `make setup-dist` locally once before the first tag push — it prints all secret values for you.

| Secret | Description |
|--------|-------------|
| `PRODUCTION_BACKEND_URL` | HTTPS base URL of your deployed FastAPI backend (e.g. `https://api.example.com`). Written as `BACKEND_URL` in `Config-Release.xcconfig`. The workflow **hard-fails** if this is empty or missing. |
| `SUPABASE_URL` | Full Supabase project URL (`https://<ref>.supabase.co`). Written into `Config-Release.xcconfig`. |
| `SUPABASE_ANON_KEY` | Supabase `anon` public key. Written into `Config-Release.xcconfig`. |
| `DEVELOPMENT_TEAM` | Apple Developer Team ID (10-character string from developer.apple.com). |
| `APP_BUNDLE_ID` | App bundle identifier, e.g. `com.example.StarterApp`. |
| `APPLE_ID` | Apple ID email address associated with your App Store Connect account. |
| `MATCH_GIT_URL` | HTTPS URL of the private Git repo used by Fastlane Match to store certificates and profiles. |
| `MATCH_PASSWORD` | Encryption passphrase used by Fastlane Match to encrypt/decrypt the certs repo. |
| `GIT_BASIC_AUTH` | `username:personal_access_token` for authenticating clone of the Match repo. |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from App Store Connect → Users and Access → Integrations → App Store Connect API. |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from the same App Store Connect API page. |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Base64-encoded content of the `.p8` private key file (`base64 -i AuthKey_<id>.p8`). |
| `POSTHOG_API_KEY` | PostHog project API key. Optional — PostHog is **disabled** when this secret is empty or absent. |

---

## Required: Supabase migrations (`supabase-migrations.yml`)

Runs on pushes to `main` that touch `supabase/migrations/` (and on `workflow_dispatch`). The job uses GitHub Environment **`production`** — create that environment if it does not exist; you can add protection rules and required reviewers there.

| Secret | Description |
|--------|-------------|
| `SUPABASE_ACCESS_TOKEN` | Personal access token from [Supabase account tokens](https://supabase.com/dashboard/account/tokens). |
| `SUPABASE_PROJECT_ID` | Project ref (short id), e.g. from **Project Settings → General** in the Supabase dashboard — *not* the full `https://….supabase.co` URL. |
| `SUPABASE_DB_PASSWORD` | Database password for the linked Supabase project (used by `supabase link` / `supabase db push`). |

---

## Optional: backend unit tests against a hosted project (`backend-ci.yml`)

Default CI runs `pytest` with `-m "not integration"` and placeholder Supabase env vars in the workflow. To hit a real Supabase project from that job, uncomment the `env:` lines in the **Run tests** step and add:

| Secret | Maps to app env var |
|--------|---------------------|
| `SUPABASE_URL` | `SUPABASE_URL` |
| `SUPABASE_ANON_KEY` | `SUPABASE_PUBLIC_ANON_KEY` |

Naming matches the commented example in `backend-ci.yml` (`SUPABASE_ANON_KEY` is the secret name; the FastAPI app still reads `SUPABASE_PUBLIC_ANON_KEY`).

---

## No repository secrets needed

| Workflow | Notes |
|----------|--------|
| [backend-integration.yml](workflows/backend-integration.yml) | Uses `supabase start` locally and `supabase status -o env` — credentials are generated in the job. |
| [ios-ci.yml](workflows/ios-ci.yml) | Builds with `Config.example.xcconfig` copies; Simulator build does not require Supabase keys. |
| Docker push in `backend-ci.yml` | Uses `GITHUB_TOKEN` (automatically provided; **do not** create a secret named `GITHUB_TOKEN`). |

---

## Related: local / runtime env (not all are CI secrets)

See `backend/.env.example` for full app configuration (`ENVIRONMENT`, `RESEND_*`, `SENTRY_DSN`, etc.). Those are for local or deployed runtimes, not wired into the current GitHub Actions workflows unless you add new jobs.
