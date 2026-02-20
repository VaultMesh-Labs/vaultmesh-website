# SOT_LOCK_v0

## Canonical Tree

- `deploy/edge/MANIFEST.json`
- `deploy/edge/etc/caddy/Caddyfile`
- `deploy/edge/root/vaultmesh/**`

## Guard Contract

Run:

```bash
bash scripts/sot_guard.sh --repo
bash scripts/sot_guard.sh --live
```

Success markers (tail order):

```text
SOT_MODE=repo|live
SOT_ROOT_SHA256=sha256:<64hex>
SOT_CADDY_SHA256=sha256:<64hex>
SOT_MANIFEST_SHA256=sha256:<64hex>
SOT_GUARD_OK=1
```

Failure markers:

```text
SOT_GUARD_FAIL=<REASON>
SOT_GUARD_RC=<code>
```

Reasons:

- `MISSING_REQUIRED`
- `ROOT_DRIFT`
- `CADDY_DRIFT`
- `UNEXPECTED_FILES`
- `TOOLING_MISSING`
- `PERMISSION_DENIED`
- `BAD_MANIFEST`

Exit codes:

- `2` usage
- `10` missing required files
- `11` root drift
- `12` caddy drift
- `13` unexpected files
- `14` tooling missing
- `15` permission denied
- `16` bad manifest

## Deploy Lane

Run:

```bash
bash scripts/deploy_edge.sh
```

Success markers (tail order):

```text
DEPLOY_HOST=edge-1
DEPLOY_ROOT=/srv/web/vaultmesh
DEPLOY_CADDYFILE=/etc/caddy/Caddyfile
DEPLOY_ROOT_SHA256=sha256:<64hex>
DEPLOY_CADDY_SHA256=sha256:<64hex>
DEPLOY_LEDGER_APPEND_OK=1
DEPLOY_OK=1
```

## Where Script

Run:

```bash
bash scripts/where_is_vaultmesh.sh
```

Success markers:

```text
WHERE_DOMAIN=vaultmesh.org
WHERE_A=49.13.217.227
WHERE_HOST=edge-1
WHERE_CADDY_ACTIVE=1
WHERE_ROOT=/srv/web/vaultmesh
WHERE_ROOT_SHA256=sha256:<64hex>
WHERE_CADDY_SHA256=sha256:<64hex>
WHERE_OK=1
```
