#!/usr/bin/env bash
# Verify fixture 01: clean cf-worker root migrated, cron-monitor.ts +
# healthz-snippet.ts installed, NO test files installed, version bumped.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

ROOT="src/lib/observability"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

# New production files copied.
test -f "$ROOT/cron-monitor.ts"    || { echo "cron-monitor.ts not installed"; exit 1; }
test -f "$ROOT/healthz-snippet.ts" || { echo "healthz-snippet.ts not installed"; exit 1; }

# Test scaffolds are template-only — engine MUST NOT ship them into projects.
test ! -e "$ROOT/cron-monitor.test.ts"    || { echo "cron-monitor.test.ts incorrectly installed (template-only)"; exit 1; }
test ! -e "$ROOT/healthz-snippet.test.ts" || { echo "healthz-snippet.test.ts incorrectly installed (template-only)"; exit 1; }

# Version bumped to 1.18.0.
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0"; exit 1; }

# No refuse artefacts emitted on the happy path.
test ! -e "$ROOT/.observability-0019.patch" \
  || { echo "fresh-apply: no .observability-0019.patch expected on clean apply"; exit 1; }

echo "fixture 01 OK — fresh clean cf-worker migrated, no test files shipped, version 1.18.0"
