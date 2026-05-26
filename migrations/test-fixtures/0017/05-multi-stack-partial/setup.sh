#!/usr/bin/env bash
# Fixture 05 — multi-stack partial: one CLEAN react root + one HAND-MODIFIED
# cf-worker root. Exercises both modes (verify.sh runs the engine twice):
#   DEFAULT       → all-clean gate aborts: ZERO writes to EITHER root, both
#                   roots reported, non-zero exit.
#   --allow-partial → clean root migrated, dirty root skipped + listed, non-zero.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Clean react-vite root.
materialize_clean_react "web/src/lib/observability"

# Hand-modified cf-worker root.
materialize_dirty_worker "api/src/lib/observability"
