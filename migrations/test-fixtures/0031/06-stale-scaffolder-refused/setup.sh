#!/bin/sh
# Fixture 06 — BEFORE: a scaffolder clone that predates 0031 — it has no
# vendored engine at setup/snapshot/hooks/gitnexus-reindex.cjs at all (as if
# ~/.claude/skills/agenticapps-workflow were on a git checkout from before
# the --skip-agents-md fix landed). Pre-flight rule 2 must refuse rather than
# silently re-syncing a project onto whatever (possibly absent, possibly
# stale) bytes a broken scaffolder clone happens to carry.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# make_old_engine reads from the vendored engine, so derive the installed
# (old) copy BEFORE removing the vendored source below.
mkdir -p .claude/hooks
make_old_engine > .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs

rm -f "$HOME/.claude/skills/agenticapps-workflow/setup/snapshot/hooks/gitnexus-reindex.cjs"
