#!/usr/bin/env bash
# scripts/check-deps.sh — Validate all prerequisite tools before running make targets.
# Usage: bash scripts/check-deps.sh
#        NO_COLOR=1 bash scripts/check-deps.sh   (plain output, e.g. in CI logs)

set -euo pipefail

# ---------------------------------------------------------------------------
# Color helpers (suppressed when NO_COLOR is set or stdout is not a tty)
# ---------------------------------------------------------------------------
if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  GREEN='' RED='' BOLD='' DIM='' RESET=''
fi

PASS="${GREEN}✓${RESET}"
FAIL="${RED}✗${RESET}"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
required_missing=()
optional_missing=()

# ---------------------------------------------------------------------------
# check_tool <label> <version_cmd> <hint> [optional]
#
#   label        — display name, padded to a fixed column width
#   version_cmd  — command string whose stdout becomes the version string
#   hint         — install instruction shown on failure
#   optional     — pass "optional" to mark as non-blocking
# ---------------------------------------------------------------------------
check_tool() {
  local label="$1"
  local version_cmd="$2"
  local hint="$3"
  local optional="${4:-}"
  local version

  if version=$(eval "$version_cmd" 2>/dev/null | head -1); then
    printf "    %b %-16s %b%s%b\n" "$PASS" "$label" "$DIM" "$version" "$RESET"
  else
    printf "    %b %-16s %bNot found%b  →  %s\n" "$FAIL" "$label" "$RED" "$RESET" "$hint"
    if [[ "$optional" == "optional" ]]; then
      optional_missing+=("$label")
    else
      required_missing+=("$label")
    fi
  fi
}

# check_docker_daemon is handled separately because two distinct conditions can fail.
check_docker() {
  local bin_hint="https://www.docker.com/products/docker-desktop/"
  local daemon_hint="open Docker Desktop (or: open -a Docker)"

  if ! command -v docker &>/dev/null; then
    printf "    %b %-16s %bNot found%b  →  %s\n" "$FAIL" "docker" "$RED" "$RESET" "$bin_hint"
    required_missing+=("docker")
    return
  fi

  local version
  version=$(docker --version 2>/dev/null | head -1)

  if docker info &>/dev/null; then
    printf "    %b %-16s %b%s%b\n" "$PASS" "docker" "$DIM" "$version" "$RESET"
  else
    printf "    %b %-16s %b%s — daemon not running%b  →  %s\n" \
      "$FAIL" "docker" "$RED" "$version" "$RESET" "$daemon_hint"
    required_missing+=("docker daemon")
  fi
}

# check_simulator: look for any available iPhone simulator
check_simulator() {
  local sim
  # `|| true` prevents grep's exit-1 (no matches) from aborting under pipefail
  sim=$(xcrun simctl list devices available 2>/dev/null \
        | grep -i iphone | tail -1 | sed 's/^ *//' | sed 's/ ([A-Z0-9-]*).*$//' || true)

  if [[ -n "$sim" ]]; then
    printf "    %b %-16s %b%s%b\n" "$PASS" "iOS simulator" "$DIM" "$sim" "$RESET"
  else
    printf "    %b %-16s %bNo iPhone simulator found%b  →  Xcode ▸ Settings ▸ Platforms → add iOS runtime\n" \
      "$FAIL" "iOS simulator" "$RED" "$RESET"
    required_missing+=("iOS simulator")
  fi
}

# ---------------------------------------------------------------------------
# Determine whether mise is available, so we can prefix commands correctly.
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISE_PREFIX=""
if command -v mise &>/dev/null; then
  MISE_PREFIX="mise exec --"
fi

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------
echo ""
printf "%bChecking dependencies…%b\n" "$BOLD" "$RESET"

# ── Core ────────────────────────────────────────────────────────────────────
echo ""
printf "  %bCore%b\n" "$BOLD" "$RESET"

check_tool "mise" \
  "mise --version" \
  "curl https://mise.run | sh  (then: mise install)"

check_docker

# ── Backend ─────────────────────────────────────────────────────────────────
echo ""
printf "  %bBackend%b\n" "$BOLD" "$RESET"

check_tool "uv" \
  "${MISE_PREFIX} uv --version" \
  "mise install  (uv is pinned in .mise.toml)"


# ── iOS ──────────────────────────────────────────────────────────────────────
echo ""
printf "  %biOS%b\n" "$BOLD" "$RESET"

check_tool "Xcode" \
  "xcode-select -p" \
  "Install Xcode from the App Store, then: xcode-select --install"

check_tool "tuist" \
  "${MISE_PREFIX} tuist version" \
  "mise install  (tuist is pinned in .mise.toml)"

check_tool "swiftlint" \
  "${MISE_PREFIX} swiftlint --version" \
  "mise install  (swiftlint is pinned in .mise.toml)"

check_simulator

check_tool "idb" \
  "idb --version" \
  "brew install idb-companion  (Facebook iOS Development Bridge — UI automation)" \
  "optional"

# ── Distribution (optional) ──────────────────────────────────────────────────
echo ""
printf "  %bDistribution%b %b(optional — only needed for beta/release)%b\n" \
  "$BOLD" "$RESET" "$DIM" "$RESET"

check_tool "fastlane" \
  "cd '$REPO_ROOT/ios/StarterApp' && bundle exec fastlane --version" \
  "cd ios/StarterApp && bundle install" \
  "optional"

check_tool "xcpretty" \
  "cd '$REPO_ROOT/ios/StarterApp' && bundle exec xcpretty --version" \
  "cd ios/StarterApp && bundle install" \
  "optional"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
printf "%b%s%b\n" "$DIM" "$(printf '─%.0s' {1..50})" "$RESET"

if [[ ${#required_missing[@]} -eq 0 && ${#optional_missing[@]} -eq 0 ]]; then
  printf "%b%b✓  All dependencies present — you're good to go.%b\n" "$BOLD" "$GREEN" "$RESET"
  exit 0
fi

if [[ ${#required_missing[@]} -gt 0 ]]; then
  printf "%b%b✗  %d required tool(s) missing: %s%b\n" \
    "$BOLD" "$RED" "${#required_missing[@]}" "$(IFS=', '; echo "${required_missing[*]}")" "$RESET"
  printf "   Fix the hints above then re-run:  %bmake check-deps%b\n" "$BOLD" "$RESET"
fi

if [[ ${#optional_missing[@]} -gt 0 ]]; then
  printf "%b  %d optional tool(s) missing: %s%b\n" \
    "$DIM" "${#optional_missing[@]}" "$(IFS=', '; echo "${optional_missing[*]}")" "$RESET"
  printf "%b  (only required for: make beta / make release)%b\n" "$DIM" "$RESET"
fi

echo ""

# Exit 1 only when required tools are absent
[[ ${#required_missing[@]} -eq 0 ]]
