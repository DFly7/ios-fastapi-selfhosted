#!/usr/bin/env bash
# rename-project.sh
#
# One-shot script to rename this template from "StarterApp" to your app's name.
# Run it once immediately after cloning, before any other work.
#
# WHERE TO RUN:
#   From the repository root (or anywhere inside the repo — the script finds the
#   root automatically via `git rev-parse --show-toplevel`).
#
# Usage:
#   ./scripts/rename-project.sh                              # interactive
#   ./scripts/rename-project.sh --app-name MyApp --bundle-id com.acme.myapp
#   ./scripts/rename-project.sh --dry-run                   # preview, no changes
#   ./scripts/rename-project.sh --help
#
# After running:
#   The script does NOT delete itself. Once you are happy with the rename, remove
#   it from your repo with:
#       git rm scripts/rename-project.sh && git commit -m "chore: remove template rename script"

set -euo pipefail

# ─── Helpers ────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}  → $*${RESET}"; }
success() { echo -e "${GREEN}  ✓ $*${RESET}"; }
warn()    { echo -e "${YELLOW}  ⚠ $*${RESET}"; }
error()   { echo -e "${RED}  ✗ $*${RESET}" >&2; }
bold()    { echo -e "${BOLD}$*${RESET}"; }

die() {
  error "$*"
  exit 1
}

# ─── Argument parsing ────────────────────────────────────────────────────────

DRY_RUN=false
APP_NAME=""
BUNDLE_ID=""
API_NAME=""
SUPABASE_PROJECT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)          DRY_RUN=true; shift ;;
    --app-name)         APP_NAME="$2"; shift 2 ;;
    --bundle-id)        BUNDLE_ID="$2"; shift 2 ;;
    --api-name)         API_NAME="$2"; shift 2 ;;
    --supabase-project) SUPABASE_PROJECT_ID="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--app-name NAME] [--bundle-id ID] [--api-name NAME] [--supabase-project ID]"
      exit 0
      ;;
    *) die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

# ─── Phase 0: Dirty-state check ─────────────────────────────────────────────

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "Not inside a git repository. Run this script from the repo root."

cd "$REPO_ROOT"

if [[ "$DRY_RUN" == false ]]; then
  if [ -n "$(git status --porcelain)" ]; then
    die "Working directory has uncommitted changes. Commit or stash your work first so you can 'git reset --hard' if needed."
  fi
fi

# ─── Phase 1: Collect & validate inputs ─────────────────────────────────────

echo ""
bold "╔══════════════════════════════════════════════════╗"
bold "║        iOS-FastAPI-Supabase Template Renamer     ║"
bold "╚══════════════════════════════════════════════════╝"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY-RUN mode — no files will be modified."
  echo ""
fi

# --- APP_NAME ---
validate_app_name() {
  [[ "$1" =~ ^[A-Z][A-Za-z0-9]+$ ]]
}

if [[ -z "$APP_NAME" ]]; then
  while true; do
    echo -n "  App name (PascalCase, e.g. TaskFlow): "
    read -r APP_NAME
    if validate_app_name "$APP_NAME"; then
      break
    fi
    error "Must start with an uppercase letter and contain only letters/digits (no spaces or symbols)."
  done
else
  validate_app_name "$APP_NAME" \
    || die "Invalid --app-name '$APP_NAME'. Must match ^[A-Z][A-Za-z0-9]+$"
fi

# --- Derived case variants ---
# kebab-case: TaskFlow → task-flow
# Insert '-' before each uppercase letter, lowercase everything, strip leading '-'
# Uses only POSIX sed + tr (no GNU \L extension) so it works on macOS.
APP_NAME_KEBAB="$(echo "$APP_NAME" | sed 's/\([A-Z]\)/-\1/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-//')"
# lowercase/slug: TaskFlow → taskflow
APP_NAME_LOWER="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')"

# --- BUNDLE_ID ---
validate_bundle_id() {
  [[ "$1" =~ ^[a-z][a-z0-9]+(\.[a-z0-9]+)+$ ]]
}

if [[ -z "$BUNDLE_ID" ]]; then
  while true; do
    echo -n "  Bundle ID (e.g. com.acme.${APP_NAME_LOWER}): "
    read -r BUNDLE_ID
    if validate_bundle_id "$BUNDLE_ID"; then
      break
    fi
    error "Must be reverse-DNS format, lowercase letters/digits only (e.g. com.acme.myapp)."
  done
else
  validate_bundle_id "$BUNDLE_ID" \
    || die "Invalid --bundle-id '$BUNDLE_ID'. Must match ^[a-z][a-z0-9]+(\.[a-z0-9]+)+$"
fi

# --- API_NAME ---
if [[ -z "$API_NAME" ]]; then
  echo -n "  API name [${APP_NAME} API]: "
  read -r API_NAME
  API_NAME="${API_NAME:-${APP_NAME} API}"
fi

# --- SUPABASE_PROJECT_ID ---
if [[ -z "$SUPABASE_PROJECT_ID" ]]; then
  echo -n "  Supabase local project ID [${APP_NAME_KEBAB}]: "
  read -r SUPABASE_PROJECT_ID
  SUPABASE_PROJECT_ID="${SUPABASE_PROJECT_ID:-${APP_NAME_KEBAB}}"
fi

# ─── Summary ────────────────────────────────────────────────────────────────

echo ""
bold "Substitution summary:"
echo "  StarterApp            →  ${APP_NAME}"
echo "  starterapp (slugs)    →  ${APP_NAME_LOWER}"
echo "  starter-app (kebab)   →  ${APP_NAME_KEBAB}"
echo "  com.example.StarterApp →  ${BUNDLE_ID}"
echo "  Starter API           →  ${API_NAME}"
echo "  ios-fastapi-supabase-starter → ${SUPABASE_PROJECT_ID}"
echo ""

if [[ "$DRY_RUN" == false ]]; then
  echo -n "  Proceed? [y/N] "
  read -r CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  echo ""
fi

# ─── Phase 2: Content replacement ───────────────────────────────────────────

# sed in-place, macOS-compatible (-i '')
do_sed() {
  local pattern="$1"
  local replacement="$2"
  local file="$3"
  if [[ "$DRY_RUN" == true ]]; then
    if grep -q "$pattern" "$file" 2>/dev/null; then
      echo "    [dry-run] $file: s|${pattern}|${replacement}|g"
    fi
  else
    sed -i '' "s|${pattern}|${replacement}|g" "$file"
  fi
}

# Ordered substitutions: longest/most-specific patterns first.
# Each is a (pattern, replacement) pair evaluated per file.
apply_substitutions() {
  local file="$1"

  # Bundle IDs — most specific first to avoid partial matches
  do_sed 'com\.example\.StarterApp\.pro\.monthly' "${BUNDLE_ID}.pro.monthly"         "$file"
  do_sed 'com\.example\.StarterAppUITests'         "${BUNDLE_ID}UITests"              "$file"
  do_sed 'com\.example\.StarterAppTests'           "${BUNDLE_ID}Tests"                "$file"
  do_sed 'com\.example\.StarterApp'                "${BUNDLE_ID}"                     "$file"
  # Auth redirect scheme (supabase config.toml uses the old bundle as a URL scheme)
  do_sed 'com\.example\.starter://'               "${BUNDLE_ID}://"                  "$file"
  # Supabase local project ID
  do_sed 'ios-fastapi-supabase-starter'            "${SUPABASE_PROJECT_ID}"           "$file"
  # Backend API name
  do_sed 'Starter API'                             "${API_NAME}"                      "$file"
  # PascalCase variants — longer compound names first
  do_sed 'StarterAppUITests'                       "${APP_NAME}UITests"               "$file"
  do_sed 'StarterAppTests'                         "${APP_NAME}Tests"                 "$file"
  do_sed 'StarterAppPackages'                      "${APP_NAME}Packages"              "$file"
  do_sed 'StarterAppApp'                           "${APP_NAME}App"                   "$file"
  do_sed 'StarterApp'                              "${APP_NAME}"                      "$file"
}

bold "Phase 2: Replacing content in tracked files…"

file_count=0
changed_count=0

while IFS= read -r file; do
  # Skip directories (git ls-files can return submodule entries)
  [[ -f "$file" ]] || continue
  # Binary-file guard: grep -Il returns exit 0 only for text files
  grep -qIl '' "$file" || continue

  file_count=$((file_count + 1))
  apply_substitutions "$file"
  changed_count=$((changed_count + 1))
done < <(git ls-files)

if [[ "$DRY_RUN" == true ]]; then
  info "Dry-run complete. ${file_count} text files scanned."
else
  success "Content replacement done (${changed_count} files processed)."
fi
echo ""

# ─── Phase 3: File and directory renames ────────────────────────────────────

safe_mv() {
  local src="$1"
  local dst="$2"
  if [[ "$DRY_RUN" == true ]]; then
    if [[ -e "$src" ]]; then
      echo "    [dry-run] mv '${src}' → '${dst}'"
    fi
  else
    if [[ -e "$src" ]]; then
      mv "$src" "$dst"
      info "Renamed: ${src} → ${dst}"
    fi
  fi
}

bold "Phase 3: Renaming files and directories…"

IOS_OLD="ios/StarterApp"

# 1. Named Swift entry-point file (must rename before its parent directory moves)
safe_mv \
  "${IOS_OLD}/StarterApp/StarterAppApp.swift" \
  "${IOS_OLD}/StarterApp/${APP_NAME}App.swift"

# 2. Entitlements file (sibling of sources directory)
safe_mv \
  "${IOS_OLD}/StarterApp.entitlements" \
  "${IOS_OLD}/${APP_NAME}.entitlements"

# 3. Source directories (inside the project dir, before the project dir moves)
safe_mv \
  "${IOS_OLD}/StarterApp" \
  "${IOS_OLD}/${APP_NAME}"

safe_mv \
  "${IOS_OLD}/StarterAppTests" \
  "${IOS_OLD}/${APP_NAME}Tests"

safe_mv \
  "${IOS_OLD}/StarterAppUITests" \
  "${IOS_OLD}/${APP_NAME}UITests"

# 4. Top-level project directory (last, after all inner renames are done)
safe_mv \
  "${IOS_OLD}" \
  "ios/${APP_NAME}"

if [[ "$DRY_RUN" == false ]]; then
  success "File and directory renames done."
fi
echo ""

# ─── Phase 4: Remove stale Tuist artifacts ──────────────────────────────────

bold "Phase 4: Removing stale Tuist/Xcode artifacts…"

# In a real run the directory is already at ios/${APP_NAME} (Phase 3 moved it).
# In dry-run it is still at ios/StarterApp, so check both to give useful output.
if [[ "$DRY_RUN" == true ]]; then
  IOS_NEW="ios/StarterApp"
else
  IOS_NEW="ios/${APP_NAME}"
fi

safe_rm() {
  local path="$1"
  if [[ "$DRY_RUN" == true ]]; then
    if [[ -e "$path" ]]; then
      echo "    [dry-run] rm -rf '${path}'"
    fi
  else
    if [[ -e "$path" ]]; then
      rm -rf "$path"
      info "Removed: ${path}"
    fi
  fi
}

# All gitignored, all embed the old project name — must be deleted before tuist generate
safe_rm "${IOS_NEW}/Derived"
safe_rm "${IOS_NEW}/DerivedDataRun"
# xcodeproj/xcworkspace: try both old and new names in case they already got renamed
safe_rm "${IOS_NEW}/StarterApp.xcodeproj"
safe_rm "${IOS_NEW}/${APP_NAME}.xcodeproj"
safe_rm "${IOS_NEW}/StarterApp.xcworkspace"
safe_rm "${IOS_NEW}/${APP_NAME}.xcworkspace"
safe_rm "${IOS_NEW}/Tuist/.build"

if [[ "$DRY_RUN" == false ]]; then
  success "Stale artifacts removed."
fi
echo ""

# ─── Phase 5: Print next steps ──────────────────────────────────────────────

bold "╔══════════════════════════════════════════════════╗"
if [[ "$DRY_RUN" == true ]]; then
  bold "║  Dry-run complete — nothing was changed.         ║"
else
  bold "║  Done! Rename complete.                          ║"
fi
bold "╚══════════════════════════════════════════════════╝"
echo ""

if [[ "$DRY_RUN" == false ]]; then
  bold "Next steps:"
  echo ""
  echo "  1. Regenerate the Xcode workspace:"
  echo "       cd ios/${APP_NAME} && tuist generate"
  echo ""
  echo "  2. Set your bundle ID in the debug config:"
  echo "       cp ios/${APP_NAME}/Config.example.xcconfig ios/${APP_NAME}/Config-Debug.xcconfig"
  echo "       # Edit Config-Debug.xcconfig:"
  echo "       #   PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID}"
  echo ""
  echo "  3. Verify the Supabase redirect URL matches your bundle ID:"
  echo "       supabase/config.toml → additional_redirect_urls = [\"${BUNDLE_ID}://\"]"
  echo ""
  echo "  4. Run the full validation suite:"
  echo "       make validate"
  echo ""
  warn "If 'tuist generate' shows stale names, clear the global Tuist cache:"
  echo "       rm -rf ~/.cache/tuist"
  echo ""
  echo "  5. Remove this one-time rename script from your repo:"
  echo "       git rm scripts/rename-project.sh"
  echo "       git commit -m \"chore: remove template rename script\""
  echo ""
fi
