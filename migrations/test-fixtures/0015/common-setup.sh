#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0015.
# Builds a sandboxed $HOME with:
#   - scaffolder skill tree at $HOME/.claude/skills/agenticapps-workflow/
#     including a stub ts-declare-first/SKILL.md (the migration's
#     `requires.verify` checks for the latter; Step 1's apply targets
#     the directory as the symlink source).
# Each fixture's setup.sh customises the $HOME/.claude/skills/
# ts-declare-first state on top of this baseline (absent, correct
# symlink, redirected symlink, non-symlink directory).
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

# 1. Stub scaffolder layout — 0015 verifies the ts-declare-first
#    directory + SKILL.md exist in the scaffolder bundle. We mirror the
#    minimum surface here (just the SKILL.md frontmatter) so the symlink
#    has a valid target. Real installs symlink from the user's clone
#    where the full skill tree (README, templates, etc.) lives.
mkdir -p "$SCAFFOLDER_DIR/ts-declare-first"
cat > "$SCAFFOLDER_DIR/ts-declare-first/SKILL.md" <<'EOF_STUB_SKILL'
---
name: ts-declare-first
version: 0.1.0
implements_spec: 0.4.0
---
EOF_STUB_SKILL

# 2. Build a v1.14.0 project skeleton inside the sandbox CWD. 0015's
#    pre-flight #1 accepts version 1.14.0 (P1 already bumped projects
#    to 1.14.0 via migration 0014's Step 2).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.14.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0015
---
EOF_PROJ_SKILL
