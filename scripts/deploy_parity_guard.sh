#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_lib/routes_required.sh
source "${SCRIPT_DIR}/_lib/routes_required.sh"

RC_USAGE=10
RC_PREREQ=11
RC_PARITY=20
RC_OK=0

REPO="."
DIST_REL="dist"
SNAPSHOT_REL="deploy/edge/root/vaultmesh"
ROUTES_CSV="${VM_ROUTES_REQUIRED_CSV}"
OUT_JSON_REL="reports/deploy_parity_guard_v1.json"
LAST_OK_JSON_REL="${LAST_OK_JSON_REL:-reports/deploy_parity_guard_v1.LAST_OK.json}"
BUILD_INFO_REL="${BUILD_INFO_REL:-${VM_BUILD_INFO_PATH}}"

usage() {
  cat <<'USAGEEOF'
Usage:
  bash scripts/deploy_parity_guard.sh [options]

Options:
  --repo <path>            Repository root (default: .)
  --dist <path>            Dist path relative to repo (default: dist)
  --snapshot-root <path>   Snapshot root relative to repo (default: deploy/edge/root/vaultmesh)
  --routes <csv>           Comma-separated route file list
  --out-json <path>        JSON report output path relative to repo (default: reports/deploy_parity_guard_v1.json)
  -h, --help               Show this help
USAGEEOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ -n "${2:-}" ]] || { usage; exit "${RC_USAGE}"; }
      REPO="$2"
      shift 2
      ;;
    --dist)
      [[ -n "${2:-}" ]] || { usage; exit "${RC_USAGE}"; }
      DIST_REL="$2"
      shift 2
      ;;
    --snapshot-root)
      [[ -n "${2:-}" ]] || { usage; exit "${RC_USAGE}"; }
      SNAPSHOT_REL="$2"
      shift 2
      ;;
    --routes)
      [[ -n "${2:-}" ]] || { usage; exit "${RC_USAGE}"; }
      ROUTES_CSV="$2"
      shift 2
      ;;
    --out-json)
      [[ -n "${2:-}" ]] || { usage; exit "${RC_USAGE}"; }
      OUT_JSON_REL="$2"
      shift 2
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

if [[ ! -d "${REPO}" ]]; then
  usage
  exit "${RC_USAGE}"
fi

REPO_ABS="$(cd "${REPO}" && pwd)"
OUT_JSON_ABS="${REPO_ABS}/${OUT_JSON_REL}"
LAST_OK_JSON_ABS="${REPO_ABS}/${LAST_OK_JSON_REL}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

hash_file() {
  local f="$1"
  if need_cmd sha256sum; then
    sha256sum "$f" | awk '{print $1}'
    return
  fi
  shasum -a 256 "$f" | awk '{print $1}'
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_bool() {
  if [[ "$1" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

write_prereq_fail_json() {
  local missing="$1"
  mkdir -p "$(dirname "${OUT_JSON_ABS}")"
  cat > "${OUT_JSON_ABS}" <<EOF
{
  "kind": "vaultmesh.website.deploy_parity_guard.v1",
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo": "${REPO_ABS}",
  "dist": "${DIST_REL}",
  "snapshot_root": "${SNAPSHOT_REL}",
  "build_info": {
    "dist_exists": false,
    "snapshot_exists": false,
    "dist_sha256": "",
    "snapshot_sha256": "",
    "dist_build_run_id": "",
    "snapshot_build_run_id": "",
    "match": false
  },
  "routes": [],
  "dist_tree_sha256": "",
  "snapshot_tree_sha256": "",
  "status": "fail",
  "rc": ${RC_PREREQ},
  "failures": ["missing_prereq:${missing}"]
}
EOF
}

if ! need_cmd awk || ! need_cmd date || ! need_cmd mktemp; then
  write_prereq_fail_json "awk/date/mktemp"
  printf 'DEPLOY_PARITY_FAIL rc=%s out_json=%s failures=%s\n' "${RC_PREREQ}" "${OUT_JSON_REL}" "1"
  exit "${RC_PREREQ}"
fi

if ! need_cmd sha256sum && ! need_cmd shasum; then
  write_prereq_fail_json "sha256sum_or_shasum"
  printf 'DEPLOY_PARITY_FAIL rc=%s out_json=%s failures=%s\n' "${RC_PREREQ}" "${OUT_JSON_REL}" "1"
  exit "${RC_PREREQ}"
fi

DIST_DIR="${REPO_ABS}/${DIST_REL}"
SNAPSHOT_DIR="${REPO_ABS}/${SNAPSHOT_REL}"
DIST_BUILD_INFO="${DIST_DIR}/${BUILD_INFO_REL}"
SNAPSHOT_BUILD_INFO="${SNAPSHOT_DIR}/${BUILD_INFO_REL}"

generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

IFS=',' read -r -a ROUTES <<< "${ROUTES_CSV}"
if [[ "${#ROUTES[@]}" -eq 0 ]]; then
  usage
  exit "${RC_USAGE}"
fi

route_tmp="$(mktemp)"
dist_tree_tmp="$(mktemp)"
snapshot_tree_tmp="$(mktemp)"
trap 'rm -f "$route_tmp" "$dist_tree_tmp" "$snapshot_tree_tmp"' EXIT

failures=()
failure_count=0

build_info_dist_exists=0
build_info_snapshot_exists=0
build_info_dist_sha=""
build_info_snapshot_sha=""
build_info_dist_run_id=""
build_info_snapshot_run_id=""
build_info_match=0

json_get_string() {
  local file="$1"
  local key="$2"
  awk -F'"' -v key="$key" '$2 == key { print $4; exit }' "$file"
}

if [[ -f "${DIST_BUILD_INFO}" ]]; then
  build_info_dist_exists=1
  build_info_dist_sha="sha256:$(hash_file "${DIST_BUILD_INFO}")"
  build_info_dist_run_id="$(json_get_string "${DIST_BUILD_INFO}" "build_run_id" || true)"
fi

if [[ -f "${SNAPSHOT_BUILD_INFO}" ]]; then
  build_info_snapshot_exists=1
  build_info_snapshot_sha="sha256:$(hash_file "${SNAPSHOT_BUILD_INFO}")"
  build_info_snapshot_run_id="$(json_get_string "${SNAPSHOT_BUILD_INFO}" "build_run_id" || true)"
fi

if [[ "${build_info_dist_exists}" -eq 1 && "${build_info_snapshot_exists}" -eq 1 ]]; then
  if [[ "${build_info_dist_sha}" == "${build_info_snapshot_sha}" ]]; then
    build_info_match=1
  fi
fi

if [[ "${build_info_dist_exists}" -eq 0 ]]; then
  failures+=("missing_dist:${BUILD_INFO_REL}")
  failure_count=$((failure_count + 1))
fi
if [[ "${build_info_snapshot_exists}" -eq 0 ]]; then
  failures+=("missing_snapshot:${BUILD_INFO_REL}")
  failure_count=$((failure_count + 1))
fi
if [[ "${build_info_dist_exists}" -eq 1 && "${build_info_snapshot_exists}" -eq 1 ]]; then
  if [[ "${build_info_match}" -eq 0 || "${build_info_dist_run_id}" != "${build_info_snapshot_run_id}" ]]; then
    failures+=("freshness_mismatch:${BUILD_INFO_REL}")
    failure_count=$((failure_count + 1))
  fi
fi

printf '[\n' > "$route_tmp"
first_route=1

for route in "${ROUTES[@]}"; do
  route="${route#"${route%%[![:space:]]*}"}"
  route="${route%"${route##*[![:space:]]}"}"
  [[ -n "${route}" ]] || continue

  dist_file="${DIST_DIR}/${route}"
  snapshot_file="${SNAPSHOT_DIR}/${route}"

  dist_exists=0
  snapshot_exists=0
  dist_sha=""
  snapshot_sha=""
  match=0

  if [[ -f "${dist_file}" ]]; then
    dist_exists=1
    dist_sha="sha256:$(hash_file "${dist_file}")"
  fi

  if [[ -f "${snapshot_file}" ]]; then
    snapshot_exists=1
    snapshot_sha="sha256:$(hash_file "${snapshot_file}")"
  fi

  if [[ "${dist_exists}" -eq 1 && "${snapshot_exists}" -eq 1 && "${dist_sha}" == "${snapshot_sha}" ]]; then
    match=1
  fi

  if [[ "${dist_exists}" -eq 0 ]]; then
    failures+=("missing_dist:${route}")
    failure_count=$((failure_count + 1))
  fi
  if [[ "${snapshot_exists}" -eq 0 ]]; then
    failures+=("missing_snapshot:${route}")
    failure_count=$((failure_count + 1))
  fi
  if [[ "${dist_exists}" -eq 1 && "${snapshot_exists}" -eq 1 && "${match}" -eq 0 ]]; then
    failures+=("hash_mismatch:${route}")
    failure_count=$((failure_count + 1))
  fi

  if [[ "${dist_exists}" -eq 1 ]]; then
    printf '%s  %s\n' "${dist_sha}" "${route}" >> "$dist_tree_tmp"
  else
    printf 'MISSING  %s\n' "${route}" >> "$dist_tree_tmp"
  fi

  if [[ "${snapshot_exists}" -eq 1 ]]; then
    printf '%s  %s\n' "${snapshot_sha}" "${route}" >> "$snapshot_tree_tmp"
  else
    printf 'MISSING  %s\n' "${route}" >> "$snapshot_tree_tmp"
  fi

  [[ "${first_route}" -eq 1 ]] || printf ',\n' >> "$route_tmp"
  first_route=0

  printf '  {\n' >> "$route_tmp"
  printf '    "file": "%s",\n' "$(json_escape "${route}")" >> "$route_tmp"
  printf '    "dist_exists": %s,\n' "$(json_bool "${dist_exists}")" >> "$route_tmp"
  printf '    "snapshot_exists": %s,\n' "$(json_bool "${snapshot_exists}")" >> "$route_tmp"
  printf '    "dist_sha256": "%s",\n' "$(json_escape "${dist_sha}")" >> "$route_tmp"
  printf '    "snapshot_sha256": "%s",\n' "$(json_escape "${snapshot_sha}")" >> "$route_tmp"
  printf '    "match": %s\n' "$(json_bool "${match}")" >> "$route_tmp"
  printf '  }' >> "$route_tmp"
done

printf '\n]\n' >> "$route_tmp"

if [[ -s "${dist_tree_tmp}" ]]; then
  dist_tree_sha256="sha256:$(hash_file "${dist_tree_tmp}")"
else
  dist_tree_sha256=""
fi

if [[ -s "${snapshot_tree_tmp}" ]]; then
  snapshot_tree_sha256="sha256:$(hash_file "${snapshot_tree_tmp}")"
else
  snapshot_tree_sha256=""
fi

status="pass"
rc="${RC_OK}"
if [[ "${failure_count}" -gt 0 ]]; then
  status="fail"
  rc="${RC_PARITY}"
fi

mkdir -p "$(dirname "${OUT_JSON_ABS}")"

{
  printf '{\n'
  printf '  "kind": "vaultmesh.website.deploy_parity_guard.v1",\n'
  printf '  "generated_at_utc": "%s",\n' "$(json_escape "${generated_at_utc}")"
  printf '  "repo": "%s",\n' "$(json_escape "${REPO_ABS}")"
  printf '  "dist": "%s",\n' "$(json_escape "${DIST_REL}")"
  printf '  "snapshot_root": "%s",\n' "$(json_escape "${SNAPSHOT_REL}")"
  printf '  "build_info": {\n'
  printf '    "dist_exists": %s,\n' "$(json_bool "${build_info_dist_exists}")"
  printf '    "snapshot_exists": %s,\n' "$(json_bool "${build_info_snapshot_exists}")"
  printf '    "dist_sha256": "%s",\n' "$(json_escape "${build_info_dist_sha}")"
  printf '    "snapshot_sha256": "%s",\n' "$(json_escape "${build_info_snapshot_sha}")"
  printf '    "dist_build_run_id": "%s",\n' "$(json_escape "${build_info_dist_run_id}")"
  printf '    "snapshot_build_run_id": "%s",\n' "$(json_escape "${build_info_snapshot_run_id}")"
  printf '    "match": %s\n' "$(json_bool "${build_info_match}")"
  printf '  },\n'
  printf '  "routes": '
  cat "$route_tmp"
  printf '  ,\n'
  printf '  "dist_tree_sha256": "%s",\n' "$(json_escape "${dist_tree_sha256}")"
  printf '  "snapshot_tree_sha256": "%s",\n' "$(json_escape "${snapshot_tree_sha256}")"
  printf '  "status": "%s",\n' "${status}"
  printf '  "rc": %s,\n' "${rc}"
  printf '  "failures": ['
  if [[ "${#failures[@]}" -gt 0 ]]; then
    for i in "${!failures[@]}"; do
      [[ "$i" -eq 0 ]] || printf ', '
      printf '"%s"' "$(json_escape "${failures[$i]}")"
    done
  fi
  printf ']\n'
  printf '}\n'
} > "${OUT_JSON_ABS}"

if [[ "${rc}" -eq 0 ]]; then
  mkdir -p "$(dirname "${LAST_OK_JSON_ABS}")"
  {
    printf '{\n'
    printf '  "kind": "vaultmesh.website.deploy_parity_guard.last_ok.v1",\n'
    printf '  "generated_at_utc": "%s",\n' "$(json_escape "${generated_at_utc}")"
    printf '  "build_run_id": "%s",\n' "$(json_escape "${build_info_dist_run_id}")"
    printf '  "dist_tree_sha256": "%s",\n' "$(json_escape "${dist_tree_sha256}")"
    printf '  "snapshot_tree_sha256": "%s",\n' "$(json_escape "${snapshot_tree_sha256}")"
    printf '  "report_path": "%s"\n' "$(json_escape "${OUT_JSON_REL}")"
    printf '}\n'
  } > "${LAST_OK_JSON_ABS}"
  printf 'DEPLOY_PARITY_OK out_json=%s\n' "${OUT_JSON_REL}"
else
  rm -f "${LAST_OK_JSON_ABS}" || true
  printf 'DEPLOY_PARITY_FAIL rc=%s out_json=%s failures=%s\n' "${rc}" "${OUT_JSON_REL}" "${failure_count}"
fi

exit "${rc}"
