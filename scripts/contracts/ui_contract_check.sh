#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CSS="${ROOT_DIR}/dist/shared/ui.css"
RC_VIOLATION=20

[[ -f "${CSS}" ]] || { echo "UI_CONTRACT_BAD=missing_css"; exit "${RC_VIOLATION}"; }

has_block_property() {
  local selector_re="$1"
  local property_re="$2"
  awk -v sel="${selector_re}" -v prop="${property_re}" '
    BEGIN { in_block = 0; found = 0 }
    {
      if ($0 ~ "^[[:space:]]*" sel "[[:space:]]*\\{") {
        in_block = 1
        next
      }
      if (in_block && $0 ~ /^[[:space:]]*}/) {
        in_block = 0
      }
      if (in_block && $0 ~ prop) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "${CSS}"
}

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

check "vm-nav gap" has_block_property "\\.vm-nav" "gap:[[:space:]]*1\\.1rem;"
check "vm-nav padding" has_block_property "\\.vm-nav" "padding:[[:space:]]*0\\.65rem[[:space:]]+0;"
check "vm-nav-cta padding" has_block_property "\\.vm-nav-cta" "padding:[[:space:]]*4px[[:space:]]+9px;"
check "vm-footer margin-top" has_block_property "\\.vm-footer" "margin-top:[[:space:]]*56px;"
check "vm-footer padding" has_block_property "\\.vm-footer" "padding:[[:space:]]*8px[[:space:]]+18px;"
check "vm-footer letter-spacing" has_block_property "\\.vm-footer" "letter-spacing:[[:space:]]*0\\.06em;"
check "vm-footer-muted opacity" has_block_property "\\.vm-footer-muted" "opacity:[[:space:]]*0\\.35;"
check "vm-footer-bottom opacity" has_block_property "\\.vm-footer-bottom" "opacity:[[:space:]]*0\\.22;"

if [[ "${failures}" -gt 0 ]]; then
  printf 'UI_CONTRACT_VIOLATIONS=%s\n' "${failures}"
  exit "${RC_VIOLATION}"
fi

echo "UI_CONTRACT_OK=1"
