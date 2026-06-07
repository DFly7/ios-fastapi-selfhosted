#!/usr/bin/env bash
# setup-dist.sh — One-time distribution setup wizard.
#
# Configures signing, creates the App Store Connect record, and seeds the
# certificates repo so CI can pull certs on the first tag push.
#
# Usage: make setup-dist   (or ./scripts/setup-dist.sh from repo root)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$REPO_ROOT/ios/StarterApp"
FASTLANE_DIR="$IOS_DIR/fastlane"

# ── Colours ──────────────────────────────────────────────────────────────────

BOLD=$(tput bold 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
RED=$(tput setaf 1 2>/dev/null || echo "")
CYAN=$(tput setaf 6 2>/dev/null || echo "")
LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

info()    { echo "${CYAN}  ▸ $*${RESET}"; }
success() { echo "${GREEN}  ✓ $*${RESET}"; }
warn()    { echo "${YELLOW}  ⚠ $*${RESET}"; }
die()     { echo "${RED}${BOLD}  ✗ $*${RESET}" >&2; exit 1; }
ask()     { echo -n "${BOLD}  $1 ${RESET}"; }

echo ""
echo "${BOLD}${LINE}${RESET}"
echo "${BOLD}  iOS StarterApp — Distribution Setup Wizard${RESET}"
echo "${BOLD}${LINE}${RESET}"
echo ""
echo "  This wizard will:"
echo "    1. Validate your environment (git status, .p8 key, credentials)"
echo "    2. Configure signing in Config-Release.xcconfig and Fastlane"
echo "    3. Create the App Store Connect record via fastlane produce"
echo "    4. Seed your private certs repo via fastlane match"
echo "    5. Print the GitHub Secrets to add before your first tag push"
echo ""

# ── Phase 1: Pre-flight checks ───────────────────────────────────────────────

echo "${BOLD}  Phase 1 — Pre-flight checks${RESET}"
echo ""

# 1a. Git status guard — uncommitted Project.swift changes could accidentally
#     ship without CODE_SIGNING_ALLOWED being removed.
info "Checking for uncommitted Project.swift changes..."
if ! git -C "$REPO_ROOT" diff --quiet HEAD -- ios/StarterApp/Project.swift 2>/dev/null; then
    die "ios/StarterApp/Project.swift has uncommitted changes. Commit or stash them first."
fi
success "Project.swift is clean"

# 1b. Verify Fastlane (Bundler) is available
info "Checking for Bundler + Fastlane..."
if ! command -v bundle &>/dev/null; then
    die "Bundler not found. Install it: gem install bundler"
fi
cd "$IOS_DIR"
if ! bundle check &>/dev/null; then
    info "Running bundle install..."
    bundle install --quiet || die "bundle install failed."
fi
success "Fastlane is available"

# 1c. Collect inputs before touching anything
echo ""
echo "${BOLD}  Phase 2 — Configuration${RESET}"
echo ""
echo "  Find your Team ID at: developer.apple.com → Account → Membership"
echo ""

ask "Apple Developer Team ID (10 characters, e.g. ABC1234567):"; read -r TEAM_ID
[[ ${#TEAM_ID} -eq 10 ]] || die "Team ID must be exactly 10 characters."

ask "App Bundle ID (e.g. com.yourcompany.yourapp):"; read -r BUNDLE_ID
[[ "$BUNDLE_ID" == *.*.* ]] || die "Bundle ID must be in reverse-DNS format (e.g. com.yourcompany.app)."

ask "App name as it will appear in App Store Connect:"; read -r APP_NAME

ask "Apple ID (email used for App Store Connect):"; read -r APPLE_ID_INPUT

echo ""
echo "  App Store Connect API key — create one at:"
echo "  appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API"
echo ""
ask "Path to your .p8 API key file:"; read -r P8_PATH
P8_PATH="${P8_PATH/#\~/$HOME}"
[[ -f "$P8_PATH" ]] || die ".p8 file not found at: $P8_PATH"
[[ -r "$P8_PATH" ]] || die ".p8 file is not readable: $P8_PATH"
success ".p8 file found"

ask "App Store Connect API Key ID (10 characters):"; read -r ASC_KEY_ID
ask "App Store Connect API Issuer ID (UUID):"; read -r ASC_ISSUER_ID

echo ""
echo "  Private certs repo — create an empty private GitHub repo"
echo "  (e.g. github.com/yourorg/yourapp-certs). Fastlane match will populate it."
echo ""
ask "Certs repo URL (e.g. https://github.com/yourorg/yourapp-certs):"; read -r MATCH_GIT_URL

ask "Match encryption password (choose a strong password — you'll add this as a GitHub Secret):"; read -rs MATCH_PASSWORD
echo ""

echo ""
echo "  GitHub Personal Access Token for the certs repo (needs repo scope)."
echo "  GIT_BASIC_AUTH = base64(username:PAT)"
echo "  Generate a PAT at: github.com/settings/tokens"
echo ""
ask "Your GitHub username:"; read -r GH_USER
ask "GitHub PAT (repo scope):"; read -rs GH_PAT
echo ""
GIT_BASIC_AUTH=$(echo -n "${GH_USER}:${GH_PAT}" | base64)

echo ""
echo "  Runtime secrets (these go into Config-Release.xcconfig and GitHub Secrets):"
echo ""
ask "Production Supabase URL (e.g. https://yourproject.supabase.co):"; read -r SUPABASE_URL
ask "Production Supabase Anon Key:"; read -r SUPABASE_ANON_KEY
ask "Production backend URL — public HTTPS root for FastAPI (e.g. https://api.yourcompany.com):"; read -r PRODUCTION_BACKEND_URL
[[ -n "$PRODUCTION_BACKEND_URL" ]] || die "Production backend URL is required for release builds."
ask "PostHog API Key (leave blank to disable):"; read -r POSTHOG_API_KEY

# 1d. Credentials smoke test — read-only, no certificate writes yet
echo ""
info "Smoke-testing App Store Connect credentials (read-only)..."
export APP_STORE_CONNECT_API_KEY_ID="$ASC_KEY_ID"
export APP_STORE_CONNECT_API_ISSUER_ID="$ASC_ISSUER_ID"
export APP_STORE_CONNECT_API_KEY_CONTENT
APP_STORE_CONNECT_API_KEY_CONTENT=$(cat "$P8_PATH")
export DEVELOPMENT_TEAM="$TEAM_ID"
export APP_BUNDLE_ID="$BUNDLE_ID"
export APPLE_ID="$APPLE_ID_INPUT"
export APP_NAME="$APP_NAME"
export MATCH_GIT_URL="$MATCH_GIT_URL"
export MATCH_PASSWORD="$MATCH_PASSWORD"
export GIT_BASIC_AUTH="$GIT_BASIC_AUTH"

if ! bundle exec fastlane run get_certificates readonly:true 2>&1 | grep -q "Successfully"; then
    warn "Credentials smoke test returned a non-success response."
    warn "This may be expected if no certificate exists yet — continuing."
else
    success "Credentials validated"
fi

# ── Phase 2: Write config files ───────────────────────────────────────────────

echo ""
echo "${BOLD}  Writing configuration files...${RESET}"
echo ""

# Config-Release.xcconfig (POSTHOG_HOST: \$ preserves $() for Xcode — bash must not expand it)
cat > "$IOS_DIR/Config-Release.xcconfig" << EOF
// Production config — generated by setup-dist.sh. Gitignored.
// Re-run 'make setup-dist' to update.

DEVELOPMENT_TEAM = ${TEAM_ID}
PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID}

BACKEND_URL = ${PRODUCTION_BACKEND_URL}
SUPABASE_URL = ${SUPABASE_URL}
SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY}

POSTHOG_ENABLED = TRUE
POSTHOG_API_KEY = ${POSTHOG_API_KEY}
POSTHOG_HOST = https:/\$()/us.i.posthog.com

DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
EOF
success "Config-Release.xcconfig written"

# fastlane/Appfile
cat > "$FASTLANE_DIR/Appfile" << EOF
app_identifier(ENV["APP_BUNDLE_ID"] || "${BUNDLE_ID}")
apple_id(ENV["APPLE_ID"] || "${APPLE_ID_INPUT}")
team_id(ENV["DEVELOPMENT_TEAM"] || "${TEAM_ID}")
EOF
success "fastlane/Appfile updated"

# fastlane/Matchfile
cat > "$FASTLANE_DIR/Matchfile" << EOF
git_url(ENV["MATCH_GIT_URL"] || "${MATCH_GIT_URL}")
git_basic_authorization(ENV["GIT_BASIC_AUTH"])

storage_mode("git")
type("appstore")

app_identifier(ENV["APP_BUNDLE_ID"] || "${BUNDLE_ID}")
username(ENV["APPLE_ID"] || "${APPLE_ID_INPUT}")
EOF
success "fastlane/Matchfile updated"

# ── Phase 3: Seed & provision ─────────────────────────────────────────────────

echo ""
echo "${BOLD}  Phase 3 — Seed & provision${RESET}"
echo ""

# 3a. Create App Store Connect record (idempotent via produce)
info "Creating App Store Connect record via fastlane produce..."
if bundle exec fastlane create_app; then
    success "App Store Connect record ready"
else
    warn "fastlane produce returned a non-zero exit (may already exist — that's fine)"
fi

# 3b. Seed the certs repo — MANDATORY before first CI run
echo ""
info "Seeding certs repo via fastlane match appstore (this may take a minute)..."
echo "  This generates/syncs certificates and provisioning profiles into:"
echo "  ${MATCH_GIT_URL}"
echo ""
if bundle exec fastlane match appstore; then
    success "Certs repo seeded — CI can now pull certificates"
else
    die "fastlane match failed. Fix the error above and re-run 'make setup-dist'."
fi

# ── Phase 4: Print GitHub Secrets ─────────────────────────────────────────────

P8_CONTENT=$(cat "$P8_PATH")

echo ""
echo "${BOLD}${GREEN}${LINE}${RESET}"
echo "${BOLD}${GREEN}  Setup complete! Add these GitHub Actions secrets:${RESET}"
echo "${BOLD}${GREEN}  github.com → your repo → Settings → Secrets → Actions${RESET}"
echo "${BOLD}${GREEN}${LINE}${RESET}"
echo ""
cat << SECRETS
  DEVELOPMENT_TEAM                = ${TEAM_ID}
  APP_BUNDLE_ID                   = ${BUNDLE_ID}
  APP_NAME                        = ${APP_NAME}
  APPLE_ID                        = ${APPLE_ID_INPUT}
  SUPABASE_URL                    = ${SUPABASE_URL}
  SUPABASE_ANON_KEY               = ${SUPABASE_ANON_KEY}
  PRODUCTION_BACKEND_URL          = ${PRODUCTION_BACKEND_URL}
  POSTHOG_API_KEY                 = ${POSTHOG_API_KEY:-<leave empty if unused>}
  MATCH_GIT_URL                   = ${MATCH_GIT_URL}
  MATCH_PASSWORD                  = <the password you entered above>
  GIT_BASIC_AUTH                  = ${GIT_BASIC_AUTH}
  APP_STORE_CONNECT_API_KEY_ID    = ${ASC_KEY_ID}
  APP_STORE_CONNECT_API_ISSUER_ID = ${ASC_ISSUER_ID}
  APP_STORE_CONNECT_API_KEY_CONTENT = <full contents of ${P8_PATH}>

SECRETS
echo "${BOLD}${LINE}${RESET}"
echo ""
echo "${BOLD}  Then ship your first build:${RESET}"
echo ""
echo "    git tag v0.1.0 && git push --tags"
echo ""
echo "  Actions → Distribute to TestFlight → check TestFlight in ~15 min."
echo ""
echo "${BOLD}${LINE}${RESET}"
echo ""
