#!/bin/sh
# Malformed config preserved (not overwritten)
grep -q "this is not json" "$HOME/Sourcecode/agenticapps/.wiki-compiler.json" || { echo "malformed config was overwritten"; exit 1; }
# Other steps proceeded
test -L "$HOME/.claude/plugins/llm-wiki-compiler" || exit 1
grep -q '^version: 1.9.2$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || exit 1
