#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
ROOT="${ROOT%/}"
RC_VIOLATION=20

fail() {
  echo "ROUTE_IDENTITY_OK=0"
  echo "FAIL: $*" >&2
  exit "${RC_VIOLATION}"
}

[ -d "${ROOT}" ] || fail "missing dist root: ${ROOT}"

mapfile -t html_files < <(find "${ROOT}" -type f -name '*.html' | sort)
[ "${#html_files[@]}" -gt 0 ] || fail "no html files found under ${ROOT}"

for f in "${html_files[@]}"; do
  rel="${f#${ROOT}/}"
  route=""

  if [[ "${rel}" == "index.html" ]]; then
    route="/"
  else
    # Contract v1 only allows directory index pages.
    if [[ "${rel}" != */index.html ]]; then
      fail "non-index html not allowed (v1): ${rel}"
    fi
    dir="${rel%index.html}"
    route="/${dir}"
  fi

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

  # Exactly one data-route in entire file and on the body tag.
  file_count="$(grep -o 'data-route="' "${f}" | wc -l | tr -d '[:space:]')"
  body_count="$(printf '%s' "${body_tag}" | grep -o 'data-route="' | wc -l | tr -d '[:space:]')"
  [[ "${file_count}" == "1" ]] || fail "data-route count mismatch file=${rel} have=${file_count} want=1"
  [[ "${body_count}" == "1" ]] || fail "data-route must be on <body> only file=${rel}"

  if ! printf '%s' "${body_tag}" | grep -q "data-route=\"${route}\""; then
    echo "---- debug: ${rel} (expected ${route}) ----" >&2
    grep -nE '<body|data-route=' "${f}" | head -n 8 >&2 || true
    fail "route identity mismatch: ${rel} expected data-route=\"${route}\""
  fi
done

echo "ROUTE_IDENTITY_OK=1"
exit 0
