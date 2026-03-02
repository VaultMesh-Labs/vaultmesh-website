#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
ROOT="${ROOT%/}"
FILE="${ROOT}/support/open/index.html"
RC_VIOLATION=20

fail() {
  echo "SUPPORT_OPEN_SURFACE_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${FILE}" ]] || fail "missing support open surface file: ${FILE}"

require_literal() {
  local needle="$1"
  grep -Fq "${needle}" "${FILE}" || fail "missing required marker: ${needle}"
}

require_count_exact() {
  local needle="$1"
  local want="$2"
  local have
  have="$(grep -Fo "${needle}" "${FILE}" | wc -l | tr -d '[:space:]')"
  [[ "${have}" == "${want}" ]] || fail "marker count mismatch: ${needle} have=${have} want=${want}"
}

require_form_field_exactly_once() {
  local field="$1"
  require_count_exact "name=\"${field}\"" 1
}

# Core identity markers
require_literal 'data-route="/support/open/"'
require_literal 'data-kind="support-open"'
require_literal '<title>Open Support Ticket | VaultMesh</title>'
require_literal '<h1>Open support ticket</h1>'

# Form contract
require_count_exact '<form method="post" action="/support/ticket" enctype="application/x-www-form-urlencoded">' 1
require_count_exact '<input type="hidden" name="form_id" value="support_ticket_v1" />' 1
require_count_exact '<input type="hidden" name="route" value="/support/open/" />' 1
require_count_exact '<button type="submit" class="btn primary">Create Ticket</button>' 1

# Exact required human fields
require_form_field_exactly_once 'name'
require_form_field_exactly_once 'email'
require_form_field_exactly_once 'company'
require_form_field_exactly_once 'severity'
require_form_field_exactly_once 'subject'
require_form_field_exactly_once 'message'

# Prevent hidden drift in field surface: enforce exact name set in this form.
form_block="$(
  awk '
    /<form[[:space:]][^>]*action="\/support\/ticket"/ { in_form = 1 }
    in_form { print }
    /<\/form>/ && in_form { exit }
  ' "${FILE}"
)"
[[ -n "${form_block}" ]] || fail "unable to isolate support form block"

names_csv="$(
  printf '%s\n' "${form_block}" \
    | grep -oE 'name="[a-z_]*"' \
    | sed -E 's/name="([a-z_]*)"/\1/' \
    | sort \
    | uniq \
    | paste -sd, -
)"
expected_csv="company,email,form_id,message,name,route,severity,subject"
[[ "${names_csv}" == "${expected_csv}" ]] || fail "unexpected form field set: have=${names_csv} want=${expected_csv}"

# Ensure contract page remains discoverable from human page
require_literal 'href="/support/ticket/"'

echo "SUPPORT_OPEN_SURFACE_OK=1"
exit 0
