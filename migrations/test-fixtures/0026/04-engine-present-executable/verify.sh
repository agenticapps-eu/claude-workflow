#!/bin/sh
# The engine ships in BOTH the snapshot (fresh-install source) and templates
# (build source), is executable, and carries the node shebang.
set -eu
SNAP="$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs"
TPL="$REPO_ROOT/templates/.claude/hooks/gitnexus-reindex.cjs"

test -f "$SNAP" || { echo "FAIL: snapshot engine missing at $SNAP"; exit 1; }
test -x "$SNAP" || { echo "FAIL: snapshot engine not executable"; exit 1; }
test -f "$TPL"  || { echo "FAIL: template engine missing at $TPL"; exit 1; }
test -x "$TPL"  || { echo "FAIL: template engine not executable"; exit 1; }
head -1 "$SNAP" | grep -q '^#!/usr/bin/env node' || { echo "FAIL: snapshot engine missing node shebang"; exit 1; }
cmp -s "$SNAP" "$TPL" || { echo "FAIL: snapshot engine differs from template source"; exit 1; }

echo "fixture 04 — engine present + executable + node shebang in snapshot and templates (identical)"
