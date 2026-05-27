#!/usr/bin/env bash
# Verify fixture 02: all 4 roots (3 cf-worker + 1 react-vite) migrated, exit 0.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

for root in services/ingest/src/lib/observability \
            services/router/src/lib/observability \
            services/notifier/src/lib/observability \
            web/src/lib/observability; do
  test -f "$root/destinations/registry.ts" || { echo "$root: registry.ts missing"; exit 1; }
  test -f "$root/destinations/axiom.ts"    || { echo "$root: axiom.ts missing"; exit 1; }
  grep -q 'buildRegistry' "$root/index.ts" || { echo "$root: wrapper not registry-dispatched"; exit 1; }
done

grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "version not bumped"; exit 1; }
grep -q '^  spec_version: 0.4.0' CLAUDE.md || { echo "CLAUDE.md not bumped"; exit 1; }

echo "fixture 02 OK — all 4 roots migrated"
