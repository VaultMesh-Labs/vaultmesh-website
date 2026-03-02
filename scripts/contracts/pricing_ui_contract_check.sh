#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CSS_FILE="${ROOT_DIR}/dist/shared/ui.css"
PRICING_FILE="${ROOT_DIR}/dist/pricing/index.html"
RC_VIOLATION=20

fail() {
  echo "PRICING_UI_CONTRACT_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${CSS_FILE}" ]] || fail "missing built css: ${CSS_FILE}"
[[ -f "${PRICING_FILE}" ]] || fail "missing built pricing page: ${PRICING_FILE}"

require_literal() {
  local file="$1"
  local needle="$2"
  grep -Fq "${needle}" "${file}" || fail "missing marker in ${file}: ${needle}"
}

# CSS route-scoped pricing readability block must be present.
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .grid {'
require_literal "${CSS_FILE}" 'gap: 14px;'
require_literal "${CSS_FILE}" 'background: transparent;'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .wrap {'
require_literal "${CSS_FILE}" 'max-width: 880px;'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .label {'
require_literal "${CSS_FILE}" 'color: var(--gold);'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .entry-card {'
require_literal "${CSS_FILE}" 'border-color: rgba(215,195,138,0.45);'
require_literal "${CSS_FILE}" 'background: linear-gradient('
require_literal "${CSS_FILE}" 'padding: 22px;'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .entry-card .v {'
require_literal "${CSS_FILE}" 'font-size: 14px;'
require_literal "${CSS_FILE}" 'font-weight: 600;'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .entry-card .snapshot-row {'
require_literal "${CSS_FILE}" 'background: rgba(215,195,138,0.06);'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .tier-card {'
require_literal "${CSS_FILE}" 'opacity: 0.85;'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .tier-card .v {'
require_literal "${CSS_FILE}" 'font-size: 11px;'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] .action-card {'
require_literal "${CSS_FILE}" 'border-color: rgba(215,195,138,0.35);'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] details.card > summary.label {'
require_literal "${CSS_FILE}" 'padding: 6px 0;'
require_literal "${CSS_FILE}" 'user-select: none;'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] details.card > summary.label::after {'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] details[open].card > summary.label::after {'
require_literal "${CSS_FILE}" 'body[data-route="/pricing/"] details.card > summary.label:focus {'
require_literal "${CSS_FILE}" 'outline: 1px solid rgba(215,195,138,0.35);'

# Page-layout collapsible card CSS.
require_literal "${CSS_FILE}" '.page details.card > summary {'
require_literal "${CSS_FILE}" '.page details.card > summary h2 {'
require_literal "${CSS_FILE}" '.page details[open].card > summary::after {'

# Pricing page must contain page-layout structure + decision markers.
require_literal "${PRICING_FILE}" 'data-route="/pricing/"'
require_literal "${PRICING_FILE}" '<main class="page">'
require_literal "${PRICING_FILE}" '<h2>Entry Points</h2>'
require_literal "${PRICING_FILE}" '<h2>Tier Details</h2>'
require_literal "${PRICING_FILE}" '<h2>Next Action</h2>'
require_literal "${PRICING_FILE}" 'Start Snapshot'
require_literal "${PRICING_FILE}" 'Start Sprint'
require_literal "${PRICING_FILE}" '<summary><h2>Expansion Tiers</h2></summary>'
require_literal "${PRICING_FILE}" '<summary><h2>Commercial Terms</h2></summary>'
require_literal "${PRICING_FILE}" '<summary><h2>FAQ</h2></summary>'

details_count="$(grep -c '<details' "${PRICING_FILE}" | tr -d '[:space:]')"
[[ "${details_count}" -ge 3 ]] || fail "expected at least 3 collapsed details sections, found ${details_count}"

first_entry_line="$(grep -n '<h2>Entry Points</h2>' "${PRICING_FILE}" | head -n 1 | cut -d: -f1 || true)"
first_details_line="$(grep -n '<details' "${PRICING_FILE}" | head -n 1 | cut -d: -f1 || true)"
[[ -n "${first_entry_line}" && -n "${first_details_line}" ]] || fail "missing entry section or details sections"
[[ "${first_entry_line}" -lt "${first_details_line}" ]] || fail "entry section must appear before first details section"

echo "PRICING_UI_CONTRACT_OK=1"
exit 0
