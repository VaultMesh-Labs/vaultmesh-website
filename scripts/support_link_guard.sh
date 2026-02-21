#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RC_USAGE=2
RC_TOOLING=14
RC_FORBIDDEN=31
RC_MISSING=32

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "SUPPORT_LINK_GUARD_FAIL missing_tool=$1" >&2
    exit "${RC_TOOLING}"
  }
}

need rg

TARGET="${1:-repo}"
if [[ "${TARGET}" != "repo" && "${TARGET}" != "dist" ]]; then
  echo "SUPPORT_LINK_GUARD_FAIL usage='bash scripts/support_link_guard.sh [repo|dist]'" >&2
  exit "${RC_USAGE}"
fi

SCAN_DIR="."
if [[ "${TARGET}" == "dist" ]]; then
  SCAN_DIR="dist"
fi

if [[ ! -d "${SCAN_DIR}" ]]; then
  echo "SUPPORT_LINK_GUARD_FAIL missing_scan_dir=${SCAN_DIR}" >&2
  exit "${RC_MISSING}"
fi

echo "SUPPORT_LINK_GUARD_PRESENT=1"
echo "SUPPORT_LINK_GUARD_MODE=${TARGET}"

forbidden_hits="$(
  rg -n --hidden --glob '!**/.git/**' --glob '!**/*.bak*' --glob '!**/*.tmp' \
    'https?://vaultmesh\.org/support/status' "${SCAN_DIR}" || true
)"

if [[ -n "${forbidden_hits}" ]]; then
  echo "SUPPORT_LINK_GUARD_FAIL forbidden_support_status_host=vaultmesh.org" >&2
  printf '%s\n' "${forbidden_hits}" >&2
  exit "${RC_FORBIDDEN}"
fi

typo_hits="$(
  rg -n --hidden --glob '!**/.git/**' --glob '!**/*.bak*' --glob '!**/*.tmp' \
    'support\.vaultmhes\.org|api\.aultmesh\.org|mcp\.aultmesh\.org' "${SCAN_DIR}" || true
)"
if [[ -n "${typo_hits}" ]]; then
  echo "SUPPORT_LINK_GUARD_FAIL typo_domain_detected=1" >&2
  printf '%s\n' "${typo_hits}" >&2
  exit "${RC_FORBIDDEN}"
fi

echo "SUPPORT_LINK_GUARD_OK=1"
