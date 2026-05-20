#!/bin/sh
# Fixture 04 — user-redirected symlink: $HOME/.claude/skills/
# ts-declare-first is a symlink, but it points somewhere other than
# the scaffolder source. Step 1's idempotency check correctly returns
# "needs apply" (target mismatch). Apply force-replaces via `ln -sfn`,
# clobbering the redirection (this is the documented 0012-precedent
# behavior — apply clobbers; rollback does not).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Create a "fork" of the skill the user has redirected to. Simulates a
# user who maintains a personal fork of ts-declare-first and redirected
# the symlink to their fork.
mkdir -p "$HOME/.claude/skills/ts-declare-first-fork"
cat > "$HOME/.claude/skills/ts-declare-first-fork/SKILL.md" <<'EOF_FORK_SKILL'
---
name: ts-declare-first
version: 0.1.0-fork
---
EOF_FORK_SKILL

# Redirect the user-global symlink to the fork.
ln -sfn "$HOME/.claude/skills/ts-declare-first-fork" \
        "$HOME/.claude/skills/ts-declare-first"
