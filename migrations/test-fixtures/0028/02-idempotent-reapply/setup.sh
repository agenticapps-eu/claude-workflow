#!/bin/sh
# Fixture 02 — BEFORE: project's .prettierignore ALREADY carries the
# .claude/hooks entry (a project that was updated once, or added it by hand).
# Applying 0028 again must be a no-op: no duplicate line.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > .prettierignore <<'EOF_PI'
dist/

# AgenticApps workflow (0028): vendored .claude hooks are .cjs/.sh Node
# tooling, not app code; exclude from prettier --check.
.claude/hooks/
EOF_PI
