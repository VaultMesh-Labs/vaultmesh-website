#!/usr/bin/env bash
set -euo pipefail

################################################################################
# attest_lane_check.sh — Attest decision-lane enforcement (ATTEST LANE v1)
#
# Thin contract layered on top of attest_surface_check.sh.
# Asserts only decision-first lane invariants:
#   - route/kind markers present
#   - exactly 1 primary CTA → /attest/attest.json
#   - secondary links to /verify/ and /status/
#   - rails collapsed (<details>, no <details open>)
#
# RC: 0 = pass, 20 = violation
################################################################################

ROOT="${1:-dist/attest/index.html}"
RC_VIOLATION=20

fail() { echo "ATTEST_LANE_OK=0"; echo "ATTEST_LANE_FAIL=$1"; exit "${RC_VIOLATION}"; }

[ -f "$ROOT" ] || fail "MISSING_FILE:${ROOT}"

html="$(cat "$ROOT")"

# Route/kind markers
echo "$html" | grep -q 'data-route="/attest/"' || fail "MISSING_DATA_ROUTE"
echo "$html" | grep -q 'data-kind="attest"' || fail "MISSING_DATA_KIND"

# Exactly 1 primary CTA on the whole page
primary_count="$(echo "$html" | grep -o 'class="btn primary"' | wc -l | tr -d '[:space:]')"
[ "$primary_count" = "1" ] || fail "PRIMARY_CTA_COUNT:have=${primary_count},want=1"

# Primary target must be canonical proof object
echo "$html" | grep -q 'class="btn primary" href="/attest/attest.json"' || fail "MISSING_PRIMARY_ATTEST_JSON"

# Secondary links must exist
echo "$html" | grep -q 'href="/verify/"' || fail "MISSING_VERIFY_LINK"
echo "$html" | grep -q 'href="/status/"' || fail "MISSING_STATUS_LINK"

# Rails must exist + must not be pre-opened
echo "$html" | grep -q '<details class="card span12 attest-rails-card">' || fail "MISSING_RAILS_DETAILS"
if echo "$html" | grep -q '<details open'; then
  fail "DETAILS_OPEN_FORBIDDEN"
fi

echo "ATTEST_LANE_OK=1"
exit 0
