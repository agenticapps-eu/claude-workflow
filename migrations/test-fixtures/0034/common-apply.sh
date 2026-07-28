#!/usr/bin/env bash
# common-apply.sh — replay migration 0034's Apply blocks (Steps 1, 2).
#
# Sourced by each fixture's verify.sh. Must stay byte-equivalent to the Apply
# blocks in migrations/0034-collapse-workflow-md-to-companion.md — that is what
# the apply-parity assertion in run-tests.sh verifies.
set -uo pipefail
SCAFFOLDER=~/.claude/skills/agenticapps-workflow

# ── Step 1 — re-vendor .claude/claude-md/workflow.md as the companion ───────
if [ -f .claude/claude-md/workflow.md ]; then
  install -m 0644 "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" \
    .claude/claude-md/workflow.md
else
  echo "SKIP: no .claude/claude-md/workflow.md here. 0034 re-vendors an existing"
  echo "      copy; installing a first one is 0000/0009's job, not this one's."
fi

# ── Step 2 — re-copy the trigger skill (3.1.0 -> 3.2.0) ─────────────────────
install -m 0644 "$SCAFFOLDER/setup/snapshot/agentic-apps-workflow-SKILL.md" \
  .claude/skills/agentic-apps-workflow/SKILL.md
