#!/usr/bin/env bash
# Fixture 06 (R09 binding) — mixed clean + dirty multi-root: TWO clean
# v1.17.0 cf-worker roots + ONE hand-modified cf-worker root. The all-clean
# gate (R08) must refuse atomically: ZERO new files written to ANY of the
# three roots; recovery .observability-0019.patch emitted for ALL THREE (the
# operator can splice the additions manually); engine exits 2; version NOT
# bumped.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_clean_worker  "services/clean-a/.observability"
seed_clean_worker  "services/clean-b/.observability"
seed_dirty_worker  "services/dirty/.observability"
