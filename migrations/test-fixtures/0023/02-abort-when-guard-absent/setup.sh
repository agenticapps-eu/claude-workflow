#!/bin/sh
# Fixture 02 — abort when injection-guard skill absent (no auto-install): project
# at v2.0.0 but the `injection-guard` skill is NOT installed in $HOME. The
# migration's pre-flight #1 must abort with exit 3 and the actionable pointer.
set -eu
GUARD_SKILL_ABSENT=1
export GUARD_SKILL_ABSENT
. "$FIXTURES_ROOT/common-setup.sh"
