#!/usr/bin/env bash
# Fixture 09 — every root dirty under --allow-partial (Bug #3).
#
# Two hand-modified cf-worker roots, no clean roots. With --allow-partial the
# engine skips both dirty roots and migrates ZERO — so it must NOT bump the
# workflow version (a repo claiming 1.16.0 with un-migrated wrappers is the bug).
# Engine exits 2 (dirty roots skipped).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_dirty_worker "api/src/lib/observability"
materialize_dirty_worker "jobs/src/lib/observability"
