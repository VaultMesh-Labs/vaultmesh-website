#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

./build.sh

rm -rf dist/site
mkdir -p dist/site
rsync -a --delete --exclude 'site/' dist/ dist/site/
