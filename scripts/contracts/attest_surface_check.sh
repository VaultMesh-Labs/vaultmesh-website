#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
ROOT="${ROOT%/}"
FILE="${ROOT}/attest/index.html"
RC_VIOLATION=20

fail() {
  echo "ATTEST_SURFACE_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -f "${FILE}" ]] || fail "missing attest surface file: ${FILE}"

require_literal() {
  local needle="$1"
  grep -Fq "${needle}" "${FILE}" || fail "missing required marker: ${needle}"
}

require_regex() {
  local pattern="$1"
  grep -Eq "${pattern}" "${FILE}" || fail "missing required pattern: ${pattern}"
}

require_count_exact() {
  local needle="$1"
  local want="$2"
  local have
  have="$(grep -Fo "${needle}" "${FILE}" | wc -l | tr -d '[:space:]')"
  [[ "${have}" == "${want}" ]] || fail "marker count mismatch: ${needle} have=${have} want=${want}"
}

# Core identity markers
require_literal 'data-route="/attest/"'
require_literal 'data-kind="attest"'
require_literal '<title>Attest — VaultMesh Live Verification Surface</title>'
require_literal '<h1>Site Build Verification</h1>'

# Build + manifest anchors
require_literal 'id="vm-attest-build"'
require_literal 'id="vm-attest-manifest"'
require_regex 'Manifest: sha256:[0-9a-f]{64}'

# Required artifact links
require_literal 'href="/attest/LATEST.txt"'
require_literal 'href="/attest/attest.json"'
require_literal 'href="/attest/ROOT_HISTORY.txt"'
require_literal 'href="/attest/ROOT_HISTORY.sig"'
require_literal 'href="/attest/RELEASE_ATTEST.json"'

# Required dynamic panel IDs
require_literal 'id="schema_id"'
require_literal 'id="ts"'
require_literal 'id="subject"'
require_literal 'id="latest"'
require_literal 'id="continuity"'
require_literal 'id="health"'
require_literal 'id="anchors"'
require_literal 'id="drift"'
require_literal 'id="authority"'
require_literal 'id="release_status"'
require_literal 'id="release_build_run_id"'
require_literal 'id="release_target_id"'
require_literal 'id="release_root_sha"'
require_literal 'id="release_caddy_sha"'

# Legend completeness
require_count_exact '<span class="badge PRESENT">PRESENT</span>' 1
require_count_exact '<span class="badge MISSING">MISSING</span>' 1
require_count_exact '<span class="badge UNKNOWN">UNKNOWN</span>' 1
require_count_exact '<span class="badge INVALID">INVALID</span>' 1

# Data source contract
require_literal 'Data source: <code>/attest/attest.json</code> and <code>/attest/LATEST.txt</code> (static). No origin API calls.'

echo "ATTEST_SURFACE_OK=1"
exit 0
