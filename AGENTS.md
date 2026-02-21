# AGENTS.md — VaultMesh Website UI/UX Investigator (console-first, no-JS)

## Mission
Make `/architecture/`, `/pricing/`, `/proof-pack/intake/`, and `/support/ticket/` visually match the `/attest/` console-first aesthetic:
- same grid/panel grammar
- same typographic rhythm
- same audit-readout feel
WITHOUT introducing JavaScript, fetch calls, or runtime dependencies.

## Non-Negotiables (Hard Gates)
1) No page JavaScript (no `<script>`, no inline JS).
2) No `fetch()` / XHR / external calls.
3) Use existing shared stylesheet reference only (for example, `/shared/ui.css?...`).
4) Preserve existing nav/footer injection model:
   - `<!-- {{NAV}} -->` and `<!-- {{FOOTER}} -->` placeholders.
5) Do not modify `/attest/*` behavior or data surfaces.
6) All new/edited pages must pass:
   - `./scripts/build.sh`
   - `bash scripts/ui_skin_guard.sh --dist`
   - `bash scripts/nav_footer_guard.sh --dist`
   - `bash scripts/support_link_guard.sh dist`

## Investigation Protocol (No Guessing)
Before editing, collect evidence:
- Read `dist/attest/index.html` (or the generated `/attest/` template source if present).
- Identify the exact DOM patterns used for:
  - wrapper container
  - grid sections
  - key/value rows
  - badge/status tokens
- Produce a short UI Grammar note (bullets) that lists:
  - class names
  - section structure
  - row structure
This note must be based on files in-repo, not memory.

## Implementation Plan
### Step 1 — Extract UI Grammar from `/attest/`
Deliverable: `reports/ui_grammar_attest.md` containing:
- wrapper classes and max-width behavior
- grid system usage
- row markup patterns (key/value)
- panel/card markup patterns
- typography helpers

### Step 2 — Apply Grammar to 4 Pages
Update:
- `public/architecture/index.html`
- `public/pricing/index.html`
- `public/proof-pack/intake/index.html`
- `public/support/ticket/index.html`

Rules:
- Convert long prose to panels + key/value rows where possible.
- Use `<details>` for secondary explanations (FAQ-style) if needed.
- Keep content accurate; do not invent product capabilities.

### Step 3 — Validate
Run the full local guard suite (see Hard Gates).
Output a single-line verdict at end of run notes:
- `UI_HARDEN_OK=1` or `UI_HARDEN_OK=0`

## Output Format Requirements
When you finish, provide:
1) List of files changed (exact paths).
2) A short diff summary (what changed structurally).
3) Proof of gates: paste the final 10 lines of each guard output.
4) A quick before/after screenshot note is optional (no tooling required).

## DoD (Definition of Done)
- The 4 pages feel like `/attest/` through structure, density, and panel grammar.
- No JS, no fetch, no new runtime dependencies.
- All build + guard checks pass.
- `/attest/*` remains unchanged.

