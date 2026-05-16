#!/bin/sh
# Fixture 04 — project-local vendored skill at CURRENT version (matches
# global). Pre-flight #2 must HARD ABORT (confused state). NO Step 1
# removal, NO Step 3 version bump.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Vendor a skill at the SAME version as the global stub (v0.3.2 — see
# common-setup.sh).
mkdir -p .claude/skills/add-observability
cat > .claude/skills/add-observability/SKILL.md <<'EOF_LOCAL'
---
name: add-observability
version: 0.3.2
---
EOF_LOCAL
