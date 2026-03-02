#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
ROOT="${ROOT%/}"
FILE="${ROOT}/proof-pack/intake/index.html"
CSS_FILE="${ROOT}/shared/ui.css"
RC_VIOLATION=20

fail() {
  echo "PROOF_PACK_INTAKE_UI_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${FILE}" ]] || fail "missing intake page: ${FILE}"
[[ -f "${CSS_FILE}" ]] || fail "missing built css: ${CSS_FILE}"

require_literal() {
  local file="$1"
  local needle="$2"
  grep -Fq "${needle}" "${file}" || fail "missing marker in ${file}: ${needle}"
}

require_count_exact() {
  local file="$1"
  local needle="$2"
  local want="$3"
  local have
  have="$(grep -Fo "${needle}" "${file}" | wc -l | tr -d '[:space:]')"
  [[ "${have}" == "${want}" ]] || fail "marker count mismatch in ${file}: ${needle} have=${have} want=${want}"
}

line_of_first() {
  local pattern="$1"
  grep -nF "${pattern}" "${FILE}" | head -n 1 | cut -d: -f1
}

# Page-layout structure.
require_literal "${FILE}" '<main class="page">'
require_literal "${FILE}" '<section class="hero">'
require_literal "${FILE}" '<h1>Proof Pack Intake</h1>'

# UX v3 section headings.
require_literal "${FILE}" '<h2>What You Get</h2>'
require_literal "${FILE}" '<h2>Choose Tier</h2>'
require_literal "${FILE}" '<h2>About You</h2>'
require_literal "${FILE}" '<h2>Define Scope</h2>'

# Tier comparison grid.
require_literal "${FILE}" 'tier-compare'

# Tier primacy + copy markers.
require_literal "${FILE}" 'name="tier" required'
require_literal "${FILE}" '<option value="" selected disabled>'
require_literal "${FILE}" "You'll receive lead_id + token_sha (receipted)."

# Form must use label/input pattern.
require_literal "${FILE}" '<label'
require_literal "${FILE}" '<form method="post" action="/proof-pack/lead"'
require_count_exact "${FILE}" '<button type="submit" class="btn primary">Request Intake</button>' 1

# Placeholders for domain-specific fields.
require_literal "${FILE}" 'placeholder='

# Decision-order invariants: hero > what-you-get > form > collapsibles.
hero_line="$(line_of_first '<section class="hero">')"
whatyouget_line="$(line_of_first '<h2>What You Get</h2>')"
form_line="$(line_of_first '<form method="post" action="/proof-pack/lead"')"
tier_line="$(line_of_first '<h2>Choose Tier</h2>')"
identity_line="$(line_of_first '<h2>About You</h2>')"
scope_line="$(line_of_first '<h2>Define Scope</h2>')"
tier_select_line="$(line_of_first 'name="tier" required')"
first_details_line="$(grep -n '<details' "${FILE}" | head -n 1 | cut -d: -f1 || true)"

[[ -n "${hero_line}" && -n "${whatyouget_line}" && -n "${form_line}" && -n "${tier_line}" && -n "${identity_line}" && -n "${scope_line}" && -n "${tier_select_line}" ]] || fail "missing one or more decision lane markers"

[[ "${hero_line}" -lt "${whatyouget_line}" ]] || fail "hero must appear before what-you-get"
[[ "${whatyouget_line}" -lt "${form_line}" ]] || fail "what-you-get must appear before form"
[[ "${form_line}" -le "${tier_line}" ]] || fail "tier card must be first inside form"
[[ "${tier_line}" -lt "${identity_line}" ]] || fail "tier card must appear before identity"
[[ "${identity_line}" -lt "${scope_line}" ]] || fail "identity must appear before scope"
[[ "${form_line}" -le "${tier_select_line}" ]] || fail "tier select must be inside form"

if [[ -n "${first_details_line}" ]]; then
  [[ "${scope_line}" -lt "${first_details_line}" ]] || fail "form must complete before collapsible rails"
fi

# Collapsible rails must be collapsed by default.
if grep -Fq '<details open' "${FILE}"; then
  fail "intake rails must not ship expanded (<details open>)"
fi

# Form skin CSS.
require_literal "${CSS_FILE}" '.route-proof-pack-intake form'
require_literal "${CSS_FILE}" '.route-proof-pack-intake form label'
require_literal "${CSS_FILE}" '.route-proof-pack-intake form input'
require_literal "${CSS_FILE}" '.route-proof-pack-intake form select'
require_literal "${CSS_FILE}" '.route-proof-pack-intake form textarea'

# Intake v3 CSS.
require_literal "${CSS_FILE}" '.route-proof-pack-intake form .card > div'
require_literal "${CSS_FILE}" '.route-proof-pack-intake .tier-compare'
require_literal "${CSS_FILE}" '.route-proof-pack-intake .tier-option h3'

# Page collapsible card CSS.
require_literal "${CSS_FILE}" '.page details.card > summary {'
require_literal "${CSS_FILE}" '.page details.card > summary h2 {'

echo "PROOF_PACK_INTAKE_UI_OK=1"
exit 0
