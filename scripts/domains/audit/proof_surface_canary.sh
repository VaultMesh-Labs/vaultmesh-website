#!/usr/bin/env bash
set -euo pipefail

################################################################################
# proof_surface_canary.sh — PROOF SURFACE CANARY v1
#
# Outside-in HTTP checks for all proof/decision surfaces:
#   1) /attest/attest.json  — 200, application/json, required keys
#   2) /status/             — 200, lane markers, primary CTA → /verify/
#   3) /verify/             — 200, lane markers, primary CTA → /verify-console/
#   4) /offer/              — 200, lane markers, primary CTA → /proof-pack/intake/
#   5) /                    — 200, lane markers, primary CTA → /offer/
#   6) /verify-console/     — 200, lane markers, link → /attest/
#
# Writes: reports/proof_surface_canary.json      (compositor summary)
# Appends: reports/proof_surface_canary.ndjson    (receipted ledger)
# Alerts: reports/ALERT_proof_surface_canary_<ts>_rc<N>.json (failure only)
#
# RC: 0=OK, 12=UNKNOWN(network), 20=FAIL(assertion)
################################################################################

RC_OK=0
RC_UNKNOWN=12
RC_FAIL=20

BASE_URL="${BASE_URL:-https://vaultmesh.org}"
TIMEOUT_SECS="${TIMEOUT_SECS:-15}"
REPORTS_DIR="${REPORTS_DIR:-reports}"
NDJSON="${REPORTS_DIR}/proof_surface_canary.ndjson"
JSON_OUT="${REPORTS_DIR}/proof_surface_canary.json"

now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
run_id() { date -u +"%Y%m%dT%H%M%SZ"; }

RID="$(run_id)"
TS="$(now_utc)"

mkdir -p "${REPORTS_DIR}"

sha256_str() { shasum -a 256 | awk '{print "sha256:"$1}'; }
json_escape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r/\\r/g'; }

worst_rc="${RC_OK}"
update_worst() { [[ "$1" -gt "${worst_rc}" ]] && worst_rc="$1"; return 0; }

write_final() {
  local rc="$1" reason="$2" results="$3"
  local ok="false"; [[ "$rc" == "$RC_OK" ]] && ok="true"

  cat > "${JSON_OUT}" <<EOF
{"ok":${ok},"rc":${rc},"reason":"$(printf "%s" "${reason}" | json_escape)","ts":"${TS}","run_id":"${RID}","base_url":"$(printf "%s" "${BASE_URL}" | json_escape)","results":${results}}
EOF

  local digest
  digest="$(cat "${JSON_OUT}" | sha256_str)"
  printf '{"ts":"%s","run_id":"%s","rc":%s,"reason":"%s","report_sha":"%s"}\n' \
    "${TS}" "${RID}" "${rc}" "$(printf "%s" "${reason}" | json_escape)" "${digest}" >> "${NDJSON}"

  if [[ "$rc" -ne 0 ]]; then
    cp -f "${JSON_OUT}" "${REPORTS_DIR}/ALERT_proof_surface_canary_${RID}_rc${rc}.json"
  fi
}

RESULTS="[]"
add_res() {
  local name="$1" ok="$2" rc="$3" reason="$4" http="${5:-}" digest="${6:-}"
  local http_frag="" digest_frag=""
  [[ -n "$http" ]] && http_frag="$(printf ',"http":"%s"' "$(printf "%s" "$http" | json_escape)")"
  [[ -n "$digest" ]] && digest_frag="$(printf ',"digest":"%s"' "$(printf "%s" "$digest" | json_escape)")"
  local item
  item="$(printf '{"name":"%s","ok":%s,"rc":%s,"reason":"%s"%s%s}' \
    "$(printf "%s" "$name" | json_escape)" "$ok" "$rc" \
    "$(printf "%s" "$reason" | json_escape)" "$http_frag" "$digest_frag")"
  RESULTS="$(python3 - "$RESULTS" "$item" <<'PY'
import json,sys
arr=json.loads(sys.argv[1]); arr.append(json.loads(sys.argv[2])); print(json.dumps(arr))
PY
)"
}

# ---- check functions ----

check_json() {
  local name="$1" path="$2"
  shift 2
  local keys=("$@")
  local tmp_hdr tmp_body http ct

  tmp_hdr="$(mktemp)"; tmp_body="$(mktemp)"
  if ! http="$(curl -sS --max-time "${TIMEOUT_SECS}" -D "$tmp_hdr" -o "$tmp_body" \
    -H "Accept: application/json" -w "%{http_code}" "${BASE_URL}${path}" 2>/dev/null)"; then
    add_res "$name" false "$RC_UNKNOWN" "curl_failed" "" ""
    update_worst "$RC_UNKNOWN"
    rm -f "$tmp_hdr" "$tmp_body"
    return
  fi

  if [[ "$http" != "200" ]]; then
    add_res "$name" false "$RC_FAIL" "HTTP_${http}" "$http" ""
    update_worst "$RC_FAIL"
    rm -f "$tmp_hdr" "$tmp_body"
    return
  fi

  ct="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/{sub(/^[^:]+:[[:space:]]*/,""); sub(/\r$/,""); print; exit}' "$tmp_hdr")"
  if ! echo "$ct" | grep -qi "application/json"; then
    add_res "$name" false "$RC_FAIL" "BAD_CONTENT_TYPE:${ct}" "$http" ""
    update_worst "$RC_FAIL"
    rm -f "$tmp_hdr" "$tmp_body"
    return
  fi

  for key in "${keys[@]}"; do
    if ! grep -q "\"${key}\"" "$tmp_body"; then
      add_res "$name" false "$RC_FAIL" "MISSING_KEY:${key}" "$http" "$(cat "$tmp_body" | sha256_str)"
      update_worst "$RC_FAIL"
      rm -f "$tmp_hdr" "$tmp_body"
      return
    fi
  done

  add_res "$name" true "$RC_OK" "ok" "$http" "$(cat "$tmp_body" | sha256_str)"
  rm -f "$tmp_hdr" "$tmp_body"
}

check_html() {
  local name="$1" path="$2"
  shift 2
  local patterns=("$@")
  local tmp_hdr tmp_body http

  tmp_hdr="$(mktemp)"; tmp_body="$(mktemp)"
  if ! http="$(curl -sS --max-time "${TIMEOUT_SECS}" -D "$tmp_hdr" -o "$tmp_body" \
    -H "Accept: text/html" -w "%{http_code}" "${BASE_URL}${path}" 2>/dev/null)"; then
    add_res "$name" false "$RC_UNKNOWN" "curl_failed" "" ""
    update_worst "$RC_UNKNOWN"
    rm -f "$tmp_hdr" "$tmp_body"
    return
  fi

  if [[ "$http" != "200" ]]; then
    add_res "$name" false "$RC_FAIL" "HTTP_${http}" "$http" ""
    update_worst "$RC_FAIL"
    rm -f "$tmp_hdr" "$tmp_body"
    return
  fi

  for pat in "${patterns[@]}"; do
    if ! grep -qF "$pat" "$tmp_body"; then
      add_res "$name" false "$RC_FAIL" "MISSING:${pat}" "$http" "$(cat "$tmp_body" | sha256_str)"
      update_worst "$RC_FAIL"
      rm -f "$tmp_hdr" "$tmp_body"
      return
    fi
  done

  add_res "$name" true "$RC_OK" "ok" "$http" "$(cat "$tmp_body" | sha256_str)"
  rm -f "$tmp_hdr" "$tmp_body"
}

# ---- run checks ----

check_json "attest:json" "/attest/attest.json" "schema_id" "continuity" "health"

check_html "status:page" "/status/" \
  'data-route="/status/"' \
  'data-kind="status"' \
  'class="btn primary" href="/verify/"'

check_html "verify:page" "/verify/" \
  'data-route="/verify/"' \
  'data-kind="verify"' \
  'class="btn primary" href="/verify-console/"'

check_html "offer:page" "/offer/" \
  'data-route="/offer/"' \
  'data-kind="offer"' \
  'class="btn primary" href="/proof-pack/intake/"'

check_html "home:page" "/" \
  'data-route="/"' \
  'data-kind="home"' \
  'class="btn primary" href="/offer/"'

check_html "verify-console:page" "/verify-console/" \
  'data-route="/verify-console/"' \
  'data-kind="verify-console"' \
  'href="/attest/"'

# ---- finalize ----

reason="ok"; [[ "${worst_rc}" -ne 0 ]] && reason="check_failed"
write_final "${worst_rc}" "${reason}" "${RESULTS}"

printf '{"ok":%s,"rc":%s,"checks":6}\n' \
  "$( [[ "${worst_rc}" -eq 0 ]] && echo true || echo false )" "${worst_rc}"

exit "${worst_rc}"
