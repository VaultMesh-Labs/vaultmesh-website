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
./build.sh
```

`build.sh` produces:
- `dist/`
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
./deploy.sh
```

Defaults:
- `REMOTE_HOST=root@49.13.217.227`
- `REMOTE_DIR=/srv/web/vaultmesh`

`deploy.sh` builds, prints `dist/MANIFEST.sha256`, deploys with rsync, then verifies remote `MANIFEST.sha256` hash matches local.
Deployment uses rsync checksum mode so content changes are propagated even with fixed mtimes.

## Make Targets

```bash
make build
make deploy
make verify
make guard
make clean
```

## Drift Guard

```bash
bash scripts/nav_footer_guard.sh
```

The guard fails if:
- any shipped page in `dist/` is missing `vm-nav` or `vm-footer`
- any source page has inline `<style>`/`style=`
- any source page hardcodes color literals
- `/shared/ui.css` is missing or not referenced
- skin tokens are defined outside `public/shared/ui.css`
