#!/bin/sh
# Sourced by each 0031 fixture setup.sh. Builds the BEFORE state:
#   - a sandboxed $HOME carrying the vendored (FIXED — --skip-agents-md)
#     reindex engine at the scaffolder path Step 1 re-syncs against, exactly
#     as 0026 installs from
#   - a project skeleton at 2.8.0 (0031's pre-flight floor)
# Each fixture then lays down its own .claude/hooks/gitnexus-reindex.cjs (or
# omits it entirely).
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

mkdir -p "$SCAFFOLDER_DIR/setup/snapshot/hooks"
cp "$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs" \
   "$SCAFFOLDER_DIR/setup/snapshot/hooks/gitnexus-reindex.cjs"
chmod +x "$SCAFFOLDER_DIR/setup/snapshot/hooks/gitnexus-reindex.cjs"

mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 2.8.0
implements_spec: 0.9.0
description: synthetic test fixture for migration 0031
---

## Stub
EOF_PROJ_SKILL

# The OLD (pre-fix) engine: the vendored engine with the --skip-agents-md
# comment block and flag mechanically removed. This reproduces, byte for
# byte, what migration 0026 copied into cparx/callbot/agenticapps-dashboard/
# fx-signal-agent before this fix — verified against the real pre-fix
# templates/.claude/hooks/gitnexus-reindex.cjs at commit bf90f89 (`diff`
# empty). Derived from the vendored engine rather than pasted so it cannot
# rot independently of it.
make_old_engine() {
  sed -e '/^  \/\/$/,/instruction files behind their back\.$/d' \
      -e "s/\['analyze', '--skip-agents-md'\]/['analyze']/" \
      "$SCAFFOLDER_DIR/setup/snapshot/hooks/gitnexus-reindex.cjs"
}
