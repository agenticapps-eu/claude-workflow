#!/usr/bin/env bash
# Fixture 09 — fresh apply on a single clean v1.17.0 cf-pages wrapper
# anchored at index.ts (canonical materialised filename) with _middleware.ts
# co-anchor. Expect: engine classifies as ts-cloudflare-pages, applies the
# three D-11 files (cron + healthz + queue per D-11 narrowed), bumps to 1.18.0, exits 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

ROOT="functions/_lib/observability"
mkdir -p "$ROOT"
cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-pages/lib-observability.ts" "$ROOT/index.ts"
cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-pages/_middleware.ts"        "$ROOT/_middleware.ts"
