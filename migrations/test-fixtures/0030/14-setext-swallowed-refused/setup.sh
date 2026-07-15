#!/bin/sh
# Fixture 14 — BEFORE: a STALE block (the same shape fixture 01 heals),
# followed by a SETEXT-style H2 heading (`User Section` underlined with
# `---`) and one line of user data. CommonMark recognizes a line of text
# followed by a `---` underline as a level-2 heading even though it carries
# no `#` characters at all; this migration's terminator, `^## `, only
# recognizes ATX headings, so the region scan does not stop there — it
# keeps scanning until the next UNINDENTED `## ` heading, swallowing the
# setext heading and the user data underneath it into the block region.
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
  printf '\nUser Section\n---\n'
  printf 'This is my important user data that must survive.\n'
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
