# SOT_LOCK_v0 Closeout - 2026-02-21

## Release Summary
This closeout finalizes SOT_LOCK_v0 for the public web plane:

- `vaultmesh.org` is static-first from `/srv/web/vaultmesh`.
- Webhooks and support dynamic status are isolated on dedicated hosts.
- Route, skin, and SOT contracts are enforced by marker-based guards.
- DNS for `support.vaultmesh.org`, `hooks.vaultmesh.org`, and `api.vaultmesh.org` is published to edge (`49.13.217.227`).

## Locked Contracts
- Static public host: `vaultmesh.org`
- Dynamic webhook host: `hooks.vaultmesh.org`
- Dynamic support status host: `support.vaultmesh.org`
- Dynamic API host: `api.vaultmesh.org`
- Dynamic MCP host: `mcp.vaultmesh.org`
- Required Caddy runtime env: `VM_HOOKS_UPSTREAM`

## Final Guard Evidence (Repo + Live)
Executed on 2026-02-21T01:13:00Z.

- `BUILD_OK=1`
- `SOT_GUARD_OK=1` (repo)
- `NAV_FOOTER_GUARD_OK=1`
- `UI_SKIN_GUARD_OK=1`
- `CADDY_GUARD_OK=1` (repo snapshot)
- `SOT_GUARD_OK=1` (live)
- `CADDY_GUARD_OK=1` (live vs snapshot)
- `WHERE_OK=1`

Key policy markers observed:

- `CADDY_POLICY_STATIC_OK=1`
- `CADDY_POLICY_ALLOWLIST_OK=1`
- `CADDY_POLICY_HOST_SPLIT_OK=1`
- `HOOKS_HOST_PRESENT=1`
- `HOOKS_NOT_ON_VAULTMESH=1`
- `HOOKS_ALLOWLIST_ONLY=1`
- `SUPPORT_HOST_PRESENT=1`
- `SUPPORT_STATUS_ALIAS_OK=1`
- `API_HOST_PRESENT=1`

Hashes observed:

- `SOT_ROOT_SHA256=sha256:b10923980907a5443a8e29cfd0f2b37509e6421a87157e44792239d17d6542ca`
- `SOT_CADDY_SHA256=sha256:d9f497dde20055bc3b54aab7cc939d1cad251267a0d3490062f32b879ec4baba`
- `SOT_MANIFEST_SHA256=sha256:744b086cabb9e0f3d0383311afbb15f0ab7e35bcf486ca0975fb6a5b9084dacb`

## DNS Verification
Verified against public resolvers `1.1.1.1` and `8.8.8.8`:

- `support.vaultmesh.org -> 49.13.217.227`
- `hooks.vaultmesh.org -> 49.13.217.227`
- `api.vaultmesh.org -> 49.13.217.227`

## HTTP Acceptance Results
- `https://vaultmesh.org/` -> `200`
- `https://vaultmesh.org/attest/` -> `200`
- `https://vaultmesh.org/proof-pack/` -> `200`
- `https://vaultmesh.org/support/` -> `200`
- `https://vaultmesh.org/trust/` -> `200`
- `https://vaultmesh.org/verify/` -> `200`

Host split behavior:

- `vaultmesh.org support/status?...` -> `404` (expected; no dynamic support on static host)
- `https://hooks.vaultmesh.org/_hooks/mailgun` (HEAD/GET) -> app-defined `405` (expected; no routing drift)
- `https://hooks.vaultmesh.org/not-allowed` -> `404` (expected)
- `https://support.vaultmesh.org/support/status?...` -> app-defined `403` for unknown ticket (expected; upstream reachable)
- `https://support.vaultmesh.org/not-allowed` -> `308` to `https://vaultmesh.org/support/` (expected)
- `https://api.vaultmesh.org/health` -> `200`
- `https://mcp.vaultmesh.org/mcp/health` -> `200`

## Final Checklist (Binary)
- [x] SOT tree and snapshot are canonical in repo.
- [x] Repo guard suite passes with required markers.
- [x] Live guard suite passes with required markers.
- [x] `vaultmesh.org` public pages return 200.
- [x] `vaultmesh.org/support/status` is not proxied (404).
- [x] Hooks allowlist is isolated on `hooks.vaultmesh.org`.
- [x] Support status endpoint is isolated on `support.vaultmesh.org`.
- [x] API and MCP are isolated dynamic surfaces.
- [x] DNS records are published and resolvable on public resolvers.
- [x] No routing-drift 502 observed in acceptance checks.

## Operator Notes
- Use quoted URLs in zsh when query strings are present, for example:
  - `curl -I 'https://support.vaultmesh.org/support/status?ticket_id=test&t=test'`
- Local resolver hiccups can still occur temporarily; public resolver checks (`@1.1.1.1`, `@8.8.8.8`) are authoritative for publication state.
