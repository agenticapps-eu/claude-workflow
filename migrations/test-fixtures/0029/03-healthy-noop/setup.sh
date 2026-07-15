#!/bin/sh
# Fixture 03 — BEFORE: §11 correctly anchored above a late region (state A).
# This is the POSITIONAL shape of cparx / fx-signal-agent (block above a late
# region) — not their byte content: this fixture builds its block from the
# canonical mirror verbatim, whereas those two repos carry the pre-34ee72e
# mirror's bytes (four blank lines short).
#
# The earlier version of this comment said all three of cparx/fx-signal/callbot
# had "lost the blank line ... to prettier normalization". Both halves were
# wrong, and migration 0030's rationale documents the verified account:
#   - callbot is NOT affected — its block is byte-identical to the mirror.
#   - Nothing was lost or stripped. Upstream core 10f2c96 (2026-05-25) ADDED
#     those blank lines to spec §11 without bumping spec_version, and 34ee72e
#     mirrored the edit here with no re-sync migration. cparx and fx-signal-agent
#     ran 0014 on 05-21 and faithfully carry §11 exactly as it read that day.
# Migration 0030 heals those two. 0029 must not touch this fixture's file at all
# (idempotency short-circuits).
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
