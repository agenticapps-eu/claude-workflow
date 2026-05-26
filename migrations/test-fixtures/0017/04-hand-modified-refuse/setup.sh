#!/usr/bin/env bash
# Fixture 04 — hand-modified refuse: the single cf-worker wrapper is a
# REALISTICALLY-SUBSTITUTED wrapper (real service name / DSN env var / sample
# rates / redacted-keys list — NOT {{TOKENS}}) carrying a bespoke hand-edit
# OUTSIDE any token site. After canonicalisation it still mismatches the
# baseline, so 0017 must REFUSE: print the diff, auto-generate
# .observability-0017.patch, write NO wrapper files, exit non-zero.
#
# This guards the P5-review concern: refuse must not be a mere artefact of
# "didn't match the raw template" — it must survive correct canonicalisation of
# a genuinely substituted wrapper.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_dirty_substituted_worker "src/lib/observability"
