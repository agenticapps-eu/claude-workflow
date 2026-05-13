#!/bin/sh
# CLAUDE.md should have exactly ONE '## Knowledge wiki' heading (not two)
COUNT=$(grep -c '^## Knowledge wiki' "$HOME/Sourcecode/agenticapps/CLAUDE.md")
test "$COUNT" = "1" || { echo "duplicate heading count=$COUNT"; exit 1; }
# Symlink still exists
test -L "$HOME/.claude/plugins/llm-wiki-compiler" || exit 1
# Version still 1.9.2
grep -q '^version: 1.9.2$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || exit 1
