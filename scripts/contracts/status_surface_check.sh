#!/usr/bin/env bash
set -euo pipefail

################################################################################
# status_surface_check.sh — Status decision-lane enforcement (STATUS LANE v1)
#
# Asserts:
#   - route/kind markers present
#   - exactly 1 primary CTA → /verify/
#   - secondary links to /attest/ and /verify-console/
#   - rails collapsed (<details>, no <details open>)
#
# RC: 0 = pass, 20 = violation
################################################################################

ROOT="${1:-dist/status/index.html}"
RC_VIOLATION=20

fail() { echo "STATUS_SURFACE_OK=0"; echo "STATUS_SURFACE_FAIL=$1"; exit "${RC_VIOLATION}"; }

[ -f "$ROOT" ] || fail "MISSING_FILE:${ROOT}"

html="$(cat "$ROOT")"

# Route/kind markers
echo "$html" | grep -q 'data-route="/status/"' || fail "MISSING_DATA_ROUTE"
echo "$html" | grep -q 'data-kind="status"' || fail "MISSING_DATA_KIND"

# Exactly 1 primary CTA on the whole page
primary_count="$(echo "$html" | grep -o 'class="btn primary"' | wc -l | tr -d '[:space:]')"
[ "$primary_count" = "1" ] || fail "PRIMARY_CTA_COUNT:have=${primary_count},want=1"

# Primary must go to /verify/
echo "$html" | grep -q 'class="btn primary" href="/verify/"' || fail "MISSING_PRIMARY_VERIFY"

# Secondary must exist
echo "$html" | grep -q 'href="/attest/"' || fail "MISSING_ATTEST_LINK"
echo "$html" | grep -q 'href="/verify-console/"' || fail "MISSING_VERIFY_CONSOLE_LINK"

# Rails must be collapsible details elements
echo "$html" | grep -q '<details class="card span12 status-rails-card">' || fail "MISSING_RAILS_DETAILS"

# No pre-opened details
if echo "$html" | grep -q '<details open'; then
  fail "DETAILS_OPEN_FORBIDDEN"
fi

echo "STATUS_SURFACE_OK=1"
exit 0
