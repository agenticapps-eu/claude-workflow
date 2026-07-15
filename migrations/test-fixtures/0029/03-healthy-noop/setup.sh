#!/bin/sh
# Fixture 03 — BEFORE: §11 correctly anchored above a late region (state A).
# This is the POSITIONAL shape of cparx / fx-signal / callbot (block above a
# late region) — not their byte content: this fixture builds its block from
# the canonical mirror verbatim, and those three repos' on-disk blocks have
# since lost the blank line after each "Anti-patterns this rule prevents:"
# heading to prettier normalization, so they no longer match it byte-for-byte.
# 0029 must not touch this fixture's file at all (idempotency short-circuits).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Project Overview\nStuff.\n\n'
  printf '<!-- gitnexus:start -->\n# GitNexus\n\n## Always Do\n- x\n<!-- gitnexus:end -->\n'
} > CLAUDE.md
