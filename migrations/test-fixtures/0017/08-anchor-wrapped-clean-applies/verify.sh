#!/usr/bin/env bash
# Verify fixture 08: an anchor-wrapped, substituted-clean wrapper classifies
# CLEAN and auto-applies (exit 0) — the canonicaliser strips the anchor markers
# before hashing. Adapters added, wrapper registry-dispatched + token-free,
# version bumped.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"
ROOT="src/lib/observability"

# Precondition: the wrapper really is anchor-wrapped AND substituted.
grep -q '// agenticapps:observability:start' "$ROOT/index.ts" || { echo "precondition: start anchor missing"; exit 1; }
grep -q '// agenticapps:observability:end'   "$ROOT/index.ts" || { echo "precondition: end anchor missing"; exit 1; }
grep -q 'cparx-api' "$ROOT/index.ts" || { echo "precondition: wrapper not substituted"; exit 1; }

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "anchor-wrapped clean wrapper was NOT auto-applied (exit $rc) — Bug #2"; exit 1; }

# Migrated: adapters present, registry-dispatched, token-free.
test -f "$ROOT/destinations/registry.ts" || { echo "registry.ts missing — anchored wrapper was refused"; exit 1; }
test -f "$ROOT/destinations/axiom.ts"    || { echo "axiom.ts missing"; exit 1; }
grep -q 'buildRegistry' "$ROOT/index.ts" || { echo "wrapper not registry-dispatched after apply"; exit 1; }
grep -q '{{' "$ROOT/index.ts" && { echo "apply left raw {{tokens}}"; exit 1; }

# Version bumped.
grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "version not bumped"; exit 1; }

echo "fixture 08 OK — anchor-wrapped clean wrapper classified CLEAN and auto-applied"
