#!/usr/bin/env bash
set -euo pipefail

# UI_SKIN_GUARD_v0
# Enforce one canonical visual contract (scc-v1):
# - public/shared/ui.css is the only token source
# - every shipped HTML imports /shared/ui.css?v=bone-v05
# - no inline style blocks or style attributes in HTML
# - no hardcoded color literals outside shared/ui.css

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

MODE="repo"
TARGET_DIR="public"
SKIN_FILE="public/shared/ui.css"
VERSION_LOCK="${UI_SKIN_VERSION_LOCK:-scc-v1}"

RC_USAGE=2
RC_MISSING=11
RC_TOOLING=12
RC_IMPORT=21
RC_INLINE=22
RC_TOKEN=23
RC_COLOR=24
RC_SHA=25
RC_ROUTE=26

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "UI_SKIN_GUARD_FAIL missing_tool=$1" >&2
    exit "${RC_TOOLING}"
  }
}

need grep
need find
need awk
need sha256sum

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      MODE="repo"
      TARGET_DIR="public"
      shift
      ;;
    --dist)
      MODE="dist"
      TARGET_DIR="dist"
      shift
      ;;
    --dir)
      TARGET_DIR="${2:-}"
      [[ -n "${TARGET_DIR}" ]] || {
        echo "UI_SKIN_GUARD_FAIL missing_arg=--dir" >&2
        exit "${RC_USAGE}"
      }
      shift 2
      ;;
    --help|-h)
      cat <<'USAGEEOF'
Usage:
  bash scripts/ui_skin_guard.sh [--repo|--dist] [--dir <path>]

Default: --repo
USAGEEOF
      exit 0
      ;;
    *)
      echo "UI_SKIN_GUARD_FAIL unknown_arg=$1" >&2
      exit "${RC_USAGE}"
      ;;
  esac
done

[[ -f "${SKIN_FILE}" ]] || {
  echo "UI_SKIN_GUARD_FAIL missing_skin=${SKIN_FILE}" >&2
  exit "${RC_MISSING}"
}

BASE="${ROOT_DIR}/${TARGET_DIR}"
[[ -d "${BASE}" ]] || {
  echo "UI_SKIN_GUARD_FAIL missing_target_dir=${TARGET_DIR}" >&2
  exit "${RC_MISSING}"
}

UI_SHA="$(sha256sum "${SKIN_FILE}" | awk '{print $1}')"

echo "UI_SKIN_PRESENT=1"
echo "UI_SKIN_MODE=${MODE}"
echo "UI_SKIN_TARGET=${TARGET_DIR}"
echo "UI_SKIN_VERSION=${VERSION_LOCK}"
echo "UI_SKIN_SHA256=sha256:${UI_SHA}"

if [[ "${MODE}" == "dist" ]]; then
  DIST_UI="${BASE}/shared/ui.css"
  [[ -f "${DIST_UI}" ]] || {
    echo "UI_SKIN_GUARD_FAIL missing_dist_skin=${TARGET_DIR}/shared/ui.css" >&2
    exit "${RC_MISSING}"
  }
  DIST_UI_SHA="$(sha256sum "${DIST_UI}" | awk '{print $1}')"
  if [[ "${DIST_UI_SHA}" != "${UI_SHA}" ]]; then
    echo "UI_SKIN_GUARD_FAIL skin_sha_mismatch repo=sha256:${UI_SHA} dist=sha256:${DIST_UI_SHA}" >&2
    exit "${RC_SHA}"
  fi
fi

mapfile -d '' HTML_FILES < <(find "${BASE}" -type f -name 'index.html' -print0 | sort -z)
if [[ "${#HTML_FILES[@]}" -eq 0 ]]; then
  echo "UI_SKIN_GUARD_FAIL no_html_found_in=${TARGET_DIR}" >&2
  exit "${RC_MISSING}"
fi

stylesheets_ok=1
inline_ok=1
route_ok=1

for file in "${HTML_FILES[@]}"; do
  rel="${file#${BASE}/}"
  rel="${rel#site/}"

  total_stylesheets="$( (grep -Eio '<link[^>]+rel=["'"'"']stylesheet["'"'"'][^>]*>' "${file}" || true) | wc -l | awk '{print $1}' )"
  locked_stylesheets="$( (grep -Eio "<link[^>]+rel=['\\\"]stylesheet['\\\"][^>]*href=['\\\"]/shared/ui\\.css\\?v=${VERSION_LOCK}['\\\"][^>]*>" "${file}" || true) | wc -l | awk '{print $1}' )"

  if [[ "${total_stylesheets}" -lt 1 || "${total_stylesheets}" -ne "${locked_stylesheets}" ]]; then
    echo "UI_SKIN_GUARD_FAIL stylesheet_lock_violation file=${file}" >&2
    stylesheets_ok=0
  fi

  if grep -nEi '<style\b|\sstyle=["'"'"']' "${file}" >/dev/null 2>&1; then
    echo "UI_SKIN_GUARD_FAIL inline_style_detected file=${file}" >&2
    inline_ok=0
  fi

  case "${rel}" in
    index.html|attest/index.html|trust/index.html|verify/index.html|proof-pack/index.html|proof-pack/intake/index.html|support/index.html|support/ticket/index.html|architecture/index.html|pricing/index.html)
      if ! grep -Eq '<body[^>]*class="[^"]*vm-attest' "${file}"; then
        echo "UI_SKIN_GUARD_FAIL route_shell_mismatch file=${file} expected=vm-attest" >&2
        route_ok=0
      fi
      if ! grep -Eq 'class="wrap"|class="page"' "${file}"; then
        echo "UI_SKIN_GUARD_FAIL route_shell_mismatch file=${file} expected=wrap|page" >&2
        route_ok=0
      fi
      ;;
  esac
done

if [[ "${stylesheets_ok}" -ne 1 ]]; then
  exit "${RC_IMPORT}"
fi

if [[ "${inline_ok}" -ne 1 ]]; then
  exit "${RC_INLINE}"
fi

if [[ "${route_ok}" -ne 1 ]]; then
  exit "${RC_ROUTE}"
fi

# Token source lock: no vm/bone token declarations outside shared/ui.css
while IFS= read -r -d '' css_file; do
  if [[ "${css_file}" == *"/shared/ui.css" ]]; then
    continue
  fi

  if grep -nE '^[[:space:]]*--(vm|bone)-[a-zA-Z0-9_-]+[[:space:]]*:' "${css_file}" >/dev/null 2>&1; then
    echo "UI_SKIN_GUARD_FAIL token_redeclared file=${css_file}" >&2
    exit "${RC_TOKEN}"
  fi
done < <(find "${BASE}" -type f -name '*.css' -print0)

# Color lock: no literal colors outside shared/ui.css (hex/rgb/hsl)
while IFS= read -r -d '' style_file; do
  if [[ "${style_file}" == *"/shared/ui.css" ]]; then
    continue
  fi

  if grep -nEi '#[0-9a-f]{3,8}\b|rgba?\s*\(|hsla?\s*\(' "${style_file}" >/dev/null 2>&1; then
    echo "UI_SKIN_GUARD_FAIL color_literal_outside_skin file=${style_file}" >&2
    grep -nEi '#[0-9a-f]{3,8}\b|rgba?\s*\(|hsla?\s*\(' "${style_file}" | head -n 5 >&2 || true
    exit "${RC_COLOR}"
  fi
done < <(find "${BASE}" -type f \( -name '*.css' -o -name '*.html' \) -print0)

echo "UI_SKIN_GUARD_OK=1"
echo "UI_SKIN_GUARD_SUMMARY mode=${MODE} checked_html=${#HTML_FILES[@]} ui_sha256=sha256:${UI_SHA}"
