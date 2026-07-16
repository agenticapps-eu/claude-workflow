#!/bin/sh
# Fixture 17 — BEFORE: a CLAUDE.md with CRLF line endings carrying a §11 block.
# CR bytes make every `^...$` anchor miss, so neither the guard nor the strip
# recognises the block — yet the insert anchor `/^## /` still matches a heading
# prefix, so without a gate Apply would append a SECOND canonical block (a
# duplicate) and report success. Step 1's clean-text gate refuses any file with
# a CR (or NUL) byte before any of that runs: exit 3, file byte-identical, no
# duplicate block inserted.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

# Build with LF, then rewrite every line as CRLF (awk interprets \r in printf;
# BSD sed does not, so awk is the portable choice here).
{
  printf '# CLAUDE.md\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Tail\nKEEP.\n'
} | awk '{ printf "%s\r\n", $0 }' > CLAUDE.md
