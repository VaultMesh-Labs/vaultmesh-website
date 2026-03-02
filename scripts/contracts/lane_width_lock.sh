#!/usr/bin/env bash
set -euo pipefail

################################################################################
# lane_width_lock.sh — Canonical lane width enforcement (LANE v1)
#
# Asserts that .page, .vm-nav, .vm-footer-inner, .vm-footer-bottom all
# converge on the same max-width (960px).
#
# RC: 0 = pass, 20 = violation
################################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CSS="${ROOT_DIR}/dist/shared/ui.css"
RC_VIOLATION=20

[[ -f "${CSS}" ]] || { echo "LANE_OK=0"; echo "LANE_FAIL=MISSING_CSS"; exit "${RC_VIOLATION}"; }

LANE="960px"
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    failures=$((failures + 1))
  fi
}

# Each selector must have max-width: 960px somewhere in the file
check ".page max-width" grep -q "\.page.*max-width:[[:space:]]*${LANE}" "$CSS"
check ".vm-nav max-width" grep -q "\.vm-nav.*max-width:[[:space:]]*${LANE}" "$CSS"
check ".vm-footer-inner max-width" grep -q "\.vm-footer-inner.*max-width:[[:space:]]*${LANE}" "$CSS"
check ".vm-footer-bottom max-width" grep -q "\.vm-footer-bottom.*max-width:[[:space:]]*${LANE}" "$CSS"

# Nav must have centering
check ".vm-nav margin-left auto" grep -q "\.vm-nav.*margin-left:[[:space:]]*auto" "$CSS"
check ".vm-nav margin-right auto" grep -q "\.vm-nav.*margin-right:[[:space:]]*auto" "$CSS"

if [[ "${failures}" -gt 0 ]]; then
  printf 'LANE_VIOLATIONS=%s\n' "${failures}"
  exit "${RC_VIOLATION}"
fi

echo "LANE_OK=1"
exit 0
