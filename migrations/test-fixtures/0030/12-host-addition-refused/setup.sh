#!/bin/sh
# Fixture 12 — THE DATA-LOSS REGRESSION TEST. BEFORE: the CANONICAL mirror
# block plus one extra, lawful host-specific anti-pattern bullet added under
# Rule 1 — exactly what spec §11 (~line 119) permits: "MAY add host-specific
# anti-pattern bullets to any of the four rules to cover failure modes
# peculiar to the host runtime. Additions do not satisfy or alter the
# canonical bullets; they layer on top." Byte-for-byte this block differs
# from the mirror, but it is not stale — it is a conformant customization.
#
# Before the blank-line-drift guard, 0030 compared bytes only: any
# difference triggered a wholesale replacement, silently deleting this
# lawful addition. That is the bug this fixture exists to catch — if the
# guard is ever removed or weakened, this fixture must go RED.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

# Insert one extra lawful bullet directly after the first anti-pattern
# bullet of Rule 1. Derived from the mirror via awk, not pasted, so the
# insertion point cannot rot independently of the canonical text.
awk '
  /^- Diving into implementation without restating what was actually requested\.$/ {
    print
    print "- host-runtime-specific: never swallow a stack trace from the sandboxed shell without echoing it."
    next
  }
  { print }
' "$MIRROR" > block-with-addition.md

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat block-with-addition.md
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md

rm -f block-with-addition.md
