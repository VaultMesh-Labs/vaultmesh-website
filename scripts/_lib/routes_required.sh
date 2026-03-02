#!/usr/bin/env bash
set -euo pipefail

# Canonical route set used by build + snapshot + deploy parity checks.
# These are file paths relative to dist/ and deploy root snapshots.
export VM_ROUTES_REQUIRED_CSV="${VM_ROUTES_REQUIRED_CSV:-about/index.html,foundation/index.html,offer/index.html,contact/index.html,support/index.html,support/open/index.html,status/index.html,verify-console/index.html,security/index.html,legal/privacy/index.html,legal/terms/index.html,support/ticket/index.html}"

# BUILD_INFO is part of freshness locking; keep it centralized.
export VM_BUILD_INFO_PATH="${VM_BUILD_INFO_PATH:-BUILD_INFO.json}"
