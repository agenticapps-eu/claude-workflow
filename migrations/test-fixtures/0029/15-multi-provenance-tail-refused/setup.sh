#!/bin/sh
# Fixture 15 — BEFORE: TWO provenance+block pairs. The first is the canonical
# mirror; the second is a STALE `@0.3.0` provenance followed by operator content
# and NO `## Coding Discipline` heading before the next `## ` — a malformed
# second region. The stale provenance means the real idempotency check reports
# not-applied (it greps specifically for `@0.4.0`), so Apply is REACHABLE.
#
# The strip reacts to EVERY provenance line. At the second (headingless) region
# it never sets `swallowed_own_h2`, so no `## ` terminates deletion: it deletes
# the second marker, the operator content, and the ENTIRE tail of the file
# (run-to-EOF). A guard that validates only the FIRST block passes (the first is
# canonical) and lets all of that be deleted. This fixture pins the fix: the
# guard must validate every block the strip touches, so the malformed second
# region forces a refusal (exit 3) with the tail intact.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.3.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Workflow\nKEEP FIRST SECTION.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.3.0 §11 -->\n'
  printf 'SECRET IN THE MALFORMED SECOND REGION.\n'
  printf '## Deployment\nKEEP THE ENTIRE TAIL.\n'
} > CLAUDE.md
