#!/usr/bin/env bash
set -euo pipefail

################################################################################
# support_open_ui_scale_check.sh — SUPPORT OPEN SCALE v2 enforcement
#
# Asserts that Support Open uses calmer card padding and lane width.
# Input/textarea styling is handled by FORM SKIN v2 (contact-unified).
#
# RC: 0 = pass, 20 = violation
################################################################################

CSS="${1:-dist/shared/ui.css}"
RC_VIOLATION=20

fail() { echo "SUPPORT_OPEN_UI_SCALE_OK=0"; echo "SUPPORT_OPEN_UI_SCALE_FAIL=$1"; exit "${RC_VIOLATION}"; }

[ -f "$CSS" ] || fail "MISSING_CSS:${CSS}"

grep -q '\.route-support-open .page' "$CSS" || fail "MISSING_PAGE_LANE"
grep -q '\.route-support-open .card' "$CSS" || fail "MISSING_CARD_SCALE"
grep -q '\.route-support-open .card.*padding: 18px 18px' "$CSS" || fail "CARD_PADDING_DRIFT"

echo "SUPPORT_OPEN_UI_SCALE_OK=1"
exit 0
