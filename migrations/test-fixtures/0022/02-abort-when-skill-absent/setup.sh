#!/bin/sh
# Fixture 02 — abort when obs skill absent (D-03, no auto-install): project at
# v1.20.0 but the `observability` skill is NOT installed in $HOME. The
# migration's pre-flight #1 must abort with exit 3 and the actionable pointer.
set -eu
OBS_SKILL_ABSENT=1
export OBS_SKILL_ABSENT
. "$FIXTURES_ROOT/common-setup.sh"
