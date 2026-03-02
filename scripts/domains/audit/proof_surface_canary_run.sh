#!/usr/bin/env bash
set -euo pipefail

################################################################################
# proof_surface_canary_run.sh — Wrapper for proof_surface_canary.sh (daily)
#
# Runs the canary. On RC!=0, copies the report to an ALERT_ artifact.
# Always appends to proof_surface_canary.ndjson (via the inner script).
#
# RC: passthrough from proof_surface_canary.sh (0=ok, 12=network, 20=assertion)
################################################################################

cd "$(dirname "$0")/../../.."  # repo root

mkdir -p reports

bash scripts/domains/audit/proof_surface_canary.sh
rc=$?

exit $rc
