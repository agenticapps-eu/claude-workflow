#!/bin/sh
# Fixture 03 — BEFORE: a project whose settings already carry TWO custom
# PostToolUse entries (and none is gitnexus-reindex). The insert must leave both.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

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
      },
      {
        "_hook": "Hook 6 — Normalize CLAUDE.md",
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/normalize-claude-md.sh \"$CLAUDE_PROJECT_DIR/CLAUDE.md\"", "timeout": 5000 }
        ]
      }
    ]
  }
}
EOF_SETTINGS
