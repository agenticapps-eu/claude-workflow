#!/bin/sh
# Fixture 02 — stale project-local vendored skill present at v0.2.1,
# no observability metadata. Step 1 will detect-and-remove; Step 2
# will chain init.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Stale vendored skill at v0.2.1 (the pre-slash-discovery vendoring pattern).
mkdir -p .claude/skills/add-observability
cat > .claude/skills/add-observability/SKILL.md <<'EOF_LOCAL'
---
name: add-observability
version: 0.2.1
---
EOF_LOCAL
# Add a couple of file shapes the v0.2.x install would have shipped so
# the file-count messaging in Step 1's apply has something to count.
mkdir -p .claude/skills/add-observability/templates
touch .claude/skills/add-observability/templates/placeholder.txt
