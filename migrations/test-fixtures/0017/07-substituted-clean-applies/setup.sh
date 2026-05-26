#!/usr/bin/env bash
# Fixture 07 — substituted-clean applies (the P5-review regression guard).
#
# Both wrapper roots are REALISTICALLY SUBSTITUTED — generator tokens replaced
# with real values (service name "cparx-api", DSN env var SENTRY_DSN, sample
# rates 0.1/0.05, a real redacted-keys list, Go package "observability"), NOT
# left as {{TOKENS}} — but otherwise UNMODIFIED. This is exactly what a real
# downstream project's wrapper looks like on disk.
#
# The old engine reversed only ENV_VAR_DSN, so a substituted wrapper never
# matched the template-byte baseline → was mis-classified hand-modified →
# refused, and (since --allow-partial also skips dirty roots) the migration
# NEVER auto-applied on a real project. With structural-masking canonicalisation
# these roots must classify CLEAN and AUTO-APPLY: adapters added, wrapper
# rewritten to the registry-dispatched target, CLAUDE.md bumped, version bumped,
# exit 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# A Go backend + a React frontend, both with substituted-but-unmodified wrappers.
materialize_substituted_go    "internal/observability"
materialize_substituted_react "src/lib/observability"
