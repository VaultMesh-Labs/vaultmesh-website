#!/usr/bin/env bash
set -euo pipefail

# CADDY_GUARD_v1
# Enforces static-first vaultmesh.org + host split for mcp/hooks.

RC_USAGE=2
RC_SNAPSHOT_MISSING=11
RC_SNAPSHOT_LIVE_MISMATCH=12
RC_PARSE_VALIDATE_FAIL=13
RC_WILDCARD_PROXY=14
RC_MISSING_HOST_BLOCKS=15
RC_FORBIDDEN_MIX=16

MODE="repo"
SNAPSHOT_CFG=""
LIVE_CFG="${CADDYFILE_PATH:-/etc/caddy/Caddyfile}"
SITE_ROOT_LOCK="${CADDY_SITE_ROOT_LOCK:-/srv/web/vaultmesh}"
ORIGIN_UPSTREAM_TOKEN='{$ORIGIN_GATEWAY_UPSTREAM:10.44.0.3:9115}'
HOOKS_UPSTREAM_TOKEN='{$VM_HOOKS_UPSTREAM}'
REMOTE_HOST="${REMOTE_HOST:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${ROOT_DIR}/deploy/edge/MANIFEST.json"

fail() {
  local reason="$1"
  local rc="$2"
  printf 'CADDY_GUARD_FAIL=%s\n' "${reason}"
  printf 'CADDY_GUARD_RC=%s\n' "${rc}"
  exit "${rc}"
}

usage() {
  cat <<'USAGEEOF'
Usage:
  bash scripts/caddy_guard.sh --repo-snapshot <path>
  bash scripts/caddy_guard.sh --live --repo-snapshot <path>

Options:
  --repo-snapshot <path>   canonical snapshot path (required)
  --live                   compare live Caddyfile against snapshot and enforce policy
  --config <path>          alias for --repo-snapshot
USAGEEOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-snapshot|--config)
      [[ -n "${2:-}" ]] || { usage; exit "${RC_USAGE}"; }
      SNAPSHOT_CFG="$2"
      shift 2
      ;;
    --live)
      MODE="live"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit "${RC_USAGE}"
      ;;
  esac
done

[[ -n "${SNAPSHOT_CFG}" ]] || { usage; exit "${RC_USAGE}"; }

if [[ "${SNAPSHOT_CFG}" != /* ]]; then
  SNAPSHOT_CFG="${ROOT_DIR}/${SNAPSHOT_CFG}"
fi

[[ -f "${SNAPSHOT_CFG}" ]] || fail "SNAPSHOT_MISSING" "${RC_SNAPSHOT_MISSING}"

if [[ -z "${REMOTE_HOST}" && -f "${MANIFEST_PATH}" ]]; then
  MANIFEST_IP="$(awk -F'"' '$2=="public_ip" {print $4; exit}' "${MANIFEST_PATH}")"
  if [[ -n "${MANIFEST_IP}" ]]; then
    REMOTE_HOST="root@${MANIFEST_IP}"
  fi
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

hash_of_file() {
  local f="$1"
  if need_cmd sha256sum; then
    sha256sum "$f" | awk '{print $1}'
    return
  fi

  if need_cmd shasum; then
    shasum -a 256 "$f" | awk '{print $1}'
    return
  fi

  fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
}

ssh_escape() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

extract_block() {
  local cfg="$1"
  local host="$2"
  local out="$3"

  local host_re
  host_re="$(printf '%s' "${host}" | sed -e 's/[.[\*^$()+?{}|]/\\&/g')"

  awk -v host_re="${host_re}" '
    function delta(s, t, o, c) {
      t=s; o=gsub(/\{/, "{", t)
      t=s; c=gsub(/\}/, "}", t)
      return o-c
    }
    BEGIN { inblk=0; depth=0 }
    {
      line=$0
      if (!inblk && line ~ "^[[:space:]]*" host_re "[[:space:]]*\\{") {
        inblk=1
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

validate_repo_cfg() {
  local cfg="$1"

  [[ -n "${VM_HOOKS_UPSTREAM:-}" ]] || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"

  if need_cmd caddy; then
    VM_HOOKS_UPSTREAM="${VM_HOOKS_UPSTREAM}" caddy validate --config "${cfg}" >/dev/null 2>&1 || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
    return
  fi

  [[ -n "${REMOTE_HOST}" ]] || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
  need_cmd ssh || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"

  local env_escaped
  env_escaped="$(ssh_escape "${VM_HOOKS_UPSTREAM}")"
  ssh "${REMOTE_HOST}" "VM_HOOKS_UPSTREAM='${env_escaped}' caddy validate --adapter caddyfile --config -" < "${cfg}" >/dev/null 2>&1 || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
}

validate_live_cfg() {
  local live_cfg="$1"

  if [[ -f "${live_cfg}" ]] && need_cmd caddy; then
    caddy validate --config "${live_cfg}" >/dev/null 2>&1 || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
    return
  fi

  [[ -n "${REMOTE_HOST}" ]] || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
  need_cmd ssh || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"

  ssh "${REMOTE_HOST}" "caddy validate --config '${live_cfg}'" >/dev/null 2>&1 || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
}

read_live_cfg_local_copy() {
  local live_cfg="$1"
  local out="$2"

  if [[ -f "${live_cfg}" ]]; then
    cp "${live_cfg}" "${out}"
    return
  fi

  [[ -n "${REMOTE_HOST}" ]] || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
  need_cmd ssh || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"

  ssh "${REMOTE_HOST}" "cat '${live_cfg}'" > "${out}" || fail "PARSE_VALIDATE_FAIL" "${RC_PARSE_VALIDATE_FAIL}"
}

check_runtime_hooks_env_live() {
  if [[ -f "${LIVE_CFG}" ]] && need_cmd systemctl; then
    systemctl show caddy --property=Environment --value | tr ' ' '\n' | grep -q '^VM_HOOKS_UPSTREAM=' || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
    return
  fi

  [[ -n "${REMOTE_HOST}" ]] || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  need_cmd ssh || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"

  ssh "${REMOTE_HOST}" "set -e; systemctl show caddy --property=Environment --value | tr ' ' '\\n' | grep -q '^VM_HOOKS_UPSTREAM='" >/dev/null 2>&1 || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
}

policy_check_vault() {
  local block="$1"

  grep -Eq "^[[:space:]]*root[[:space:]]+\*[[:space:]]+${SITE_ROOT_LOCK}([[:space:]]|$)" "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  grep -Eq "^[[:space:]]*file_server([[:space:]]|$)" "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"

  if grep -Eq '/_hooks/|/webhook' "${block}"; then
    fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  fi

  if grep -Eq 'reverse_proxy[[:space:]]+/\*' "${block}"; then
    fail "WILDCARD_PROXY" "${RC_WILDCARD_PROXY}"
  fi

  local required_paths=(
    '/proof-pack/lead*'
    '/proof-pack/intake'
    '/proof-pack/payment'
    '/proof-pack/status'
    '/support/ticket'
    '/support/update'
    '/support/resolve'
    '/support/close'
    '/support/reopen'
    '/verify/zk'
    '/proof/cc/heads'
    '/proof/cc/heads/latest'
  )

  local p
  for p in "${required_paths[@]}"; do
    grep -Fq "${p}" "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  done

  grep -Eq '^\s*handle\s+@origin_gateway\s*\{' "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  grep -Fq "${ORIGIN_UPSTREAM_TOKEN}" "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"

  # Dynamic support status is quarantined to hooks host, never proxied on vaultmesh.org.
  if awk '
    BEGIN { in_matcher=0; depth=0; bad=0 }
    function d(s,t,o,c){t=s;o=gsub(/\{/,"{",t);t=s;c=gsub(/\}/,"}",t);return o-c}
    {
      line=$0
      if (!in_matcher && line ~ /^[[:space:]]*@origin_gateway[[:space:]]*\{/) {
        in_matcher=1
        depth=d(line)
      } else if (in_matcher) {
        if (line ~ /\/support\/status/) bad=1
        depth += d(line)
        if (depth <= 0) in_matcher=0
      }
    }
    END { exit(bad?0:1) }
  ' "${block}"; then
    fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  fi

  if ! awk '
    function d(s,t,o,c){t=s;o=gsub(/\{/,"{",t);t=s;c=gsub(/\}/,"}",t);return o-c}
    BEGIN{inh=0;depth=0;name="";bad=0;rp=0}
    {
      line=$0
      if (!inh && line ~ /^[[:space:]]*handle[[:space:]]+@[A-Za-z0-9_]+[[:space:]]*\{/) {
        tmp=line
        sub(/^[[:space:]]*handle[[:space:]]+@/, "", tmp)
        sub(/[[:space:]]*\{.*/, "", tmp)
        inh=1
        name=tmp
        depth=d(line)
      }
      if (inh) {
        if (line ~ /reverse_proxy/) { rp++; if (name != "origin_gateway") bad=1 }
        depth += d(line)
        if (depth <= 0) { inh=0; name="" }
        next
      }
      if (line ~ /reverse_proxy/) { rp++; bad=1 }
    }
    END {
      if (rp==0) exit 2
      if (bad) exit 1
      exit 0
    }
  ' "${block}"; then
    rc=$?
    if [[ "${rc}" -eq 2 ]]; then
      fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
    fi
    fail "WILDCARD_PROXY" "${RC_WILDCARD_PROXY}"
  fi

  printf 'CADDY_POLICY_STATIC_OK=1\n'
  printf 'CADDY_POLICY_ALLOWLIST_OK=1\n'
  printf 'HOOKS_NOT_ON_VAULTMESH=1\n'
}

policy_check_hooks() {
  local block="$1"

  grep -Eq '^\s*@hooks_allowlist\s*\{' "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"

  local required_hook_paths=(
    '/_hooks/mailgun'
    '/_hooks/n8n/*'
    '/webhook/*'
    '/webhook-test/*'
    '/support/status'
  )

  local p
  for p in "${required_hook_paths[@]}"; do
    grep -Fq "${p}" "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  done

  grep -Fq "reverse_proxy ${HOOKS_UPSTREAM_TOKEN}" "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  grep -Eq '^\s*handle\s*\{\s*$' "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  grep -Eq '^\s*respond\s+404\s*$|^\s*respond\s+"Not found"\s+404\s*$' "${block}" || fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"

  if grep -Eq "^[[:space:]]*root[[:space:]]+\*[[:space:]]+${SITE_ROOT_LOCK}([[:space:]]|$)" "${block}"; then
    fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  fi

  if ! awk '
    function d(s,t,o,c){t=s;o=gsub(/\{/,"{",t);t=s;c=gsub(/\}/,"}",t);return o-c}
    BEGIN{inh=0;depth=0;name="";bad=0;rp=0}
    {
      line=$0
      if (!inh && line ~ /^[[:space:]]*handle[[:space:]]+@[A-Za-z0-9_]+[[:space:]]*\{/) {
        tmp=line
        sub(/^[[:space:]]*handle[[:space:]]+@/, "", tmp)
        sub(/[[:space:]]*\{.*/, "", tmp)
        inh=1
        name=tmp
        depth=d(line)
      } else if (!inh && line ~ /^[[:space:]]*handle[[:space:]]*\{/) {
        inh=1
        name="default"
        depth=d(line)
      }
      if (inh) {
        if (line ~ /reverse_proxy/) { rp++; if (name != "hooks_allowlist") bad=1 }
        depth += d(line)
        if (depth <= 0) { inh=0; name="" }
        next
      }
      if (line ~ /reverse_proxy/) { rp++; bad=1 }
    }
    END{
      if (rp==0) exit 2
      if (bad) exit 1
      exit 0
    }
  ' "${block}"; then
    rc=$?
    if [[ "${rc}" -eq 2 ]]; then
      fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
    fi
    fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  fi

  printf 'HOOKS_HOST_PRESENT=1\n'
  printf 'HOOKS_ALLOWLIST_ONLY=1\n'
}

policy_check_mcp() {
  local block="$1"

  grep -q 'reverse_proxy' "${block}" || fail "MISSING_HOST_BLOCKS" "${RC_MISSING_HOST_BLOCKS}"
  if grep -Eq "^[[:space:]]*root[[:space:]]+\*[[:space:]]+${SITE_ROOT_LOCK}([[:space:]]|$)" "${block}"; then
    fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  fi
}

printf 'CADDY_GUARD_PRESENT=1\n'

SNAPSHOT_SHA="$(hash_of_file "${SNAPSHOT_CFG}")"

if [[ "${MODE}" == "repo" ]]; then
  validate_repo_cfg "${SNAPSHOT_CFG}"
  printf 'CADDYFILE_SHA256=sha256:%s\n' "${SNAPSHOT_SHA}"
else
  validate_live_cfg "${LIVE_CFG}"

  LIVE_TMP="$(mktemp)"
  read_live_cfg_local_copy "${LIVE_CFG}" "${LIVE_TMP}"
  LIVE_SHA="$(hash_of_file "${LIVE_TMP}")"

  printf 'CADDYFILE_SHA256=sha256:%s\n' "${LIVE_SHA}"
  printf 'CADDY_SNAPSHOT_SHA256=sha256:%s\n' "${SNAPSHOT_SHA}"

  if [[ "${LIVE_SHA}" != "${SNAPSHOT_SHA}" ]]; then
    rm -f "${LIVE_TMP}"
    fail "SNAPSHOT_LIVE_MISMATCH" "${RC_SNAPSHOT_LIVE_MISMATCH}"
  fi

  check_runtime_hooks_env_live
  printf 'HOOKS_UPSTREAM_ENV_PRESENT=1\n'

  TARGET_CFG="${LIVE_TMP}"
fi

if [[ "${MODE}" == "repo" ]]; then
  TARGET_CFG="${SNAPSHOT_CFG}"
  if [[ -n "${VM_HOOKS_UPSTREAM:-}" ]]; then
    printf 'HOOKS_UPSTREAM_ENV_PRESENT=1\n'
  else
    fail "FORBIDDEN_MIX" "${RC_FORBIDDEN_MIX}"
  fi
fi

VAULT_TMP="$(mktemp)"
HOOKS_TMP="$(mktemp)"
MCP_TMP="$(mktemp)"

extract_block "${TARGET_CFG}" "vaultmesh.org" "${VAULT_TMP}"
extract_block "${TARGET_CFG}" "hooks.vaultmesh.org" "${HOOKS_TMP}"
extract_block "${TARGET_CFG}" "mcp.vaultmesh.org" "${MCP_TMP}"

[[ -s "${VAULT_TMP}" ]] || { rm -f "${VAULT_TMP}" "${HOOKS_TMP}" "${MCP_TMP}"; fail "MISSING_HOST_BLOCKS" "${RC_MISSING_HOST_BLOCKS}"; }
[[ -s "${HOOKS_TMP}" ]] || { rm -f "${VAULT_TMP}" "${HOOKS_TMP}" "${MCP_TMP}"; fail "MISSING_HOST_BLOCKS" "${RC_MISSING_HOST_BLOCKS}"; }
[[ -s "${MCP_TMP}" ]] || { rm -f "${VAULT_TMP}" "${HOOKS_TMP}" "${MCP_TMP}"; fail "MISSING_HOST_BLOCKS" "${RC_MISSING_HOST_BLOCKS}"; }

policy_check_vault "${VAULT_TMP}"
policy_check_hooks "${HOOKS_TMP}"
policy_check_mcp "${MCP_TMP}"

printf 'CADDY_POLICY_HOST_SPLIT_OK=1\n'
printf 'CADDY_GUARD_OK=1\n'

rm -f "${VAULT_TMP}" "${HOOKS_TMP}" "${MCP_TMP}" "${LIVE_TMP:-}"
