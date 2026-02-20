#!/usr/bin/env bash
set -euo pipefail

./build.sh
rsync -avz --delete dist/ root@49.13.217.227:/srv/web/vaultmesh/

echo "DEPLOY_OK"
