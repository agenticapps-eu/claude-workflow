#!/bin/sh
# Fixture 04 — BEFORE: project has no CLAUDE.md at all. 0029 Step 1 must emit an
# informational skip rather than abort, so Step 2 still runs (0014's idiom).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
rm -f CLAUDE.md
