#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

fail() {
  echo "NAV_FOOTER_GUARD_FAIL: $*" >&2
  exit 1
}

[[ -f public/shared/ui.css ]] || fail "missing public/shared/ui.css"
[[ -f public/shared/nav.html ]] || fail "missing public/shared/nav.html"
[[ -f public/shared/footer.html ]] || fail "missing public/shared/footer.html"

./build.sh >/dev/null

while IFS= read -r -d '' page; do
  grep -q 'class="vm-nav"' "${page}" || fail "${page} missing vm-nav"
  grep -q 'class="vm-footer"' "${page}" || fail "${page} missing vm-footer"
  grep -q '/shared/ui.css' "${page}" || fail "${page} missing /shared/ui.css reference"
done < <(find dist -type f -name 'index.html' -print0 | sort -z)

while IFS= read -r -d '' source_page; do
  grep -q '/shared/ui.css' "${source_page}" || fail "${source_page} missing /shared/ui.css reference"
  grep -Eqi '<style[[:space:]>]' "${source_page}" && fail "${source_page} contains inline <style>"
  grep -Eqi 'style=' "${source_page}" && fail "${source_page} contains inline style= attribute"
  grep -Eqi '#[0-9a-fA-F]{3,8}|rgb\(|hsl\(' "${source_page}" && fail "${source_page} hardcodes color value"
done < <(find public -type f -name 'index.html' -print0 | sort -z)

if rg -n --glob '*.html' '\{\{NAV\}\}|\{\{FOOTER\}\}' dist >/dev/null; then
  fail "dist contains unresolved NAV/FOOTER placeholders"
fi

token_hits="$(rg -n '(--vm-|--border|--font-mono)' public --glob '*.css' --glob '*.html' --glob '*.htm' || true)"
if [[ -n "${token_hits}" ]]; then
  token_hits_filtered="$(printf '%s\n' "${token_hits}" | grep -v '^public/shared/ui.css:' || true)"
  if [[ -n "${token_hits_filtered}" ]]; then
    printf '%s\n' "${token_hits_filtered}" >&2
    fail "skin tokens found outside public/shared/ui.css"
  fi
fi

BUILD_ID="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
MANIFEST_SHA="$( (sha256sum dist/MANIFEST.sha256 2>/dev/null || shasum -a 256 dist/MANIFEST.sha256) | awk '{print $1}')"
PAGE_COUNT="$(find dist -type f -name 'index.html' | wc -l | tr -d ' ')"

echo "GUARD_OK build=${BUILD_ID} manifest_sha256=sha256:${MANIFEST_SHA} pages=${PAGE_COUNT}"
