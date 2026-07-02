#!/usr/bin/env bash
# scripts/e2e-test.sh — Local E2E: dev stack + clean sim + one UI happy path.
#
# Prerequisites: make dev running (backend on localhost:8000).
#
# Usage: bash scripts/e2e-test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BASE="${BACKEND_URL:-http://localhost:8000}"
API="${BASE}/api/v1"
E2E_EMAIL="e2e@example.com"
E2E_PASSWORD="E2ETest123!"
SIM_ID="${SIM_ID:-}"

echo "==> E2E UI test (dev stack at ${BASE})"
echo ""

# ── 1. Health check ───────────────────────────────────────────────────────
echo "── Health check ──"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/healthz" 2>/dev/null || echo "000")
if [[ "$STATUS" != "200" ]]; then
  echo "ERROR: ${BASE}/healthz returned ${STATUS} (expected 200)."
  echo "Start the dev stack first: make dev"
  exit 1
fi
echo "  OK: /healthz → 200"
echo ""

# ── 2. Ensure E2E user exists ─────────────────────────────────────────────
echo "── Ensure E2E user ──"
REGISTER_STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${API}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${E2E_EMAIL}\",\"password\":\"${E2E_PASSWORD}\"}")
if [[ "$REGISTER_STATUS" == "201" ]]; then
  echo "  OK: registered ${E2E_EMAIL}"
elif [[ "$REGISTER_STATUS" == "409" ]]; then
  echo "  OK: ${E2E_EMAIL} already registered"
else
  echo "ERROR: POST /auth/register returned ${REGISTER_STATUS} (expected 201 or 409)"
  exit 1
fi
echo ""

# ── 3. Boot simulator with clean state ──────────────────────────────────────
echo "── Simulator (clean state) ──"
./scripts/ios-sim.sh --headless --clean-state
echo ""

# Resolve SIM_ID if not set (same pattern as Makefile)
if [[ -z "$SIM_ID" ]]; then
  SIM_ID=$(xcrun simctl list devices booted -j | python3 -c "
import sys, json
for runtime in json.load(sys.stdin).get('devices', {}).values():
    for d in runtime:
        if d.get('state') == 'Booted':
            print(d['udid'])
            raise SystemExit
raise SystemExit('No booted simulator after ios-sim.sh')
")
fi
echo "  Using simulator: ${SIM_ID}"
echo ""

# ── 4. Run UI test ──────────────────────────────────────────────────────────
echo "── UI test ──"
set -o pipefail
cd ios/StarterApp
xcodebuild test \
  -workspace StarterApp.xcworkspace \
  -scheme StarterApp \
  -destination "platform=iOS Simulator,id=${SIM_ID}" \
  -only-testing:StarterAppUITests/E2EHappyPathTests/testSignInSecureTestAndCreateNote \
  2>&1 | bundle exec xcpretty --color

echo ""
echo "✓  E2E UI test passed."
