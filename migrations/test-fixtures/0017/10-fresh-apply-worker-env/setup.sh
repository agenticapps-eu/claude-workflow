#!/usr/bin/env bash
# Fixture 10 — clean cf-worker apply, env-var extraction must NOT collapse.
#
# The cf-worker InitEnv interface lists the three env tokens with an IDENTICAL
# prefix/suffix:
#     {{ENV_VAR_DSN}}?: string;
#     {{ENV_VAR_ENV}}?: string;
#     {{ENV_VAR_SERVICE}}?: string;
# A naive first-match extractor gives all three the FIRST field's value (the DSN
# env var) → three duplicate `SENTRY_DSN?: string;` fields and `env.SENTRY_DSN`
# at the service-name / deploy-env sites. No other fixture exercises a CLEAN
# cf-worker apply, so this is the guard for that path.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_clean_worker "src/lib/observability"
