#!/usr/bin/env bash
# Fixture 05 — fxsa-shape: a multi-module monorepo with THREE clean v1.17.0
# cf-worker wrappers + ONE clean v1.17.0 react-vite wrapper. The three workers
# all migrate; the react-vite wrapper is SKIP_UNSUPPORTED (D10). Engine exits 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_clean_worker "services/worker-a/.observability"
seed_clean_worker "services/worker-b/.observability"
seed_clean_worker "services/worker-c/.observability"
seed_clean_react  "apps/web/.observability"
