#!/bin/sh
# Run rollback inside verify
ROLLBACK="${REPO_ROOT:-/}/templates/.claude/scripts/rollback-gitnexus.sh"
if [ ! -x "$ROLLBACK" ]; then
  cur="$PWD"
  while [ "$cur" != "/" ]; do
    [ -f "$cur/migrations/run-tests.sh" ] && ROLLBACK="$cur/templates/.claude/scripts/rollback-gitnexus.sh" && break
    cur=$(dirname "$cur")
  done
fi
bash "$ROLLBACK" >/dev/null 2>&1 || { echo "rollback failed"; exit 1; }
# MCP entry removed
! jq -e '.mcpServers.gitnexus // empty' "$HOME/.claude.json" >/dev/null 2>&1 || { echo "MCP entry still present"; exit 1; }
# Version reverted
grep -q '^version: 1.9.2$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || { echo "version not reverted"; exit 1; }
