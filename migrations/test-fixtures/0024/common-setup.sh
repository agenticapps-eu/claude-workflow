#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0024.
# Builds a sandboxed project (BEFORE state) with a project-local hyphenated
# SKILL.md at a controllable version (default 2.1.0 — Step 2's bump floor).
# Each fixture's setup.sh writes its own `.gitignore` (the artifact under test).
#
#   SKILL_VERSION=2.2.0 . "$FIXTURES_ROOT/common-setup.sh"   # already-applied state
set -eu

: "${SKILL_VERSION:=2.1.0}"

mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<EOF_PROJ_SKILL
---
name: agentic-apps-workflow
version: ${SKILL_VERSION}
implements_spec: 0.4.0
description: synthetic test fixture for migration 0024
---
EOF_PROJ_SKILL
