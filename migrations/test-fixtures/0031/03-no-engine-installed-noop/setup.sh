#!/bin/sh
# Fixture 03 — BEFORE: no .claude/hooks/gitnexus-reindex.cjs at all, and no
# .claude/hooks/ directory either. This is claude-workflow's own state today
# (0026 was never applied to this repo) and the state of any project that
# never opted into the reindex hook. 0031 must never install one — that is
# 0026's job.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# Deliberately: no .claude/hooks/ created.
