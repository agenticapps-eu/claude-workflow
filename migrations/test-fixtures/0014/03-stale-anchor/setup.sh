#!/bin/sh
# Fixture 03 — stale anchor: project at v1.12.0, CLAUDE.md has §11
# heading with a simulated older provenance (e.g. @0.4.0-pre). Step 1
# idempotency check fails (provenance not at current @0.4.0) → migration
# would replace the §11 section. Step 2 still needs to apply (version
# bump from 1.12.0).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Append §11 section with a STALE provenance version. Use @0.4.0-pre
# so future spec bumps don't collide (the stale-version regex is
# `@[^[:space:]]+ §11` — anything that isn't exactly @0.4.0).
{
  echo ""
  echo "<!-- spec-source: agenticapps-workflow-core@0.4.0-pre §11 -->"
  cat "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  echo ""
} >> CLAUDE.md
