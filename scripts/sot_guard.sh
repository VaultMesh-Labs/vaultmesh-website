#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RC_USAGE=2
RC_MISSING_REQUIRED=10
RC_ROOT_DRIFT=11
RC_CADDY_DRIFT=12
RC_UNEXPECTED_FILES=13
RC_TOOLING_MISSING=14
RC_PERMISSION_DENIED=15
RC_BAD_MANIFEST=16

MODE="repo"

fail() {
  local reason="$1"
  local rc="$2"
  printf 'SOT_GUARD_FAIL=%s\n' "$reason"
  printf 'SOT_GUARD_RC=%s\n' "$rc"
  exit "$rc"
}

usage() {
  cat <<'USAGEEOF'
Usage:
  bash scripts/sot_guard.sh [--repo|--pre|--live]

Env overrides:
  SOT_MANIFEST_PATH
  SOT_LIVE_ROOT
  SOT_LIVE_CADDY
  SOT_REMOTE_HOST
USAGEEOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo|--pre)
      MODE="repo"
      shift
      ;;
    --live)
      MODE="live"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit "${RC_USAGE}"
      ;;
  esac
done

need() {
  command -v "$1" >/dev/null 2>&1 || fail "TOOLING_MISSING" "${RC_TOOLING_MISSING}"
}

need awk
need grep
need find
need sort
need comm

hash_of_file() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi

  fail "TOOLING_MISSING" "${RC_TOOLING_MISSING}"
}

MANIFEST_PATH="${SOT_MANIFEST_PATH:-${ROOT_DIR}/deploy/edge/MANIFEST.json}"
[[ -f "${MANIFEST_PATH}" ]] || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"

json_get_first_string() {
  local key="$1"
  awk -F'"' -v key="$key" '$2 == key { print $4; exit }' "${MANIFEST_PATH}"
}

json_get_array() {
  local key="$1"
  awk -v key="$key" '
    BEGIN { in_array=0 }
    $0 ~ "\"" key "\"[[:space:]]*:[[:space:]]*\\[" { in_array=1; next }
    in_array {
      if ($0 ~ /\]/) exit
      while (match($0, /"[^"]+"/)) {
        item = substr($0, RSTART + 1, RLENGTH - 2)
        print item
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
  ' "${MANIFEST_PATH}"
}

SCHEMA="$(json_get_first_string schema)"
CANON_ROOT_REL="$(json_get_first_string root_dir)"
CANON_CADDY_REL="$(json_get_first_string caddyfile)"
TARGET_ROOT_FROM_MANIFEST="$(json_get_first_string root_path)"
TARGET_CADDY_FROM_MANIFEST="$(json_get_first_string caddyfile_path)"
TARGET_IP_FROM_MANIFEST="$(json_get_first_string public_ip)"

[[ "${SCHEMA}" == "vaultmesh.site.sot_lock.v0" ]] || fail "BAD_MANIFEST" "${RC_BAD_MANIFEST}"
[[ -n "${CANON_ROOT_REL}" && -n "${CANON_CADDY_REL}" ]] || fail "BAD_MANIFEST" "${RC_BAD_MANIFEST}"
[[ -n "${TARGET_ROOT_FROM_MANIFEST}" && -n "${TARGET_CADDY_FROM_MANIFEST}" ]] || fail "BAD_MANIFEST" "${RC_BAD_MANIFEST}"
[[ -n "${TARGET_IP_FROM_MANIFEST}" ]] || fail "BAD_MANIFEST" "${RC_BAD_MANIFEST}"

CANON_ROOT="${ROOT_DIR}/${CANON_ROOT_REL}"
CANON_CADDY="${ROOT_DIR}/${CANON_CADDY_REL}"
LIVE_ROOT="${SOT_LIVE_ROOT:-${TARGET_ROOT_FROM_MANIFEST}}"
LIVE_CADDY="${SOT_LIVE_CADDY:-${TARGET_CADDY_FROM_MANIFEST}}"

[[ -d "${CANON_ROOT}" ]] || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"
[[ -f "${CANON_CADDY}" ]] || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"

declare -A MUTABLE_PATHS=()
declare -A MUTABLE_SYMLINKS=()

while IFS= read -r item; do
  [[ -n "${item}" ]] && MUTABLE_PATHS["${item}"]=1
done < <(json_get_array mutable_paths)

while IFS= read -r item; do
  [[ -n "${item}" ]] && MUTABLE_SYMLINKS["${item}"]=1
done < <(json_get_array mutable_symlinks)

is_mutable_path() {
  local rel="$1"

  if [[ -n "${MUTABLE_PATHS["${rel}"]+x}" ]]; then
    return 0
  fi

  local prefix
  for prefix in "${!MUTABLE_SYMLINKS[@]}"; do
    if [[ "${rel}" == "${prefix}" || "${rel}" == "${prefix}/"* ]]; then
      return 0
    fi
  done

  return 1
}

list_relative_files() {
  local dir="$1"

  find "$dir" -type f -print | sed -e "s#^${dir}/##" | sort
}

dir_digest() {
  local dir="$1"
  local tmp
  tmp="$(mktemp)"

  while IFS= read -r rel; do
    [[ -n "${rel}" ]] || continue
    if is_mutable_path "${rel}"; then
      continue
    fi

    local file_hash
    if ! file_hash="$(hash_of_file "${dir}/${rel}" 2>/dev/null)"; then
      rm -f "${tmp}"
      fail "PERMISSION_DENIED" "${RC_PERMISSION_DENIED}"
    fi

    printf '%s  %s\n' "${file_hash}" "${rel}" >> "${tmp}"
  done < <(list_relative_files "${dir}")

  local digest
  digest="$(hash_of_file "${tmp}")"
  rm -f "${tmp}"
  printf '%s\n' "${digest}"
}

canonical_root_sha="$(dir_digest "${CANON_ROOT}")"
canonical_caddy_sha="$(hash_of_file "${CANON_CADDY}")"
manifest_sha="$(hash_of_file "${MANIFEST_PATH}")"

if [[ "${MODE}" == "repo" ]]; then
  printf 'SOT_MODE=repo\n'
  printf 'SOT_ROOT_SHA256=sha256:%s\n' "${canonical_root_sha}"
  printf 'SOT_CADDY_SHA256=sha256:%s\n' "${canonical_caddy_sha}"
  printf 'SOT_MANIFEST_SHA256=sha256:%s\n' "${manifest_sha}"
  printf 'SOT_GUARD_OK=1\n'
  exit 0
fi

if [[ ! -d "${LIVE_ROOT}" || ! -f "${LIVE_CADDY}" ]]; then
  need ssh
  need rsync
  REMOTE_HOST="${SOT_REMOTE_HOST:-root@${TARGET_IP_FROM_MANIFEST}}"
  REMOTE_TMP="/tmp/vaultmesh_sot_guard_$(date -u +%Y%m%dT%H%M%SZ)"

  ssh "${REMOTE_HOST}" "mkdir -p '${REMOTE_TMP}/scripts' '${REMOTE_TMP}/deploy/edge/etc/caddy' '${REMOTE_TMP}/deploy/edge/root/vaultmesh'" >/dev/null 2>&1 || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"
  rsync -az "${ROOT_DIR}/scripts/sot_guard.sh" "${REMOTE_HOST}:${REMOTE_TMP}/scripts/sot_guard.sh" >/dev/null 2>&1 || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"
  rsync -az "${MANIFEST_PATH}" "${REMOTE_HOST}:${REMOTE_TMP}/deploy/edge/MANIFEST.json" >/dev/null 2>&1 || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"
  rsync -az "${CANON_CADDY}" "${REMOTE_HOST}:${REMOTE_TMP}/deploy/edge/etc/caddy/Caddyfile" >/dev/null 2>&1 || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"
  rsync -az --delete "${CANON_ROOT}/" "${REMOTE_HOST}:${REMOTE_TMP}/deploy/edge/root/vaultmesh/" >/dev/null 2>&1 || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"

  REMOTE_OUTPUT="$(ssh "${REMOTE_HOST}" "cd '${REMOTE_TMP}' && bash scripts/sot_guard.sh --live" 2>&1)" || {
    rc=$?
    ssh "${REMOTE_HOST}" "rm -rf '${REMOTE_TMP}'" >/dev/null 2>&1 || true
    printf '%s\n' "${REMOTE_OUTPUT}"
    exit "${rc}"
  }

  ssh "${REMOTE_HOST}" "rm -rf '${REMOTE_TMP}'" >/dev/null 2>&1 || true
  printf '%s\n' "${REMOTE_OUTPUT}"
  exit 0
fi

[[ -d "${LIVE_ROOT}" ]] || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"
[[ -f "${LIVE_CADDY}" ]] || fail "MISSING_REQUIRED" "${RC_MISSING_REQUIRED}"

if [[ ! -r "${LIVE_ROOT}" || ! -r "${LIVE_CADDY}" ]]; then
  fail "PERMISSION_DENIED" "${RC_PERMISSION_DENIED}"
fi

live_list="$(mktemp)"
canon_list="$(mktemp)"

while IFS= read -r rel; do
  [[ -n "${rel}" ]] || continue
  if is_mutable_path "${rel}"; then
    continue
  fi
  printf '%s\n' "${rel}" >> "${canon_list}"
done < <(list_relative_files "${CANON_ROOT}")

while IFS= read -r rel; do
  [[ -n "${rel}" ]] || continue
  if is_mutable_path "${rel}"; then
    continue
  fi
  printf '%s\n' "${rel}" >> "${live_list}"
done < <(list_relative_files "${LIVE_ROOT}")

sort -u -o "${canon_list}" "${canon_list}"
sort -u -o "${live_list}" "${live_list}"

if [[ -n "$(comm -13 "${canon_list}" "${live_list}")" ]]; then
  rm -f "${live_list}" "${canon_list}"
  fail "UNEXPECTED_FILES" "${RC_UNEXPECTED_FILES}"
fi

rm -f "${live_list}" "${canon_list}"

live_root_sha="$(dir_digest "${LIVE_ROOT}")"
live_caddy_sha="$(hash_of_file "${LIVE_CADDY}")"

if [[ "${live_root_sha}" != "${canonical_root_sha}" ]]; then
  fail "ROOT_DRIFT" "${RC_ROOT_DRIFT}"
fi

if [[ "${live_caddy_sha}" != "${canonical_caddy_sha}" ]]; then
  fail "CADDY_DRIFT" "${RC_CADDY_DRIFT}"
fi

printf 'SOT_MODE=live\n'
printf 'SOT_ROOT_SHA256=sha256:%s\n' "${live_root_sha}"
printf 'SOT_CADDY_SHA256=sha256:%s\n' "${live_caddy_sha}"
printf 'SOT_MANIFEST_SHA256=sha256:%s\n' "${manifest_sha}"
printf 'SOT_GUARD_OK=1\n'
