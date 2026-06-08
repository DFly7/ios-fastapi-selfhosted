#!/usr/bin/env bash
# scripts/smoke-test.sh — Curl-based happy-path verification against a running backend.
#
# Assumes backend is running at http://localhost:8000. Does NOT start Docker.
# Registers a test user, logs in, creates a note, reads profile, cleans up.
#
# Usage:
#   bash scripts/smoke-test.sh              # default: localhost:8000
#   BACKEND_URL=http://pi.local:8000 bash scripts/smoke-test.sh

set -euo pipefail

BASE="${BACKEND_URL:-http://localhost:8000}"
API="${BASE}/api/v1"
EMAIL="smoke-test-$(date +%s)@example.com"
PASSWORD="SmokeTest123!"
PASS=0
FAIL=0

fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  OK:   $1"; PASS=$((PASS + 1)); }

echo "==> Smoke test against ${BASE}"
echo ""

# ── Health check ──────────────────────────────────────────────────────────
echo "── Health ──"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/healthz" 2>/dev/null || echo "000")
if [[ "$STATUS" == "200" ]]; then pass "/healthz → 200"; else fail "/healthz → ${STATUS} (expected 200)"; fi

# ── Register ──────────────────────────────────────────────────────────────
echo "── Register ──"
REGISTER=$(curl -s -X POST "${API}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}")
ACCESS=$(echo "$REGISTER" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
REFRESH=$(echo "$REGISTER" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null || echo "")

if [[ -n "$ACCESS" && -n "$REFRESH" ]]; then
  pass "Register → got tokens"
else
  fail "Register → no tokens returned"
  echo "  Response: ${REGISTER}"
  echo ""
  echo "RESULT: ${PASS} passed, ${FAIL} failed (aborted early)"
  exit 1
fi

AUTH="Authorization: Bearer ${ACCESS}"

# ── Profile ───────────────────────────────────────────────────────────────
echo "── Profile ──"
PROFILE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${API}/me/profile" -H "${AUTH}")
if [[ "$PROFILE_STATUS" == "200" ]]; then pass "GET /me/profile → 200"; else fail "GET /me/profile → ${PROFILE_STATUS}"; fi

# ── Notes CRUD ────────────────────────────────────────────────────────────
echo "── Notes ──"
CREATE=$(curl -s -X POST "${API}/me/notes" \
  -H "${AUTH}" -H "Content-Type: application/json" \
  -d '{"title":"Smoke test note","body":"Created by smoke-test.sh"}')
NOTE_ID=$(echo "$CREATE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

if [[ -n "$NOTE_ID" ]]; then pass "POST /me/notes → created (${NOTE_ID})"; else fail "POST /me/notes → no id"; fi

LIST_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${API}/me/notes" -H "${AUTH}")
if [[ "$LIST_STATUS" == "200" ]]; then pass "GET /me/notes → 200"; else fail "GET /me/notes → ${LIST_STATUS}"; fi

if [[ -n "$NOTE_ID" ]]; then
  DEL_STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "${API}/me/notes/${NOTE_ID}" -H "${AUTH}")
  if [[ "$DEL_STATUS" == "204" ]]; then pass "DELETE /me/notes/${NOTE_ID} → 204"; else fail "DELETE → ${DEL_STATUS}"; fi
fi

# ── Refresh ───────────────────────────────────────────────────────────────
echo "── Refresh ──"
REFRESH_RESP=$(curl -s -X POST "${API}/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"${REFRESH}\"}")
NEW_ACCESS=$(echo "$REFRESH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
if [[ -n "$NEW_ACCESS" ]]; then pass "POST /auth/refresh → new token"; else fail "POST /auth/refresh → no token"; fi

# ── Logout ────────────────────────────────────────────────────────────────
echo "── Logout ──"
NEW_REFRESH=$(echo "$REFRESH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null || echo "")
if [[ -n "$NEW_REFRESH" ]]; then
  LOGOUT_STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${API}/auth/logout" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\":\"${NEW_REFRESH}\"}")
  if [[ "$LOGOUT_STATUS" == "204" ]]; then pass "POST /auth/logout → 204"; else fail "POST /auth/logout → ${LOGOUT_STATUS}"; fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "RESULT: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
