#!/bin/sh
# Fixture 02 — already applied (post-apply state): project at v1.14.0,
# CLAUDE.md has §11 section with current provenance @0.4.0. All
# idempotency checks pass; the migration is a no-op on re-run.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Bump SKILL.md to the post-apply state (1.14.0 / 0.4.0).
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.14.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0014 (post-apply)
---
EOF_PROJ_SKILL

# Append §11 section with provenance comment + the vendored block bytes.
{
  echo ""
  echo "<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->"
  cat "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  echo ""
} >> CLAUDE.md
