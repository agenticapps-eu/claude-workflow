#!/bin/sh
# Fixture 01 — BEFORE: project has a .prettierignore WITHOUT a .claude/hooks
# entry. This is the case migration 0028 exists for: a repo whose formatter
# would otherwise catch the vendored .cjs reindex hook.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > .prettierignore <<'EOF_PI'
dist/
coverage/
# project's own pre-existing ignore
docs/generated/
EOF_PI
