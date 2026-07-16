#!/bin/sh
# Fixture 09 — BEFORE: a healthy, correctly-anchored CLAUDE.md, built on top
# of common-setup.sh's good vendored mirror. The mirror is then truncated
# AFTER common-setup.sh has already vendored the good copy and CLAUDE.md has
# been built from it — so it is pre-flight's mirror-integrity guard (rule 1)
# under test here, not a corrupt CLAUDE.md.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$MIRROR"
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md

head -n 20 "$MIRROR" > "$MIRROR.trunc.$$"
mv "$MIRROR.trunc.$$" "$MIRROR"
