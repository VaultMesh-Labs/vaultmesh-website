#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HTML="${ROOT_DIR}/dist/index.html"
RC_VIOLATION=20

[[ -f "${HTML}" ]] || { echo "FOOTER_CONTRACT_BAD=missing_index_html"; exit "${RC_VIOLATION}"; }

failures=0
check() {
  local label="$1"
  shift
  if "$@"; then
    printf 'PASS  %s\n' "${label}"
  else
    printf 'FAIL  %s\n' "${label}"
    failures=$((failures + 1))
  fi
}

check "footer includes privacy link" grep -q 'href="/legal/privacy/"' "${HTML}"
check "footer includes terms link" grep -q 'href="/legal/terms/"' "${HTML}"
check "footer includes security link" grep -q 'href="/security/"' "${HTML}"
check "manifest footer line removed" bash -c "! grep -q 'Manifest:' \"${HTML}\""

if [[ "${failures}" -gt 0 ]]; then
  printf 'FOOTER_CONTRACT_VIOLATIONS=%s\n' "${failures}"
  exit "${RC_VIOLATION}"
fi

echo "FOOTER_CONTRACT_OK=1"
