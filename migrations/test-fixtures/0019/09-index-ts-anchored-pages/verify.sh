#!/usr/bin/env bash
# Verify fixture 09: clean cf-pages root anchored at index.ts migrated.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
ROOT="functions/_lib/observability"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

test -f "$ROOT/cron-monitor.ts"    || { echo "cron-monitor.ts not installed"; exit 1; }
test -f "$ROOT/healthz-snippet.ts" || { echo "healthz-snippet.ts not installed"; exit 1; }
test -f "$ROOT/queue-monitor.ts"   || { echo "queue-monitor.ts not installed (D-11 narrowed: cf-pages)"; exit 1; }
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0"; exit 1; }
test -f "$ROOT/index.ts" || { echo "index.ts disappeared (engine should preserve anchor)"; exit 1; }

echo "fixture 09 OK — index.ts-anchored cf-pages migrated cleanly"
