#!/bin/sh
# Fixture 09 — BEFORE: CLAUDE.md carries TWO provenance+block pairs, each
# properly terminated by a real project `## ` heading (not back-to-back).
# This is the shape that exercises the `swallowed_own_h2` reset at the
# terminator (I-2): after the first block terminates at "## Workflow", the
# strip pass must re-enter a clean state before the second provenance line,
# or the second block's own heading gets mistaken for ITS terminator (because
# swallowed_own_h2 is stale-true from the first block), leaving the second
# heading and its body un-stripped and orphaned in the output.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nThis file provides guidance to Claude Code.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n'
  printf '## Workflow\nFirst project section.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n'
  printf '## Deployment\nSecond project section.\n'
} > CLAUDE.md
