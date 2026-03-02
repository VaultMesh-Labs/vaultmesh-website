#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
ROOT="${ROOT%/}"
CSS_FILE="${ROOT}/shared/ui.css"
RC_VIOLATION=20

fail() {
  echo "FORM_SKIN_CONTRACT_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${CSS_FILE}" ]] || fail "missing built css: ${CSS_FILE}"

require_literal() {
  local needle="$1"
  grep -Fq "${needle}" "${CSS_FILE}" || fail "missing marker in ${CSS_FILE}: ${needle}"
}

require_literal 'FORM SKIN v2 (contact-unified)'
require_literal '.route-proof-pack-intake form .row'
require_literal '.route-support-open form .row'
require_literal '.route-support-ticket form .row'
require_literal '.route-contact form label'
require_literal '.route-pricing .wrap > .card'
require_literal '.route-pricing .grid'

echo "FORM_SKIN_CONTRACT_OK=1"
exit 0
