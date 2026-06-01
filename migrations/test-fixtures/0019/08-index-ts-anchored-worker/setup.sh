#!/usr/bin/env bash
# Fixture 08 — fresh apply on a single clean v1.17.0 cf-worker wrapper
# anchored at index.ts (canonical materialised filename per meta.yaml;
# the issue #56 Finding 1 regression case). Expect: engine recognises
# the wrapper, applies cron-monitor.ts + healthz-snippet.ts + queue-monitor.ts
# (D-11 narrowed: cf-worker + cf-pages only), bumps version to 1.18.0, exits 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Seed the v1.17.0 wrapper bytes but materialise as index.ts (production
# shape) instead of lib-observability.ts (template-source shape).
ROOT="src/lib/observability"
mkdir -p "$ROOT"
cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/lib-observability.ts" "$ROOT/index.ts"
cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/middleware.ts"        "$ROOT/middleware.ts"
