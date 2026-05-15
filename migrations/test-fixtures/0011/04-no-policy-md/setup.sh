#!/bin/sh
# Fixture 04 — pre-flight abort: observability: present but no policy.md.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Remove the policy file that common-setup created.
rm -rf lib/observability/policy.md
