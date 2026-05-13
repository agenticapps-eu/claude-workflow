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
mkdir -p "$HOME/Sourcecode/agenticapps/claude-workflow/.git"
# NO CLAUDE.md
