#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
ROOT="${ROOT%/}"
FILE="${ROOT}/proof-pack/intake/index.html"
RC_VIOLATION=20

fail() {
  echo "PROOF_PACK_INTAKE_SURFACE_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${FILE}" ]] || fail "missing proof pack intake surface file: ${FILE}"

require_literal() {
  local needle="$1"
  grep -Fq "${needle}" "${FILE}" || fail "missing required marker: ${needle}"
}

require_count_exact() {
  local needle="$1"
  local want="$2"
  local have
  have="$( (grep -Fo "${needle}" "${FILE}" || true) | wc -l | tr -d '[:space:]' )"
  [[ "${have}" == "${want}" ]] || fail "marker count mismatch: ${needle} have=${have} want=${want}"
}

require_field_once() {
  local field="$1"
  require_count_exact "name=\"${field}\"" 1
}

# Core identity markers
require_literal 'data-route="/proof-pack/intake/"'
require_literal 'data-kind="proof-pack-intake"'
require_literal 'Proof Pack Intake'

# Page-layout structure.
require_literal '<main class="page">'
require_literal '<section class="hero">'

# Form contract
require_count_exact '<form method="post" action="/proof-pack/lead" enctype="application/x-www-form-urlencoded">' 1
require_count_exact '<input type="hidden" name="form_id" value="proof_pack_lead_v1" />' 1
require_count_exact '<input type="hidden" name="route" value="/proof-pack/intake/" />' 1
require_count_exact '<button type="submit" class="btn primary">Request Intake</button>' 1

# Tier must be selected explicitly, never hidden.
if grep -Eq '<input[^>]*type="hidden"[^>]*name="tier"' "${FILE}"; then
  fail "hidden tier input is not allowed"
fi
require_literal 'name="tier" required'
require_literal '<option value="" selected disabled>'
require_count_exact '<option value="snapshot_4500">' 1
require_count_exact '<option value="sprint_7500">' 1

# Enforce exact option set/order for tier selector.
tier_block="$(
  awk '
    /name="tier"/ { in_tier = 1 }
    in_tier { print }
    /<\/select>/ && in_tier { exit }
  ' "${FILE}"
)"
[[ -n "${tier_block}" ]] || fail "missing tier select block"

tier_values="$(
  printf '%s\n' "${tier_block}" \
    | grep -oE '<option[[:space:]]+value="[^"]*"' \
    | sed -E 's/^<option[[:space:]]+value="([^"]*)"/\1/' \
    | paste -sd, -
)"
[[ "${tier_values}" == ",snapshot_4500,sprint_7500" ]] || fail "tier option set mismatch: have=${tier_values} want=,snapshot_4500,sprint_7500"

# Required field set in form.
require_field_once 'tier'
require_field_once 'name'
require_field_once 'email'
require_field_once 'company'
require_field_once 'boundary'
require_field_once 'claim_set'
require_field_once 'audience'
require_field_once 'form_id'
require_field_once 'route'

form_block="$(
  awk '
    /<form[[:space:]][^>]*action="\/proof-pack\/lead"/ { in_form = 1 }
    in_form { print }
    /<\/form>/ && in_form { exit }
  ' "${FILE}"
)"
[[ -n "${form_block}" ]] || fail "unable to isolate intake form block"

names_csv="$(
  printf '%s\n' "${form_block}" \
    | grep -oE 'name="[a-z_]*"' \
    | sed -E 's/name="([a-z_]*)"/\1/' \
    | sort \
    | uniq \
    | paste -sd, -
)"
expected_csv="audience,boundary,claim_set,company,email,form_id,name,route,tier"
[[ "${names_csv}" == "${expected_csv}" ]] || fail "unexpected form field set: have=${names_csv} want=${expected_csv}"

echo "PROOF_PACK_INTAKE_SURFACE_OK=1"
exit 0
