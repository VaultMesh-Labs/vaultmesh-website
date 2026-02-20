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
rsync -av --delete public/ dist/

BUILD_ID=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
find dist -type f -name "*.html" -exec sed -i.bak "s/{{BUILD_ID}}/${BUILD_ID}/g" {} +
find dist -type f -name "*.bak" -delete

find dist -exec touch -t 202001010000 {} +

(
  cd dist
  while IFS= read -r -d '' file; do
    hash_file "$file"
  done < <(find . -type f ! -name "MANIFEST.sha256" ! -name "BUILD_PROOF.txt" -print0 | sort -z) > MANIFEST.sha256
)

hash_file dist/MANIFEST.sha256 > dist/BUILD_PROOF.txt

echo "BUILD_OK"
