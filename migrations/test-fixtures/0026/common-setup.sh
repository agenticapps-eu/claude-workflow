#!/bin/sh
# Sourced by each 0026 fixture's setup.sh. Builds a sandboxed BEFORE state:
# a fresh git repo (one commit — gives HEAD a value) with a project-local
# hyphenated SKILL.md at a controllable version (default 2.3.0 — Step 3's bump
# floor), a baseline .claude/settings.json (existing PostToolUse entries, no
# gitnexus-reindex binding), and an empty .claude/hooks/ (Step 1's copy target).
#
#   SKILL_VERSION=2.4.0 . "$FIXTURES_ROOT/common-setup.sh"   # already-applied state
set -eu

: "${SKILL_VERSION:=2.3.0}"

# A real git repo so the engine and `git rev-parse HEAD` have a HEAD to read.
git init -q
git config user.email fixture@example.com
git config user.name  fixture
git commit --allow-empty -qm "fixture: initial commit"

mkdir -p .claude/skills/agentic-apps-workflow .claude/hooks
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<EOF_PROJ_SKILL
---
name: agentic-apps-workflow
version: ${SKILL_VERSION}
implements_spec: 0.4.0
description: synthetic test fixture for migration 0026
---

## Daily Quick Reference

1. stub
EOF_PROJ_SKILL

# Baseline settings: one pre-existing PostToolUse entry, NO gitnexus-reindex.
cat > .claude/settings.json <<'EOF_SETTINGS'
{
  "hooks": {
    "PostToolUse": [
      {
        "_hook": "Hook 4a — Skill Router Audit Log",
        "matcher": "mcp__skills__.*|Bash",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/skill-router-log.sh", "timeout": 5000 }
        ]
      }
    ]
  }
}
EOF_SETTINGS
