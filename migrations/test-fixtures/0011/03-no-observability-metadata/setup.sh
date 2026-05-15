#!/bin/sh
# Fixture 03 — pre-flight abort: no observability: block in CLAUDE.md.
# Migration MUST refuse to apply with the "run init first" message.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Overwrite the canonical CLAUDE.md to remove the observability block.
cat > CLAUDE.md <<'EOF_CLAUDE_MD'
# Project

## Skills

- /gsd-review
EOF_CLAUDE_MD
