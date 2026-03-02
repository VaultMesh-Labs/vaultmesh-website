#!/usr/bin/env bash
set -euo pipefail

################################################################################
# assert_baseline_match.sh — Post-deploy baseline content assertion
#
# Verifies that the live edge-1 content matches the local dist/site/ build
# output by comparing MANIFEST.sha256 content hashes over SSH.
#
# Usage:
#   bash scripts/assert_baseline_match.sh [--remote HOST]
#
# RC: 0 = match, 21 = manifest mismatch, 22 = remote unreachable, 20 = prereq
################################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

MANIFEST_REL="deploy/edge/MANIFEST.json"
[[ -f "${MANIFEST_REL}" ]] || { echo "FAIL: ${MANIFEST_REL} not found"; exit 20; }

RC_OK=0
RC_MISMATCH=21
RC_UNREACHABLE=22
RC_PREREQ=20

json_get() {
  awk -F'"' -v key="$1" '$2 == key { print $4; exit }' "${MANIFEST_REL}"
}

TARGET_HOST_ALIAS="$(json_get host_alias)"
TARGET_PUBLIC_IP="$(json_get public_ip)"
TARGET_ROOT="$(json_get root_path)"

REMOTE_HOST="${1:-}"
if [[ "$REMOTE_HOST" == "--remote" ]]; then
  REMOTE_HOST="${2:-root@${TARGET_PUBLIC_IP}}"
elif [[ -z "$REMOTE_HOST" ]]; then
  REMOTE_HOST="root@${TARGET_PUBLIC_IP}"
fi

DIST_SITE="dist/site"
[[ -d "${DIST_SITE}" ]] || { echo "FAIL: ${DIST_SITE}/ not found — run build.sh first"; exit "${RC_PREREQ}"; }
[[ -f "${DIST_SITE}/MANIFEST.sha256" ]] || { echo "FAIL: ${DIST_SITE}/MANIFEST.sha256 missing"; exit "${RC_PREREQ}"; }

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# 1) Check remote is reachable
if ! ssh -o ConnectTimeout=10 "${REMOTE_HOST}" "test -f '${TARGET_ROOT}/MANIFEST.sha256'" >/dev/null 2>&1; then
  printf 'BASELINE_FAIL=REMOTE_UNREACHABLE host=%s\n' "${REMOTE_HOST}"
  exit "${RC_UNREACHABLE}"
fi

# 2) Compare MANIFEST.sha256 content hash (covers all tracked files)
LOCAL_MANIFEST_SHA="$(hash_file "${DIST_SITE}/MANIFEST.sha256")"
REMOTE_MANIFEST_SHA="$(ssh "${REMOTE_HOST}" "sha256sum '${TARGET_ROOT}/MANIFEST.sha256' 2>/dev/null || shasum -a 256 '${TARGET_ROOT}/MANIFEST.sha256'" | awk '{print $1}' || true)"

if [[ -z "${REMOTE_MANIFEST_SHA}" ]]; then
  printf 'BASELINE_FAIL=REMOTE_HASH_ERROR host=%s\n' "${REMOTE_HOST}"
  exit "${RC_UNREACHABLE}"
fi

if [[ "${LOCAL_MANIFEST_SHA}" != "${REMOTE_MANIFEST_SHA}" ]]; then
  printf 'BASELINE_MISMATCH host=%s\n' "${TARGET_HOST_ALIAS}"
  printf 'LOCAL_MANIFEST_SHA=%s\n' "${LOCAL_MANIFEST_SHA}"
  printf 'REMOTE_MANIFEST_SHA=%s\n' "${REMOTE_MANIFEST_SHA}"
  exit "${RC_MISMATCH}"
fi

# 3) Spot-check: compare a few critical route hashes directly
SPOT_ROUTES=("index.html" "pricing/index.html" "proof-pack/intake/index.html" "verify-console/index.html" "shared/ui.css")
spot_failures=0

for route in "${SPOT_ROUTES[@]}"; do
  if [[ -f "${DIST_SITE}/${route}" ]]; then
    local_sha="$(hash_file "${DIST_SITE}/${route}")"
    remote_sha="$(ssh "${REMOTE_HOST}" "sha256sum '${TARGET_ROOT}/${route}' 2>/dev/null || shasum -a 256 '${TARGET_ROOT}/${route}'" 2>/dev/null | awk '{print $1}' || true)"
    if [[ -n "${remote_sha}" && "${local_sha}" != "${remote_sha}" ]]; then
      printf 'SPOT_MISMATCH route=%s local=%s remote=%s\n' "${route}" "${local_sha}" "${remote_sha}"
      spot_failures=$((spot_failures + 1))
    fi
  fi
done

if [[ "${spot_failures}" -gt 0 ]]; then
  printf 'BASELINE_FAIL=SPOT_CHECK_MISMATCH count=%s\n' "${spot_failures}"
  exit "${RC_MISMATCH}"
fi

printf 'BASELINE_HOST=%s\n' "${TARGET_HOST_ALIAS}"
printf 'BASELINE_MANIFEST_SHA=%s\n' "${LOCAL_MANIFEST_SHA}"
printf 'BASELINE_SPOT_CHECKS=%s\n' "${#SPOT_ROUTES[@]}"
printf 'BASELINE_OK=1\n'
exit "${RC_OK}"
