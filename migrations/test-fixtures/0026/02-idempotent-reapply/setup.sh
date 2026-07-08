#!/bin/sh
# Fixture 02 — BEFORE: 0026 already applied. Re-running must be a no-op.
set -eu
SKILL_VERSION=2.4.0 . "$FIXTURES_ROOT/common-setup.sh"

# Install the engine + entry so the fixture starts in the applied state.
cp "$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
jq '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
        "timeout": 5000
      }]
    }])' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
