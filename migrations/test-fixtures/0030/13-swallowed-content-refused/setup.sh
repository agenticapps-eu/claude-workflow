#!/bin/sh
# Fixture 13 — BEFORE: a STALE block (the same shape fixture 01 heals),
# followed by an INDENTED heading `  ## User Section` and one line of user
# data. CommonMark permits a heading marker to carry up to 3 leading spaces
# (and permits a tab after the `#` sequence in place of a space); this
# migration's terminator, `^## `, recognizes neither form,
# so the region scan does not stop there — it keeps scanning until the next
# UNINDENTED `## ` heading, swallowing the indented heading and the user
# data underneath it into the block region.
#
# Before the blank-line-drift guard, that swallowed content was silently
# replaced along with the stale block. This fixture asserts the guard
# refuses instead, and the user's data survives byte-identical.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n  ## User Section\n'
  printf 'This is my important user data that must survive.\n'
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
