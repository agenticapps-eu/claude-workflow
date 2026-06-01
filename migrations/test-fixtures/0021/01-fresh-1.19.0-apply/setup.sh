#!/usr/bin/env bash
# Fixture 0021/01 — happy-path fresh apply on a single v1.19.0 cf-worker wrapper
# (post-0019 state). cron-monitor.ts seeded from frozen v1.19.0 baseline (codex M-1).
# Expect: 0021 engine ships updated cron-monitor.ts (matches v1.20.0 baseline hash)
# AND new queue-monitor.ts, bumps to 1.20.0, exits 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_v1_19_0_worker "src/lib/observability"
