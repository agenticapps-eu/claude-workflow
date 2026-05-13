#!/bin/sh
# Pre-state (set by harness's install run): applied state.
# Now run rollback and assert post-rollback state.
# We need REPO_ROOT to find the rollback script. The harness exports it,
# but verify.sh runs in a subshell without that var by default. Detect it:
ROLLBACK_SCRIPT="${REPO_ROOT:-$PWD/../../../..}/templates/.claude/scripts/rollback-wiki-compiler.sh"
if [ ! -x "$ROLLBACK_SCRIPT" ]; then
  # Walk up to find the repo root by looking for migrations/run-tests.sh
  cur="$PWD"
  while [ "$cur" != "/" ]; do
    if [ -f "$cur/migrations/run-tests.sh" ]; then
      ROLLBACK_SCRIPT="$cur/templates/.claude/scripts/rollback-wiki-compiler.sh"
      break
    fi
    cur=$(dirname "$cur")
  done
fi
test -x "$ROLLBACK_SCRIPT" || { echo "rollback script not found: $ROLLBACK_SCRIPT"; exit 1; }

bash "$ROLLBACK_SCRIPT" >/dev/null 2>&1 || { echo "rollback script failed"; exit 1; }

# Symlink removed
test ! -e "$HOME/.claude/plugins/llm-wiki-compiler" || { echo "symlink still present after rollback"; exit 1; }
# Version reverted
grep -q '^version: 1.9.1$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || { echo "version not reverted"; exit 1; }
# Family data PRESERVED (preserve-data semantics)
test -d "$HOME/Sourcecode/agenticapps/.knowledge/raw" || { echo "knowledge dir destroyed"; exit 1; }
test -f "$HOME/Sourcecode/agenticapps/.wiki-compiler.json" || { echo "config destroyed"; exit 1; }
grep -q '^## Knowledge wiki' "$HOME/Sourcecode/agenticapps/CLAUDE.md" || { echo "CLAUDE.md section stripped"; exit 1; }
