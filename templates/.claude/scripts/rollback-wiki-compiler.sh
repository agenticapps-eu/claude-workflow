#!/usr/bin/env bash
# Migration 0006 — Rollback the LLM wiki compiler install.
#
# Preserve-data semantics (RESEARCH §3): removes only the host-level
# symlink and the version bump. Family-level data (.knowledge/, configs,
# CLAUDE.md sections) is preserved. Users who want a clean uninstall
# run the cleanup commands documented at the bottom of this script.

set -e

PLUGIN_LINK="$HOME/.claude/plugins/llm-wiki-compiler"
SKILL_MD="${WIKI_SKILL_MD:-.claude/skills/agentic-apps-workflow/SKILL.md}"

# Step 1: remove host-level symlink.
if [ -L "$PLUGIN_LINK" ]; then
  rm -f "$PLUGIN_LINK"
fi

# Step 2: revert skill version.
if grep -q '^version: 1.9.2$' "$SKILL_MD" 2>/dev/null; then
  sed -i.bak 's/^version: 1\.9\.2$/version: 1.9.1/' "$SKILL_MD" && rm -f "$SKILL_MD.bak"
fi

# Note: family-level data preserved by design. To remove manually:
#   rm -rf ~/Sourcecode/*/.knowledge/
#   rm    ~/Sourcecode/*/.wiki-compiler.json
#   # Strip the `## Knowledge wiki` section from each family's CLAUDE.md
#   # (the section content is bounded by the heading and the next H2 or EOF).

echo "Migration 0006 rolled back (family data preserved)."
exit 0
