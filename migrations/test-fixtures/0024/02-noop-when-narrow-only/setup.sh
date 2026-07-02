#!/bin/sh
# Fixture 02 — BEFORE: project at v2.1.0 whose .gitignore already commits phase
# artifacts (NO whole-tree ignore) and carries only a narrow scratch ignore under
# the tree. Step 1's idempotency anchor is already positive -> Step 1 is a no-op.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > .gitignore <<'EOF_GI'
node_modules/
.claude/worktrees/
.planning/phases/*/.review-prompt.md
EOF_GI
