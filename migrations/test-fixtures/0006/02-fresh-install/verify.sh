#!/bin/sh
# Symlink installed
test -L "$HOME/.claude/plugins/llm-wiki-compiler" || { echo "no symlink"; exit 1; }
# Knowledge dirs scaffolded
test -d "$HOME/Sourcecode/agenticapps/.knowledge/raw" || { echo "no raw dir"; exit 1; }
test -d "$HOME/Sourcecode/agenticapps/.knowledge/wiki" || { echo "no wiki dir"; exit 1; }
# Config written
test -f "$HOME/Sourcecode/agenticapps/.wiki-compiler.json" || { echo "no config"; exit 1; }
jq empty "$HOME/Sourcecode/agenticapps/.wiki-compiler.json" || { echo "config does not parse"; exit 1; }
# CLAUDE.md section added
grep -q '^## Knowledge wiki' "$HOME/Sourcecode/agenticapps/CLAUDE.md" || { echo "no section"; exit 1; }
# Version bumped
grep -q '^version: 1.9.2$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || { echo "version not bumped"; exit 1; }
