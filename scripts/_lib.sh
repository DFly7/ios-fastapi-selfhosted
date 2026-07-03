#!/usr/bin/env bash
# scripts/_lib.sh — Shared shell functions for Makefile targets.
# SOURCE this file; do not execute it directly.  No side effects on source.

# ---------------------------------------------------------------------------
# check_config_files
#
# Validates the local dev configuration (env files, xcconfig, tool pins).
# Requires $REPO_ROOT to be set by the caller (Makefile sets it to $(CURDIR)).
# Exits non-zero if any REQUIRED item is missing.
# ---------------------------------------------------------------------------
check_config_files() {
  local repo_root="${REPO_ROOT:?'REPO_ROOT must be set before sourcing _lib.sh'}"

  # ── Color helpers (suppressed when NO_COLOR is set or stdout is not a tty) ──
  local GREEN='' RED='' YELLOW='' BOLD='' DIM='' RESET=''
  if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
  fi

  local PASS="${GREEN}✓${RESET}"
  local FAIL="${RED}✗${RESET}"
  local WARN="${YELLOW}⚠${RESET}"

  local errors=()
  local warnings=()

  # ── Helpers ────────────────────────────────────────────────────────────────

  # _pass <label> <detail>
  _pass() {
    printf "    %b %-38s %b%s%b\n" "$PASS" "$1" "$DIM" "$2" "$RESET"
  }

  # _fail <label> <hint>  — records a required failure
  _fail() {
    printf "    %b %-38s %b%s%b\n" "$FAIL" "$1" "$RED" "$2" "$RESET"
    errors+=("$1")
  }

  # _warn <label> <hint>  — non-fatal but loud
  _warn() {
    printf "    %b %-38s %b%s%b\n" "$WARN" "$1" "$YELLOW" "$2" "$RESET"
    warnings+=("$1")
  }

  # _extract_env_value <file> <key>  — prints the value or empty string
  _extract_env_value() {
    local file="$1" key="$2"
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | sed "s/^${key}=//" | tr -d '"'"'" | xargs 2>/dev/null || true
  }

  # _is_placeholder <value>  — returns 0 (true) if the value looks like a placeholder
  _is_placeholder() {
    local val="$1"
    [[ "$val" =~ (change-me|CHANGE.ME|REPLACE|xxxx|your-secret|placeholder|TODO|changeme|CHANGEME) ]]
  }

  # ── Section: Environment files ─────────────────────────────────────────────
  echo ""
  printf "  %bEnvironment files%b\n" "$BOLD" "$RESET"

  # Root .env
  local root_env="$repo_root/.env"
  local root_env_example="$repo_root/.env.example"
  if [[ -f "$root_env" ]]; then
    _pass ".env" "found"
  else
    _fail ".env" "missing → run: cp .env.example .env  (or: make bootstrap)"
  fi

  # backend/.env
  local backend_env="$repo_root/backend/.env"
  local backend_env_example="$repo_root/backend/.env.example"
  if [[ -f "$backend_env" ]]; then
    _pass "backend/.env" "found"
  else
    _fail "backend/.env" "missing → run: cp backend/.env.example backend/.env  (or: make bootstrap)"
  fi

  # ── Section: JWT_SECRET ────────────────────────────────────────────────────
  echo ""
  printf "  %bJWT_SECRET%b\n" "$BOLD" "$RESET"

  # Check both env files for JWT_SECRET; prefer root .env (used by Docker Compose).
  local jwt_val=""
  local jwt_source=""

  if [[ -f "$root_env" ]]; then
    jwt_val=$(_extract_env_value "$root_env" "JWT_SECRET")
    [[ -n "$jwt_val" ]] && jwt_source=".env"
  fi

  # Fall back to backend/.env if root didn't have it (or was missing)
  if [[ -z "$jwt_val" && -f "$backend_env" ]]; then
    jwt_val=$(_extract_env_value "$backend_env" "JWT_SECRET")
    [[ -n "$jwt_val" ]] && jwt_source="backend/.env"
  fi

  if [[ -z "$jwt_val" ]]; then
    _fail "JWT_SECRET" "not set in .env or backend/.env"
  elif _is_placeholder "$jwt_val"; then
    _warn "JWT_SECRET (${jwt_source})" "still a placeholder — generate: openssl rand -hex 32"
  elif [[ ${#jwt_val} -lt 32 ]]; then
    _warn "JWT_SECRET (${jwt_source})" "only ${#jwt_val} chars — should be ≥32 (openssl rand -hex 32)"
  else
    _pass "JWT_SECRET (${jwt_source})" "${#jwt_val} chars — looks good"
  fi

  # ── Section: iOS xcconfig ──────────────────────────────────────────────────
  echo ""
  printf "  %biOS xcconfig%b\n" "$BOLD" "$RESET"

  local xcconfig_debug="$repo_root/ios/StarterApp/Config-Debug.xcconfig"
  local xcconfig_release="$repo_root/ios/StarterApp/Config-Release.xcconfig"
  local xcconfig_example="$repo_root/ios/StarterApp/Config.example.xcconfig"

  # Config-Debug.xcconfig (gitignored, may be absent — not required)
  if [[ -f "$xcconfig_debug" ]]; then
    _pass "Config-Debug.xcconfig" "found (local dev config)"
  else
    printf "    %b %-38s %b%s%b\n" "$WARN" "Config-Debug.xcconfig" "$DIM" "absent (gitignored — run: make dev  to generate)" "$RESET"
  fi

  # Config.example.xcconfig MUST exist (it's checked in)
  if [[ -f "$xcconfig_example" ]]; then
    _pass "Config.example.xcconfig" "found (template)"
  else
    _fail "Config.example.xcconfig" "missing — repo may be corrupt (git checkout ios/StarterApp/Config.example.xcconfig)"
  fi

  # ── Section: Tool pins ─────────────────────────────────────────────────────
  echo ""
  printf "  %bTool pins%b\n" "$BOLD" "$RESET"

  local mise_toml="$repo_root/.mise.toml"
  if [[ -f "$mise_toml" ]]; then
    local tools
    tools=$(grep -E '^\s*[a-z]' "$mise_toml" 2>/dev/null | wc -l | tr -d ' ')
    _pass ".mise.toml" "${tools} tool(s) pinned"
  else
    _fail ".mise.toml" "missing — tool versions are not pinned (run: make bootstrap)"
  fi

  # ── Summary ────────────────────────────────────────────────────────────────
  echo ""
  printf "%b%s%b\n" "$DIM" "$(printf '─%.0s' {1..50})" "$RESET"

  if [[ ${#errors[@]} -eq 0 && ${#warnings[@]} -eq 0 ]]; then
    printf "%b%b✓  Config looks good — ready to run: make dev%b\n" "$BOLD" "$GREEN" "$RESET"
    echo ""
    return 0
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    printf "%b%b⚠  %d warning(s): %s%b\n" \
      "$BOLD" "$YELLOW" "${#warnings[@]}" "$(IFS=', '; echo "${warnings[*]}")" "$RESET"
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    printf "%b%b✗  %d required item(s) missing: %s%b\n" \
      "$BOLD" "$RED" "${#errors[@]}" "$(IFS=', '; echo "${errors[*]}")" "$RESET"
    printf "   Fix the items above, then re-run: %bmake check-config%b\n" "$BOLD" "$RESET"
    echo ""
    return 1
  fi

  echo ""
  return 0
}
