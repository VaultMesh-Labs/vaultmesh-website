#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist/index.html}"

fail() { echo "HOME_SURFACE_OK=0"; echo "HOME_SURFACE_FAIL=$1"; exit 20; }

[ -f "$ROOT" ] || fail "MISSING_FILE:$ROOT"

html="$(cat "$ROOT")"

echo "$html" | grep -q 'data-route="/"' || fail "MISSING_DATA_ROUTE"
echo "$html" | grep -q 'data-kind="home"' || fail "MISSING_DATA_KIND"

# Hero primary conversion path
echo "$html" | grep -q 'class="btn primary" href="/offer/"' || fail "MISSING_PRIMARY_OFFER_CTA"
echo "$html" | grep -q '>See the Offer<' || fail "MISSING_OFFER_TEXT"

# Secondary paths (explicit, deterministic)
echo "$html" | grep -q 'href="/verify/"' || fail "MISSING_VERIFY_LINK"
echo "$html" | grep -q '>Verify<' || fail "MISSING_VERIFY_TEXT"
echo "$html" | grep -q 'href="/support/"' || fail "MISSING_SUPPORT_LINK"
echo "$html" | grep -q '>Support<' || fail "MISSING_SUPPORT_TEXT"

# Exactly one primary CTA on the entire page, and it must be the offer link.
primary_count="$(echo "$html" | grep -o 'class="btn primary"' | wc -l | tr -d '[:space:]')"
[ "$primary_count" = "1" ] || fail "PRIMARY_CTA_COUNT:have=${primary_count},want=1"

# Secondary CTAs must NOT carry the primary class
if echo "$html" | grep -q 'class="btn primary".*href="/verify/"'; then
  fail "VERIFY_MUST_BE_SECONDARY"
fi
if echo "$html" | grep -q 'class="btn primary".*href="/support/"'; then
  fail "SUPPORT_MUST_BE_SECONDARY"
fi

# No legacy hero CTA label
if echo "$html" | grep -q '>Proof Status<'; then
  fail "LEGACY_PROOF_STATUS_PRESENT"
fi

echo "HOME_SURFACE_OK=1"
exit 0
