#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0014.
# Builds a sandboxed $HOME with:
#   - scaffolder skill tree at $HOME/.claude/skills/agenticapps-workflow/
#     with a stub templates/spec-mirrors/11-coding-discipline-0.4.0.md
#     (the migration's `requires.verify` checks for the latter; Step 1's
#     apply reads bytes from it for injection).
# Each fixture's setup.sh customises the project state on top of this
# baseline (e.g. presence/absence of CLAUDE.md; presence/absence of the
# §11 anchor; stale vs current spec-source provenance).
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

# 1. Stub scaffolder layout — 0014 verifies the spec-mirror exists
#    (requires.verify); Step 1's apply reads bytes from it for the
#    verbatim §11 injection.
mkdir -p "$SCAFFOLDER_DIR/templates/spec-mirrors"
# The stub block is byte-identical to the real vendored block in the
# scaffolder repo. We copy from the repo's checked-in copy so the
# fixture's $HOME mirror matches what a real install would have.
cp "$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
   "$SCAFFOLDER_DIR/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

# 2. Build a v1.12.0 project skeleton inside the sandbox CWD.
#    0014's pre-flight #1 accepts version 1.12.0 OR 1.14.0 (re-apply).
#    Per-fixture setup.sh may overwrite this file to simulate a
#    post-bump state (e.g. fixture 02 "already-applied" sets 1.14.0).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.12.0
implements_spec: 0.3.2
description: synthetic test fixture for migration 0014
---
EOF_PROJ_SKILL

# 3. Minimal CLAUDE.md so fresh-apply / replace / no-op fixtures have a
#    target file. Fixture 05 (no-claudemd) deletes this after sourcing
#    common-setup; fixtures 02/03/04/06 overwrite it to layer the per-
#    fixture state on top.
cat > CLAUDE.md <<'EOF_CLAUDE'
# Test fixture CLAUDE.md (migration 0014)

This stand-in project preamble is here so that 0014 Step 1's insertion
logic has an H1 + blank line to anchor against. Per-fixture setup may
append a §11 section, append a §11 heading without provenance, or
delete this file entirely.
EOF_CLAUDE
