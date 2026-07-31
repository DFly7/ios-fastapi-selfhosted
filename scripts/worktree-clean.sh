#!/usr/bin/env bash
# Reclaim the disk a worktree's verification loop consumes.
#
# Nothing in this repo ever collected these, so they accumulate until the volume fills — and a full
# disk does not announce itself. xcodebuild reports it as:
#     error: You can't save the file "XCTest.framework" … out of space   →  Error 65
# which reads like a broken test target and sends agents off debugging their own code.
#
# Per worktree this reclaims roughly:
#     DerivedDataRun               ~650 MB   (build cache)
#     StarterApp-<worktree> sim    ~2.0 GB   (created by ios-sim.sh --session-sim, never deleted)
#
# Everything deleted here is regenerable: the next `make ios-build` / `ios-sim.sh` rebuilds it.
#
#   ./scripts/worktree-clean.sh            # this worktree only (safe while others are running)
#   ./scripts/worktree-clean.sh --stale    # + StarterApp-* sims whose worktree no longer exists
#   ./scripts/worktree-clean.sh --dry-run  # show what would go, delete nothing
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STALE=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --stale)   STALE=true;   shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

say() { if $DRY_RUN; then echo "  [dry-run] would remove $*"; else echo "  ✓ removed $*"; fi; }
size_of() { du -sh "$1" 2>/dev/null | cut -f1 || echo "?"; }

WORKTREE_NAME="$(basename "$REPO_ROOT")"
echo "==> Cleaning worktree: $WORKTREE_NAME"

# ---------------------------------------------------------------------------
# 1. Build caches (regenerable)
# ---------------------------------------------------------------------------
for dir in ios/StarterApp/DerivedDataRun ios/StarterApp/DerivedDataDevice; do
  if [[ -d "$dir" ]]; then
    sz="$(size_of "$dir")"
    $DRY_RUN || rm -rf "$dir"
    say "$dir ($sz)"
  fi
done

# ---------------------------------------------------------------------------
# 2. This worktree's session simulator
# ---------------------------------------------------------------------------
# ios-sim.sh --session-sim creates "StarterApp-<worktree>" and writes .sim-udid. Delete only ours by
# default: other worktrees' sims may belong to agents that are still running.
SIM_NAME="StarterApp-${WORKTREE_NAME}"
SIM_UDID="$(xcrun simctl list devices | grep -F "$SIM_NAME (" | grep -oEi '[0-9A-F-]{36}' | head -1 || true)"
if [[ -n "$SIM_UDID" ]]; then
  $DRY_RUN || { xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true; xcrun simctl delete "$SIM_UDID"; }
  say "simulator $SIM_NAME ($SIM_UDID)"
  $DRY_RUN || rm -f .sim-udid
else
  echo "  · no session simulator named $SIM_NAME"
fi

# ---------------------------------------------------------------------------
# 3. Simulators orphaned by deleted worktrees (--stale)
# ---------------------------------------------------------------------------
if $STALE; then
  echo "==> Pruning StarterApp-* simulators with no matching worktree…"
  # Names of every live worktree, plus the main checkout.
  live="$(git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r p; do basename "$p"; done)"
  xcrun simctl list devices \
    | grep -oE 'StarterApp-[A-Za-z0-9._-]+ \([0-9A-Fa-f-]{36}\)' \
    | while read -r name udid_paren; do
        udid="${udid_paren//[()]/}"
        suffix="${name#StarterApp-}"
        if grep -qxF "$suffix" <<<"$live"; then
          echo "  · keeping $name (worktree still exists)"
        else
          $DRY_RUN || { xcrun simctl shutdown "$udid" 2>/dev/null || true; xcrun simctl delete "$udid"; }
          say "stale simulator $name ($udid)"
        fi
      done
fi

echo ""
if $DRY_RUN; then
  echo "Dry run — nothing was deleted."
else
  echo "✓  Done. Free space: $(df -h / | awk 'NR==2{print $4}')"
fi
