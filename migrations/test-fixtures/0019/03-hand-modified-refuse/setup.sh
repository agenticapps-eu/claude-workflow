#!/usr/bin/env bash
# Fixture 03 — single hand-modified cf-worker wrapper. middleware.ts carries
# an injected comment line that survives canonicalisation → DIRTY. Engine
# must refuse (atomic all-clean gate, R08 binding), exit 2, emit a recovery
# .observability-0019.patch, and NOT install cron-monitor.ts.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_dirty_worker "src/lib/observability"
