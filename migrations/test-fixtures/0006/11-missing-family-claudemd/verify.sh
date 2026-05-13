#!/bin/sh
# CLAUDE.md still not present (migration did NOT create one)
test ! -e "$HOME/Sourcecode/agenticapps/CLAUDE.md" || { echo "migration created CLAUDE.md (shouldn't)"; exit 1; }
# Everything else applied
test -L "$HOME/.claude/plugins/llm-wiki-compiler" || exit 1
test -f "$HOME/Sourcecode/agenticapps/.wiki-compiler.json" || exit 1
grep -q '^version: 1.9.2$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || exit 1
