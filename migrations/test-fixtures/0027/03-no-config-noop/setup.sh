#!/bin/sh
# Fixture 03 — BEFORE: project at v2.4.0 with NO .planning/config.json and no
# .claude/settings.json / hooks at all. Steps 4 and 5 must no-op; Steps
# 1/2/3/6 must still complete.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
