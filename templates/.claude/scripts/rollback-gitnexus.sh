#!/usr/bin/env bash
# Migration 0007 — Rollback the GitNexus MCP wiring.
#
# Preserve-data: removes the MCP entry + reverts version. Does NOT
# npm-uninstall gitnexus (user may use it directly). Does NOT remove
# ~/.gitnexus/ registry. See migration 0007 Notes for manual cleanup.

set -e

SKILL_MD="${WIKI_SKILL_MD:-$HOME/.claude/skills/agentic-apps-workflow/SKILL.md}"
CLAUDE_JSON="$HOME/.claude.json"

# Step 1: remove MCP entry.
if [ -f "$CLAUDE_JSON" ] && jq empty "$CLAUDE_JSON" 2>/dev/null; then
  if jq -e '.mcpServers.gitnexus // empty' "$CLAUDE_JSON" >/dev/null 2>&1; then
    jq 'del(.mcpServers.gitnexus)' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" \
      && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
  fi
fi

# Step 2: revert skill version (CSO H1 fix: explicit if/then/else).
if grep -q '^version: 1.9.3$' "$SKILL_MD" 2>/dev/null; then
  if sed -i.bak 's/^version: 1\.9\.3$/version: 1.9.2/' "$SKILL_MD"; then
    rm -f "${SKILL_MD}.bak"
  else
    rm -f "${SKILL_MD}.bak"
    echo "ERROR: failed to revert version in $SKILL_MD" >&2
    exit 1
  fi
fi

# Notes: ~/.gitnexus/ + npm install preserved. Manual cleanup if desired:
#   npm uninstall -g gitnexus
#   rm -rf ~/.gitnexus/
#   for repo in $(jq -r '.repos[]?' ~/.gitnexus/registry.json 2>/dev/null); do
#     rm -rf "$repo/.claude/skills/gitnexus-"* "$repo/.claude/hooks/gitnexus-hook.js"
#     sed -i.bak '/<!-- gitnexus:start -->/,/<!-- gitnexus:end -->/d' "$repo/CLAUDE.md" 2>/dev/null
#   done

echo "Migration 0007 rolled back (gitnexus install + registry preserved)."
exit 0
