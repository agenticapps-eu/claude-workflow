#!/bin/sh
# Fixture 02 — BEFORE: the engine is already re-synced (byte-identical to the
# vendored source). This is the steady state after 0031 has already run once.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"
mkdir -p .claude/hooks
cp "$SCAFFOLDER_DIR/setup/snapshot/hooks/gitnexus-reindex.cjs" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
