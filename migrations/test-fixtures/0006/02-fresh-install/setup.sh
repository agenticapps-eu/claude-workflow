#!/bin/sh
mkdir -p "$HOME/.claude/skills/agentic-apps-workflow"
cat > "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" <<EOF_SKILL
---
name: agentic-apps-workflow
version: 1.9.1
---
EOF_SKILL
# Vendored plugin stub
mkdir -p "$HOME/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin"
echo '{"name":"llm-wiki-compiler","version":"2.1.0","commands":[{"name":"wiki-compile"},{"name":"wiki-lint"}]}' > "$HOME/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json"
# Stub family: a directory with a child git repo (so heuristic matches)
mkdir -p "$HOME/Sourcecode/agenticapps/claude-workflow/.git"
mkdir -p "$HOME/Sourcecode/agenticapps/claude-workflow/docs/decisions"
printf '# CLAUDE.md\n\n' > "$HOME/Sourcecode/agenticapps/CLAUDE.md"
