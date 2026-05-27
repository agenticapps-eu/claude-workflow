#!/usr/bin/env bash
# Verify fixture 06: wrapper migrated; a new CLAUDE.md with a v0.4.0
# observability: stub block is created; exit 0.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"

test ! -f CLAUDE.md || { echo "fixture 06 expects NO CLAUDE.md before run"; exit 1; }

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

# Wrapper migrated.
test -f src/lib/observability/destinations/registry.ts || { echo "registry.ts missing"; exit 1; }
grep -q 'buildRegistry' src/lib/observability/index.ts || { echo "wrapper not dispatched"; exit 1; }

# New CLAUDE.md created with a v0.4.0 observability: stub block.
test -f CLAUDE.md || { echo "CLAUDE.md not created"; exit 1; }
grep -q '^observability:' CLAUDE.md || { echo "observability: block missing"; exit 1; }
grep -q 'spec_version: 0.4.0' CLAUDE.md || { echo "stub not at spec_version 0.4.0"; exit 1; }
grep -q 'destinations:.*errors: sentry.*logs: axiom' CLAUDE.md || { echo "stub destinations line missing"; exit 1; }

grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "version not bumped"; exit 1; }

echo "fixture 06 OK — wrapper migrated + stub observability block written to new CLAUDE.md"
