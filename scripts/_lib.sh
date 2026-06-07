#!/usr/bin/env bash
# scripts/_lib.sh — Shared helpers sourced by dev.sh and dev-logs.sh.
# Requires REPO_ROOT to be set by the caller before sourcing.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BACKEND_DIR="$REPO_ROOT/backend"
ENV_FILE="$BACKEND_DIR/.env"
ENV_EXAMPLE="$BACKEND_DIR/.env.example"
XCCONFIG="$REPO_ROOT/ios/StarterApp/Config-Debug.xcconfig"
XCCONFIG_EXAMPLE="$REPO_ROOT/ios/StarterApp/Config.example.xcconfig"
IOS_DIR="$REPO_ROOT/ios/StarterApp"
IOS_SIM="$REPO_ROOT/scripts/ios-sim.sh"

# ---------------------------------------------------------------------------
# URLs
# ---------------------------------------------------------------------------
SUPA_LOCAL_URL="http://127.0.0.1:54321"
SUPA_DOCKER_URL="http://host.docker.internal:54321"
BACKEND_LOCAL_URL="http://127.0.0.1:8000"
BACKEND_HEALTHZ="$BACKEND_LOCAL_URL/healthz"

# ---------------------------------------------------------------------------
# Config file helpers
# ---------------------------------------------------------------------------

# ── Pretty-print helpers (used by check_config_files / check-config) ────────

# Masks long secrets: first 16 chars + …
_mask_secret() {
  local v="$1"
  [[ ${#v} -gt 20 ]] && echo "${v:0:16}…" || echo "$v"
}

# Returns 0 (true) if $1 looks like an unfilled placeholder value
_is_placeholder() {
  case "$1" in
    ""|XXXXXXXXXX|your_*|appl_xxx*|*yourproject*|*yourcompany*|*your-anon-key*|*your_anon_key*|*your-key*|*your_key*) return 0 ;;
    *) return 1 ;;
  esac
}

# Reverse xcconfig URL escaping for display: http:/$()/  →  http://
_display_url() { echo "$1" | sed 's|:/$()/|://|g'; }

# Print one config row with ✓ / ⚠ prefix
_config_row() {
  local key="$1" raw_val="$2" is_secret="${3:-false}"
  local display_val="$raw_val"
  $is_secret && display_val=$(_mask_secret "$raw_val")
  # Undo xcconfig URL encoding for display
  display_val=$(_display_url "$display_val")
  if _is_placeholder "$raw_val"; then
    printf "  \033[33m⚠\033[0m  %-40s = %s  \033[33m← placeholder\033[0m\n" "$key" "$display_val"
  elif [[ -z "$raw_val" ]]; then
    printf "  \033[2m-\033[0m  %-40s = \033[2m(empty)\033[0m\n" "$key"
  else
    printf "  \033[32m✓\033[0m  %-40s = %s\n" "$key" "$display_val"
  fi
}

# Print all non-comment, non-empty KEY=VALUE lines from an xcconfig file
_print_xcconfig() {
  local file="$1"
  while IFS= read -r line; do
    # Skip comment and blank lines
    [[ "$line" =~ ^[[:space:]]*(//|#|$) ]] && continue
    # xcconfig format: KEY = VALUE  (note spaces around =)
    [[ "$line" != *" = "* ]] && continue
    local key raw_val
    key="${line%% =*}"
    raw_val="${line#*= }"
    [[ -z "$key" ]] && continue
    case "$key" in
      *KEY*|*SECRET*|*PASSWORD*|*TOKEN*) _config_row "$key" "$raw_val" true ;;
      *) _config_row "$key" "$raw_val" false ;;
    esac
  done < "$file"
}

# Print all non-comment, non-empty KEY=VALUE lines from a .env file
_print_env() {
  local file="$1"
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    local key raw_val
    key=$(echo "$line" | cut -d= -f1)
    raw_val=$(echo "$line" | cut -d= -f2-)
    [[ -z "$key" ]] && continue
    case "$key" in
      *KEY*|*SECRET*|*PASSWORD*|*TOKEN*) _config_row "$key" "$raw_val" true ;;
      *) _config_row "$key" "$raw_val" false ;;
    esac
  done < "$file"
}

# Validate and display xcconfigs + backend .env.
# Exits with status 1 if any required file is missing.
check_config_files() {
  local exit_code=0
  local XCCONFIG_RELEASE
  XCCONFIG_RELEASE="${XCCONFIG/Config-Debug/Config-Release}"

  printf "\n\033[1m── iOS: Config-Debug.xcconfig ──────────────────────────────────\033[0m\n"
  if [[ -f "$XCCONFIG" ]]; then
    _print_xcconfig "$XCCONFIG"
  else
    printf "  \033[31m✗  MISSING\033[0m\n"
    printf "     Copy ios/StarterApp/Config.example.xcconfig → Config-Debug.xcconfig\n"
    exit_code=1
  fi

  printf "\n\033[1m── iOS: Config-Release.xcconfig ─────────────────────────────────\033[0m\n"
  if [[ -f "$XCCONFIG_RELEASE" ]]; then
    _print_xcconfig "$XCCONFIG_RELEASE"
  else
    printf "  \033[33m⚠  MISSING\033[0m  (only needed for device / TestFlight builds)\n"
    printf "     Copy ios/StarterApp/Config.example.xcconfig → Config-Release.xcconfig\n"
    printf "     and fill in your production DEVELOPMENT_TEAM, bundle ID, URLs, and keys.\n"
  fi

  printf "\n\033[1m── Backend: .env ────────────────────────────────────────────────\033[0m\n"
  if [[ -f "$ENV_FILE" ]]; then
    _print_env "$ENV_FILE"
  else
    printf "  \033[31m✗  MISSING\033[0m\n"
    printf "     Copy backend/.env.example → backend/.env\n"
    exit_code=1
  fi

  echo ""
  if [[ $exit_code -ne 0 ]]; then
    printf "\033[31mOne or more required config files are missing — see above.\033[0m\n\n"
  else
    printf "\033[32mAll required config files present.\033[0m\n\n"
  fi
  return $exit_code
}

# ── Upsert helpers ──────────────────────────────────────────────────────────

# Upsert KEY=VALUE in a .env-style file (adds if missing, updates if wrong)
upsert_env() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    local current
    current=$(grep "^${key}=" "$file" | cut -d= -f2-)
    if [[ "$current" != "$value" ]]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
      echo "    updated $key"
    fi
  else
    echo "${key}=${value}" >> "$file"
    echo "    added   $key"
  fi
}

# Upsert KEY = VALUE in an xcconfig file
upsert_xcconfig() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key} = " "$file" 2>/dev/null; then
    local current
    current=$(grep "^${key} = " "$file" | sed "s|^${key} = ||")
    if [[ "$current" != "$value" ]]; then
      sed -i '' "s|^${key} = .*|${key} = ${value}|" "$file"
      echo "    updated $key"
    fi
  else
    echo "${key} = ${value}" >> "$file"
    echo "    added   $key"
  fi
}

# Convert a plain URL to xcconfig-safe form: http://  →  http:/$()/
xcconfig_url() { echo "$1" | sed 's|://|:/$()/|'; }

# ---------------------------------------------------------------------------
# Bootstrap steps
# ---------------------------------------------------------------------------

# Start Supabase and export SUPA_ANON_KEY.
start_supabase() {
  echo "==> Starting Supabase (local)…"
  cd "$REPO_ROOT"
  supabase start

  echo "==> Reading Supabase credentials…"
  local status
  status=$(supabase status 2>/dev/null)

  # CLI >= 2.x → "Publishable" column; CLI 1.x fallback → "anon key" row
  SUPA_ANON_KEY=$(echo "$status" | grep "Publishable" | awk '{print $4}')
  if [[ -z "$SUPA_ANON_KEY" ]]; then
    SUPA_ANON_KEY=$(echo "$status" | grep "anon key" | awk '{print $NF}')
  fi

  [[ -n "$SUPA_ANON_KEY" ]] || {
    echo "Error: Could not read anon key from 'supabase status'."
    echo "       Output was:"
    echo "$status"
    exit 1
  }
  echo "    anon key: ${SUPA_ANON_KEY:0:24}…"
}

# Write/update backend/.env with Supabase connection details.
# Requires SUPA_ANON_KEY to be set (call start_supabase first).
configure_backend_env() {
  echo "==> Configuring backend/.env…"
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "    created from .env.example"
  fi
  upsert_env "$ENV_FILE" "SUPABASE_URL"             "$SUPA_DOCKER_URL"
  upsert_env "$ENV_FILE" "SUPABASE_PUBLIC_ANON_KEY" "$SUPA_ANON_KEY"
}

# Write/update ios/StarterApp/Config-Debug.xcconfig.
# Requires SUPA_ANON_KEY to be set (call start_supabase first).
configure_ios_xcconfig() {
  echo "==> Configuring ios/Config-Debug.xcconfig…"
  if [[ ! -f "$XCCONFIG" ]]; then
    cp "$XCCONFIG_EXAMPLE" "$XCCONFIG"
    echo "    created from Config.example.xcconfig"
  fi
  upsert_xcconfig "$XCCONFIG" "BACKEND_URL"       "$(xcconfig_url "$BACKEND_LOCAL_URL")"
  upsert_xcconfig "$XCCONFIG" "SUPABASE_URL"      "$(xcconfig_url "$SUPA_LOCAL_URL")"
  upsert_xcconfig "$XCCONFIG" "SUPABASE_ANON_KEY" "$SUPA_ANON_KEY"
}

# Run tuist install (if needed) then tuist generate.
# $1 = "true" to force tuist install (--regen flag).
run_tuist() {
  local regen="${1:-false}"
  command -v tuist &>/dev/null || {
    echo "Error: 'tuist' not found. Install from https://docs.tuist.dev"
    exit 1
  }
  if [[ "$regen" == "true" ]] || [[ ! -d "$IOS_DIR/Tuist/.build" ]]; then
    echo "==> tuist install (resolving packages)…"
    (cd "$IOS_DIR" && tuist install)
  fi
  echo "==> tuist generate (refreshing Xcode project)…"
  (cd "$IOS_DIR" && tuist generate --no-open)
}

# Poll /healthz until the backend responds or times out.
wait_for_backend() {
  echo "==> Waiting for backend to be ready…"
  local max=60 i=0
  until curl -sf "$BACKEND_HEALTHZ" &>/dev/null; do
    i=$((i + 1))
    [[ $i -ge $max ]] && {
      echo "Error: Backend did not respond at $BACKEND_HEALTHZ after ${max}s."
      echo "       Check logs: docker compose logs -f  (in backend/)"
      exit 1
    }
    printf '.'
    sleep 1
  done
  echo " ready."
}
