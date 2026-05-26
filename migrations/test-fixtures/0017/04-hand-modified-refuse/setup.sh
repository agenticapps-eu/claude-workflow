#!/usr/bin/env bash
# Fixture 04 — hand-modified refuse: the single cf-worker wrapper has a bespoke
# hand-edit (hash mismatch vs baseline). 0017 must REFUSE: print the diff,
# auto-generate .observability-0017.patch, write NO wrapper files, exit non-zero.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_dirty_worker "src/lib/observability"
