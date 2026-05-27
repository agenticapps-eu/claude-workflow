#!/bin/sh
# Fixture 01 — fresh v1.16.0 project: hook not installed, config.json has no
# observability_scan entry. All three migration steps need to apply.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# Nothing else — the common baseline IS the pre-apply state.
