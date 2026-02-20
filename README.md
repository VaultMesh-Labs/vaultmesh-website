# VaultMesh Website

Deterministic static public surface for `vaultmesh.org`.

## Authoritative Layout

```text
public/
  index.html
  proof-pack/index.html
  support/index.html
  trust/index.html
  verify/index.html
  attest/
    index.html
    ROOT_HISTORY.txt
    ROOT_HISTORY.sig
  shared/
    ui.css
    nav.html
    footer.html
    partials/
      attest_panel.html
```

Historical snapshots are not stored in `public/`; history is preserved in Git commits.

## Build

```bash
./scripts/build.sh
```

`scripts/build.sh` produces:
- `dist/` (site artifact root)
- `dist/site/` (deploy export lane)
- fixed mtimes (`2020-01-01T00:00:00`)
- `dist/MANIFEST.sha256`
- `dist/BUILD_PROOF.txt`

The script also replaces `{{BUILD_ID}}` in HTML files with `git rev-parse --short HEAD`.
`dist/attest/index.html` is built by injecting `public/shared/partials/attest_panel.html` into the `{{ATTEST_PANEL}}` placeholder.
The script injects `public/shared/nav.html` and `public/shared/footer.html` into every page via `<!-- {{NAV}} -->` and `<!-- {{FOOTER}} -->` markers.
Footer placeholders are populated with:
- `Build: <shortsha>`
- `Manifest: sha256:<hex>`

## Deploy

```bash
bash scripts/deploy_edge.sh
```

Defaults:
- `host_alias=edge-1`
- `root_path=/srv/web/vaultmesh`
- `caddyfile_path=/etc/caddy/Caddyfile`

`scripts/deploy_edge.sh` performs:
1. build/export to `dist/site/`
2. `scripts/sot_guard.sh --pre`
3. staged upload on edge
4. staging hash verification
5. atomic promote to live root
6. Caddyfile install from repo snapshot
7. Caddy validate + reload
8. remote `sot_guard --live` postcheck
9. append-only `reports/site_deploy.ndjson` receipt

## Make Targets

```bash
make build
make deploy
make deploy-edge
make verify
make guard
make sot-lock
make sot-guard
make host-split-lock
make ui-skin-lock
make where
make clean
```

## Drift Guard

```bash
bash scripts/nav_footer_guard.sh
```

The guard fails if:
- any shipped page in `dist/` is missing `vm-nav` or `vm-footer`
- `/shared/ui.css` is missing or not referenced
- skin tokens are defined outside `public/shared/ui.css`

## Caddy Guard

```bash
bash scripts/caddy_guard.sh --repo-snapshot deploy/edge/etc/caddy/Caddyfile
```

`scripts/caddy_guard.sh` enforces:
- config validates with `caddy validate`
- `vaultmesh.org` root lock to `/srv/web/vaultmesh`
- no static reverse-proxy drift on `/proof-pack/*` and `/support/*`

## Host Split Guard

```bash
bash scripts/host_split_guard.sh --config deploy/edge/etc/caddy/Caddyfile
```

`scripts/host_split_guard.sh` enforces:
- `vaultmesh.org` is static-only (`root * /srv/web/vaultmesh` + `file_server`)
- `vaultmesh.org` contains no `reverse_proxy`
- `cc.vaultmesh.org` exists and carries dynamic `reverse_proxy` handling

## SOT Guard

```bash
bash scripts/sot_guard.sh --repo
bash scripts/sot_guard.sh --live
```

`scripts/sot_guard.sh` enforces:
- canonical snapshot exists at `deploy/edge/root/vaultmesh` and `deploy/edge/etc/caddy/Caddyfile`
- live root/caddy parity against canonical snapshot
- explicit failure codes and deterministic stdout markers

## Canonical Deploy Snapshot

```text
deploy/edge/MANIFEST.json
deploy/edge/etc/caddy/Caddyfile
deploy/edge/root/vaultmesh/**
```

## UI Skin Guard

```bash
bash scripts/ui_skin_guard.sh --repo
./build.sh
bash scripts/ui_skin_guard.sh --dist
```

`scripts/ui_skin_guard.sh` enforces:
- every HTML surface imports `/shared/ui.css?v=bone-v04`
- no inline `<style>` blocks or `style=` attributes in HTML
- no `--vm-*` / `--bone-*` token redeclarations outside `shared/ui.css`
- no hardcoded color literals outside `shared/ui.css`
