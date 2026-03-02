#!/usr/bin/env bash
set -euo pipefail

FILE="${1:-dist/pricing/index.html}"
RC_VIOLATION=20
TARGET_FILE="${FILE}"

fail() {
  echo "PRICING_UI_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${FILE}" ]] || fail "pricing page not found: ${FILE}"

BODY_TMP="$(mktemp)"
trap 'rm -f "${BODY_TMP}"' EXIT
awk '
  BEGIN { in_body = 0 }
  /<body[[:space:]>]/ { in_body = 1 }
  in_body { print }
  /<\/body>/ && in_body { exit }
' "${FILE}" > "${BODY_TMP}"
[[ -s "${BODY_TMP}" ]] || fail "unable to isolate body content"
TARGET_FILE="${BODY_TMP}"

require_literal() {
  local needle="$1"
  grep -Fq "${needle}" "${TARGET_FILE}" || fail "missing required marker: ${needle}"
}

reject_literal() {
  local needle="$1"
  if grep -Fq "${needle}" "${TARGET_FILE}"; then
    fail "forbidden marker present: ${needle}"
  fi
}

line_of_first() {
  local pattern="$1"
  grep -nF "${pattern}" "${TARGET_FILE}" | head -n 1 | cut -d: -f1
}

# Page-layout structure.
require_literal '<main class="page">'
require_literal '<section class="hero">'
require_literal '<h1>Pricing</h1>'

# Decision-first lane must exist.
require_literal '<h2>Entry Points</h2>'
require_literal '<a class="btn primary" href="/proof-pack/intake/?tier=snapshot">Start Snapshot</a>'
require_literal '<a class="btn" href="/proof-pack/intake/?tier=sprint">Start Sprint</a>'
require_literal 'You will choose tier again on intake. No silent downgrade.'
require_literal '<h2>Tier Details</h2>'
require_literal '<h2>Next Action</h2>'

# Collapsible sections.
require_literal '<summary><h2>Expansion Tiers</h2></summary>'
require_literal '<summary><h2>Commercial Terms</h2></summary>'
require_literal '<summary><h2>FAQ</h2></summary>'

# Decision order: Entry Points > CTAs > Tier Details > Collapsibles.
entry_line="$(line_of_first '<h2>Entry Points</h2>')"
snapshot_cta_line="$(line_of_first 'Start Snapshot')"
sprint_cta_line="$(line_of_first 'Start Sprint')"
tier_line="$(line_of_first '<h2>Tier Details</h2>')"
details_line="$(grep -n '<details' "${TARGET_FILE}" | head -n 1 | cut -d: -f1 || true)"

[[ -n "${entry_line}" ]] || fail "missing entry points block"
[[ -n "${snapshot_cta_line}" ]] || fail "missing snapshot CTA"
[[ -n "${sprint_cta_line}" ]] || fail "missing sprint CTA"
[[ -n "${tier_line}" ]] || fail "missing tier details block"

if [[ "${snapshot_cta_line}" -lt "${entry_line}" || "${sprint_cta_line}" -lt "${entry_line}" ]]; then
  fail "tier CTA appears before Entry Points block"
fi

if [[ "${tier_line}" -lt "${snapshot_cta_line}" ]]; then
  fail "tier details appears before tier CTA"
fi

if [[ -n "${details_line}" ]] && [[ "${details_line}" -lt "${tier_line}" ]]; then
  fail "details block appears before tier details"
fi

# Old attest-console layout must not return.
reject_literal '<div class="wrap">'
reject_literal '<div class="label">Entry Points</div>'
reject_literal '<div class="label">Action Row</div>'
reject_literal '<div class="card span12 entry-card">'
reject_literal '<div class="card span12 tier-card">'
reject_literal '<div class="card span12 action-card">'
reject_literal '<div class="grid">'
reject_literal '<div class="label">Status Bar</div>'
reject_literal '<div class="label">Bundle</div>'
reject_literal '<details open'

echo "PRICING_UI_OK=1"
exit 0
