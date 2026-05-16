#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0012.
# Builds a sandbox $HOME with:
#   - scaffolder skill tree at ~/.claude/skills/agenticapps-workflow/
#     (incl. nested add-observability/ subdirectory the symlink targets)
#   - per-fixture project directory at $PWD (= $tmp dir) with the
#     per-project workflow SKILL.md at v1.10.0 (the from_version 0012
#     expects).
# Caller's setup.sh customizes the $HOME/.claude/skills/add-observability
# state on top of this baseline.
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

# 1. Stub scaffolder layout — 0012 verifies the nested add-observability
#    dir exists (pre-flight #2) and the resolved SKILL.md identifies as
#    add-observability (Step 2).
mkdir -p "$SCAFFOLDER_DIR/add-observability"
cat > "$SCAFFOLDER_DIR/add-observability/SKILL.md" <<'EOF_SKILL'
---
name: add-observability
version: 0.3.1
implements_spec: 0.3.0
---
EOF_SKILL

# 2. Build a v1.10.0 project skeleton inside the sandbox CWD.
#    0012's pre-flight #1 accepts version 1.10.0 OR 1.11.0 (re-apply).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.10.0
---
EOF_PROJ_SKILL
