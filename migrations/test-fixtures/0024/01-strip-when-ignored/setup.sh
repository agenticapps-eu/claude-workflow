#!/bin/sh
# Fixture 01 — BEFORE: project at v2.1.0 whose .gitignore carries a whole-tree
# `.planning/phases/` ignore (the friction 0024 fixes), alongside ordinary stack
# ignores and a NARROW scratch ignore that must survive Step 1's surgical strip.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > .gitignore <<'EOF_GI'
node_modules/
dist/
.planning/phases/
.claude/worktrees/
*.log
.planning/phases/*/.codex-review.md
EOF_GI
