#!/usr/bin/env bash
set -euo pipefail

################################################################################
# color_lock_check.sh — COLOR v1 Respectful Gold enforcement
#
# Asserts that gold palette variables match the canonical brass values
# and that no old-gold (#d4af37 / rgba(212,175,55)) values remain.
#
# RC: 0 = pass, 20 = violation
################################################################################

CSS="${1:-dist/shared/ui.css}"
RC_VIOLATION=20

fail() { echo "COLOR_LOCK_OK=0"; echo "COLOR_LOCK_FAIL=$1"; exit "${RC_VIOLATION}"; }

[ -f "$CSS" ] || fail "MISSING_CSS:${CSS}"

# Canonical variable values
grep -q -- '--gold: #D7C38A;' "$CSS" || fail "GOLD_DRIFT"
grep -q -- '--gold-dim: rgba(215,195,138,0.3);' "$CSS" || fail "GOLD_DIM_DRIFT"
grep -q -- '--border-active: rgba(215,195,138,0.72);' "$CSS" || fail "BORDER_ACTIVE_DRIFT"
grep -q -- '--vm-line: rgba(215,195,138,0.12);' "$CSS" || fail "VM_LINE_DRIFT"

# No old gold remnants
if grep -q '#d4af37' "$CSS"; then
  fail "OLD_GOLD_HEX_PRESENT"
fi
if grep -q 'rgba(212,175,55,' "$CSS"; then
  fail "OLD_GOLD_RGBA_PRESENT"
fi

echo "COLOR_LOCK_OK=1"
exit 0
