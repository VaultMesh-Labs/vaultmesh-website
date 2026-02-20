#!/usr/bin/env bash
set -euo pipefail

# HOST_SPLIT_LOCK_v0
# Enforce host split policy:
# - vaultmesh.org: static-only surface
# - cc.vaultmesh.org: dynamic/proxy surface

CFG="${CADDYFILE_PATH:-/etc/caddy/Caddyfile}"
PUBLIC_HOST="${HOST_SPLIT_PUBLIC_HOST:-vaultmesh.org}"
DYNAMIC_HOST="${HOST_SPLIT_DYNAMIC_HOST:-cc.vaultmesh.org}"
SITE_ROOT_LOCK="${HOST_SPLIT_SITE_ROOT_LOCK:-/srv/web/vaultmesh}"

RC_USAGE=2
RC_MISSING=11
RC_TOOLING=12
RC_VALIDATE_FAIL=21
RC_PUBLIC_BLOCK_FAIL=31
RC_DYNAMIC_BLOCK_FAIL=32
RC_POLICY_FAIL=33

say() {
  printf '%s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    say "HOST_SPLIT_LOCK_FAIL missing_tool=$1"
    exit "${RC_TOOLING}"
  }
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256:%s' "$(sha256sum "$file" | awk '{print $1}')"
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf 'sha256:%s' "$(shasum -a 256 "$file" | awk '{print $1}')"
    return
  fi

  say "HOST_SPLIT_LOCK_FAIL missing_tool=sha256sum_or_shasum"
  exit "${RC_TOOLING}"
}

usage() {
  cat <<'USAGEEOF'
Usage:
  bash scripts/host_split_guard.sh [--config /path/to/Caddyfile]

Env:
  CADDYFILE_PATH=/etc/caddy/Caddyfile
  HOST_SPLIT_PUBLIC_HOST=vaultmesh.org
  HOST_SPLIT_DYNAMIC_HOST=cc.vaultmesh.org
  HOST_SPLIT_SITE_ROOT_LOCK=/srv/web/vaultmesh
USAGEEOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--config" ]]; then
  [[ -n "${2:-}" ]] || { usage; exit "${RC_USAGE}"; }
  CFG="$2"
  shift 2
fi

if [[ "$#" -ne 0 ]]; then
  usage
  exit "${RC_USAGE}"
fi

[[ -f "${CFG}" ]] || {
  say "HOST_SPLIT_LOCK_FAIL missing_file=${CFG}"
  exit "${RC_MISSING}"
}

need_cmd caddy
need_cmd awk
need_cmd grep

say "HOST_SPLIT_LOCK_PRESENT=1"
say "HOST_SPLIT_LOCK_CONFIG_SHA256=$(sha256_file "${CFG}")"
say "HOST_SPLIT_PUBLIC_HOST=${PUBLIC_HOST}"
say "HOST_SPLIT_DYNAMIC_HOST=${DYNAMIC_HOST}"
say "HOST_SPLIT_SITE_ROOT=${SITE_ROOT_LOCK}"

if ! caddy validate --config "${CFG}" >/dev/null 2>&1; then
  say "HOST_SPLIT_LOCK_FAIL reason=validate_failed"
  exit "${RC_VALIDATE_FAIL}"
fi
say "HOST_SPLIT_LOCK_VALIDATE_OK=1"

escape_regex() {
  printf '%s' "$1" | sed -e 's/[.[\*^$()+?{}|]/\\&/g'
}

extract_host_block() {
  local host="$1"
  local cfg="$2"
  local out="$3"
  local host_re

  host_re="$(escape_regex "${host}")"

  awk -v host_re="${host_re}" '
    function delta(s, t, opens, closes) {
      t = s
      opens = gsub(/\{/, "{", t)
      t = s
      closes = gsub(/\}/, "}", t)
      return opens - closes
    }
    BEGIN { inblk=0; depth=0 }
    {
      line = $0
      if (!inblk && line ~ "^[[:space:]]*" host_re "[[:space:]]*\\{") {
        inblk = 1
      }

      if (inblk) {
        print line
        depth += delta(line)
        if (depth <= 0) {
          exit
        }
      }
    }
  ' "${cfg}" > "${out}"
}

PUBLIC_BLOCK="$(mktemp)"
DYNAMIC_BLOCK="$(mktemp)"

extract_host_block "${PUBLIC_HOST}" "${CFG}" "${PUBLIC_BLOCK}"
extract_host_block "${DYNAMIC_HOST}" "${CFG}" "${DYNAMIC_BLOCK}"

if [[ ! -s "${PUBLIC_BLOCK}" ]]; then
  rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"
  say "HOST_SPLIT_LOCK_FAIL reason=public_host_block_missing host=${PUBLIC_HOST}"
  exit "${RC_PUBLIC_BLOCK_FAIL}"
fi

if [[ ! -s "${DYNAMIC_BLOCK}" ]]; then
  rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"
  say "HOST_SPLIT_LOCK_FAIL reason=dynamic_host_block_missing host=${DYNAMIC_HOST}"
  exit "${RC_DYNAMIC_BLOCK_FAIL}"
fi

if ! grep -Eq "^[[:space:]]*root[[:space:]]+\*[[:space:]]+${SITE_ROOT_LOCK}([[:space:]]|$)" "${PUBLIC_BLOCK}"; then
  rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"
  say "HOST_SPLIT_LOCK_FAIL reason=public_root_lock_missing expected=${SITE_ROOT_LOCK}"
  exit "${RC_PUBLIC_BLOCK_FAIL}"
fi

if ! grep -Eq "^[[:space:]]*file_server([[:space:]]|$)" "${PUBLIC_BLOCK}"; then
  rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"
  say "HOST_SPLIT_LOCK_FAIL reason=public_file_server_missing"
  exit "${RC_PUBLIC_BLOCK_FAIL}"
fi

if grep -Eq "^[[:space:]]*reverse_proxy([[:space:]]|$)" "${PUBLIC_BLOCK}"; then
  rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"
  say "HOST_SPLIT_LOCK_FAIL reason=public_reverse_proxy_detected"
  exit "${RC_POLICY_FAIL}"
fi

if ! grep -Eq "^[[:space:]]*reverse_proxy([[:space:]]|$)" "${DYNAMIC_BLOCK}"; then
  rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"
  say "HOST_SPLIT_LOCK_FAIL reason=dynamic_reverse_proxy_missing host=${DYNAMIC_HOST}"
  exit "${RC_POLICY_FAIL}"
fi

if grep -Eq "^[[:space:]]*root[[:space:]]+\*[[:space:]]+${SITE_ROOT_LOCK}([[:space:]]|$)" "${DYNAMIC_BLOCK}"; then
  rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"
  say "HOST_SPLIT_LOCK_FAIL reason=dynamic_host_uses_public_root"
  exit "${RC_POLICY_FAIL}"
fi

PUBLIC_SHA="$(sha256_file "${PUBLIC_BLOCK}")"
DYNAMIC_SHA="$(sha256_file "${DYNAMIC_BLOCK}")"

rm -f "${PUBLIC_BLOCK}" "${DYNAMIC_BLOCK}"

say "HOST_SPLIT_LOCK_PUBLIC_BLOCK_SHA256=${PUBLIC_SHA}"
say "HOST_SPLIT_LOCK_DYNAMIC_BLOCK_SHA256=${DYNAMIC_SHA}"
say "HOST_SPLIT_LOCK_OK=1"
