#!/usr/bin/env bash
# Run the iOS unit tests against a simulator, surviving a stale simulator.
#
# A long-lived session sim (booted once by ios-sim.sh, reused all day) eventually stops being able
# to host a test runner. xcodebuild then fails with:
#
#   Failed to establish communication with the test runner. (… Simulator indicated unix domain
#   socket for testmanagerd at path …, but no file was found at that path.)  → Error 65
#
# Nothing is wrong with the code or the tests — the device just needs a clean boot. Left to itself
# that failure reads like a broken test target, which is an expensive thing for an agent to chase.
# So: run the tests, and if and only if we see that error, reboot the device and try once more.
#
# A wedged simulator can also make `xcodebuild test` hang *forever* rather than fail — ten minutes
# of silence is worse for an agent than an error, so the run is capped by TEST_TIMEOUT and a timeout
# is treated the same as the socket error: reboot, retry once.
#
# Usage: ios-unit-test.sh <sim-udid> <derived-data-path>
set -uo pipefail

UDID="${1:?usage: ios-unit-test.sh <sim-udid> <derived-data-path>}"
DERIVED_DATA="${2:?usage: ios-unit-test.sh <sim-udid> <derived-data-path>}"
# The suite itself runs in 11-40s. 180s is generous even with several agents loading the machine,
# and keeps recovery from a wedged device to ~3min instead of an unbounded hang.
TEST_TIMEOUT="${TEST_TIMEOUT:-180}"

# Resolve both paths before the cd — BASH_SOURCE is relative, so it stops resolving afterwards.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/../ios/StarterApp" && pwd)"
cd "$IOS_DIR"

LOG="$(mktemp -t ios-unit-test)"
trap 'rm -f "$LOG"' EXIT

# `timeout` is not part of a stock macOS, so go through with-timeout.sh, which falls back to a bash
# watchdog rather than quietly running uncapped on a machine without coreutils.
TIMEOUT=(bash "$SCRIPT_DIR/with-timeout.sh" "$TEST_TIMEOUT")

# Pre-flight: xcodebuild will happily sit forever against a device that is shut down or still coming
# up, so wait for it to be genuinely ready first. Cheap when it is already booted.
ensure_booted() {
  xcrun simctl boot "$UDID" 2>/dev/null || true   # no-op if already booted
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
}

# Pre-flight: the app in the shared cache must actually carry the test bundle.
#
# `xcodebuild build` and `xcodebuild build-for-testing` write the same StarterApp.app, but only the
# latter embeds PlugIns/StarterAppTests.xctest. Since every entry point now shares one DerivedData, a
# plain `make ios-build` (or a screenshot run) leaves an app that cannot host tests, and
# test-without-building fails with "Failed to create a bundle instance … Check that the bundle
# exists on disk" → Error 65. That reads like a broken test target; it is a stale build product.
ensure_test_bundle() {
  local app="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/StarterApp.app"
  [[ -d "$app/PlugIns/StarterAppTests.xctest" ]] && return 0

  echo "→ Test bundle missing from the built app (a plain build overwrote it) — rebuilding for testing…"
  set -o pipefail
  "${TIMEOUT[@]}" xcodebuild build-for-testing \
    -workspace StarterApp.xcworkspace \
    -scheme StarterApp \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=iOS Simulator,id=$UDID" \
    2>&1 | bundle exec xcpretty --color
  return "${PIPESTATUS[0]}"
}

# Print the verdict xcpretty drops.
#
# xcpretty's formatters are regexes against XCTest's console output, and it predates Swift Testing —
# which this suite uses. Its verdict line ("Test run with 158 tests in 37 suites passed") matches
# none of them and is swallowed. All that survives is "Test execute Succeeded", which says the
# process exited 0, not which tests ran.
#
# That distinction is the whole ballgame in a Tuist project: a test file that is not a member of the
# test target compiles, links, and silently never runs. The suite stays green and the only tell is
# the count going down. So read it out of the raw log, every run, pass or fail.
print_verdict() {
  local line
  line="$(grep -aoE "Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed)" "$LOG" | tail -1)"
  echo ""
  if [[ -n "$line" ]]; then
    echo "── $line"
  else
    echo "⚠  No Swift Testing verdict in the log — zero tests may have run."
    echo "   Check the test target membership (make ios-gen) before trusting this result."
  fi
}

run_tests() {
  ensure_booted
  ensure_test_bundle || return $?
  set -o pipefail
  "${TIMEOUT[@]}" xcodebuild test-without-building \
    -workspace StarterApp.xcworkspace \
    -scheme StarterApp \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:StarterAppTests \
    -parallel-testing-enabled NO \
    -destination "platform=iOS Simulator,id=$UDID" \
    2>&1 | tee "$LOG" | bundle exec xcpretty --color
  return "${PIPESTATUS[0]}"
}

run_tests
rc=$?
if [[ $rc -eq 0 ]]; then
  print_verdict
  exit 0
fi

# 124 = timed out. Both symptoms mean the same thing: the device cannot host a test runner.
if [[ $rc -eq 124 ]]; then
  echo ""
  echo "⚠  Tests hung for ${TEST_TIMEOUT}s — the simulator is wedged, not the tests."
elif ! grep -q "testmanagerd" "$LOG"; then
  # A real test failure, or something we don't understand. xcpretty swallows the reason, so print
  # the verdict from the raw log before giving up.
  print_verdict
  echo "── xcodebuild verdict ──────────────────────────────────────────"
  grep -aA3 "^Testing failed:\|^Failing tests:" "$LOG" | head -20 || true
  exit "$rc"
else
  echo ""
  echo "⚠  Simulator could not host the test runner (stale testmanagerd socket)."
fi

echo "   Rebooting $UDID and retrying once — this is a device problem, not a code problem."
# A timed-out run can leave an xcodebuild still holding the device; it must go before the reboot.
pkill -f "xcodebuild.*$UDID" 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

run_tests
rc=$?
print_verdict
if [[ $rc -ne 0 ]]; then
  echo "── xcodebuild verdict (after reboot) ───────────────────────────"
  grep -aA3 "^Testing failed:\|^Failing tests:" "$LOG" | head -20 || true
fi
exit "$rc"
