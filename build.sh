#!/usr/bin/env bash
set -euo pipefail

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@"
    return
  fi

  echo "Missing hash tool: sha256sum or shasum" >&2
  exit 1
}

inject_marker_file() {
  local marker="$1"
  local fragment="$2"
  local file="$3"
  local tmp

  if ! grep -Fq "$marker" "$file"; then
    return
  fi

  tmp="${file}.tmp"
  awk -v marker="$marker" -v fragment="$fragment" '
    index($0, marker) > 0 {
      while ((getline line < fragment) > 0) {
        print line
      }
      close(fragment)
      next
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

write_manifest() {
  (
    cd dist
    while IFS= read -r -d '' file; do
      if [[ "$file" == *.html ]]; then
        tmp="$(mktemp)"
        sed -E 's#Manifest: sha256:[0-9a-fA-F]{64}#Manifest: sha256:UNSET#g' "$file" > "$tmp"
        file_hash="$(hash_file "$tmp" | awk '{print $1}')"
        rm -f "$tmp"
        printf "%s  %s\n" "$file_hash" "$file"
      else
        hash_file "$file"
      fi
    done < <(find . -type f ! -name "MANIFEST.sha256" ! -name "BUILD_PROOF.txt" ! -name ".DS_Store" -print0 | sort -z) > MANIFEST.sha256
  )
}

rm -rf dist
mkdir -p dist
rsync -av --delete --exclude '.DS_Store' public/ dist/
find dist -name '.DS_Store' -delete

BUILD_ID=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
# Inject canonical attestation panel partial only when wrapper placeholder is present.
if [[ -f dist/attest/index.html && -f public/shared/partials/attest_panel.html ]] && grep -q "{{ATTEST_PANEL}}" dist/attest/index.html; then
  sed '/{{ATTEST_PANEL}}/{
    r public/shared/partials/attest_panel.html
    d
  }' dist/attest/index.html > dist/attest/index.html.tmp
  mv dist/attest/index.html.tmp dist/attest/index.html
fi

while IFS= read -r -d '' html_file; do
  inject_marker_file "<!-- {{NAV}} -->" "public/shared/nav.html" "$html_file"
  inject_marker_file "<!-- {{FOOTER}} -->" "public/shared/footer.html" "$html_file"
done < <(find dist -type f -name "*.html" -print0)

# Shared template fragments are build inputs, not shipped artifacts.
rm -f dist/shared/nav.html dist/shared/footer.html
rm -rf dist/shared/partials

find dist -type f -name "*.html" -exec sed -i.bak "s/{{BUILD_ID}}/${BUILD_ID}/g" {} +
find dist -type f -name "*.html" -exec sed -E -i.bak "s/Build: STATIC/Build: ${BUILD_ID}/g" {} +
find dist -type f -name "*.bak" -delete

find dist -exec touch -t 202001010000 {} +

write_manifest
MANIFEST_SHA="$(hash_file dist/MANIFEST.sha256 | awk '{print $1}')"
find dist -type f -name "*.html" -exec sed -E -i.bak "s#Manifest: sha256:(UNSET|[0-9a-fA-F]{64})#Manifest: sha256:${MANIFEST_SHA}#g" {} +
find dist -type f -name "*.bak" -delete

write_manifest
FINAL_MANIFEST_SHA="$(hash_file dist/MANIFEST.sha256 | awk '{print $1}')"
if [[ "${FINAL_MANIFEST_SHA}" != "${MANIFEST_SHA}" ]]; then
  find dist -type f -name "*.html" -exec sed -E -i.bak "s#Manifest: sha256:(UNSET|[0-9a-fA-F]{64})#Manifest: sha256:${FINAL_MANIFEST_SHA}#g" {} +
  find dist -type f -name "*.bak" -delete
  write_manifest
fi

hash_file dist/MANIFEST.sha256 > dist/BUILD_PROOF.txt

echo "BUILD_OK=1"
