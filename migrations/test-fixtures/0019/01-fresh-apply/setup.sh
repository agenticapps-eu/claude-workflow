#!/usr/bin/env bash
# Fixture 01 — fresh apply on a single clean v1.17.0 cf-worker wrapper. The
# wrapper carries only the fingerprint files the engine checks; the new files
# 0019 installs (cron-monitor.ts + healthz-snippet.ts) are absent. Expect:
# engine applies both new files, bumps version to 1.18.0, exits 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_clean_worker "src/lib/observability"
