#!/usr/bin/env bash
# Run a command under a wall-clock cap. Exits 124 if the cap was hit, like GNU `timeout`.
#
# macOS ships no `timeout`, and coreutils may not be installed. A gate whose timeout silently
# evaporates on a machine without Homebrew is worse than one that never claimed to have a cap, so
# fall back to a plain-bash watchdog rather than running unbounded.
#
# Usage: with-timeout.sh <seconds> <command> [args...]
set -uo pipefail

SECS="${1:?usage: with-timeout.sh <seconds> <command> [args...]}"
shift
[[ $# -gt 0 ]] || { echo "usage: with-timeout.sh <seconds> <command> [args...]" >&2; exit 2; }

if   command -v timeout  >/dev/null 2>&1; then exec timeout  "$SECS" "$@"
elif command -v gtimeout >/dev/null 2>&1; then exec gtimeout "$SECS" "$@"
fi

# --- fallback watchdog ---
MARK="$(mktemp -t with-timeout)"
rm -f "$MARK"

"$@" &
cmd=$!

(
  sleep "$SECS"
  if kill -0 "$cmd" 2>/dev/null; then
    : > "$MARK"                      # tell the parent this was a timeout, not the command's own rc
    kill -TERM "$cmd" 2>/dev/null
    sleep 5
    kill -KILL "$cmd" 2>/dev/null    # xcodebuild ignores TERM when it is truly wedged
  fi
) &
watchdog=$!

# 2>/dev/null: on a kill, the shell would otherwise print its own "Terminated: 15" job notice, which
# reads like an error from the command itself.
wait "$cmd" 2>/dev/null; rc=$?

kill "$watchdog" 2>/dev/null
wait "$watchdog" 2>/dev/null

if [[ -e "$MARK" ]]; then rm -f "$MARK"; exit 124; fi
rm -f "$MARK"
exit "$rc"
