#!/bin/sh
mkdir -p "$HOME/.claude/skills/agentic-apps-workflow"
cat > "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" <<EOF_SKILL
---
name: agentic-apps-workflow
version: 1.9.1
---
EOF_SKILL
mkdir -p "$HOME/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin"
echo '{"name":"llm-wiki-compiler","version":"2.1.0"}' > "$HOME/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json"
# Only skip-listed dirs under Sourcecode (no real families).
# Plus the agenticapps dir, but make it skip the family heuristic by having NO child .git dirs.
mkdir -p "$HOME/Sourcecode/personal" "$HOME/Sourcecode/shared" "$HOME/Sourcecode/archive"
# agenticapps exists as a parent for wiki-builder but has no immediate child .git repos (wiki-builder is a sibling, not a .git child here)
