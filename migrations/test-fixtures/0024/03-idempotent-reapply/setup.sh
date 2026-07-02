#!/bin/sh
# Fixture 03 — AFTER state: migration already applied. Version is 2.2.0 and the
# .gitignore commits phases. Both idempotency anchors are positive; a re-run must
# be a clean no-op.
set -eu
SKILL_VERSION=2.2.0 . "$FIXTURES_ROOT/common-setup.sh"

cat > .gitignore <<'EOF_GI'
node_modules/
.claude/worktrees/
EOF_GI
