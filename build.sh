#!/usr/bin/env bash
set -euo pipefail

rm -rf dist
mkdir -p dist
cp -R public/* dist/

echo "BUILD_OK"
