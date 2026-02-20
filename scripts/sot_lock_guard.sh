#!/usr/bin/env bash
set -euo pipefail

# SOT_LOCK_v0
# Single source of truth lock:
# - source edits live in public/
# - build emits dist/
# - publish root is updated from dist/ only

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SOURCE_DIR="${SOT_SOURCE_DIR:-public}"
BUILD_DIR="${SOT_BUILD_DIR:-dist}"
PUBLISH_ROOT="${SOT_PUBLISH_ROOT:-/srv/web/vaultmesh}"
REMOTE_HOST="${REMOTE_HOST:-root@49.13.217.227}"

RC_USAGE=2
RC_MISSING=11
RC_TOOLING=12
RC_BUILD_CONTRACT=21
RC_DEPLOY_CONTRACT=22
RC_EDGE_CHECK=23

MODE="repo"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      MODE="repo"
      shift
      ;;
    --edge)
      MODE="edge"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage:
  bash scripts/sot_lock_guard.sh [--repo|--edge]

Modes:
  --repo  Validate source/build/deploy contracts in repository (default)
  --edge  Validate remote publish root parity using local dist manifest
EOF
      exit 0
      ;;
    *)
      echo "SOT_LOCK_FAIL unknown_arg=$1" >&2
      exit "${RC_USAGE}"
      ;;
  esac
done

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "SOT_LOCK_FAIL missing_tool=$1" >&2
    exit "${RC_TOOLING}"
  }
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi
  shasum -a 256 "$1" | awk '{print $1}'
}

need grep
need awk
need find

echo "SOT_LOCK_PRESENT=1"
echo "SOT_LOCK_MODE=${MODE}"
echo "SOT_LOCK_SOURCE_DIR=${SOURCE_DIR}"
echo "SOT_LOCK_BUILD_DIR=${BUILD_DIR}"
echo "SOT_LOCK_PUBLISH_ROOT=${PUBLISH_ROOT}"

[[ -d "${SOURCE_DIR}" ]] || {
  echo "SOT_LOCK_FAIL missing_source_dir=${SOURCE_DIR}" >&2
  exit "${RC_MISSING}"
}
[[ -f build.sh ]] || {
  echo "SOT_LOCK_FAIL missing_file=build.sh" >&2
  exit "${RC_MISSING}"
}
[[ -f deploy.sh ]] || {
  echo "SOT_LOCK_FAIL missing_file=deploy.sh" >&2
  exit "${RC_MISSING}"
}
[[ -f .gitignore ]] || {
  echo "SOT_LOCK_FAIL missing_file=.gitignore" >&2
  exit "${RC_MISSING}"
}

if [[ "${MODE}" == "repo" ]]; then
  # Build contract: source -> dist and manifest/proof generation.
  grep -Eq 'rsync[[:space:]].*public/.*dist/' build.sh || {
    echo "SOT_LOCK_FAIL reason=build_not_public_to_dist" >&2
    exit "${RC_BUILD_CONTRACT}"
  }
  grep -Eq 'MANIFEST\.sha256' build.sh || {
    echo "SOT_LOCK_FAIL reason=manifest_generation_missing" >&2
    exit "${RC_BUILD_CONTRACT}"
  }
  grep -Eq 'BUILD_PROOF\.txt' build.sh || {
    echo "SOT_LOCK_FAIL reason=build_proof_generation_missing" >&2
    exit "${RC_BUILD_CONTRACT}"
  }

  # Deploy contract: dist-only publish and remote manifest verify.
  grep -Eq '^\./build\.sh$' deploy.sh || {
    echo "SOT_LOCK_FAIL reason=deploy_missing_build_step" >&2
    exit "${RC_DEPLOY_CONTRACT}"
  }
  grep -Eq 'rsync[[:space:]].*--delete[[:space:]]+dist/[[:space:]]+"?\$\{?REMOTE_HOST\}?:\$\{?REMOTE_DIR\}?/?' deploy.sh || {
    echo "SOT_LOCK_FAIL reason=deploy_not_dist_only" >&2
    exit "${RC_DEPLOY_CONTRACT}"
  }
  grep -Eq 'REMOTE_MANIFEST_HASH' deploy.sh || {
    echo "SOT_LOCK_FAIL reason=deploy_remote_manifest_verify_missing" >&2
    exit "${RC_DEPLOY_CONTRACT}"
  }

  # Keep dist out of source control.
  grep -Eq '^dist/$' .gitignore || {
    echo "SOT_LOCK_FAIL reason=dist_not_ignored" >&2
    exit "${RC_BUILD_CONTRACT}"
  }

  # Ensure no shell script deploys public/ directly to publish root.
  if rg -n --glob '*.sh' --glob '!scripts/sot_lock_guard.sh' 'rsync.*public/.*([A-Za-z0-9._-]+@|/srv/web/vaultmesh|\$\{?REMOTE_DIR\}?)' . >/dev/null; then
    echo "SOT_LOCK_FAIL reason=public_direct_publish_detected" >&2
    exit "${RC_DEPLOY_CONTRACT}"
  fi

  BUILD_SHA="$(hash_file build.sh)"
  DEPLOY_SHA="$(hash_file deploy.sh)"
  echo "SOT_LOCK_BUILD_SHA256=sha256:${BUILD_SHA}"
  echo "SOT_LOCK_DEPLOY_SHA256=sha256:${DEPLOY_SHA}"
  echo "SOT_LOCK_OK=1"
  exit 0
fi

# edge mode
need ssh

[[ -f "${BUILD_DIR}/MANIFEST.sha256" ]] || {
  echo "SOT_LOCK_FAIL missing_local_manifest=${BUILD_DIR}/MANIFEST.sha256" >&2
  exit "${RC_MISSING}"
}

LOCAL_MANIFEST_SHA="$(hash_file "${BUILD_DIR}/MANIFEST.sha256")"

REMOTE_REALPATH="$(ssh "${REMOTE_HOST}" "readlink -f '${PUBLISH_ROOT}'")" || {
  echo "SOT_LOCK_FAIL reason=remote_publish_root_unreachable host=${REMOTE_HOST}" >&2
  exit "${RC_EDGE_CHECK}"
}

if [[ "${REMOTE_REALPATH}" != "${PUBLISH_ROOT}" ]]; then
  echo "SOT_LOCK_FAIL reason=publish_root_mismatch resolved=${REMOTE_REALPATH} expected=${PUBLISH_ROOT}" >&2
  exit "${RC_EDGE_CHECK}"
fi

REMOTE_MANIFEST_SHA="$(ssh "${REMOTE_HOST}" "sha256sum '${PUBLISH_ROOT}/MANIFEST.sha256' 2>/dev/null || shasum -a 256 '${PUBLISH_ROOT}/MANIFEST.sha256'" | awk '{print $1}')" || {
  echo "SOT_LOCK_FAIL reason=remote_manifest_missing path=${PUBLISH_ROOT}/MANIFEST.sha256" >&2
  exit "${RC_EDGE_CHECK}"
}

if [[ "${LOCAL_MANIFEST_SHA}" != "${REMOTE_MANIFEST_SHA}" ]]; then
  echo "SOT_LOCK_FAIL reason=manifest_mismatch local=sha256:${LOCAL_MANIFEST_SHA} remote=sha256:${REMOTE_MANIFEST_SHA}" >&2
  exit "${RC_EDGE_CHECK}"
fi

echo "SOT_LOCK_REMOTE_HOST=${REMOTE_HOST}"
echo "SOT_LOCK_LOCAL_MANIFEST_SHA256=sha256:${LOCAL_MANIFEST_SHA}"
echo "SOT_LOCK_REMOTE_MANIFEST_SHA256=sha256:${REMOTE_MANIFEST_SHA}"
echo "SOT_LOCK_OK=1"
