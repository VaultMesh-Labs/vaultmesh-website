#!/usr/bin/env bash
# sign_manifest.sh — Sign MANIFEST.sha256 with Ed25519
#
# Usage:
#   sign_manifest.sh <signing_key.pem> <dist_dir>
#
# Produces:
#   <dist_dir>/attest/MANIFEST.sha256.sig   (raw 64-byte Ed25519 signature)
#
# Key generation (one-time):
#   openssl genpkey -algorithm Ed25519 -out website_manifest_ed25519.pem
#
# Extract raw 32-byte public key for CC:
#   openssl pkey -in website_manifest_ed25519.pem -pubout -outform DER | tail -c 32 > website_manifest_ed25519.pub
#
# Requires: OpenSSL 1.1.1+ with Ed25519 support.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: sign_manifest.sh <signing_key.pem> <dist_dir>" >&2
  exit 1
fi

KEY_FILE="$1"
DIST_DIR="$2"
MANIFEST="${DIST_DIR}/MANIFEST.sha256"
SIG_OUT="${DIST_DIR}/attest/MANIFEST.sha256.sig"

if [[ ! -f "${KEY_FILE}" ]]; then
  echo "SIGN_FAIL: key file not found: ${KEY_FILE}" >&2
  exit 2
fi

if [[ ! -f "${MANIFEST}" ]]; then
  echo "SIGN_FAIL: manifest not found: ${MANIFEST}" >&2
  exit 3
fi

# Verify openssl has Ed25519 support
if ! openssl pkey -in "${KEY_FILE}" -noout 2>/dev/null; then
  echo "SIGN_FAIL: cannot read key (OpenSSL Ed25519 support required)" >&2
  exit 4
fi

mkdir -p "$(dirname "${SIG_OUT}")"

openssl pkeyutl -sign \
  -inkey "${KEY_FILE}" \
  -in "${MANIFEST}" \
  -out "${SIG_OUT}"

# Verify the signature length is exactly 64 bytes (Ed25519)
SIG_SIZE="$(wc -c < "${SIG_OUT}" | tr -d ' ')"
if [[ "${SIG_SIZE}" -ne 64 ]]; then
  echo "SIGN_FAIL: unexpected signature size ${SIG_SIZE} (expected 64)" >&2
  rm -f "${SIG_OUT}"
  exit 5
fi

echo "SIGN_OK=1"
echo "SIGN_SIG=${SIG_OUT}"
