#!/bin/sh
# Fixture 04 — BEFORE: project has a .prettierignore that already ignores the
# WHOLE .claude directory. This subsumes .claude/hooks/, so migration 0028 has
# nothing to add: prettier already skips the vendored reindex hook.
#
# Real case: factiv/fbc-platform ships exactly this (a bare `.claude` on line 7).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > .prettierignore <<'EOF_PI'
dist/
coverage/
.claude
docs/generated/
EOF_PI
