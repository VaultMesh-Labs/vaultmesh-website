#!/usr/bin/env bash
set -euo pipefail

################################################################################
# intake_canary_run.sh — Wrapper for intake_canary.sh (daily systemd/cron)
#
# Runs the canary. On RC!=0, copies the report to an ALERT_ artifact.
# Always appends to intake_canary.ndjson (via the inner script).
#
# ALERT_*.json files are the only signal surface for external alerting.
# RC: passthrough from intake_canary.sh (0=ok, 12=network, 20=assertion)
################################################################################

cd "$(dirname "$0")/../../.."  # repo root

mkdir -p reports
ts="$(date -u +%Y%m%dT%H%M%SZ)"

bash scripts/domains/audit/intake_canary.sh
rc=$?

# RC!=0 → emit alert artifact
if [[ $rc -ne 0 ]]; then
  cp -f reports/intake_canary.json "reports/ALERT_intake_canary_${ts}_rc${rc}.json"
fi

exit $rc
