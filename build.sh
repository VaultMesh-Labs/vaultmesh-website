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

inject_route_identity() {
  local file="$1"
  local route="$2"

  python3 - "$file" "$route" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
route = sys.argv[2]
data = path.read_text(encoding="utf-8")

match = re.search(r"<body\b[^>]*>", data, flags=re.IGNORECASE)
if not match:
    raise SystemExit(f"missing <body> tag in {path}")

tag = match.group(0)
if re.search(r'\bdata-route\s*=\s*"[^"]*"', tag, flags=re.IGNORECASE):
    new_tag = re.sub(r'\bdata-route\s*=\s*"[^"]*"', f'data-route="{route}"', tag, flags=re.IGNORECASE)
else:
    new_tag = tag[:-1] + f' data-route="{route}">'

if new_tag != tag:
    data = data[:match.start()] + new_tag + data[match.end():]
    path.write_text(data, encoding="utf-8")
PY
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
    done < <(find . -type f ! -name "MANIFEST.sha256" ! -name "BUILD_PROOF.txt" ! -name "vaultmesh-site.json" ! -name ".DS_Store" -print0 | sort -z) > MANIFEST.sha256
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

while IFS= read -r -d '' html_file; do
  rel_path="${html_file#dist}"
  if [[ "${rel_path}" == */index.html ]]; then
    route="${rel_path%index.html}"
    [[ -n "${route}" ]] || route="/"
  else
    echo "BUILD_FAIL=non_index_html_not_allowed path=${html_file}" >&2
    exit 1
  fi
  inject_route_identity "${html_file}" "${route}"
done < <(find dist -type f -name "*.html" -print0 | sort -z)

# Parity file — website's signed claim of what depot index it believes is current.
# Included in MANIFEST.sha256 (and therefore covered by manifest signature).
# Set VM_PARITY_PUBLIC_INDEX_PATH to a local copy of bastion PUBLIC_INDEX.json.
PARITY_FILE="dist/.well-known/vaultmesh-parity.json"
mkdir -p "$(dirname "${PARITY_FILE}")"
if [[ -n "${VM_PARITY_PUBLIC_INDEX_PATH:-}" && -f "${VM_PARITY_PUBLIC_INDEX_PATH}" ]]; then
  PARITY_INDEX_SHA="sha256:$(hash_file "${VM_PARITY_PUBLIC_INDEX_PATH}" | awk '{print $1}')"
  # Extract latest release fields (first entry) via awk — no jq dependency.
  PARITY_LATEST_NAME="$(awk -F'"' '/"name"/ {print $4; exit}' "${VM_PARITY_PUBLIC_INDEX_PATH}")"
  PARITY_LATEST_SHA="$(awk -F'"' '/"sha256"/ {print $4; exit}' "${VM_PARITY_PUBLIC_INDEX_PATH}")"
  cat > "${PARITY_FILE}" <<PARITY
{
  "kind": "vaultmesh.website.parity.v1",
  "schema_version": 1,
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "scc_depot": {
    "source": "local_snapshot",
    "public_index_path": "${VM_PARITY_PUBLIC_INDEX_REMOTE_PATH:-/srv/vaultmesh/releases/public/PUBLIC_INDEX.json}",
    "public_index_sha256": "${PARITY_INDEX_SHA}",
    "latest_release": {
      "name": "${PARITY_LATEST_NAME}",
      "sha256": "${PARITY_LATEST_SHA}"
    }
  }
}
PARITY
else
  cat > "${PARITY_FILE}" <<PARITY
{
  "kind": "vaultmesh.website.parity.v1",
  "schema_version": 1,
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "scc_depot": {
    "source": "none"
  }
}
PARITY
fi

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

# Manifest signing — conditional on VM_SITE_SIGNING_KEY.
# Produces /attest/MANIFEST.sha256.sig (raw 64-byte Ed25519 signature).
MANIFEST_SIGNED="false"
if [[ -n "${VM_SITE_SIGNING_KEY:-}" && -f "${VM_SITE_SIGNING_KEY}" ]]; then
  if bash "${SCRIPT_DIR}/scripts/sign_manifest.sh" "${VM_SITE_SIGNING_KEY}" dist >/dev/null; then
    MANIFEST_SIGNED="true"
  else
    echo "WARN: manifest signing failed (build continues unsigned)" >&2
  fi
fi

# Site identity document — machine-readable build heartbeat.
# Excluded from manifest so it can reference the final manifest hash.
SITE_ID_FILE="dist/.well-known/vaultmesh-site.json"
mkdir -p "$(dirname "${SITE_ID_FILE}")"
SITE_ORIGIN="${VM_SITE_ORIGIN:-https://vaultmesh.org}"
if [[ "${MANIFEST_SIGNED}" == "true" ]]; then
  SIG_URL_LINE="\"signature_url\": \"/attest/MANIFEST.sha256.sig\","
else
  SIG_URL_LINE="\"signature_url\": null,"
fi
cat > "${SITE_ID_FILE}" <<SITEID
{
  "kind": "vaultmesh.website.site_identity.v1",
  "schema_version": 1,
  "origin": "${SITE_ORIGIN}",
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_id": "${BUILD_ID}",
  "manifest_sha256": "sha256:${FINAL_MANIFEST_SHA:-${MANIFEST_SHA}}",
  "manifest_url": "/MANIFEST.sha256",
  ${SIG_URL_LINE}
  "attest_url": "/attest/",
  "verification_instructions_url": "/attest/#verify",
  "manifest_signed": ${MANIFEST_SIGNED},
  "artifacts": {
    "latest_txt": "/attest/LATEST.txt",
    "root_history": "/attest/ROOT_HISTORY.txt",
    "root_history_sig": "/attest/ROOT_HISTORY.sig"
  }
}
SITEID
touch -t 202001010000 "${SITE_ID_FILE}"

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

# Keep BUILD_INFO mtime deterministic for parity/freshness guard.
touch -t 202001010000 "${BUILD_INFO_FILE}"

echo "BUILD_OK=1"
