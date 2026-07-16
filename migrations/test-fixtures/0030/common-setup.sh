#!/bin/sh
# Sourced by each 0030 fixture setup.sh. Builds the BEFORE state:
#   - a sandboxed $HOME carrying the vendored §11 canonical block (Apply reads
#     its bytes from there, exactly as 0014 and 0029 do)
#   - a project skeleton at 2.7.0 (0030's pre-flight floor)
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
version: 2.7.0
implements_spec: 0.9.0
description: synthetic test fixture for migration 0030
---

## Stub
EOF_PROJ_SKILL

# The STALE block: the canonical mirror with the blank line after each
# "Anti-patterns this rule prevents:" removed. This reproduces, byte for byte,
# what migration 0014 wrote into cparx (e6e44e7b) and fx-signal-agent
# (d38a97c) when it read the pre-34ee72e mirror. Derived from the mirror
# rather than pasted so it cannot rot independently of it.
make_stale_block() {
  awk '
    /^Anti-patterns this rule prevents:$/ { print; skip_next_blank=1; next }
    skip_next_blank && /^$/ { skip_next_blank=0; next }
    { skip_next_blank=0; print }
  ' "$SCAFFOLDER_DIR/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
}
