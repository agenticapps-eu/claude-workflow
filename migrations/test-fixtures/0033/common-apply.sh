#!/usr/bin/env bash
# common-apply.sh — replay migration 0033's Apply blocks (Steps 1, 2, 3).
#
# Sourced by each fixture's verify.sh.
#
# Must stay byte-equivalent to the Apply blocks in
# migrations/0033-revendor-openspec-instruction-payload.md — that is what the
# apply-parity assertion in run-tests.sh verifies.
set -uo pipefail
SCAFFOLDER=~/.claude/skills/agenticapps-workflow

# ── Step 1 — re-vendor .claude/claude-md/workflow.md ────────────────────────
if [ -f .claude/claude-md/workflow.md ]; then
  install -m 0644 "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" \
    .claude/claude-md/workflow.md
else
  echo "SKIP: no .claude/claude-md/workflow.md here. 0033 re-vendors an existing"
  echo "      copy; installing a first one is 0000/0009's job, not this one's."
fi

# ── Step 2 — re-vendor the hooks section of .claude/workflow-config.md ──────
if [ -f .claude/workflow-config.md ]; then
  _sect() {
    awk -v h="## Superpowers Integration Hooks" '
      $0 == h { inb=1; print; next }
      inb && /^## / { inb=0 }
      inb { print }' "$1"
  }
  _canon="$(mktemp)"; _out="$(mktemp)"
  _sect "$SCAFFOLDER/setup/snapshot/workflow-config.md" > "$_canon"
  # Splice: on the heading line emit the canonical section (which starts with
  # that same heading), drop the old section body, resume at the next `## `.
  awk -v h="## Superpowers Integration Hooks" -v canon="$_canon" '
    $0 == h { inb=1; while ((getline line < canon) > 0) print line; close(canon); next }
    inb && /^## / { inb=0 }
    inb { next }
    { print }' .claude/workflow-config.md > "$_out" && mv "$_out" .claude/workflow-config.md
  rm -f "$_canon"
else
  echo "SKIP: no .claude/workflow-config.md here — nothing to re-vendor."
fi

# ── Step 3 — re-copy the trigger skill (3.0.0 -> 3.1.0) ─────────────────────
install -m 0644 "$SCAFFOLDER/setup/snapshot/agentic-apps-workflow-SKILL.md" \
  .claude/skills/agentic-apps-workflow/SKILL.md
