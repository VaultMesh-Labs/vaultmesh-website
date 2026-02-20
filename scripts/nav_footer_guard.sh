#!/usr/bin/env bash
# scripts/nav_footer_guard.sh
# NAV_FOOTER_v0 guard: marker-first, token-safe, CI-friendly.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RC_USAGE=2
RC_MISSING=11
RC_TOKEN_DRIFT=12
RC_MARKER_MISSING=13
RC_IMPORT_MISSING=14
RC_BUILD_MISSING=15
RC_BAD_SHA=16

need() { command -v "$1" >/dev/null 2>&1 || { echo "NAV_FOOTER_GUARD_FAIL tooling_missing=$1" >&2; exit "$RC_BUILD_MISSING"; }; }
need sha256sum
need grep
need find
need awk

MODE="dist"
TARGET_DIR="dist"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) MODE="repo"; TARGET_DIR="public"; shift ;;
    --dist) MODE="dist"; TARGET_DIR="dist"; shift ;;
    --dir)  TARGET_DIR="${2:-}"; [[ -n "${TARGET_DIR:-}" ]] || { echo "usage: --dir <path>" >&2; exit "$RC_USAGE"; }; shift 2 ;;
    -h|--help)
      cat <<'USAGEEOF'
Usage:
  bash scripts/nav_footer_guard.sh [--dist|--repo] [--dir <path>]

Default: --dist (checks dist/)
--repo: checks public/ (pre-build)
--dir: override base dir for HTML scan
USAGEEOF
      exit 0
      ;;
    *)
      echo "NAV_FOOTER_GUARD_FAIL unknown_arg=$1" >&2
      exit "$RC_USAGE"
      ;;
  esac
done

UI_CSS="$ROOT_DIR/public/shared/ui.css"
NAV_PART="$ROOT_DIR/public/shared/nav.html"
FOOT_PART="$ROOT_DIR/public/shared/footer.html"

# --- Required canonical files ---
[[ -f "$UI_CSS" ]] || { echo "NAV_FOOTER_GUARD_FAIL missing=public/shared/ui.css" >&2; exit "$RC_MISSING"; }
[[ -f "$NAV_PART" ]] || { echo "NAV_FOOTER_GUARD_FAIL missing=public/shared/nav.html" >&2; exit "$RC_MISSING"; }
[[ -f "$FOOT_PART" ]] || { echo "NAV_FOOTER_GUARD_FAIL missing=public/shared/footer.html" >&2; exit "$RC_MISSING"; }

UI_SHA="$(sha256sum "$UI_CSS" | awk '{print $1}')"
NAV_SHA="$(sha256sum "$NAV_PART" | awk '{print $1}')"
FOOT_SHA="$(sha256sum "$FOOT_PART" | awk '{print $1}')"

echo "NAV_FOOTER_PRESENT=1"
echo "NAV_FOOTER_MODE=$MODE"
echo "UI_SKIN_SHA256=sha256:$UI_SHA"
echo "NAV_SHA256=sha256:$NAV_SHA"
echo "FOOTER_SHA256=sha256:$FOOT_SHA"

# --- Token drift guard: forbid redeclaring canonical CSS vars outside UI_CSS ---
# We treat any '--bone-' or '--vm-' variable definitions as token redeclarations.
# Allow only in public/shared/ui.css
scan_token_redefs() {
  local base="$1"
  local bad=0
  while IFS= read -r -d '' f; do
    if [[ "$f" == *"/shared/ui.css" ]]; then
      continue
    fi
    if grep -nE '^[[:space:]]*--(bone|vm)-[a-zA-Z0-9_-]+[[:space:]]*:' "$f" >/dev/null 2>&1; then
      echo "NAV_FOOTER_GUARD_FAIL token_redeclared_in=$f" >&2
      grep -nE '^[[:space:]]*--(bone|vm)-[a-zA-Z0-9_-]+[[:space:]]*:' "$f" | head -n 5 >&2 || true
      bad=1
    fi
  done < <(find "$base" -type f -name '*.css' -print0 2>/dev/null)
  return "$bad"
}

# --- Import guard: HTML must reference shared/ui.css (versioned import allowed) ---
css_import_ok() {
  local f="$1"
  grep -Eq "href=['\\\"](\\./)?shared/ui\\.css(\\?v=[^'\\\" ]+)?['\\\"]" "$f" && return 0
  grep -Eq "href=['\\\"]/shared/ui\\.css(\\?v=[^'\\\" ]+)?['\\\"]" "$f" && return 0
  return 1
}

# --- Marker guard ---
has_repo_placeholders() {
  local f="$1"
  grep -q '<!-- {{NAV}} -->' "$f" && grep -q '<!-- {{FOOTER}} -->' "$f"
}

has_dist_blocks() {
  local f="$1"
  grep -q 'class="vm-nav' "$f" && grep -q 'class="vm-footer' "$f"
}

if [[ ! -d "$ROOT_DIR/$TARGET_DIR" ]]; then
  echo "NAV_FOOTER_GUARD_FAIL missing_target_dir=$TARGET_DIR" >&2
  exit "$RC_MISSING"
fi

mapfile -d '' HTMLS < <(find "$ROOT_DIR/$TARGET_DIR" -type f -name 'index.html' -print0 2>/dev/null || true)

if [[ "${#HTMLS[@]}" -eq 0 ]]; then
  echo "NAV_FOOTER_GUARD_FAIL no_html_found_in=$TARGET_DIR" >&2
  exit "$RC_MISSING"
fi

if [[ "$MODE" == "dist" ]]; then
  [[ -f "$ROOT_DIR/$TARGET_DIR/shared/ui.css" ]] || {
    echo "NAV_FOOTER_GUARD_FAIL dist_missing=shared/ui.css" >&2
    exit "$RC_MISSING"
  }
  DIST_UI_SHA="$(sha256sum "$ROOT_DIR/$TARGET_DIR/shared/ui.css" | awk '{print $1}')"
  if [[ "$DIST_UI_SHA" != "$UI_SHA" ]]; then
    echo "NAV_FOOTER_GUARD_FAIL ui_css_sha_mismatch repo=sha256:$UI_SHA dist=sha256:$DIST_UI_SHA" >&2
    exit "$RC_BAD_SHA"
  fi
fi

if scan_token_redefs "$ROOT_DIR/$TARGET_DIR"; then
  :
else
  echo "NAV_FOOTER_GUARD_FAIL token_drift=1" >&2
  exit "$RC_TOKEN_DRIFT"
fi

missing_import=0
missing_markers=0
checked=0

for f in "${HTMLS[@]}"; do
  checked=$((checked+1))

  if ! css_import_ok "$f"; then
    echo "NAV_FOOTER_GUARD_FAIL css_import_missing file=$f" >&2
    missing_import=1
  fi

  if [[ "$MODE" == "repo" ]]; then
    if ! has_repo_placeholders "$f"; then
      echo "NAV_FOOTER_GUARD_FAIL placeholders_missing file=$f" >&2
      missing_markers=1
    fi
  else
    if ! has_dist_blocks "$f"; then
      echo "NAV_FOOTER_GUARD_FAIL nav_footer_blocks_missing file=$f" >&2
      missing_markers=1
    fi
  fi
done

if [[ "$missing_import" -ne 0 ]]; then
  echo "NAV_FOOTER_GUARD_FAIL import_ok=0 checked=$checked" >&2
  exit "$RC_IMPORT_MISSING"
fi

if [[ "$missing_markers" -ne 0 ]]; then
  echo "NAV_FOOTER_GUARD_FAIL markers_ok=0 checked=$checked mode=$MODE" >&2
  exit "$RC_MARKER_MISSING"
fi

echo "NAV_FOOTER_GUARD_OK=1"
echo "NAV_FOOTER_GUARD_SUMMARY mode=$MODE checked=$checked ui_sha256=sha256:$UI_SHA"
