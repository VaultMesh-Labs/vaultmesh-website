#!/usr/bin/env bash
set -euo pipefail

# INTAKE CANARY v1
# RC contract:
#   0  = OK
#   12 = UNKNOWN (network / upstream unreachable)
#   20 = ASSERTION FAIL (contract violated)

RC_OK=0
RC_UNKNOWN=12
RC_FAIL=20

BASE_URL="${BASE_URL:-https://vaultmesh.org}"
TIMEOUT_SECS="${TIMEOUT_SECS:-15}"
REPORTS_DIR="${REPORTS_DIR:-reports}"
NDJSON="${REPORTS_DIR}/intake_canary.ndjson"
JSON_OUT="${REPORTS_DIR}/intake_canary.json"

# Toggle contact canary if you want
CONTACT_CANARY="${CONTACT_CANARY:-1}"

# Test identity (set to a sink inbox you control if you want)
TEST_EMAIL_HTML="${TEST_EMAIL_HTML:-test-intake-html@example.com}"
TEST_EMAIL_API="${TEST_EMAIL_API:-test-intake-api@example.com}"
TEST_EMAIL_SUPPORT="${TEST_EMAIL_SUPPORT:-test-support@example.com}"
TEST_EMAIL_CONTACT="${TEST_EMAIL_CONTACT:-test-contact@example.com}"

now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
run_id() { date -u +"%Y%m%dT%H%M%SZ"; }

RID="$(run_id)"
TS="$(now_utc)"

mkdir -p "${REPORTS_DIR}"

sha256_str() {
  # stdin -> sha256:<hex>
  local h
  h="$(shasum -a 256 | awk '{print $1}')"
  printf "sha256:%s" "${h}"
}

json_escape() {
  # minimal JSON escape for strings
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g' -e 's/\n/\\n/g'
}

fail() {
  local reason="$1"
  write_final "${RC_FAIL}" "${reason}"
  exit "${RC_FAIL}"
}

unknown() {
  local reason="$1"
  write_final "${RC_UNKNOWN}" "${reason}"
  exit "${RC_UNKNOWN}"
}

# curl wrapper: writes headers+body to temp files; returns http code in stdout
http_req() {
  # args: METHOD URL ACCEPT DATA(optional)
  local method="$1"
  local url="$2"
  local accept="${3:-}"
  local data="${4:-}"

  local hdr_file body_file
  hdr_file="$(mktemp)"
  body_file="$(mktemp)"

  local curl_args=(
    -sS
    --max-time "${TIMEOUT_SECS}"
    -D "${hdr_file}"
    -o "${body_file}"
    -X "${method}"
    "${url}"
  )

  if [[ -n "${accept}" ]]; then
    curl_args+=( -H "Accept: ${accept}" )
  fi

  if [[ -n "${data}" ]]; then
    curl_args+=( --data "${data}" )
    curl_args+=( -H "Content-Type: application/x-www-form-urlencoded" )
  fi

  # If curl fails, mark unknown (network)
  local http_code
  if ! http_code="$(curl "${curl_args[@]}" -w "%{http_code}")"; then
    rm -f "${hdr_file}" "${body_file}"
    printf "CURL_FAIL"
    return 1
  fi

  printf "%s|%s|%s" "${http_code}" "${hdr_file}" "${body_file}"
  return 0
}

hdr_get() {
  # args: HDR_FILE HEADER_NAME
  local f="$1" key="$2"
  awk -v k="$(printf "%s" "${key}" | tr '[:upper:]' '[:lower:]')" '
    BEGIN{IGNORECASE=1}
    $0 ~ "^[^:]+:" {
      split($0,a,":")
      h=tolower(a[1])
      if (h==k) {
        sub(/^[^:]+:[[:space:]]*/,"",$0)
        sub(/\r$/,"",$0)
        print $0
        exit
      }
    }
  ' "${f}"
}

contains() { grep -q "$1" "$2"; }

# Results accumulator
RESULTS_JSON="[]"
add_result() {
  # name, ok(true/false), rc, reason, http(optional), digest(optional)
  local name="$1" ok="$2" rc="$3" reason="$4" http="${5:-}" digest="${6:-}"
  local item
  item="$(cat <<EOF
{"name":"$(printf "%s" "$name" | json_escape)","ok":${ok},"rc":${rc},"reason":"$(printf "%s" "$reason" | json_escape)"$( [[ -n "$http" ]] && printf ',"http":"%s"' "$(printf "%s" "$http" | json_escape)" )$( [[ -n "$digest" ]] && printf ',"digest":"%s"' "$(printf "%s" "$digest" | json_escape)" )}
EOF
)"
  RESULTS_JSON="$(python3 - "${RESULTS_JSON}" "${item}" <<'PY'
import json,sys
arr=json.loads(sys.argv[1])
arr.append(json.loads(sys.argv[2]))
print(json.dumps(arr))
PY
)"
}

write_final() {
  local rc="$1" reason="$2"
  local ok="false"
  [[ "${rc}" == "${RC_OK}" ]] && ok="true"

  cat > "${JSON_OUT}" <<EOF
{
  "ok": ${ok},
  "rc": ${rc},
  "reason": "$(printf "%s" "${reason}" | json_escape)",
  "ts": "${TS}",
  "run_id": "${RID}",
  "base_url": "$(printf "%s" "${BASE_URL}" | json_escape)",
  "results": ${RESULTS_JSON}
}
EOF

  # NDJSON append (receipted-ish record)
  local digest
  digest="$(cat "${JSON_OUT}" | sha256_str)"
  printf '{"ts":"%s","run_id":"%s","rc":%s,"reason":"%s","report_sha":"%s"}\n' \
    "${TS}" "${RID}" "${rc}" "$(printf "%s" "${reason}" | json_escape)" "${digest}" >> "${NDJSON}"
}

# -------------------------
# 1) PROOF PACK INTAKE (GET)
# -------------------------
PROOF_GET="${BASE_URL}/proof-pack/intake/"
r="$(http_req GET "${PROOF_GET}" "text/html" "")" || unknown "NETWORK:GET_PROOF_PACK_INTAKE"
http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

if [[ "${http}" != "200" ]]; then
  add_result "proof-pack:get" false "${RC_FAIL}" "HTTP_${http}" "${http}"
  fail "PROOF_PACK_INTAKE_GET_HTTP_${http}"
fi

# Assert presence of POST target + tier selector
if ! grep -q 'action="/proof-pack/lead"' "${body}"; then
  add_result "proof-pack:get" false "${RC_FAIL}" "MISSING_FORM_ACTION" "${http}"
  fail "PROOF_PACK_INTAKE_MISSING_FORM_ACTION"
fi
if ! grep -q 'name="tier"' "${body}"; then
  add_result "proof-pack:get" false "${RC_FAIL}" "MISSING_TIER_SELECT" "${http}"
  fail "PROOF_PACK_INTAKE_MISSING_TIER"
fi

add_result "proof-pack:get" true "${RC_OK}" "ok" "${http}" "$(cat "${body}" | sha256_str)"
rm -f "${hdr}" "${body}"

# -----------------------------------
# 2) PROOF PACK LEAD (POST HTML -> 303)
# -----------------------------------
PROOF_POST="${BASE_URL}/proof-pack/lead"
boundary_html="TEST-BOUNDARY-HTML-${RID}"
data_html="form_id=proof_pack_lead_v1&route=%2Fproof-pack%2Fintake%2F&tier=snapshot_4500&name=TEST+INTAKE&email=$(printf "%s" "${TEST_EMAIL_HTML}" | python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.stdin.read().strip()))')&company=TEST&boundary=${boundary_html}&claim_set=TEST+CLAIM+SET&audience=audit"

r="$(http_req POST "${PROOF_POST}" "text/html" "${data_html}")" || unknown "NETWORK:POST_PROOF_PACK_LEAD_HTML"
http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

if [[ "${http}" != "303" ]]; then
  add_result "proof-pack:post_html" false "${RC_FAIL}" "EXPECTED_303_GOT_${http}" "${http}" "$(cat "${body}" | sha256_str)"
  fail "PROOF_PACK_LEAD_HTML_EXPECTED_303"
fi

loc="$(hdr_get "${hdr}" "Location")"
# Location may be absolute (https://...) or relative (/proof-pack/received/...)
if [[ -z "${loc}" ]] || ! printf '%s' "${loc}" | grep -q '/proof-pack/received/'; then
  add_result "proof-pack:post_html" false "${RC_FAIL}" "BAD_LOCATION:${loc}" "${http}"
  fail "PROOF_PACK_LEAD_HTML_BAD_LOCATION"
fi

add_result "proof-pack:post_html" true "${RC_OK}" "ok" "${http}" "$(printf "%s" "${loc}" | sha256_str)"
rm -f "${hdr}" "${body}"

# Follow redirect (GET received) — normalize to absolute URL
received_url="${loc}"
[[ "${received_url}" == http* ]] || received_url="${BASE_URL}${received_url}"
r="$(http_req GET "${received_url}" "text/html" "")" || unknown "NETWORK:GET_PROOF_PACK_RECEIVED"
http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

if [[ "${http}" != "200" ]]; then
  add_result "proof-pack:received" false "${RC_FAIL}" "HTTP_${http}" "${http}"
  fail "PROOF_PACK_RECEIVED_HTTP_${http}"
fi

# lightweight assertion: page should mention lead/token receipt guidance
if ! grep -qi 'lead_id' "${body}"; then
  add_result "proof-pack:received" false "${RC_FAIL}" "MISSING_LEAD_ID_TEXT" "${http}"
  fail "PROOF_PACK_RECEIVED_MISSING_LEAD_ID_TEXT"
fi

add_result "proof-pack:received" true "${RC_OK}" "ok" "${http}" "$(cat "${body}" | sha256_str)"
rm -f "${hdr}" "${body}"

# -----------------------------------
# 3) PROOF PACK LEAD (POST JSON -> 200)
# -----------------------------------
boundary_api="TEST-BOUNDARY-API-${RID}"
data_api="form_id=proof_pack_lead_v1&route=%2Fproof-pack%2Fintake%2F&tier=sprint_7500&name=TEST+INTAKE+API&email=$(printf "%s" "${TEST_EMAIL_API}" | python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.stdin.read().strip()))')&company=TEST&boundary=${boundary_api}&claim_set=TEST+CLAIM+SET+API&audience=internal"

r="$(http_req POST "${PROOF_POST}" "application/json" "${data_api}")" || unknown "NETWORK:POST_PROOF_PACK_LEAD_JSON"
http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

if [[ "${http}" != "200" ]]; then
  add_result "proof-pack:post_json" false "${RC_FAIL}" "EXPECTED_200_GOT_${http}" "${http}" "$(cat "${body}" | sha256_str)"
  fail "PROOF_PACK_LEAD_JSON_EXPECTED_200"
fi

# must contain ok true + lead_id
if ! grep -q '"ok"[[:space:]]*:[[:space:]]*true' "${body}"; then
  add_result "proof-pack:post_json" false "${RC_FAIL}" "MISSING_OK_TRUE" "${http}"
  fail "PROOF_PACK_LEAD_JSON_MISSING_OK"
fi
if ! grep -q '"lead_id"' "${body}"; then
  add_result "proof-pack:post_json" false "${RC_FAIL}" "MISSING_LEAD_ID" "${http}"
  fail "PROOF_PACK_LEAD_JSON_MISSING_LEAD_ID"
fi
# accept either token_sha or token
if ! (grep -q '"token_sha"' "${body}" || grep -q '"token"' "${body}"); then
  add_result "proof-pack:post_json" false "${RC_FAIL}" "MISSING_TOKEN_FIELD" "${http}"
  fail "PROOF_PACK_LEAD_JSON_MISSING_TOKEN"
fi

add_result "proof-pack:post_json" true "${RC_OK}" "ok" "${http}" "$(cat "${body}" | sha256_str)"
rm -f "${hdr}" "${body}"

# -------------------------
# 4) SUPPORT OPEN (GET + POST)
# -------------------------
SUPPORT_GET="${BASE_URL}/support/open/"
r="$(http_req GET "${SUPPORT_GET}" "text/html" "")" || unknown "NETWORK:GET_SUPPORT_OPEN"
http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

if [[ "${http}" != "200" ]]; then
  add_result "support:get" false "${RC_FAIL}" "HTTP_${http}" "${http}"
  fail "SUPPORT_OPEN_GET_HTTP_${http}"
fi

if ! grep -q 'action="/support/ticket"' "${body}"; then
  add_result "support:get" false "${RC_FAIL}" "MISSING_FORM_ACTION" "${http}"
  fail "SUPPORT_OPEN_MISSING_FORM_ACTION"
fi

add_result "support:get" true "${RC_OK}" "ok" "${http}" "$(cat "${body}" | sha256_str)"
rm -f "${hdr}" "${body}"

SUPPORT_POST="${BASE_URL}/support/ticket"
subject="TEST-SUPPORT-${RID}"
data_support="form_id=support_ticket_v1&route=%2Fsupport%2Fopen%2F&name=TEST+SUPPORT&email=$(printf "%s" "${TEST_EMAIL_SUPPORT}" | python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.stdin.read().strip()))')&company=TEST&severity=P3&subject=${subject}&message=TEST+MESSAGE"

r="$(http_req POST "${SUPPORT_POST}" "application/json" "${data_support}")" || unknown "NETWORK:POST_SUPPORT_TICKET"
http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

if [[ "${http}" != "200" ]]; then
  add_result "support:post" false "${RC_FAIL}" "EXPECTED_200_GOT_${http}" "${http}" "$(cat "${body}" | sha256_str)"
  fail "SUPPORT_TICKET_EXPECTED_200"
fi

# accept either ok:true or a ticket id field
if ! (grep -q '"ok"[[:space:]]*:[[:space:]]*true' "${body}" || grep -q '"ticket' "${body}" || grep -q '"id"' "${body}"); then
  add_result "support:post" false "${RC_FAIL}" "MISSING_OK_OR_TICKET_ID" "${http}" "$(cat "${body}" | sha256_str)"
  fail "SUPPORT_TICKET_BAD_RESPONSE"
fi

add_result "support:post" true "${RC_OK}" "ok" "${http}" "$(cat "${body}" | sha256_str)"
rm -f "${hdr}" "${body}"

# -------------------------
# 5) CONTACT (optional, auto-detect POST action)
# -------------------------
if [[ "${CONTACT_CANARY}" == "1" ]]; then
  CONTACT_GET="${BASE_URL}/contact/"
  r="$(http_req GET "${CONTACT_GET}" "text/html" "")" || unknown "NETWORK:GET_CONTACT"
  http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

  if [[ "${http}" != "200" ]]; then
    add_result "contact:get" false "${RC_FAIL}" "HTTP_${http}" "${http}"
    fail "CONTACT_GET_HTTP_${http}"
  fi

  # Extract first form action (very lightweight)
  action="$(grep -oE '<form[^>]+action="[^"]+"' "${body}" | head -n 1 | sed -E 's/.*action="([^"]+)".*/\1/')"
  if [[ -z "${action}" ]]; then
    add_result "contact:get" false "${RC_FAIL}" "MISSING_FORM_ACTION" "${http}"
    fail "CONTACT_MISSING_FORM_ACTION"
  fi
  add_result "contact:get" true "${RC_OK}" "ok" "${http}" "$(printf "%s" "${action}" | sha256_str)"
  rm -f "${hdr}" "${body}"

  # Normalize action URL
  if [[ "${action}" == http* ]]; then
    CONTACT_POST="${action}"
  else
    # ensure leading slash
    [[ "${action}" != /* ]] && action="/${action}"
    CONTACT_POST="${BASE_URL}${action}"
  fi

  msg="TEST-CONTACT-${RID}"
  data_contact="name=TEST+CONTACT&email=$(printf "%s" "${TEST_EMAIL_CONTACT}" | python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.stdin.read().strip()))')&subject=General+inquiry&message=${msg}"

  r="$(http_req POST "${CONTACT_POST}" "application/json" "${data_contact}")" || unknown "NETWORK:POST_CONTACT"
  http="${r%%|*}"; rest="${r#*|}"; hdr="${rest%%|*}"; body="${rest#*|}"

  # Some contact handlers may respond 200 JSON, 303 redirect, or 204.
  if [[ "${http}" != "200" && "${http}" != "303" && "${http}" != "204" ]]; then
    add_result "contact:post" false "${RC_FAIL}" "UNEXPECTED_HTTP_${http}" "${http}" "$(cat "${body}" | sha256_str)"
    fail "CONTACT_POST_UNEXPECTED_HTTP_${http}"
  fi

  add_result "contact:post" true "${RC_OK}" "ok" "${http}" "$(cat "${body}" | sha256_str)"
  rm -f "${hdr}" "${body}"
else
  add_result "contact:skipped" true "${RC_OK}" "CONTACT_CANARY_DISABLED"
fi

# Final OK
write_final "${RC_OK}" "ok"
exit "${RC_OK}"
