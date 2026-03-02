#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
ROOT="${ROOT%/}"
FILE="${ROOT}/proof-pack/index.html"
RC_VIOLATION=20

fail() {
  echo "PROOF_PACK_SURFACE_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${FILE}" ]] || fail "missing proof pack surface file: ${FILE}"

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

reject_literal() {
  local needle="$1"
  if grep -Fq "${needle}" "${FILE}"; then
    fail "legacy marker must not appear: ${needle}"
  fi
}

# Core identity markers
require_literal 'data-route="/proof-pack/"'
require_literal 'data-kind="proof-pack"'
require_literal '<title>Proof Snapshot — VaultMesh</title>'

# Ensure NAV/FOOTER are actually injected in dist output.
require_literal '<nav class="vm-nav" aria-label="Primary">'
require_literal '<footer class="vm-footer">'
reject_literal '{{NAV}}'
reject_literal '{{FOOTER}}'

# CTA contract (both CTA rows must point to deterministic intake + pricing compare).
require_count_exact '<a class="btn primary" href="/proof-pack/intake/">Request Snapshot Intake</a>' 2
require_count_exact '<a class="btn" href="/pricing/">Compare tiers</a>' 2

# Pricing anchor and drift rejection.
require_literal 'Proof Snapshot — $4,500'
reject_literal 'Book a 15-Minute Snapshot Call'

echo "PROOF_PACK_SURFACE_OK=1"
exit 0
