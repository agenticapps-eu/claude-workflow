#!/bin/sh
mkdir -p "$HOME/.claude/skills/agentic-apps-workflow"
cat > "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" <<EOF_SKILL
---
name: agentic-apps-workflow
version: 1.9.1
---
EOF_SKILL
# NO vendored plugin at $HOME/Sourcecode/agenticapps/wiki-builder/plugin
