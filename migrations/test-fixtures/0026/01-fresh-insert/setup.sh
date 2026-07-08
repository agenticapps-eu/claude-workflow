#!/bin/sh
# Fixture 01 — BEFORE: project at v2.3.0, baseline settings with one PostToolUse
# entry and NO gitnexus-reindex binding, empty .claude/hooks/. The typical fleet
# state 0026 upgrades.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
