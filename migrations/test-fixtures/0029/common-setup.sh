#!/bin/sh
# Sourced by each 0029 fixture setup.sh. Builds the BEFORE state:
#   - a sandboxed $HOME carrying the vendored §11 canonical block (Step 1's
#     apply reads its bytes from there, exactly as 0014 does)
#   - a project skeleton at 2.6.0 (0029's pre-flight floor)
# Each fixture layers its own CLAUDE.md on top (or deletes it).
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

mkdir -p "$SCAFFOLDER_DIR/templates/spec-mirrors"
cp "$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
   "$SCAFFOLDER_DIR/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 2.6.0
implements_spec: 0.9.0
description: synthetic test fixture for migration 0029
---

## Stub
EOF_PROJ_SKILL
