# AGENT.md — VaultMesh Website Surface Protocol

## 1. Mission

> Maintain a static-first, verifiable public surface that never claims more than it can prove.

This repository serves `vaultmesh.org` with static HTML pages plus a public attestation console.
Any changes must preserve determinism, verifiability, and security posture.

---

## 2. Scope

Observed routes (depth ≤ 2 crawl):

- `/` (GET 200)
- `/attest/` (GET 200)
- `/verify/` (GET 200)
- `/trust/` (GET 200)
- `/support/` (GET 200)
- `/proof-pack/` (GET 200)

Also observed by link / probe (may be non-GET surfaces or missing):

- `/proof-pack/intake` (GET 405)
- `/support/ticket` (GET 405)
- `/architecture/` (GET 404)
- `/docs` (GET 404)
- `/docs/` (GET 404)
- `/proof/` (GET 404)

Navigation links must remain consistent with the shared header/footer fragments.

---

## 3. Goal Hierarchy

### Primary Goals

1. Maintain static-first determinism (static edge artifact).
2. Preserve attestation surface behavior (static artifacts + deterministic console rendering).
3. Support institutional positioning without fluff.
4. Ensure existing GET routes continue to return HTTP 200.
5. Protect non-GET endpoints from GET collisions.

### Secondary Goals

1. Shared navigation and layout styling.
2. Consistent dark aesthetic.
3. Usable, legible typography and hierarchy.

---

## 4. Invariants (Non-negotiable)

- No runtime network calls to third-party origins from `vaultmesh.org` pages.
- `/attest/attest.json` and `/attest/LATEST.txt` must be served verbatim (static artifacts).
- `/attest/` may fetch only same-origin static artifacts (currently `./attest.json` and `./LATEST.txt`).
- New static pages must be reachable via GET and return HTTP 200.
- Non-GET endpoints (e.g. POST-only handlers) must not be broken by static GET surfaces.
- Static content must not degrade `/attest/` page rendering.

---

## 5. Investigation Mode

When an agent is asked to analyze the site or propose a change, it must:

1. Enumerate routes exactly using the inventory JSON (depth ≤ 2).
2. Extract static headings, grid blocks, and interactive elements.
3. Detect external calls (if any).
4. Output a route inventory JSON structured like:

```json
{
  "site_map": [],
  "routes": [
    {
      "path": "",
      "status_code": 200,
      "title": "",
      "meta_description": "",
      "navigation": {
        "header_links": [],
        "footer_links": []
      },
      "sections": [
        {
          "heading": "",
          "text_excerpt": "",
          "component_type": "static|console|grid|artifact|form|cta"
        }
      ],
      "interactive_elements": [],
      "data_sources": [],
      "external_calls_detected": false,
      "design_profile": {
        "background": "",
        "primary_colors": [],
        "font_style": "",
        "layout_style": ""
      }
    }
  ],
  "surface_assessment": {
    "marketing_layer_present": true,
    "console_first_design": true,
    "institutional_positioning_visible": true,
    "trust_surface_maturity": "v0|v1|v2"
  }
}
```

No interpretation — only inventory.

---

## 6. Change Mode (Propose Patches)

Before writing code or markup, output this manifest:

INTENT:
TARGET:
FILES AFFECTED:
RISK:
ROLLBACK:
TEST PLAN:

Only after that should you output a diff/patch.

---

## 7. Build / Deployment Invariants

- Build scripts must pass: `./scripts/build.sh` and all guard scripts in `./scripts/`.
- No page may introduce console errors or regress deterministic output.
- CSS/HTML changes must preserve the dark palette and monospace typography used by the surface.

---

## 8. UX Constraints

- Navigation links must match the canonical set in the observed inventory (header links).
- New pages must use the shared nav and footer templates (build-injected fragments).
- All UI must be readable on black background (`#050505`).
- Interaction feedback (hover/focus) must be done with CSS only.

---

## 9. New Route Requirements

If adding a route:

- Confirm it fits a static surface (no third-party network behavior).
- Add GET HTML at `public/<route>/index.html`.
- Ensure the shared nav/footer placeholders are present so build injection works:
  - `<!-- {{NAV}} -->`
  - `<!-- {{FOOTER}} -->`
- Verify build + guards.

---

## 10. Acceptance Criteria

After any change:

- All existing GET=200 routes remain GET=200.
- No regressions in `/attest/` attestation grid.
- New pages include:
  - `<title>`
  - `<meta name="description" ...>`
  - Shared header nav
  - Shared footer
- CSS remains shared (no style drift).
- Guards pass.

Suggested checks:

- `bash build.sh`
- `bash scripts/ui_skin_guard.sh`
- `bash scripts/nav_footer_guard.sh`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/attest/`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/verify/`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/trust/`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/support/`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/proof-pack/`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/attest/attest.json`
- `curl -sS -o /dev/null -w "%{http_code}\n" https://vaultmesh.org/attest/LATEST.txt`

---

## 11. Edge Integration (Phase 2)

Edge config must:

- Serve new static GET surfaces (200).
- Preserve non-GET handler semantics for endpoints like `/proof-pack/intake` and `/support/ticket`.
- Continue to serve the `/attest/` static artifacts correctly.

If a routing conflict occurs, propose a minimal rule patch.

---

## 12. Aesthetic Rules

The website maintains a Black Surface Aesthetic:

- Background: `#050505`
- Panels: charcoal/near-black with thin borders
- Typography: monospaced for structured content
- Confidence colors:
  - Green: success/present
  - Amber: missing/unknown
  - Red: invalid/stop

No gradients, no heavy illustrations.

---

## 13. Page Template Requirements

All new static pages must include:

- Shared header fragment placeholder
- Shared footer placeholder
- No inline `<script>` tags except those required for existing static console behavior
- Explicit static links to other canonical surfaces

---

## 14. Incident and Issue Filing

If an agent identifies a routing or build failure:

- Create an issue with:
  - Repro steps (curl + build)
  - Expected vs actual
  - Suggested minimal patch

Follow deterministic evidence style: include the hash of the failing artifact when available.

---

## 15. Versioning

Static pages include verifiability markers in the shared footer:

- `Build: <git-sha>`
- `Manifest: sha256:<artifact-sha256>`

---

## 16. Fail Early

If a requested change violates:

- Deterministic behavior
- Static-only requirements
- No third-party runtime calls
- Trust-surface rendering

Stop and raise a conflict explanation.

---

End of AGENT.md
