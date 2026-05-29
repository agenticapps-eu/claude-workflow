#!/usr/bin/env bash
# Fixture 04 — cparx-shape: an operator who has installed the v1.17.0 worker
# wrapper but has NOT (yet) wired any scheduled handler in their entry file.
# The wrapper's mere presence qualifies the root for migration 0019: the new
# exports are OPT-IN (CONTEXT G2), so whether the operator calls them is
# invisible to the engine. Expect: clean apply identical to fixture 01.
#
# To make the scenario concrete on disk we also seed a stub entry file with
# NO `scheduled` export (verify.sh asserts it survives untouched — proves the
# migration is purely additive at the wrapper-dir level).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_clean_worker "src/lib/observability"

mkdir -p src
cat > src/index.ts <<'EOF_ENTRY'
// Operator's worker entry — fetch handler only, no scheduled() export.
// Migration 0019 must NOT touch this file (it only touches the wrapper dir).
import { withMiddleware } from "./lib/observability/middleware";

export default {
  fetch: withMiddleware(async (req: Request) => new Response("ok")),
};
EOF_ENTRY
