#!/bin/sh
# Fixture 01 — BEFORE: the OLD (pre-`--skip-agents-md`) engine installed at
# .claude/hooks/gitnexus-reindex.cjs, matching cparx/callbot/
# agenticapps-dashboard/fx-signal-agent's real installed bytes today.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

mkdir -p .claude/hooks
make_old_engine > .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
