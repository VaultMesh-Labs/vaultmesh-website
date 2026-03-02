#!/usr/bin/env bash
set -euo pipefail

################################################################################
# verify_surface_check.sh — Verify decision-lane enforcement (VERIFY LANE v1)
#
# Asserts:
#   - route/kind markers present
#   - exactly 1 primary CTA → /verify-console/
#   - secondary links to /proof-pack/ and /trust/
#   - rails collapsed (<details>, no <details open>)
#   - no legacy dead-end CTA labels
#
# RC: 0 = pass, 20 = violation
################################################################################

ROOT="${1:-dist/verify/index.html}"
RC_VIOLATION=20

fail() { echo "VERIFY_SURFACE_OK=0"; echo "VERIFY_SURFACE_FAIL=$1"; exit "${RC_VIOLATION}"; }

[ -f "$ROOT" ] || fail "MISSING_FILE:${ROOT}"

html="$(cat "$ROOT")"

# Route/kind markers
echo "$html" | grep -q 'data-route="/verify/"' || fail "MISSING_DATA_ROUTE"
echo "$html" | grep -q 'data-kind="verify"' || fail "MISSING_DATA_KIND"

# Exactly 1 primary CTA on the whole page
primary_count="$(echo "$html" | grep -o 'class="btn primary"' | wc -l | tr -d '[:space:]')"
[ "$primary_count" = "1" ] || fail "PRIMARY_CTA_COUNT:have=${primary_count},want=1"

# Primary must go to verify-console
echo "$html" | grep -q 'class="btn primary" href="/verify-console/"' || fail "MISSING_PRIMARY_CONSOLE_CTA"

# Secondary must exist
echo "$html" | grep -q 'href="/proof-pack/"' || fail "MISSING_PROOF_PACK_LINK"
echo "$html" | grep -q 'href="/trust/"' || fail "MISSING_TRUST_LINK"

# Rails must be collapsible details elements
echo "$html" | grep -q '<details class="card span12 verify-rails-card">' || fail "MISSING_RAILS_DETAILS"

# No pre-opened details
if echo "$html" | grep -q '<details open'; then
  fail "DETAILS_OPEN_FORBIDDEN"
fi

# Reject legacy dead-end CTA labels
if echo "$html" | grep -q 'Get a Proof Pack.*btn primary\|btn primary.*Get a Proof Pack'; then
  fail "LEGACY_PRIMARY_PROOF_PACK_CTA"
fi

echo "VERIFY_SURFACE_OK=1"
exit 0
