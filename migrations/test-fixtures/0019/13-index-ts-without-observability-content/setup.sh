#!/usr/bin/env bash
# Fixture 13 — index.ts + middleware.ts pair WITHOUT any observability
# markers (vanilla Hono worker). Phase 26 D-06a / CR-D content-marker firewall.
#
# Expectation (post-Plan-03 / Wave 3 GREEN):
#   - engine's _filter_index_ts_requires_co_anchor REJECTS src/index.ts
#     (content-marker grep finds no observability|lib-observability|
#     withObservability|sentry|agenticapps:observability marker)
#   - NO .observability-0019.patch emitted in project root for that path
#   - Engine output indicates the pair was classified as SKIP/unsupported
#     (or equivalent — see verify.sh comments for SC-5 evidence strategy)
#
# Wave 0 RED state (today): the engine does NOT have the content-marker
# check yet, so it classifies this vanilla pair as ts-cloudflare-worker
# and emits .observability-0019.patch — verify.sh's PRIMARY assertion
# fails. That FAILURE is the RED baseline; Plan 03 lands the engine fix
# which flips it GREEN.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

FIXDIR="$FIXTURES_ROOT/13-index-ts-without-observability-content"
mkdir -p src
cp "$FIXDIR/src/index.ts"      src/index.ts
cp "$FIXDIR/src/middleware.ts" src/middleware.ts
