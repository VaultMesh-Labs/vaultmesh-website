#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
MAP="${2:-scripts/contracts/kind_map.v1.tsv}"
ROOT="${ROOT%/}"
RC_VIOLATION=20

fail() {
  echo "PAGE_KIND_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[[ -d "${ROOT}" ]] || fail "missing dist root: ${ROOT}"
[[ -f "${MAP}" ]] || fail "missing kind map: ${MAP}"

declare -A route_kind
while IFS=$'\t' read -r route kind _extra; do
  [[ -z "${route// }" ]] && continue
  [[ "${route:0:1}" == "#" ]] && continue
  [[ -n "${kind// }" ]] || fail "empty kind for route: ${route}"
  route_kind["${route}"]="${kind}"
done < "${MAP}"

[[ "${#route_kind[@]}" -gt 0 ]] || fail "kind map is empty: ${MAP}"

mapfile -t html_files < <(find "${ROOT}" -type f -name '*.html' | sort)
[[ "${#html_files[@]}" -gt 0 ]] || fail "no html files found under ${ROOT}"

for f in "${html_files[@]}"; do
  rel="${f#${ROOT}/}"
  route=""

  if [[ "${rel}" == "index.html" ]]; then
    route="/"
  else
    if [[ "${rel}" != */index.html ]]; then
      fail "non-index html not allowed (v1): ${rel}"
    fi
    dir="${rel%index.html}"
    route="/${dir}"
  fi

  expected="${route_kind[${route}]:-}"
  [[ -n "${expected}" ]] || fail "route missing from kind map: ${route} (file ${rel})"

  body_tag="$(
    awk '
      BEGIN { in_body = 0; tag = "" }
      {
        line_l = tolower($0)
        if (!in_body && line_l ~ /<body[[:space:]>]/) {
          in_body = 1
        }
        if (in_body) {
          tag = tag $0 "\n"
          if (index($0, ">") > 0) {
            print tag
            exit
          }
        }
      }
    ' "${f}"
  )"

  [[ -n "${body_tag}" ]] || fail "missing <body> tag: ${rel}"

  file_count="$(grep -o 'data-kind="' "${f}" | wc -l | tr -d '[:space:]')"
  body_count="$(printf '%s' "${body_tag}" | grep -o 'data-kind="' | wc -l | tr -d '[:space:]')"
  [[ "${file_count}" == "1" ]] || fail "data-kind count mismatch file=${rel} have=${file_count} want=1"
  [[ "${body_count}" == "1" ]] || fail "data-kind must be on <body> only file=${rel}"

  if ! printf '%s' "${body_tag}" | grep -q "data-kind=\"${expected}\""; then
    echo "---- debug: ${rel} route=${route} expected=${expected} ----" >&2
    grep -nE '<body|data-kind=' "${f}" | head -n 8 >&2 || true
    fail "kind mismatch: ${rel} expected data-kind=\"${expected}\""
  fi
done

echo "PAGE_KIND_OK=1"
exit 0
