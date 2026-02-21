#!/usr/bin/env bash
set -euo pipefail

# vaultmesh.website.release_attest_deploy.v1
#
# Emits RELEASE_ATTEST.json describing the exact deployed snapshot root.
#
# RC:
# 0 ok
# 10 usage
# 11 prereq
# 20 mismatch / write failure

die() { echo "DEPLOY_ATTEST_FAIL rc=${1} ${2:-}" >&2; exit "${1}"; }
ok()  { echo "DEPLOY_ATTEST_OK out_json=${1}"; }

need() { command -v "$1" >/dev/null 2>&1 || die 11 "missing_prereq:$1"; }

usage() {
  cat >&2 <<'EOF'
Usage:
  bash scripts/deploy_release_attest.sh \
    --dist-build-info dist/BUILD_INFO.json \
    --deploy-root deploy/edge/root/vaultmesh \
    --deploy-target-id edge-1:vaultmesh-root \
    --deploy-host edge-1 \
    --base-url https://vaultmesh.org \
    --caddyfile deploy/edge/etc/caddy/Caddyfile \
    --out-json deploy/edge/root/vaultmesh/attest/RELEASE_ATTEST.json
EOF
  exit 10
}

DIST_BUILD_INFO=""
DEPLOY_ROOT=""
DEPLOY_TARGET_ID=""
DEPLOY_HOST=""
BASE_URL=""
CADDYFILE=""
OUT_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist-build-info) DIST_BUILD_INFO="$2"; shift 2;;
    --deploy-root)     DEPLOY_ROOT="$2"; shift 2;;
    --deploy-target-id) DEPLOY_TARGET_ID="$2"; shift 2;;
    --deploy-host)     DEPLOY_HOST="$2"; shift 2;;
    --base-url)        BASE_URL="$2"; shift 2;;
    --caddyfile)       CADDYFILE="$2"; shift 2;;
    --out-json)        OUT_JSON="$2"; shift 2;;
    -h|--help)         usage;;
    *) die 10 "unknown_arg:$1";;
  esac
done

[[ -n "$DIST_BUILD_INFO" && -n "$DEPLOY_ROOT" && -n "$DEPLOY_TARGET_ID" && -n "$DEPLOY_HOST" && -n "$BASE_URL" && -n "$CADDYFILE" && -n "$OUT_JSON" ]] || usage

need python3
need shasum
need find
need sort
need awk
need date

[[ -f "$DIST_BUILD_INFO" ]] || die 11 "missing_file:$DIST_BUILD_INFO"
[[ -f "$CADDYFILE" ]] || die 11 "missing_file:$CADDYFILE"
[[ -d "$DEPLOY_ROOT" ]] || die 11 "missing_dir:$DEPLOY_ROOT"

# Build run id from dist build info
BUILD_RUN_ID="$(python3 - <<PY
import json
p="$DIST_BUILD_INFO"
d=json.load(open(p,"r",encoding="utf-8"))
print(d.get("build_run_id",""))
PY
)"
[[ -n "$BUILD_RUN_ID" ]] || die 11 "missing_build_run_id_in:$DIST_BUILD_INFO"

# Canonical tree hash of deploy root (stable list of file sha256s, relative paths)
# Excludes:
# - anything under .git
# - reports/
# - the attestation output file itself (if it is inside deploy root), to avoid self-reference
TREE_SHA256="$(
DEPLOY_ROOT="$DEPLOY_ROOT" OUT_JSON="$OUT_JSON" python3 - <<'PY'
import hashlib
import os

root = os.path.realpath(os.environ["DEPLOY_ROOT"])
out_json = os.path.realpath(os.environ["OUT_JSON"])
ignore_prefixes = (".git/", "reports/")

out_rel = None
if out_json.startswith(root + os.sep):
  out_rel = os.path.relpath(out_json, root).replace("\\", "/")

# Canonical public deploy attestation path is excluded from tree hash to avoid
# self-reference and allow deterministic verification re-runs.
excluded_files = {"attest/RELEASE_ATTEST.json"}
if out_rel is not None:
  excluded_files.add(out_rel)

items = []
for base, dirs, files in os.walk(root):
  rel_base = os.path.relpath(base, root)
  if rel_base == ".":
    rel_base = ""

  pruned = []
  for d in dirs:
    rel_dir = (rel_base + ("/" if rel_base else "") + d + "/")
    if rel_dir.startswith(ignore_prefixes):
      continue
    pruned.append(d)
  dirs[:] = pruned

  for f in files:
    rel = (rel_base + ("/" if rel_base else "") + f)
    if rel.startswith(ignore_prefixes):
      continue
    if rel in excluded_files:
      continue
    path = os.path.join(base, f)
    h = hashlib.sha256()
    with open(path, "rb") as fp:
      for chunk in iter(lambda: fp.read(1024 * 1024), b""):
        h.update(chunk)
    items.append(f"{h.hexdigest()}  {rel}")

items.sort()
root_h = hashlib.sha256(("\n".join(items) + "\n").encode("utf-8")).hexdigest()
print("sha256:" + root_h)
PY
)"

CADDY_SHA256="sha256:$(shasum -a 256 "$CADDYFILE" | awk '{print $1}')"
TS_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$(dirname "$OUT_JSON")"

python3 - <<PY
import json
out = {
  "kind": "vaultmesh.website.release_attest_deploy.v1",
  "generated_at_utc": "$TS_UTC",
  "build_run_id": "$BUILD_RUN_ID",
  "deploy_target_id": "$DEPLOY_TARGET_ID",
  "deploy_host": "$DEPLOY_HOST",
  "base_url": "$BASE_URL",
  "deployed_root_tree_sha256": "$TREE_SHA256",
  "caddyfile_sha256": "$CADDY_SHA256",
  "attest_excludes": ["attest/RELEASE_ATTEST.json"]
}
with open("$OUT_JSON","w",encoding="utf-8") as f:
  json.dump(out,f,indent=2,sort_keys=True)
  f.write("\n")
PY

# Read back and sanity-check we wrote what we think we wrote
READBACK_TREE="$(python3 - <<PY
import json
d=json.load(open("$OUT_JSON","r",encoding="utf-8"))
print(d.get("deployed_root_tree_sha256",""))
PY
)"
[[ "$READBACK_TREE" == "$TREE_SHA256" ]] || die 20 "attest_writeback_mismatch"

ok "$OUT_JSON"
exit 0
