#!/bin/sh
# The Step 2 insert appends the gitnexus-reindex entry and leaves BOTH existing
# PostToolUse entries (skill-router-log, normalize-claude-md) intact.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

before=$(jq '.hooks.PostToolUse | length' .claude/settings.json)
[ "$before" = "2" ] || { echo "PRE: expected 2 existing entries, got $before"; exit 1; }

jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs", "timeout": 5000 }]
    }])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

after=$(jq '.hooks.PostToolUse | length' .claude/settings.json)
[ "$after" = "3" ] || { echo "FAIL: expected 3 entries after insert, got $after"; exit 1; }
for cmd in skill-router-log normalize-claude-md gitnexus-reindex; do
  jq -e ".hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test(\"$cmd\"))" \
    .claude/settings.json >/dev/null || { echo "FAIL: entry '$cmd' missing after insert"; exit 1; }
done

echo "fixture 03 — insert preserved both existing PostToolUse entries (2 -> 3)"
