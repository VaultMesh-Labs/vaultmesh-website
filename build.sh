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

rm -rf dist
mkdir -p dist
rsync -av --delete --exclude '.DS_Store' public/ dist/
find dist -name '.DS_Store' -delete

BUILD_ID=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
# Inject canonical attestation panel partial into thin wrapper page.
if [[ -f dist/attest/index.html && -f public/shared/partials/attest_panel.html ]]; then
  sed '/{{ATTEST_PANEL}}/{
    r public/shared/partials/attest_panel.html
    d
  }' dist/attest/index.html > dist/attest/index.html.tmp
  mv dist/attest/index.html.tmp dist/attest/index.html
fi

find dist -type f -name "*.html" -exec sed -i.bak "s/{{BUILD_ID}}/${BUILD_ID}/g" {} +
find dist -type f -name "*.bak" -delete

find dist -exec touch -t 202001010000 {} +

(
  cd dist
  while IFS= read -r -d '' file; do
    hash_file "$file"
  done < <(find . -type f ! -name "MANIFEST.sha256" ! -name "BUILD_PROOF.txt" ! -name ".DS_Store" -print0 | sort -z) > MANIFEST.sha256
)

hash_file dist/MANIFEST.sha256 > dist/BUILD_PROOF.txt

echo "BUILD_OK"
