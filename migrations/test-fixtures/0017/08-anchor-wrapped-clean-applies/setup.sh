#!/usr/bin/env bash
# Fixture 08 — anchor-wrapped clean wrapper (migration 0014 / init idiom).
#
# A substituted-but-unmodified react-vite wrapper whose content is bracketed by
# `// agenticapps:observability:start` / `:end` markers. The canonicaliser must
# strip those markers BEFORE hashing so the wrapper canonicalises to the
# anchor-free baseline and classifies CLEAN → auto-applies, exit 0.
#
# Regression guard for Bug #2: pre-fix the markers survived masking, the wrapper
# was wrongly classified hand-modified and refused — exactly what blocked
# cparx's frontend from migrating.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_anchored_react "src/lib/observability"
