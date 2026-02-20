#!/usr/bin/env bash
set -euo pipefail

# CADDY_GUARD_v0
# Goal: prevent drift where public routes become origin-dependent again.

CFG="${CADDYFILE_PATH:-/etc/caddy/Caddyfile}"
SITE_ROOT_LOCK="${CADDY_SITE_ROOT_LOCK:-/srv/web/vaultmesh}"
ALLOW_CC_REVERSE_PROXY="${CADDY_ALLOW_CC_REVERSE_PROXY:-1}"
# Allowed context markers in the preceding lines for reverse_proxy within vaultmesh.org.
ALLOWED_PROXY_CONTEXT_REGEX="${CADDY_ALLOWED_REVERSE_PROXY_CONTEXT_REGEX:-/cc/[*]|@origin_gateway}"

# Exit codes (CI-friendly)
RC_USAGE=2
RC_MISSING=11
RC_TOOLING=12
RC_VALIDATE_FAIL=21
RC_ROOT_LOCK_FAIL=31
RC_STATIC_LOCK_FAIL=32
RC_CC_PROXY_POLICY_FAIL=33

say() { printf "%s\n" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { say "CADDY_GUARD_FAIL missing_tool=$1"; exit "$RC_TOOLING"; }
}

sha256_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf "sha256:%s" "$(sha256sum "$f" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    printf "sha256:%s" "$(shasum -a 256 "$f" | awk '{print $1}')"
  else
    say "CADDY_GUARD_FAIL missing_tool=sha256sum_or_shasum"
    exit "$RC_TOOLING"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  scripts/caddy_guard.sh [--config /path/to/Caddyfile]

Env:
  CADDYFILE_PATH=/etc/caddy/Caddyfile
  CADDY_SITE_ROOT_LOCK=/srv/web/vaultmesh
  CADDY_ALLOW_CC_REVERSE_PROXY=1|0
  CADDY_ALLOWED_REVERSE_PROXY_CONTEXT_REGEX=/cc/[*]|@origin_gateway
EOF
}

if [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi
if [[ "${1:-}" == "--config" ]]; then
  [[ -n "${2:-}" ]] || { usage; exit "$RC_USAGE"; }
  CFG="$2"
  shift 2
fi
if [[ $# -ne 0 ]]; then usage; exit "$RC_USAGE"; fi

[[ -f "$CFG" ]] || { say "CADDY_GUARD_MISSING file=$CFG"; exit "$RC_MISSING"; }

need_cmd caddy
need_cmd awk
need_cmd grep

say "CADDY_GUARD_PRESENT=1"
CFG_SHA="$(sha256_file "$CFG")"
say "CADDY_GUARD_SHA256=$CFG_SHA"

if ! caddy validate --config "$CFG" >/dev/null 2>&1; then
  say "CADDY_GUARD_INVALID_CONFIG=1"
  say "CADDY_GUARD_FAIL reason=validate_failed"
  exit "$RC_VALIDATE_FAIL"
fi
say "CADDY_GUARD_VALIDATE_OK=1"

VAULT_TMP="$(mktemp)"
awk '
  BEGIN{inblk=0; depth=0}
  {
    line=$0
    if (!inblk && line ~ /^[[:space:]]*vaultmesh\.org[[:space:]]*\{/) {
      inblk=1
    }
    if (inblk) {
      print line
      opens=gsub(/\{/, "{", line)
      closes=gsub(/\}/, "}", line)
      depth += opens - closes
      if (depth<=0) exit
    }
  }
' "$CFG" > "$VAULT_TMP"

if [[ ! -s "$VAULT_TMP" ]]; then
  rm -f "$VAULT_TMP"
  say "CADDY_GUARD_ROOT_LOCK_FAIL=1"
  say "CADDY_GUARD_FAIL reason=vaultmesh_block_not_found"
  exit "$RC_ROOT_LOCK_FAIL"
fi

if ! grep -Eq "^[[:space:]]*root[[:space:]]+\\*[[:space:]]+${SITE_ROOT_LOCK}([[:space:]]|$)" "$VAULT_TMP"; then
  rm -f "$VAULT_TMP"
  say "CADDY_GUARD_ROOT_LOCK_FAIL=1"
  say "CADDY_GUARD_FAIL reason=root_lock_missing expected=$SITE_ROOT_LOCK"
  exit "$RC_ROOT_LOCK_FAIL"
fi
say "CADDY_GUARD_ROOT_LOCK_OK=1"

if ! awk '
  function brace_delta(s, t, opens, closes) {
    t=s
    opens=gsub(/\{/, "{", t)
    t=s
    closes=gsub(/\}/, "}", t)
    return opens-closes
  }
  BEGIN{
    bad=0
    in_def=0
    in_handle=0
    in_handle_path=0
    def_depth=0
    handle_depth=0
    handle_path_depth=0
    handle_proxy=0
    handle_path_proxy=0
    def_name=""
    handle_name=""
    forbidden="(^|[[:space:]])/(proof-pack|support)(/\\*|/)?([[:space:]]|$)"
  }
  {
    line=$0
    if (!in_def && match(line, /^[[:space:]]*@([A-Za-z0-9_]+)[[:space:]]*\{/, m)) {
      in_def=1
      def_name=m[1]
      def_depth=brace_delta(line)
      def_body[def_name]=def_body[def_name] line "\n"
      next
    }
    if (in_def) {
      def_body[def_name]=def_body[def_name] line "\n"
      def_depth += brace_delta(line)
      if (def_depth<=0) {
        in_def=0
        def_name=""
      }
      next
    }

    if (!in_handle && match(line, /^[[:space:]]*handle[[:space:]]+@([A-Za-z0-9_]+)[[:space:]]*\{/, m)) {
      in_handle=1
      handle_name=m[1]
      handle_depth=brace_delta(line)
      handle_proxy=0
      next
    }
    if (in_handle) {
      if (line ~ /reverse_proxy/) handle_proxy=1
      handle_depth += brace_delta(line)
      if (handle_depth<=0) {
        if (handle_proxy) {
          proxy_handle[++proxy_count]=handle_name
        }
        in_handle=0
        handle_name=""
      }
      next
    }

    if (!in_handle_path && match(line, /^[[:space:]]*handle_path[[:space:]]+(\/proof-pack\/\*|\/support\/\*)[[:space:]]*\{/, m)) {
      in_handle_path=1
      handle_path_name=m[1]
      handle_path_depth=brace_delta(line)
      handle_path_proxy=0
      next
    }
    if (in_handle_path) {
      if (line ~ /reverse_proxy/) handle_path_proxy=1
      handle_path_depth += brace_delta(line)
      if (handle_path_depth<=0) {
        if (handle_path_proxy) bad=1
        in_handle_path=0
        handle_path_name=""
      }
      next
    }
  }
  END{
    for (i=1; i<=proxy_count; i++) {
      name=proxy_handle[i]
      body=def_body[name]
      if (body ~ forbidden) bad=1
    }
    exit(bad?1:0)
  }
' "$VAULT_TMP"; then
  rm -f "$VAULT_TMP"
  say "CADDY_GUARD_PUBLIC_PROXY_FAIL=1"
  say "CADDY_GUARD_FAIL reason=public_static_paths_proxy_detected"
  exit "$RC_STATIC_LOCK_FAIL"
fi
say "CADDY_GUARD_PROOF_PACK_STATIC_OK=1"
say "CADDY_GUARD_SUPPORT_STATIC_OK=1"

if [[ "$ALLOW_CC_REVERSE_PROXY" == "1" ]]; then
  if ! awk -v allowed="$ALLOWED_PROXY_CONTEXT_REGEX" '
    BEGIN{bad=0}
    {line[NR]=$0}
    END{
      for(i=1;i<=NR;i++){
        if(line[i] ~ /reverse_proxy/){
          ok=0
          for(j=i-8;j<=i;j++){
            if(j>=1 && line[j] ~ allowed){ok=1}
          }
          if(!ok) bad=1
        }
      }
      exit(bad?1:0)
    }
  ' "$VAULT_TMP"; then
    rm -f "$VAULT_TMP"
    say "CADDY_GUARD_CC_PROXY_POLICY_FAIL=1"
    say "CADDY_GUARD_FAIL reason=reverse_proxy_found_outside_allowed_context"
    exit "$RC_CC_PROXY_POLICY_FAIL"
  fi
  say "CADDY_GUARD_CC_PROXY_OK=1"
else
  if grep -n "reverse_proxy" "$VAULT_TMP" >/dev/null 2>&1; then
    rm -f "$VAULT_TMP"
    say "CADDY_GUARD_CC_PROXY_POLICY_FAIL=1"
    say "CADDY_GUARD_FAIL reason=reverse_proxy_forbidden"
    exit "$RC_CC_PROXY_POLICY_FAIL"
  fi
  say "CADDY_GUARD_CC_PROXY_OK=1"
fi

rm -f "$VAULT_TMP"
say "CADDY_GUARD_OK=1"
