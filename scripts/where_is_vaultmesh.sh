#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RC_USAGE=2
RC_TOOLING=20
RC_DNS=21
RC_SSH=22
RC_STATUS=23
RC_HASH=24

fail() {
  local reason="$1"
  local rc="$2"
  printf 'WHERE_FAIL=%s\n' "$reason"
  printf 'WHERE_RC=%s\n' "$rc"
  exit "$rc"
}

usage() {
  cat <<'USAGEEOF'
Usage:
  bash scripts/where_is_vaultmesh.sh
USAGEEOF
}

if [[ "$#" -ne 0 ]]; then
  usage
  exit "${RC_USAGE}"
fi

MANIFEST="deploy/edge/MANIFEST.json"
[[ -f "${MANIFEST}" ]] || fail "MISSING_MANIFEST" "${RC_TOOLING}"

json_get_first_string() {
  local key="$1"
  awk -F'"' -v key="$key" '$2 == key { print $4; exit }' "${MANIFEST}"
}

DOMAIN="${WHERE_DOMAIN:-vaultmesh.org}"
HOST_ALIAS="$(json_get_first_string host_alias)"
PUBLIC_IP="$(json_get_first_string public_ip)"
ROOT_PATH="$(json_get_first_string root_path)"
CADDY_PATH="$(json_get_first_string caddyfile_path)"
REMOTE_HOST="${REMOTE_HOST:-root@${PUBLIC_IP}}"

[[ -n "${HOST_ALIAS}" && -n "${PUBLIC_IP}" && -n "${ROOT_PATH}" && -n "${CADDY_PATH}" ]] || fail "BAD_MANIFEST" "${RC_TOOLING}"

resolve_a() {
  if command -v dig >/dev/null 2>&1; then
    dig +short A "${DOMAIN}" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }'
    return
  fi

  if command -v nslookup >/dev/null 2>&1; then
    nslookup "${DOMAIN}" | awk '/^Address: / { print $2; exit }'
    return
  fi

  fail "TOOLING_MISSING" "${RC_TOOLING}"
}

RESOLVED_A="$(resolve_a || true)"
[[ -n "${RESOLVED_A}" ]] || fail "DNS_LOOKUP_FAIL" "${RC_DNS}"

CADDY_ACTIVE="$(ssh "${REMOTE_HOST}" "systemctl is-active caddy" 2>/dev/null || true)"
if [[ "${CADDY_ACTIVE}" != "active" ]]; then
  fail "CADDY_INACTIVE" "${RC_STATUS}"
fi

ROOT_SHA="$(ssh "${REMOTE_HOST}" "cd '${ROOT_PATH}' && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum 2>/dev/null || (find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)" | awk '{print $1}' || true)"
CADDY_SHA="$(ssh "${REMOTE_HOST}" "sha256sum '${CADDY_PATH}' 2>/dev/null || shasum -a 256 '${CADDY_PATH}'" | awk '{print $1}' || true)"

[[ -n "${ROOT_SHA}" && -n "${CADDY_SHA}" ]] || fail "HASH_FAIL" "${RC_HASH}"

printf 'WHERE_DOMAIN=%s\n' "${DOMAIN}"
printf 'WHERE_A=%s\n' "${RESOLVED_A}"
printf 'WHERE_HOST=%s\n' "${HOST_ALIAS}"
printf 'WHERE_CADDY_ACTIVE=1\n'
printf 'WHERE_ROOT=%s\n' "${ROOT_PATH}"
printf 'WHERE_ROOT_SHA256=sha256:%s\n' "${ROOT_SHA}"
printf 'WHERE_CADDY_SHA256=sha256:%s\n' "${CADDY_SHA}"
printf 'WHERE_OK=1\n'
