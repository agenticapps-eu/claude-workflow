#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0025.
# Builds a sandboxed project (BEFORE state) with a project-local hyphenated
# SKILL.md at a controllable version (default 2.2.0 — Step 3's bump floor) and
# a stub body WITHOUT the knowledge-capture section (Step 2's append target).
# Each fixture's setup.sh writes its own `.planning/config.json` (or omits it).
#
#   SKILL_VERSION=2.3.0 . "$FIXTURES_ROOT/common-setup.sh"   # already-applied state
set -eu

: "${SKILL_VERSION:=2.2.0}"

mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<EOF_PROJ_SKILL
---
name: agentic-apps-workflow
version: ${SKILL_VERSION}
implements_spec: 0.4.0
description: synthetic test fixture for migration 0025
---

## Daily Quick Reference

1. stub — the ritual-tail section is appended after this
EOF_PROJ_SKILL
