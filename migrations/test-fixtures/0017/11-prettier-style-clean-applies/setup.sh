#!/usr/bin/env bash
# Fixture 11 — Prettier-styled clean wrapper (issue #47).
#
# A substituted-but-unmodified cf-worker wrapper reformatted with a non-default
# `.prettierrc` (single quotes, no semicolons). The masking rules assume the
# template's double-quote/semicolon style, so without style normalisation EVERY
# line differs and the (clean) wrapper is wrongly refused — which blocked real
# downstream projects (callbot) from migrating. The canonicaliser must fold the
# style to canonical form before hashing, classify CLEAN, and auto-apply.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_prettier_worker "src/lib/observability"
