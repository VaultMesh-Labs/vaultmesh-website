#!/usr/bin/env bash
set -euo pipefail

################################################################################
# verify_deploy_contracts.sh — Pre-deploy invariant verification
#
# Asserts that deploy_edge.sh respects DEPLOY CONTRACT v1:
#   1) Checksum-based sync (rsync -c on all deploy rsyncs)
#   2) Single exclude list (DEPLOY_RSYNC_EXCLUDES referenced, no inline excludes)
#
# RC: 0 = all checks pass, 20 = contract violation detected
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy_edge.sh"
UI_CONTRACT_SCRIPT="${SCRIPT_DIR}/contracts/ui_contract_check.sh"
LANE_WIDTH_SCRIPT="${SCRIPT_DIR}/contracts/lane_width_lock.sh"
COLOR_LOCK_SCRIPT="${SCRIPT_DIR}/contracts/color_lock_check.sh"
FOOTER_CONTRACT_SCRIPT="${SCRIPT_DIR}/contracts/footer_contract_check.sh"
ROUTE_IDENTITY_SCRIPT="${SCRIPT_DIR}/contracts/route_identity_check.sh"
PAGE_KIND_SCRIPT="${SCRIPT_DIR}/contracts/page_kind_check.sh"
KIND_MAP_FILE="${SCRIPT_DIR}/contracts/kind_map.v1.tsv"
HOME_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/home_surface_check.sh"
ATTEST_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/attest_surface_check.sh"
SUPPORT_OPEN_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/support_open_surface_check.sh"
SUPPORT_OPEN_UI_SCALE_SCRIPT="${SCRIPT_DIR}/contracts/support_open_ui_scale_check.sh"
PROOF_PACK_INTAKE_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/proof_pack_intake_surface_check.sh"
PROOF_PACK_INTAKE_UI_SCRIPT="${SCRIPT_DIR}/contracts/proof_pack_intake_ui_contract_check.sh"
FORM_SKIN_CONTRACT_SCRIPT="${SCRIPT_DIR}/contracts/form_skin_contract_check.sh"
PROOF_PACK_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/proof_pack_surface_check.sh"
PRICING_UI_LOCK_SCRIPT="${SCRIPT_DIR}/contracts/pricing_ui_order_lock.sh"
PRICING_UI_CONTRACT_SCRIPT="${SCRIPT_DIR}/contracts/pricing_ui_contract_check.sh"
OFFER_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/offer_surface_check.sh"
VERIFY_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/verify_surface_check.sh"
STATUS_SURFACE_SCRIPT="${SCRIPT_DIR}/contracts/status_surface_check.sh"
ATTEST_LANE_SCRIPT="${SCRIPT_DIR}/contracts/attest_lane_check.sh"

RC_OK=0
RC_VIOLATION=20
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    failures=$((failures + 1))
  fi
}

[[ -f "${DEPLOY_SCRIPT}" ]] || { printf 'FAIL  deploy_edge.sh not found at %s\n' "${DEPLOY_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${UI_CONTRACT_SCRIPT}" ]] || { printf 'FAIL  ui_contract_check.sh not found at %s\n' "${UI_CONTRACT_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${LANE_WIDTH_SCRIPT}" ]] || { printf 'FAIL  lane_width_lock.sh not found at %s\n' "${LANE_WIDTH_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${COLOR_LOCK_SCRIPT}" ]] || { printf 'FAIL  color_lock_check.sh not found at %s\n' "${COLOR_LOCK_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${FOOTER_CONTRACT_SCRIPT}" ]] || { printf 'FAIL  footer_contract_check.sh not found at %s\n' "${FOOTER_CONTRACT_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${ROUTE_IDENTITY_SCRIPT}" ]] || { printf 'FAIL  route_identity_check.sh not found at %s\n' "${ROUTE_IDENTITY_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${PAGE_KIND_SCRIPT}" ]] || { printf 'FAIL  page_kind_check.sh not found at %s\n' "${PAGE_KIND_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${KIND_MAP_FILE}" ]] || { printf 'FAIL  kind_map.v1.tsv not found at %s\n' "${KIND_MAP_FILE}"; exit "${RC_VIOLATION}"; }
[[ -f "${HOME_SURFACE_SCRIPT}" ]] || { printf 'FAIL  home_surface_check.sh not found at %s\n' "${HOME_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${ATTEST_SURFACE_SCRIPT}" ]] || { printf 'FAIL  attest_surface_check.sh not found at %s\n' "${ATTEST_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${SUPPORT_OPEN_SURFACE_SCRIPT}" ]] || { printf 'FAIL  support_open_surface_check.sh not found at %s\n' "${SUPPORT_OPEN_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${SUPPORT_OPEN_UI_SCALE_SCRIPT}" ]] || { printf 'FAIL  support_open_ui_scale_check.sh not found at %s\n' "${SUPPORT_OPEN_UI_SCALE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${PROOF_PACK_INTAKE_SURFACE_SCRIPT}" ]] || { printf 'FAIL  proof_pack_intake_surface_check.sh not found at %s\n' "${PROOF_PACK_INTAKE_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${PROOF_PACK_INTAKE_UI_SCRIPT}" ]] || { printf 'FAIL  proof_pack_intake_ui_contract_check.sh not found at %s\n' "${PROOF_PACK_INTAKE_UI_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${FORM_SKIN_CONTRACT_SCRIPT}" ]] || { printf 'FAIL  form_skin_contract_check.sh not found at %s\n' "${FORM_SKIN_CONTRACT_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${PROOF_PACK_SURFACE_SCRIPT}" ]] || { printf 'FAIL  proof_pack_surface_check.sh not found at %s\n' "${PROOF_PACK_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${PRICING_UI_LOCK_SCRIPT}" ]] || { printf 'FAIL  pricing_ui_order_lock.sh not found at %s\n' "${PRICING_UI_LOCK_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${PRICING_UI_CONTRACT_SCRIPT}" ]] || { printf 'FAIL  pricing_ui_contract_check.sh not found at %s\n' "${PRICING_UI_CONTRACT_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${OFFER_SURFACE_SCRIPT}" ]] || { printf 'FAIL  offer_surface_check.sh not found at %s\n' "${OFFER_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${VERIFY_SURFACE_SCRIPT}" ]] || { printf 'FAIL  verify_surface_check.sh not found at %s\n' "${VERIFY_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${STATUS_SURFACE_SCRIPT}" ]] || { printf 'FAIL  status_surface_check.sh not found at %s\n' "${STATUS_SURFACE_SCRIPT}"; exit "${RC_VIOLATION}"; }
[[ -f "${ATTEST_LANE_SCRIPT}" ]] || { printf 'FAIL  attest_lane_check.sh not found at %s\n' "${ATTEST_LANE_SCRIPT}"; exit "${RC_VIOLATION}"; }

# 1) DEPLOY_RSYNC_EXCLUDES array must be defined
check "DEPLOY_RSYNC_EXCLUDES defined" \
  grep -q '^DEPLOY_RSYNC_EXCLUDES=(' "${DEPLOY_SCRIPT}"

# 2) Runtime guard must exist
check "runtime guard present" \
  grep -q 'DEPLOY_RSYNC_EXCLUDES:?' "${DEPLOY_SCRIPT}"

# 3) Snapshot sync rsync must use -c and reference the excludes array
check "snapshot sync uses -c flag" \
  grep -q 'rsync -ac.*DEPLOY_RSYNC_EXCLUDES' "${DEPLOY_SCRIPT}"

# 4) Drift check rsync must reference the excludes array
check "drift check references DEPLOY_RSYNC_EXCLUDES" \
  grep -q 'rsync -rcni.*DEPLOY_RSYNC_EXCLUDES\|DEPLOY_RSYNC_EXCLUDES.*dist/site.*CANON_ROOT' "${DEPLOY_SCRIPT}"

# 5) No inline --exclude on rsync lines that touch dist/site/ → CANON_ROOT
#    (The dist/ → dist/site/ internal copy is allowed to have its own excludes.)
_inline_count=0
while IFS= read -r line; do
  # Skip the array definition block
  [[ "$line" =~ ^[[:space:]]*--exclude ]] && continue
  # Skip the dist/ → dist/site/ build-internal rsync
  [[ "$line" =~ dist/[[:space:]]+dist/site/ ]] && continue
  # Flag lines that have --exclude AND reference CANON_ROOT or dist/site/→remote
  if [[ "$line" =~ --exclude ]] && [[ "$line" =~ CANON_ROOT || "$line" =~ REMOTE_STAGE ]]; then
    _inline_count=$((_inline_count + 1))
  fi
done < "${DEPLOY_SCRIPT}"
check "no inline excludes on deploy rsyncs" \
  test "${_inline_count}" -eq 0

# 6) Remote staging upload uses -c flag
check "staging upload uses checksum sync" \
  grep -q 'rsync -azc.*REMOTE_STAGE' "${DEPLOY_SCRIPT}"

# 7) UI/FOOTER contract guards must execute in deploy precheck lane
check "deploy precheck executes ui contract guard" \
  grep -q 'scripts/contracts/ui_contract_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes lane width lock" \
  grep -q 'scripts/contracts/lane_width_lock.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes color lock" \
  grep -q 'scripts/contracts/color_lock_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes footer contract guard" \
  grep -q 'scripts/contracts/footer_contract_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes home surface check" \
  grep -q 'scripts/contracts/home_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes route identity guard" \
  grep -q 'scripts/contracts/route_identity_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes page kind guard" \
  grep -q 'scripts/contracts/page_kind_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes attest surface guard" \
  grep -q 'scripts/contracts/attest_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes support open surface guard" \
  grep -q 'scripts/contracts/support_open_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes support open ui scale" \
  grep -q 'scripts/contracts/support_open_ui_scale_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes proof pack intake surface guard" \
  grep -q 'scripts/contracts/proof_pack_intake_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes proof pack intake ui lock" \
  grep -q 'scripts/contracts/proof_pack_intake_ui_contract_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes form skin contract check" \
  grep -q 'scripts/contracts/form_skin_contract_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes proof pack surface guard" \
  grep -q 'scripts/contracts/proof_pack_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes pricing ui lock" \
  grep -q 'scripts/contracts/pricing_ui_order_lock.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes pricing ui contract check" \
  grep -q 'scripts/contracts/pricing_ui_contract_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes offer surface check" \
  grep -q 'scripts/contracts/offer_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes verify surface check" \
  grep -q 'scripts/contracts/verify_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes status surface check" \
  grep -q 'scripts/contracts/status_surface_check.sh' "${DEPLOY_SCRIPT}"
check "deploy precheck executes attest lane check" \
  grep -q 'scripts/contracts/attest_lane_check.sh' "${DEPLOY_SCRIPT}"

# 8) Contract scripts are executable
check "ui contract script executable" \
  test -x "${UI_CONTRACT_SCRIPT}"
check "lane width script executable" \
  test -x "${LANE_WIDTH_SCRIPT}"
check "color lock script executable" \
  test -x "${COLOR_LOCK_SCRIPT}"
check "footer contract script executable" \
  test -x "${FOOTER_CONTRACT_SCRIPT}"
check "home surface script executable" \
  test -x "${HOME_SURFACE_SCRIPT}"
check "route identity script executable" \
  test -x "${ROUTE_IDENTITY_SCRIPT}"
check "page kind script executable" \
  test -x "${PAGE_KIND_SCRIPT}"
check "attest surface script executable" \
  test -x "${ATTEST_SURFACE_SCRIPT}"
check "support open surface script executable" \
  test -x "${SUPPORT_OPEN_SURFACE_SCRIPT}"
check "support open ui scale script executable" \
  test -x "${SUPPORT_OPEN_UI_SCALE_SCRIPT}"
check "proof pack intake surface script executable" \
  test -x "${PROOF_PACK_INTAKE_SURFACE_SCRIPT}"
check "proof pack intake ui script executable" \
  test -x "${PROOF_PACK_INTAKE_UI_SCRIPT}"
check "form skin contract script executable" \
  test -x "${FORM_SKIN_CONTRACT_SCRIPT}"
check "proof pack surface script executable" \
  test -x "${PROOF_PACK_SURFACE_SCRIPT}"
check "pricing ui lock script executable" \
  test -x "${PRICING_UI_LOCK_SCRIPT}"
check "pricing ui contract script executable" \
  test -x "${PRICING_UI_CONTRACT_SCRIPT}"
check "offer surface script executable" \
  test -x "${OFFER_SURFACE_SCRIPT}"
check "verify surface script executable" \
  test -x "${VERIFY_SURFACE_SCRIPT}"
check "status surface script executable" \
  test -x "${STATUS_SURFACE_SCRIPT}"
check "attest lane script executable" \
  test -x "${ATTEST_LANE_SCRIPT}"

if [[ "${failures}" -gt 0 ]]; then
  printf '\nCONTRACT_VIOLATIONS=%s\n' "${failures}"
  exit "${RC_VIOLATION}"
fi

printf '\nDEPLOY_CONTRACT_OK=1\n'
exit "${RC_OK}"
