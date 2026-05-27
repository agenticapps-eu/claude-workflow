#!/usr/bin/env bash
# Verify fixture 09: --allow-partial with EVERY root dirty migrates zero roots,
# so the workflow version must stay 1.15.0 (Bug #3) and the engine exits 2.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"
SKILL=".claude/skills/agentic-apps-workflow/SKILL.md"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" --allow-partial >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "expected exit 2 (all dirty under --allow-partial), got $rc"; exit 1; }

# Bug #3 — zero roots migrated → version must NOT be bumped.
grep -q '^version: 1.15.0$' "$SKILL" \
  || { echo "version no longer 1.15.0 — bumped despite 0 roots migrated (Bug #3)"; exit 1; }
grep -q '^version: 1.16.0$' "$SKILL" \
  && { echo "version wrongly bumped to 1.16.0 with 0 roots migrated (Bug #3)"; exit 1; }

# Neither dirty root was migrated.
test -f api/src/lib/observability/destinations/registry.ts  && { echo "api root wrongly migrated"; exit 1; }
test -f jobs/src/lib/observability/destinations/registry.ts && { echo "jobs root wrongly migrated"; exit 1; }

echo "fixture 09 OK — all-dirty --allow-partial: 0 migrated, version unchanged (1.15.0), exit 2"
