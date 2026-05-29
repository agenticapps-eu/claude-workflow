#!/usr/bin/env bash
# Fixture 07 — --allow-partial: 2 clean + 1 dirty roots.
# Engine applies clean roots and skips dirty root; exits 0.
# Under --allow-partial, patches emitted for ALL roots (dirty AND clean).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_clean_worker  "services/clean-a/.observability"
seed_clean_worker  "services/clean-b/.observability"
seed_dirty_worker  "services/dirty/.observability"
