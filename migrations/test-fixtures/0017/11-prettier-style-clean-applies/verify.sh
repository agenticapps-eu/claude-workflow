#!/usr/bin/env bash
# Verify fixture 11: a clean wrapper in non-default Prettier style (single
# quotes, no semicolons) classifies CLEAN and auto-applies — style is normalised
# before hashing, so formatting alone never triggers a hand-modified refusal.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"
ROOT="src/lib/observability"

# Precondition: the wrapper really is in the alternate style (single quote, no semi).
grep -q "from 'node:async_hooks'" "$ROOT/index.ts" || { echo "precondition: wrapper not single-quoted"; exit 1; }
grep -qE ";[[:space:]]*$" "$ROOT/index.ts" && { echo "precondition: wrapper still has trailing semicolons"; exit 1; }

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "Prettier-styled clean wrapper was NOT auto-applied (exit $rc) — style false-positive (issue #47)"; exit 1; }

test -f "$ROOT/destinations/registry.ts" || { echo "registry.ts missing — styled wrapper was refused"; exit 1; }
grep -q 'buildRegistry' "$ROOT/index.ts" || { echo "wrapper not registry-dispatched after apply"; exit 1; }
grep -q '{{' "$ROOT/index.ts" && { echo "apply left raw {{tokens}}"; exit 1; }
# env-var extraction still correct under the alternate style.
grep -q 'env.SERVICE_NAME' "$ROOT/index.ts" || { echo "ENV_VAR_SERVICE extraction broke under alternate style"; exit 1; }

grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "version not bumped"; exit 1; }

echo "fixture 11 OK — Prettier-styled clean wrapper classified CLEAN and auto-applied"
