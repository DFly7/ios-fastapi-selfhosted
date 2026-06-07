#!/usr/bin/env bash
# scripts/dev-logs.sh — One-command local dev with a 3-pane log view.
#
# Does everything dev.sh does, then splits the current terminal into log panes:
#
#   ┌─────────────────────────────┐
#   │         FastAPI Logs        │  ← this pane (current terminal)
#   ├──────────────┬──────────────┤
#   │  Supabase    │     iOS      │
#   │    Logs      │    Logs      │
#   └──────────────┴──────────────┘
#
# In iTerm2: uses AppleScript to split the current tab (no new window).
# Other terminals: falls back to tmux  (brew install tmux).
#
# Usage:
#   ./scripts/dev-logs.sh              # full stack + 3-pane log view
#   ./scripts/dev-logs.sh --regen      # run tuist install + generate before iOS build
#   ./scripts/dev-logs.sh --no-ios     # services only, 2-pane log view
#
# Controls (iTerm2):
#   Click or Cmd+Opt+Arrow   switch panes
#   Ctrl+C                   stop all services and exit

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
REGEN=false
NO_IOS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --regen)  REGEN=true;  shift ;;
    --no-ios) NO_IOS=true; shift ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1  (try --help)"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$REPO_ROOT/scripts/_lib.sh"

SESSION="dev-stack"

# ---------------------------------------------------------------------------
# Prerequisites — tmux only needed outside iTerm2
# ---------------------------------------------------------------------------
if [[ "${TERM_PROGRAM:-}" != "iTerm.app" ]]; then
  command -v tmux &>/dev/null || {
    echo "Error: 'tmux' not found (required outside iTerm2)."
    echo "       Install with: brew install tmux"
    exit 1
  }
fi

# ---------------------------------------------------------------------------
# Cleanup — idempotent so INT + EXIT don't double-fire
# ---------------------------------------------------------------------------
CLEANED_UP=false
cleanup() {
  $CLEANED_UP && return
  CLEANED_UP=true
  echo ""
  echo "==> Shutting down…"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  (cd "$BACKEND_DIR" && docker compose down 2>/dev/null) || true
  supabase stop --no-backup 2>/dev/null || true
  echo "==> Done."
}
trap cleanup INT TERM EXIT

# ---------------------------------------------------------------------------
# 1–2. Supabase
# ---------------------------------------------------------------------------
start_supabase

# ---------------------------------------------------------------------------
# 3. Backend .env
# ---------------------------------------------------------------------------
configure_backend_env

# ---------------------------------------------------------------------------
# 4–5. FastAPI — detached so we can proceed; logs streamed in tmux pane
# ---------------------------------------------------------------------------
echo "==> Starting FastAPI backend (docker compose)…"
(cd "$BACKEND_DIR" && docker compose up --build --detach)

wait_for_backend

# ---------------------------------------------------------------------------
# 6. iOS xcconfig
# ---------------------------------------------------------------------------
configure_ios_xcconfig

# ---------------------------------------------------------------------------
# 7. Tuist + iOS Simulator
# ---------------------------------------------------------------------------
if ! $NO_IOS; then
  run_tuist "$REGEN"
  echo "==> Building and launching iOS Simulator…"
  "$IOS_SIM"
fi

# ---------------------------------------------------------------------------
# 8. Build log scripts (written to temp files — runs inside each pane at
#    open time, not now, so container lookups are always fresh and errors
#    keep the pane alive rather than silently exiting).
# ---------------------------------------------------------------------------
LOGSCRIPTS=$(mktemp -d)

# Panes launched via AppleScript get a minimal non-login shell — Docker and
# other tools won't be on PATH unless we add their locations explicitly.
PANE_PATH='/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin'
PANE_PATH="${PANE_PATH}:/Applications/Docker.app/Contents/Resources/bin"

cat > "$LOGSCRIPTS/fastapi.sh" <<SCRIPT
#!/usr/bin/env bash
export PATH="${PANE_PATH}:\$PATH"
cd '${BACKEND_DIR}'
echo "==> FastAPI logs (docker compose)"
echo ""
docker compose logs -f --tail=100
SCRIPT

# Supabase — resolves the right container at open time, never exits on error
cat > "$LOGSCRIPTS/supa.sh" <<SCRIPT
#!/usr/bin/env bash
export PATH="${PANE_PATH}:\$PATH"
echo "==> Supabase logs"
echo ""
# Try most-useful containers first (kong = API gateway, auth, then any supabase)
CID=""
for pat in supabase_kong supabase-kong supabase_auth supabase_rest supabase; do
  CID=\$(docker ps --filter "name=\${pat}" --format '{{.ID}}' | head -1)
  [[ -n "\$CID" ]] && break
done
if [[ -n "\$CID" ]]; then
  NAME=\$(docker inspect --format '{{.Name}}' "\$CID" | tr -d '/')
  echo "    container : \$NAME"
  echo ""
  docker logs -f --tail=100 "\$CID"
else
  echo "No Supabase container found. Running containers:"
  echo ""
  docker ps --format "  {{.Names}}"
  echo ""
  echo "Waiting — press Ctrl+C to close."
  read -r
fi
SCRIPT

cat > "$LOGSCRIPTS/ios.sh" <<SCRIPT
#!/usr/bin/env bash
export PATH="${PANE_PATH}:\$PATH"
echo "==> iOS Simulator logs (StarterApp)"
echo ""
xcrun simctl spawn booted log stream \\
  --predicate 'process == "StarterApp" AND subsystem == "com.example.StarterApp"' \\
  --level info 2>&1
SCRIPT

chmod +x "$LOGSCRIPTS/fastapi.sh" "$LOGSCRIPTS/supa.sh" "$LOGSCRIPTS/ios.sh"

# ---------------------------------------------------------------------------
# 9. Open log panes
# ---------------------------------------------------------------------------
echo ""
echo "==> Launching log view…"
echo ""
printf '  %-16s  →  %s\n' "Supabase Studio"  "http://127.0.0.1:54323"
printf '  %-16s  →  %s\n' "FastAPI docs"     "http://127.0.0.1:8000/docs"
echo ""

if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]] && [[ -z "${TMUX:-}" ]]; then
  # ── iTerm2: split this tab in-place, no new window ───────────────────────

  if $NO_IOS; then
    osascript <<APPLESCRIPT
tell application "iTerm2"
  tell current window
    tell current tab
      tell current session
        split horizontally with default profile command "$LOGSCRIPTS/supa.sh"
      end tell
    end tell
  end tell
end tell
APPLESCRIPT
  else
    osascript <<APPLESCRIPT
tell application "iTerm2"
  tell current window
    tell current tab
      tell current session
        set bottomPane to (split horizontally with default profile command "$LOGSCRIPTS/supa.sh")
      end tell
      tell bottomPane
        split vertically with default profile command "$LOGSCRIPTS/ios.sh"
      end tell
    end tell
  end tell
end tell
APPLESCRIPT
  fi

  echo "  Click pane or Cmd+Opt+Arrow to switch  |  Ctrl+C here to stop all"
  echo ""
  # Run FastAPI logs in this (top) pane.
  # EXIT trap fires cleanup when this pane is closed or Ctrl+C'd.
  "$LOGSCRIPTS/fastapi.sh" || true

else
  # ── tmux fallback (non-iTerm2 or already inside tmux) ────────────────────
  echo "  Ctrl+B ← →  switch panes  |  Ctrl+B D  detach  |  Ctrl+C  stop all"
  echo ""

  tmux kill-session -t "$SESSION" 2>/dev/null || true
  COLS=$(tput cols  2>/dev/null || echo 220)
  ROWS=$(tput lines 2>/dev/null || echo 50)
  tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format " #[bold]#{pane_title}#[nobold] "

  if $NO_IOS; then
    tmux rename-window -t "$SESSION:0" "logs"
    tmux split-window -v -t "$SESSION:0"
    tmux select-layout -t "$SESSION:0" even-vertical
    tmux select-pane -t "$SESSION:0.0" -T "  FastAPI  "
    tmux select-pane -t "$SESSION:0.1" -T "  Supabase  "
    tmux send-keys -t "$SESSION:0.0" "'$LOGSCRIPTS/fastapi.sh'" Enter
    tmux send-keys -t "$SESSION:0.1" "'$LOGSCRIPTS/supa.sh'"    Enter
  else
    tmux rename-window -t "$SESSION:0" "logs"
    tmux split-window -v -p 40 -t "$SESSION:0"
    tmux split-window -h    -t "$SESSION:0.1"
    tmux select-pane -t "$SESSION:0.0" -T "  FastAPI  "
    tmux select-pane -t "$SESSION:0.1" -T "  Supabase  "
    tmux select-pane -t "$SESSION:0.2" -T "  iOS Simulator  "
    tmux send-keys -t "$SESSION:0.0" "'$LOGSCRIPTS/fastapi.sh'" Enter
    tmux send-keys -t "$SESSION:0.1" "'$LOGSCRIPTS/supa.sh'"    Enter
    tmux send-keys -t "$SESSION:0.2" "'$LOGSCRIPTS/ios.sh'"     Enter
  fi

  tmux select-pane -t "$SESSION:0.0"

  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$SESSION"
  else
    tmux attach-session -t "$SESSION"
  fi

  # After tmux detach — disable EXIT so closing this shell doesn't stop services
  trap - EXIT
  echo ""
  echo "==> Detached. Services running independently.  make stop  to shut down."
  echo ""
fi
