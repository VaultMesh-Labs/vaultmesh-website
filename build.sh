#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_lib/routes_required.sh
source "${SCRIPT_DIR}/scripts/_lib/routes_required.sh"

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

inject_marker_file() {
  local marker="$1"
  local fragment="$2"
  local file="$3"
  local tmp

  if ! grep -Fq "$marker" "$file"; then
    return
  fi

  tmp="${file}.tmp"
  awk -v marker="$marker" -v fragment="$fragment" '
    index($0, marker) > 0 {
      while ((getline line < fragment) > 0) {
        print line
      }
      close(fragment)
      next
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

is_nojs_static_surface() {
  local file="$1"
  case "$file" in
    */architecture/index.html|*/pricing/index.html|*/proof-pack/intake/index.html|*/support/ticket/index.html)
      return 0
      ;;
  esac
  return 1
}

write_manifest() {
  (
    cd dist
    while IFS= read -r -d '' file; do
      if [[ "$file" == *.html ]]; then
        tmp="$(mktemp)"
        sed -E 's#Manifest: sha256:[0-9a-fA-F]{64}#Manifest: sha256:UNSET#g' "$file" > "$tmp"
        file_hash="$(hash_file "$tmp" | awk '{print $1}')"
        rm -f "$tmp"
        printf "%s  %s\n" "$file_hash" "$file"
      else
        hash_file "$file"
      fi
    done < <(find . -type f ! -name "MANIFEST.sha256" ! -name "BUILD_PROOF.txt" ! -name ".DS_Store" -print0 | sort -z) > MANIFEST.sha256
  )
}

rm -rf dist
mkdir -p dist
rsync -av --delete --exclude '.DS_Store' public/ dist/
find dist -name '.DS_Store' -delete

if [[ -n "${BUILD_ID_OVERRIDE:-}" ]]; then
  BUILD_ID="${BUILD_ID_OVERRIDE}"
else
  BUILD_ID="$(git log -n 1 --format=%h -- public 2>/dev/null || true)"
  if [[ -z "${BUILD_ID}" ]]; then
    BUILD_ID="$(git rev-parse --short HEAD 2>/dev/null || echo "dev")"
  fi
fi
# Inject canonical attestation panel partial only when wrapper placeholder is present.
if [[ -f dist/attest/index.html && -f public/shared/partials/attest_panel.html ]] && grep -q "{{ATTEST_PANEL}}" dist/attest/index.html; then
  sed '/{{ATTEST_PANEL}}/{
    r public/shared/partials/attest_panel.html
    d
  }' dist/attest/index.html > dist/attest/index.html.tmp
  mv dist/attest/index.html.tmp dist/attest/index.html
fi

NAV_NOJS_TMP="$(mktemp)"
awk '
  /<script[[:space:]>]/ { in_script=1; next }
  /<\/script>/ { in_script=0; next }
  !in_script { print }
' public/shared/nav.html > "$NAV_NOJS_TMP"

while IFS= read -r -d '' html_file; do
  nav_fragment="public/shared/nav.html"
  if is_nojs_static_surface "$html_file"; then
    nav_fragment="$NAV_NOJS_TMP"
  fi
  inject_marker_file "<!-- {{NAV}} -->" "$nav_fragment" "$html_file"
  inject_marker_file "<!-- {{FOOTER}} -->" "public/shared/footer.html" "$html_file"
done < <(find dist -type f -name "*.html" -print0)
rm -f "$NAV_NOJS_TMP"

# Shared template fragments are build inputs, not shipped artifacts.
rm -f dist/shared/nav.html dist/shared/footer.html
rm -rf dist/shared/partials

find dist -type f -name "*.html" -exec sed -i.bak "s/{{BUILD_ID}}/${BUILD_ID}/g" {} +
find dist -type f -name "*.html" -exec sed -E -i.bak "s/Build: STATIC/Build: ${BUILD_ID}/g" {} +
find dist -type f -name "*.bak" -delete

find dist -exec touch -t 202001010000 {} +

write_manifest
MANIFEST_SHA="$(hash_file dist/MANIFEST.sha256 | awk '{print $1}')"
find dist -type f -name "*.html" -exec sed -E -i.bak "s#Manifest: sha256:(UNSET|[0-9a-fA-F]{64})#Manifest: sha256:${MANIFEST_SHA}#g" {} +
find dist -type f -name "*.bak" -delete

write_manifest
FINAL_MANIFEST_SHA="$(hash_file dist/MANIFEST.sha256 | awk '{print $1}')"
if [[ "${FINAL_MANIFEST_SHA}" != "${MANIFEST_SHA}" ]]; then
  find dist -type f -name "*.html" -exec sed -E -i.bak "s#Manifest: sha256:(UNSET|[0-9a-fA-F]{64})#Manifest: sha256:${FINAL_MANIFEST_SHA}#g" {} +
  find dist -type f -name "*.bak" -delete
  write_manifest
fi

hash_file dist/MANIFEST.sha256 > dist/BUILD_PROOF.txt

ROUTES_CSV="${VM_ROUTES_REQUIRED_CSV}"
BUILD_INFO_TMP="$(mktemp)"
IFS=',' read -r -a REQUIRED_ROUTES <<< "${ROUTES_CSV}"
for route in "${REQUIRED_ROUTES[@]}"; do
  route="${route#"${route%%[![:space:]]*}"}"
  route="${route%"${route##*[![:space:]]}"}"
  [[ -n "${route}" ]] || continue
  if [[ -f "dist/${route}" ]]; then
    route_sha="sha256:$(hash_file "dist/${route}" | awk '{print $1}')"
  else
    route_sha="MISSING"
  fi
  printf '%s  %s\n' "${route_sha}" "${route}" >> "${BUILD_INFO_TMP}"
done
DIST_TREE_SHA256="sha256:$(hash_file "${BUILD_INFO_TMP}" | awk '{print $1}')"
rm -f "${BUILD_INFO_TMP}"

BUILD_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-${BUILD_ID}"
BUILD_INFO_FILE="dist/${VM_BUILD_INFO_PATH}"
mkdir -p "$(dirname "${BUILD_INFO_FILE}")"
cat > "${BUILD_INFO_FILE}" <<EOF
{
  "kind": "vaultmesh.website.build_info.v1",
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_id": "${BUILD_ID}",
  "build_run_id": "${BUILD_RUN_ID}",
  "routes_csv": "${ROUTES_CSV}",
  "dist_tree_sha256": "${DIST_TREE_SHA256}"
}
EOF

echo "BUILD_OK=1"
