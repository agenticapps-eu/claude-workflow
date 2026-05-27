#!/usr/bin/env bash
# Fixture 02 — fxsa shape: a monorepo with several cf-worker service roots plus
# one react-vite web root, ALL un-modified. Every root migrates; exit 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Three cf-worker service roots (distinct service dirs, same wrapper layout).
materialize_clean_worker "services/ingest/src/lib/observability"
materialize_clean_worker "services/router/src/lib/observability"
materialize_clean_worker "services/notifier/src/lib/observability"

# One react-vite web root.
materialize_clean_react "web/src/lib/observability"
