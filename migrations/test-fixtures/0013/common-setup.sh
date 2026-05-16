#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0013.
# Builds a sandbox $HOME with:
#   - scaffolder skill tree at $HOME/.claude/skills/agenticapps-workflow/
#     including a stub add-observability/SKILL.md @ v0.3.2 and a stub
#     init/INIT.md (the migration's `requires.verify` checks for the
#     latter; Step 2's chained init delegates to the same path).
# Each fixture's setup.sh customises the project state on top of this
# baseline (e.g. presence/absence of project-local vendored skill;
# presence/absence of observability: in CLAUDE.md).
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

# 1. Stub scaffolder layout — 0013 verifies the nested add-observability
#    dir + init/INIT.md exist (requires.verify); Step 1's apply reads
#    the global SKILL.md to surface the version that's about to take
#    over.
mkdir -p "$SCAFFOLDER_DIR/add-observability/init"
cat > "$SCAFFOLDER_DIR/add-observability/SKILL.md" <<'EOF_GLOBAL_SKILL'
---
name: add-observability
version: 0.3.2
implements_spec: 0.3.0
---
EOF_GLOBAL_SKILL
cat > "$SCAFFOLDER_DIR/add-observability/init/INIT.md" <<'EOF_INIT'
# add-observability init (stub for migration 0013 fixtures)
This is a stub — the real INIT.md ships in the scaffolder repo's
add-observability/init/ directory and is symlinked into $HOME via
migration 0012. Fixtures only need this file to exist so the
migration's `requires.verify` passes.
EOF_INIT

# 2. Build a v1.11.0 project skeleton inside the sandbox CWD.
#    0013's pre-flight #1 accepts version 1.11.0 OR 1.12.0 (re-apply).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.11.0
---
EOF_PROJ_SKILL

# 3. Minimal CLAUDE.md so file-existence checks pass. Per-fixture
#    setup.sh may overwrite to add `observability:` metadata.
cat > CLAUDE.md <<'EOF_CLAUDE'
# Test fixture CLAUDE.md (migration 0013)
EOF_CLAUDE
