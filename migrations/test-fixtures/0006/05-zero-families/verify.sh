#!/bin/sh
# Symlink should be installed (host-level always runs)
test -L "$HOME/.claude/plugins/llm-wiki-compiler" || exit 1
# No family configs were written
test ! -f "$HOME/Sourcecode/personal/.wiki-compiler.json" || { echo "config written in skip-list dir"; exit 1; }
# Version still bumped (host-level success)
grep -q '^version: 1.9.2$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || exit 1
