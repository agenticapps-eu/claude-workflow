#!/bin/sh
# Fixture 16 — BEFORE: a canonical §11 block with operator SECRET content after
# it, and a NUL byte on an earlier line. A NUL makes BSD grep classify the whole
# file as binary and report no match, which (a) makes the idempotency check
# report not-applied, so Apply runs, and (b) — with a plain `grep` — makes the
# guard's own presence check miss the provenance and skip entirely, while the
# awk-based strip still deletes the block and the SECRET. The guard uses
# `grep -a` (text mode) so the NUL cannot bypass it: it must still fire, see the
# SECRET as non-canonical, and refuse (exit 3) with the file byte-identical.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\n'
  printf 'x'; printf '\000'; printf 'y\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\nSECRET USER CONTENT after the block; must survive.\n\n'
  printf '## Tail\nKEEP TAIL.\n'
} > CLAUDE.md
