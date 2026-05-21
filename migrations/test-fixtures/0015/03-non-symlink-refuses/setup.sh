#!/bin/sh
# Fixture 03 — non-symlink at the install path: a regular directory
# (or file) at $HOME/.claude/skills/ts-declare-first triggers the
# conflict-detect refusal. The migration MUST NOT clobber user data.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Create a regular directory at the install path with a non-symlinked
# SKILL.md inside. Simulates an operator who hand-vendored the skill
# (the cparx F1 pattern migration 0013 was designed to clean up — for
# the add-observability case — but applied here pre-emptively for
# ts-declare-first so 0013-style cleanup migrations aren't needed
# down the road for this skill).
mkdir -p "$HOME/.claude/skills/ts-declare-first"
cat > "$HOME/.claude/skills/ts-declare-first/SKILL.md" <<'EOF_HAND_VENDORED'
---
name: ts-declare-first
version: 0.0.99-hand-vendored
---
EOF_HAND_VENDORED
