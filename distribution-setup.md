# Distribution Setup Guide

Everything you need to do **outside the IDE** before running `make setup-dist` and pushing your first TestFlight build. Follow these steps in order — each section produces values you will need later.

---

## Overview of what you're collecting

| # | Where | What you get |
|---|---|---|
| 1 | Apple Developer Portal | Team ID |
| 2 | App Store Connect | API Key ID, Issuer ID, `.p8` file |
| 3 | GitHub | Private certs repo URL, Personal Access Token |
| 4 | Supabase | Production project URL + Anon Key |
| 5 | Backend hosting | Public HTTPS base URL of your deployed FastAPI (`PRODUCTION_BACKEND_URL`) |
| 6 | PostHog *(optional)* | API Key |

At the end you will have all GitHub Actions secrets listed in [Step 6](#step-6--add-github-secrets) and be ready to run `make setup-dist`.

---

## Step 1 — Apple Developer Team ID

**Where:** [developer.apple.com](https://developer.apple.com) → Account → Membership Details

1. Sign in with your Apple ID.
2. Under **Membership Details**, find **Team ID** — a 10-character alphanumeric string (e.g. `ABC1234567`).

> If you belong to multiple teams, make sure you are looking at the team that will own the app.

**Save this value:**
```
DEVELOPMENT_TEAM = ABC1234567
```

---

## Step 2 — App Store Connect API Key

This key lets CI bypass 2FA when uploading builds to TestFlight. You create it once and it never expires (unless you revoke it).

**Where:** [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users and Access → Integrations → App Store Connect API

### 2a. Generate the key

1. Click the **+** button to generate a new key.
2. **Name:** something like `CI Distribution`.
3. **Access:** select **App Manager** (minimum required for TestFlight uploads).
4. Click **Generate**.

### 2b. Download the `.p8` file

> **You can only download the `.p8` file once.** If you close the page without downloading it, you must revoke the key and create a new one.

1. Click **Download API Key**.
2. Save the file somewhere permanent on your Mac (e.g. `~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8`).
3. Note the filename — it contains the Key ID: `AuthKey_KEYID.p8`.

### 2c. Note the Key ID and Issuer ID

On the same page:

| Value | Where to find it |
|---|---|
| **Key ID** | Listed next to the key name, also in the `.p8` filename |
| **Issuer ID** | Shown at the top of the API Keys page, above the key list |

**Save these values:**
```
APP_STORE_CONNECT_API_KEY_ID    = XXXXXXXXXX
APP_STORE_CONNECT_API_ISSUER_ID = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
APP_STORE_CONNECT_API_KEY_CONTENT = <full contents of the .p8 file — see note below>
```

> **APP_STORE_CONNECT_API_KEY_CONTENT** is the raw text content of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` header and footer lines. You can get it by running:
> ```sh
> cat ~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
> ```

---

## Step 3 — Private Certificates Repository

Fastlane Match stores your signing certificates and provisioning profiles in a private Git repository. Only you (and CI) ever access it.

### 3a. Create the repo on GitHub

1. Go to [github.com/new](https://github.com/new).
2. **Repository name:** something like `yourapp-certs` or `ios-certs`.
3. Set visibility to **Private**.
4. **Do not** add a README, `.gitignore`, or licence — leave it completely empty.
5. Click **Create repository**.
6. Copy the HTTPS URL (e.g. `https://github.com/yourorg/yourapp-certs`).

**Save this value:**
```
MATCH_GIT_URL = https://github.com/yourorg/yourapp-certs
```

### 3b. Create a GitHub Personal Access Token (PAT)

CI needs read access to the certs repo to pull certificates at build time.

**Where:** [github.com/settings/tokens](https://github.com/settings/tokens) → Personal access tokens → Tokens (classic)

1. Click **Generate new token (classic)**.
2. **Note:** `CI Match Access` (or similar).
3. **Expiration:** set to your preference (1 year is practical).
4. **Scopes:** tick **repo** (full control of private repositories).
5. Click **Generate token**.
6. Copy the token immediately — you cannot see it again.

### 3c. Compute GIT_BASIC_AUTH

CI authenticates to the certs repo using a base64-encoded `username:token` string.

Run this in your terminal, replacing with your actual GitHub username and the PAT you just created:

```sh
echo -n "your_github_username:ghp_yourPersonalAccessToken" | base64
```

Copy the output — it will look like `eW91cl9naXRodWJfdXNlcm5hbWU6Z2hwX3h4eA==`.

**Save this value:**
```
GIT_BASIC_AUTH = eW91cl9naXRodWJfdXNlcm5hbWU6Z2hwX3h4eA==
```

### 3d. Choose a Match encryption password

Fastlane Match encrypts everything it stores in the certs repo. Choose a strong password now — you will need to enter it during `make setup-dist` and also add it as a GitHub Secret.

> Store this password somewhere safe (password manager). If you lose it, you must run `fastlane match nuke` and start over.

**Save this value:**
```
MATCH_PASSWORD = <your chosen encryption password>
```

---

## Step 4 — Supabase Production Project

### 4a. Get your project URL

**Where:** [supabase.com/dashboard](https://supabase.com/dashboard) → your project → Settings → API

Under **Project URL**, copy the URL (e.g. `https://abcdefghijkl.supabase.co`).

**Save this value:**
```
SUPABASE_URL = https://abcdefghijkl.supabase.co
```

### 4b. Get your Anon Key

On the same Settings → API page, under **Project API keys**, copy the **anon public** key.

> This key is safe to ship in the app binary — it is intentionally public. Row-Level Security policies on your tables control what unauthenticated requests can access.

**Save this value:**
```
SUPABASE_ANON_KEY = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 4c. Production FastAPI base URL (`BACKEND_URL` / `PRODUCTION_BACKEND_URL`)

TestFlight and release builds read the backend URL from `Config-Release.xcconfig` as `BACKEND_URL`. That value must be the **public HTTPS origin** of your deployed FastAPI — the same host your App Store users can reach (for example Load Balancer, Railway, Fly.io, or API Gateway URL).

Use the API root only (no path unless your app is configured for it), for example:

- `https://api.yourcompany.com`

> **CI:** The **Distribute to TestFlight** workflow (`.github/workflows/distribute.yml`) does **not** ship a placeholder. It requires the GitHub Actions secret `PRODUCTION_BACKEND_URL` and writes it into the generated `Config-Release.xcconfig` as `BACKEND_URL`.

**Save this value (secret name must match exactly for CI):**
```
PRODUCTION_BACKEND_URL = https://api.yourcompany.com
```

---

## Step 5 — PostHog *(optional)*

Skip this step if you don't want analytics. Leave `POSTHOG_API_KEY` blank in GitHub Secrets and PostHog will be disabled automatically.

**Where:** [us.posthog.com](https://us.posthog.com) (or [eu.posthog.com](https://eu.posthog.com)) → your project → Settings → Project → Project API key

Copy the **Project API key** (starts with `phc_`).

**Save this value:**
```
POSTHOG_API_KEY = phc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Step 6 — Add GitHub Secrets

**Where:** your GitHub repo → Settings → Secrets and variables → Actions → New repository secret

Add each of the following secrets. The name must match exactly (case-sensitive).

| Secret name | Where you got it | Example / format |
|---|---|---|
| `DEVELOPMENT_TEAM` | Step 1 | `ABC1234567` |
| `APP_BUNDLE_ID` | You choose | `com.yourcompany.yourapp` |
| `APP_NAME` | You choose | `My App` |
| `APPLE_ID` | Your Apple ID email | `you@example.com` |
| `SUPABASE_URL` | Step 4a | `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | Step 4b | `eyJhbGci...` |
| `PRODUCTION_BACKEND_URL` | Step 4c | `https://api.yourcompany.com` |
| `POSTHOG_API_KEY` | Step 5 *(leave blank to disable)* | `phc_xxxx` |
| `MATCH_GIT_URL` | Step 3a | `https://github.com/yourorg/yourapp-certs` |
| `MATCH_PASSWORD` | Step 3d | your chosen password |
| `GIT_BASIC_AUTH` | Step 3c | base64 string |
| `APP_STORE_CONNECT_API_KEY_ID` | Step 2c | `XXXXXXXXXX` |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Step 2c | UUID |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Step 2b | full `.p8` file contents |

> **Tip:** To add `APP_STORE_CONNECT_API_KEY_CONTENT`, open the `.p8` file in a text editor, select all, and paste the entire contents including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.

---

## Step 7 — Run the local setup wizard

With all the above values in hand, run from the repo root:

```sh
make setup-dist
```

The wizard will:
1. Check your `Project.swift` has no uncommitted changes
2. Validate your `.p8` key file is readable
3. Smoke-test your credentials against App Store Connect
4. Write `Config-Release.xcconfig` and update `fastlane/Appfile` + `fastlane/Matchfile`
5. Create the App Store Connect app record via `fastlane produce`
6. Seed your certs repo via `fastlane match appstore` — **this must complete successfully before you push a tag**
7. Print every repository secret (including `PRODUCTION_BACKEND_URL`) so you can copy-paste them into GitHub

---

## Step 8 — Ship your first build

```sh
git add -A && git commit -m "chore: configure distribution"
git tag v0.1.0 && git push && git push --tags
```

GitHub Actions → **Distribute to TestFlight** workflow runs automatically. The build appears in TestFlight within ~15 minutes of the workflow completing.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `PRODUCTION_BACKEND_URL Actions secret is empty or missing` | Secret not set or typo in name | Add `PRODUCTION_BACKEND_URL` under **Settings → Secrets** (see Step 4c); re-run the workflow |
| `tuist generate` fails in CI | `Config-Debug.xcconfig` or `Config-Release.xcconfig` missing | Check the "Write xcconfig" steps ran before `tuist generate` in the workflow log |
| `match` fails in CI with "repo is empty" | `make setup-dist` was not run locally first | Run `make setup-dist` locally to seed the certs repo, then re-push the tag |
| `upload_to_testflight` fails with "app not found" | App Store Connect record doesn't exist | Run `make create-app` locally |
| Build stuck in "Missing Compliance" on TestFlight | `ITSAppUsesNonExemptEncryption` key missing | Already set to `false` in `Project.swift` — verify your `tuist generate` ran with the latest `Project.swift` |
| `match` fails with "certificate has been revoked" | Someone revoked the cert outside of match | Run `fastlane match appstore --force` locally to regenerate |
| CI fails with "No profiles for bundle ID" | Bundle ID in secret doesn't match the registered App ID | Verify `APP_BUNDLE_ID` secret matches exactly what was registered in the Developer Portal |
