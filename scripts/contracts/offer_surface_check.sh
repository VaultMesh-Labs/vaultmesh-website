#!/usr/bin/env bash
set -euo pipefail

################################################################################
# offer_surface_check.sh — Offer decision-lane enforcement (OFFER LANE v1)
#
# Asserts:
#   - route/kind markers present
#   - exactly 1 primary CTA → /proof-pack/intake/
#   - secondary links to /pricing/ and /verify/
#   - rails collapsed (<details>, no <details open>)
#   - no legacy dead-end CTA labels
#
# RC: 0 = pass, 20 = violation
################################################################################

ROOT="${1:-dist/offer/index.html}"
RC_VIOLATION=20

fail() { echo "OFFER_SURFACE_OK=0"; echo "OFFER_SURFACE_FAIL=$1"; exit "${RC_VIOLATION}"; }

[ -f "$ROOT" ] || fail "MISSING_FILE:${ROOT}"

html="$(cat "$ROOT")"

# Route/kind markers
echo "$html" | grep -q 'data-route="/offer/"' || fail "MISSING_DATA_ROUTE"
echo "$html" | grep -q 'data-kind="offer"' || fail "MISSING_DATA_KIND"

# Exactly 1 primary CTA on the whole page
primary_count="$(echo "$html" | grep -o 'class="btn primary"' | wc -l | tr -d '[:space:]')"
[ "$primary_count" = "1" ] || fail "PRIMARY_CTA_COUNT:have=${primary_count},want=1"

# Primary must go to intake
echo "$html" | grep -q 'class="btn primary" href="/proof-pack/intake/"' || fail "MISSING_PRIMARY_INTAKE_CTA"

# Secondary must exist
echo "$html" | grep -q 'href="/pricing/"' || fail "MISSING_PRICING_LINK"
echo "$html" | grep -q 'href="/verify/"' || fail "MISSING_VERIFY_LINK"

# Rails must be collapsible details elements
echo "$html" | grep -q '<details class="card span12 offer-rails-card">' || fail "MISSING_RAILS_DETAILS"

# No pre-opened details
if echo "$html" | grep -q '<details open'; then
  fail "DETAILS_OPEN_FORBIDDEN"
fi

# Reject legacy dead-end CTA labels
if echo "$html" | grep -q 'View Proof Status'; then
  fail "LEGACY_VIEW_PROOF_STATUS_PRESENT"
fi

echo "OFFER_SURFACE_OK=1"
exit 0
