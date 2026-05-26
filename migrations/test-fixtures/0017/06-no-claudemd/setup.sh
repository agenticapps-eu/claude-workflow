#!/usr/bin/env bash
# Fixture 06 — no CLAUDE.md: a clean cf-worker root, but the project has no
# CLAUDE.md. 0017 migrates the wrapper AND writes a stub observability: block
# to a freshly created CLAUDE.md. Exit 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_clean_worker "src/lib/observability"

# Remove the CLAUDE.md the common setup created.
rm -f CLAUDE.md
