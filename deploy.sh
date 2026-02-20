#!/usr/bin/env bash
set -euo pipefail

hash_first_field() {
  awk '{print $1}'
}

local_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | hash_first_field
    return
  fi

  shasum -a 256 "$1" | hash_first_field
}

remote_hash() {
  local host="$1"
  local file="$2"
  ssh "$host" "sha256sum '$file' 2>/dev/null || shasum -a 256 '$file'" | hash_first_field
}

REMOTE_HOST="${REMOTE_HOST:-root@49.13.217.227}"
REMOTE_DIR="${REMOTE_DIR:-/srv/web/vaultmesh}"
REMOTE_DIR="${REMOTE_DIR%/}"

./build.sh
cat dist/MANIFEST.sha256
# Use checksum mode because files have deterministic mtimes and may keep equal size
# across commits while content changes (e.g., BUILD_ID placeholder replacement).
rsync -avzc --delete dist/ "${REMOTE_HOST}:${REMOTE_DIR}/"

LOCAL_MANIFEST_HASH=$(local_hash "dist/MANIFEST.sha256")
REMOTE_MANIFEST_HASH=$(remote_hash "${REMOTE_HOST}" "${REMOTE_DIR}/MANIFEST.sha256")

if [[ "${LOCAL_MANIFEST_HASH}" != "${REMOTE_MANIFEST_HASH}" ]]; then
  echo "DEPLOY_VERIFY_FAILED local=${LOCAL_MANIFEST_HASH} remote=${REMOTE_MANIFEST_HASH}" >&2
  exit 1
fi

echo "DEPLOY_OK manifest=${REMOTE_MANIFEST_HASH}"
