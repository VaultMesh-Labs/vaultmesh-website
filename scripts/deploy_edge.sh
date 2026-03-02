#!/usr/bin/env bash
set -euo pipefail

################################################################################
# DEPLOY CONTRACT v1 — Static Site Sync Invariants
#
# This file codifies the deployment invariants for the VaultMesh public surface
# (static HTML/CSS, no JS, edge-1 artifact layer). Any future edits to this
# script must preserve these invariants.
#
# 1) CHECKSUM-BASED SYNC
#    All static artifacts under dist/ must be synced using checksum compare.
#    Because build.sh normalizes mtimes to 2020-01-01, relying on mtime+size
#    will silently skip updated content whose byte-length did not change.
#    Therefore every rsync that copies built output MUST include -c.
#
#    Pattern:  rsync -ac --delete "${DEPLOY_RSYNC_EXCLUDES[@]}" [src] [dst]
#
#    DO NOT remove the -c flag or replace it with size/mtime-only logic.
#
# 2) SINGLE EXCLUDE SET
#    DEPLOY_RSYNC_EXCLUDES is the sole source of truth for paths excluded
#    from both the canonical-snapshot sync AND the drift check.  Diverging
#    exclude lists cause false-positive drift or missed drift detection.
#
#    The array must reflect:
#      - OS noise (.DS_Store)
#      - Mutable runtime paths from MANIFEST.json allowlist
#      - Symlink targets managed outside the build
#
#    DO NOT add excludes inline at individual rsync call sites.
#    Update the single array below, nowhere else.
#
################################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=scripts/_lib/routes_required.sh
source "${ROOT_DIR}/scripts/_lib/routes_required.sh"

################################################################################
# RSYNC EXCLUDE LIST — single source for deploy sync + drift checks.
# Mutable runtime paths from MANIFEST.json allowlist plus OS noise.
# Add new excludes ONLY HERE.
################################################################################
DEPLOY_RSYNC_EXCLUDES=(
  --exclude '.DS_Store'
  --exclude 'attest/attest.json'
  --exclude 'attest/LATEST.txt'
  --exclude 'shared/'
)

# Runtime guard — fails loud if this variable is unset or empty.
: "${DEPLOY_RSYNC_EXCLUDES:?DEPLOY_RSYNC_EXCLUDES not defined — contract violated}"

RC_PRECHECK=20
RC_STAGING_UPLOAD=21
RC_REMOTE_VERIFY=22
RC_PROMOTE=23
RC_CADDY_VALIDATE=24
RC_CADDY_RELOAD=25
RC_POSTCHECK=26
RC_LEDGER_APPEND=27

fail() {
  local reason="$1"
  local rc="$2"
  printf 'DEPLOY_FAIL=%s\n' "$reason"
  printf 'DEPLOY_RC=%s\n' "$rc"
  exit "$rc"
}

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
  fail "PRECHECK_FAIL" "${RC_PRECHECK}"
}

MANIFEST="deploy/edge/MANIFEST.json"
[[ -f "${MANIFEST}" ]] || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

json_get_first_string() {
  local key="$1"
  awk -F'"' -v key="$key" '$2 == key { print $4; exit }' "${MANIFEST}"
}

TARGET_HOST_ALIAS="$(json_get_first_string host_alias)"
TARGET_PUBLIC_IP="$(json_get_first_string public_ip)"
TARGET_ROOT="$(json_get_first_string root_path)"
TARGET_CADDY="$(json_get_first_string caddyfile_path)"
CANON_ROOT_REL="$(json_get_first_string root_dir)"
CANON_CADDY_REL="$(json_get_first_string caddyfile)"

[[ -n "${TARGET_HOST_ALIAS}" && -n "${TARGET_ROOT}" && -n "${TARGET_CADDY}" && -n "${CANON_ROOT_REL}" && -n "${CANON_CADDY_REL}" ]] || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

CANON_ROOT="${ROOT_DIR}/${CANON_ROOT_REL}"
CANON_CADDY="${ROOT_DIR}/${CANON_CADDY_REL}"
[[ -d "${CANON_ROOT}" ]] || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
[[ -f "${CANON_CADDY}" ]] || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

REMOTE_HOST="${REMOTE_HOST:-root@${TARGET_PUBLIC_IP}}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_STAGE="${TARGET_ROOT}.__staging_${TS}"
REMOTE_OLD="${TARGET_ROOT}.__old_${TS}"
REMOTE_SOT_TMP="/tmp/vaultmesh_sot_${TS}"
BUILD_INFO_FILE="${ROOT_DIR}/dist/${VM_BUILD_INFO_PATH}"
PARITY_LAST_OK_FILE="${ROOT_DIR}/${LAST_OK_JSON_REL:-reports/deploy_parity_guard_v1.LAST_OK.json}"
RELEASE_ATTEST_CANON="${CANON_ROOT}/attest/RELEASE_ATTEST.json"
RELEASE_ATTEST_STAGE="${ROOT_DIR}/dist/site/attest/RELEASE_ATTEST.json"
RELEASE_TARGET_ID="${TARGET_HOST_ALIAS}:vaultmesh-root"
RELEASE_BASE_URL="${SITE_BASE_URL:-https://vaultmesh.org}"

json_get_first_string_file() {
  local file="$1"
  local key="$2"
  awk -F'"' -v key="$key" '$2 == key { print $4; exit }' "${file}"
}

./build.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/ui_contract_check.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/lane_width_lock.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/color_lock_check.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/footer_contract_check.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/home_surface_check.sh "dist/index.html" >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/route_identity_check.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/page_kind_check.sh dist scripts/contracts/kind_map.v1.tsv >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/attest_surface_check.sh dist >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/support_open_surface_check.sh dist >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/support_open_ui_scale_check.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/proof_pack_intake_surface_check.sh dist >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/proof_pack_intake_ui_contract_check.sh dist >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/form_skin_contract_check.sh dist >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/proof_pack_surface_check.sh dist >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/pricing_ui_order_lock.sh dist/pricing/index.html >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/pricing_ui_contract_check.sh >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/offer_surface_check.sh dist/offer/index.html >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/verify_surface_check.sh dist/verify/index.html >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/status_surface_check.sh dist/status/index.html >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
bash scripts/contracts/attest_lane_check.sh dist/attest/index.html >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

rm -rf dist/site
mkdir -p dist/site
rsync -a --delete --exclude '.DS_Store' --exclude 'site/' dist/ dist/site/ || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

# Verify all required routes exist in the build output.
IFS=',' read -r -a GUARD_ROUTES <<< "${VM_ROUTES_REQUIRED_CSV}"
for route in "${GUARD_ROUTES[@]}"; do
  route="${route#"${route%%[![:space:]]*}"}"
  route="${route%"${route##*[![:space:]]}"}"
  [[ -n "${route}" ]] || continue
  [[ -f "dist/site/${route}" ]] || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
done

# Sync canonical snapshot from current build.
# The deploy drift check (below) then validates this sync is clean.
rsync -ac --delete "${DEPLOY_RSYNC_EXCLUDES[@]}" dist/site/ "${CANON_ROOT}/" || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

bash scripts/deploy_parity_guard.sh || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

[[ -f "${BUILD_INFO_FILE}" ]] || fail "GUARD_NOT_FOR_CURRENT_BUILD" "${RC_PRECHECK}"
[[ -f "${PARITY_LAST_OK_FILE}" ]] || fail "GUARD_NOT_FOR_CURRENT_BUILD" "${RC_PRECHECK}"
DIST_BUILD_RUN_ID="$(json_get_first_string_file "${BUILD_INFO_FILE}" "build_run_id")"
LAST_OK_BUILD_RUN_ID="$(json_get_first_string_file "${PARITY_LAST_OK_FILE}" "build_run_id")"
if [[ -z "${DIST_BUILD_RUN_ID}" || -z "${LAST_OK_BUILD_RUN_ID}" || "${DIST_BUILD_RUN_ID}" != "${LAST_OK_BUILD_RUN_ID}" ]]; then
  fail "GUARD_NOT_FOR_CURRENT_BUILD" "${RC_PRECHECK}"
fi

# --- ATTEST DEPLOY LAYER v1 ---
bash scripts/deploy_release_attest.sh \
  --dist-build-info "${BUILD_INFO_FILE}" \
  --deploy-root "${CANON_ROOT}" \
  --deploy-target-id "${RELEASE_TARGET_ID}" \
  --deploy-host "${TARGET_HOST_ALIAS}" \
  --base-url "${RELEASE_BASE_URL}" \
  --caddyfile "${CANON_CADDY}" \
  --out-json "${RELEASE_ATTEST_CANON}" \
  >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

mkdir -p "$(dirname "${RELEASE_ATTEST_STAGE}")"
cp "${RELEASE_ATTEST_CANON}" "${RELEASE_ATTEST_STAGE}" || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

ATTEST_TREE="$(json_get_first_string_file "${RELEASE_ATTEST_CANON}" "deployed_root_tree_sha256")"
[[ -n "${ATTEST_TREE}" ]] || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

TMP_ATTEST="$(mktemp)"
bash scripts/deploy_release_attest.sh \
  --dist-build-info "${BUILD_INFO_FILE}" \
  --deploy-root "${CANON_ROOT}" \
  --deploy-target-id "${RELEASE_TARGET_ID}" \
  --deploy-host "${TARGET_HOST_ALIAS}" \
  --base-url "${RELEASE_BASE_URL}" \
  --caddyfile "${CANON_CADDY}" \
  --out-json "${TMP_ATTEST}" \
  >/dev/null || { rm -f "${TMP_ATTEST}" || true; fail "PRECHECK_FAIL" "${RC_PRECHECK}"; }

RECOMP_TREE="$(json_get_first_string_file "${TMP_ATTEST}" "deployed_root_tree_sha256")"
rm -f "${TMP_ATTEST}" || true

if [[ -z "${RECOMP_TREE}" || "${ATTEST_TREE}" != "${RECOMP_TREE}" ]]; then
  printf 'DEPLOY_ATTEST_GUARD_FAIL expected=%s recomputed=%s\n' "${ATTEST_TREE}" "${RECOMP_TREE}" >&2
  fail "PRECHECK_FAIL" "${RC_PRECHECK}"
fi
# --- end ATTEST DEPLOY LAYER v1 ---

bash scripts/sot_guard.sh --pre >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"
VM_HOOKS_UPSTREAM=127.0.0.1:65535 bash scripts/caddy_guard.sh --repo-snapshot deploy/edge/etc/caddy/Caddyfile >/dev/null || fail "PRECHECK_FAIL" "${RC_PRECHECK}"

DRIFT_CHECK="$(rsync -rcni --delete \
  "${DEPLOY_RSYNC_EXCLUDES[@]}" \
  dist/site/ "${CANON_ROOT}/" || true)"
if [[ -n "${DRIFT_CHECK}" ]]; then
  fail "PRECHECK_FAIL" "${RC_PRECHECK}"
fi

ssh "${REMOTE_HOST}" "mkdir -p '${REMOTE_STAGE}'" >/dev/null 2>&1 || fail "STAGING_UPLOAD_FAIL" "${RC_STAGING_UPLOAD}"
rsync -azc --delete dist/site/ "${REMOTE_HOST}:${REMOTE_STAGE}/" >/dev/null 2>&1 || fail "STAGING_UPLOAD_FAIL" "${RC_STAGING_UPLOAD}"

LOCAL_STAGE_MANIFEST_SHA="$(hash_of_file dist/site/MANIFEST.sha256)"
REMOTE_STAGE_MANIFEST_SHA="$(ssh "${REMOTE_HOST}" "sha256sum '${REMOTE_STAGE}/MANIFEST.sha256' 2>/dev/null || shasum -a 256 '${REMOTE_STAGE}/MANIFEST.sha256'" | awk '{print $1}' || true)"

if [[ -z "${REMOTE_STAGE_MANIFEST_SHA}" || "${LOCAL_STAGE_MANIFEST_SHA}" != "${REMOTE_STAGE_MANIFEST_SHA}" ]]; then
  fail "REMOTE_VERIFY_FAIL" "${RC_REMOTE_VERIFY}"
fi

if ! ssh "${REMOTE_HOST}" "set -e; systemctl show caddy --property=Environment --value | tr ' ' '\n' | grep -q '^VM_HOOKS_UPSTREAM='"; then
  fail "PRECHECK_FAIL" "${RC_PRECHECK}"
fi

ssh "${REMOTE_HOST}" "set -euo pipefail; if [[ -e '${TARGET_ROOT}' ]]; then rm -rf '${REMOTE_OLD}'; mv '${TARGET_ROOT}' '${REMOTE_OLD}'; fi; mv '${REMOTE_STAGE}' '${TARGET_ROOT}'" >/dev/null 2>&1 || fail "PROMOTE_FAIL" "${RC_PROMOTE}"

rsync -az "${CANON_CADDY}" "${REMOTE_HOST}:/tmp/vaultmesh_caddy_${TS}" >/dev/null 2>&1 || fail "CADDY_VALIDATE_FAIL" "${RC_CADDY_VALIDATE}"
ssh "${REMOTE_HOST}" "cp '/tmp/vaultmesh_caddy_${TS}' '${TARGET_CADDY}'" >/dev/null 2>&1 || fail "CADDY_VALIDATE_FAIL" "${RC_CADDY_VALIDATE}"

ssh "${REMOTE_HOST}" "caddy validate --config '${TARGET_CADDY}' >/dev/null" >/dev/null 2>&1 || fail "CADDY_VALIDATE_FAIL" "${RC_CADDY_VALIDATE}"
ssh "${REMOTE_HOST}" "systemctl reload caddy" >/dev/null 2>&1 || fail "CADDY_RELOAD_FAIL" "${RC_CADDY_RELOAD}"
bash scripts/caddy_guard.sh --live --repo-snapshot deploy/edge/etc/caddy/Caddyfile >/dev/null || fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"

ssh "${REMOTE_HOST}" "mkdir -p '${REMOTE_SOT_TMP}/scripts' '${REMOTE_SOT_TMP}/deploy/edge/etc/caddy' '${REMOTE_SOT_TMP}/deploy/edge/root/vaultmesh'" >/dev/null 2>&1 || fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"
rsync -az scripts/sot_guard.sh "${REMOTE_HOST}:${REMOTE_SOT_TMP}/scripts/sot_guard.sh" >/dev/null 2>&1 || fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"
rsync -az deploy/edge/MANIFEST.json "${REMOTE_HOST}:${REMOTE_SOT_TMP}/deploy/edge/MANIFEST.json" >/dev/null 2>&1 || fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"
rsync -az "${CANON_CADDY}" "${REMOTE_HOST}:${REMOTE_SOT_TMP}/deploy/edge/etc/caddy/Caddyfile" >/dev/null 2>&1 || fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"
rsync -az --delete "${CANON_ROOT}/" "${REMOTE_HOST}:${REMOTE_SOT_TMP}/deploy/edge/root/vaultmesh/" >/dev/null 2>&1 || fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"

POSTCHECK_OUTPUT="$(ssh "${REMOTE_HOST}" "cd '${REMOTE_SOT_TMP}' && bash scripts/sot_guard.sh --live" || true)"
if ! printf '%s\n' "${POSTCHECK_OUTPUT}" | grep -q '^SOT_GUARD_OK=1$'; then
  fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"
fi

DEPLOY_ROOT_SHA="$(printf '%s\n' "${POSTCHECK_OUTPUT}" | awk -F= '/^SOT_ROOT_SHA256=/{print $2; exit}')"
DEPLOY_CADDY_SHA="$(printf '%s\n' "${POSTCHECK_OUTPUT}" | awk -F= '/^SOT_CADDY_SHA256=/{print $2; exit}')"
[[ -n "${DEPLOY_ROOT_SHA}" && -n "${DEPLOY_CADDY_SHA}" ]] || fail "POSTCHECK_FAIL" "${RC_POSTCHECK}"

mkdir -p reports
COMMIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

LEDGER_LINE="{\"ts\":\"${NOW_ISO}\",\"commit\":\"${COMMIT_SHA}\",\"root_sha\":\"${DEPLOY_ROOT_SHA}\",\"caddy_sha\":\"${DEPLOY_CADDY_SHA}\",\"host\":\"${TARGET_HOST_ALIAS}\",\"outcome\":\"ok\"}"
printf '%s\n' "${LEDGER_LINE}" >> reports/site_deploy.ndjson || fail "LEDGER_APPEND_FAIL" "${RC_LEDGER_APPEND}"

ssh "${REMOTE_HOST}" "rm -rf '${REMOTE_SOT_TMP}' '/tmp/vaultmesh_caddy_${TS}'" >/dev/null 2>&1 || true

printf 'DEPLOY_HOST=%s\n' "${TARGET_HOST_ALIAS}"
printf 'DEPLOY_ROOT=%s\n' "${TARGET_ROOT}"
printf 'DEPLOY_CADDYFILE=%s\n' "${TARGET_CADDY}"
printf 'DEPLOY_ROOT_SHA256=%s\n' "${DEPLOY_ROOT_SHA}"
printf 'DEPLOY_CADDY_SHA256=%s\n' "${DEPLOY_CADDY_SHA}"
printf 'DEPLOY_LEDGER_APPEND_OK=1\n'
printf 'DEPLOY_OK=1\n'
