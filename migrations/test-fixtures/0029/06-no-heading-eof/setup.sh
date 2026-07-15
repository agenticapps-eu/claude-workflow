#!/bin/sh
# Fixture 06 — BEFORE: a CLAUDE.md with no `## ` heading and no region at all.
# The anchor scan finds nothing; the END branch must append rather than drop.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > CLAUDE.md <<'EOF_CLAUDE'
# CLAUDE.md

Just prose. No level-2 headings anywhere in this file.
EOF_CLAUDE
