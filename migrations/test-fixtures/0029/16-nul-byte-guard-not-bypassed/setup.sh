#!/bin/sh
# Fixture 16 — BEFORE: a canonical §11 block with operator SECRET content after
# it, and a NUL byte on an earlier line. NUL bytes make the line-oriented tools
# behave in undefined, locale-dependent ways: BSD grep can report "binary, no
# match" (skipping the guard while the awk strip still runs to EOF), and BSD awk
# truncates a record at its first NUL (so the guard would validate a canonical
# prefix while the strip deletes the whole record). Rather than chase each
# divergence, Step 1 refuses any file containing a NUL or CR byte via a
# clean-text gate that runs BEFORE the provenance/heading greps and the strip.
# This fixture pins that gate: a NUL anywhere must produce a clean refusal
# (exit 3) with the file byte-identical and the SECRET intact.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

# The NUL sits INSIDE the block's heading line, immediately after the canonical
# heading text: `## Coding Discipline (NON-NEGOTIABLE)\0SECRET USER SUFFIX`.
# BSD awk truncates the record at the NUL, so the guard sees only the canonical
# heading and would APPROVE — while the forward strip deletes the whole line
# (suffix and all). This is the shape only the clean-text gate catches (grep -a
# alone does not, since the guard's own comparison is fooled by the truncation),
# so it mutation-proves the gate.
{
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  printf '## Coding Discipline (NON-NEGOTIABLE)'; printf '\000'; printf 'SECRET USER SUFFIX; must survive.\n'
  tail -n +2 "$BLOCK"
  printf '## Tail\nKEEP TAIL.\n'
} > CLAUDE.md
