#!/usr/bin/env bash
# Fixture 0021/02 — REFUSE case. v1.19.0 cf-worker wrapper from frozen baseline,
# then HAND-MODIFY cron-monitor.ts to simulate callbot's LOCAL-PATCH at
# cron-monitor.ts:141-149 (`as Record<string, unknown>` cast pattern).
# Engine must canonicalise the modified file; canonical hash matches NEITHER
# the v1.19.0 baseline NOR the v1.20.0 template baseline; engine REFUSEs;
# emits .observability-0021.patch.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_v1_19_0_worker "src/lib/observability"

# Simulate callbot's LOCAL-PATCH — append a line that the canonicaliser
# cannot strip. Any non-whitespace, non-comment delta breaks the hash match.
cat >> src/lib/observability/cron-monitor.ts <<'EOF'

// LOCAL-PATCH (callbot — simulating cron-monitor.ts:141-149 cast pattern)
export const _localPatchSentinel = (env: Record<string, unknown>) => env;
EOF
