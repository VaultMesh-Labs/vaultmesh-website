#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PAGES=(
  "$ROOT_DIR/public/index.html"
  "$ROOT_DIR/public/proof-pack/index.html"
  "$ROOT_DIR/public/attest/index.html"
  "$ROOT_DIR/public/about/index.html"
  "$ROOT_DIR/public/support/index.html"
)

NAV_FILE="$ROOT_DIR/public/shared/nav.html"

fail=0

for f in "${PAGES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "PARITY_FAIL missing_page=$f"
    fail=1
    continue
  fi

  grep -q '<!-- {{NAV}} -->' "$f" || { echo "PARITY_FAIL nav_placeholder_missing=$f"; fail=1; }
  grep -q '<!-- {{FOOTER}} -->' "$f" || { echo "PARITY_FAIL footer_placeholder_missing=$f"; fail=1; }
  grep -q '/shared/ui.css' "$f" || { echo "PARITY_FAIL shared_css_missing=$f"; fail=1; }
done

[[ -f "$NAV_FILE" ]] || { echo "PARITY_FAIL missing_nav_file=$NAV_FILE"; fail=1; }

for href in '/proof-pack/' '/attest/' '/about/' '/support/' '/proof-pack/intake/'; do
  grep -q "href=\"$href\"" "$NAV_FILE" || { echo "PARITY_FAIL nav_link_missing=$href"; fail=1; }
done

grep -qi 'noindex' "$ROOT_DIR/public/support/index.html" || { echo "PARITY_FAIL support_noindex_missing=1"; fail=1; }

if [[ "$fail" -ne 0 ]]; then
  echo "PARITY_GUARD=FAIL"
  exit 12
fi

echo "PARITY_GUARD=OK"
