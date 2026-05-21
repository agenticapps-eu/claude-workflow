#!/bin/sh
# Fixture 01 — fresh apply (before state): project at v1.12.0, CLAUDE.md
# exists with no §11 section. Pre-flight passes; both Step 1 (inject)
# and Step 2 (version+spec bump) need to apply.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# Nothing else — canonical clean v1.12.0 project, never had §11 injected.
