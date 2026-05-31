#!/usr/bin/env bash
# Verify fixture 0021/01: v1.19.0 cf-worker root migrated; queue-monitor.ts
# installed; cron-monitor.ts updated to v1.20.0 (D-03 discriminated-union
# present); healthz-snippet.ts unchanged; version 1.20.0.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
ROOT="src/lib/observability"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

test -f "$ROOT/queue-monitor.ts"   || { echo "queue-monitor.ts not installed by 0021"; exit 1; }
test -f "$ROOT/cron-monitor.ts"    || { echo "cron-monitor.ts disappeared"; exit 1; }
test -f "$ROOT/healthz-snippet.ts" || { echo "healthz-snippet.ts disappeared"; exit 1; }

# cron-monitor.ts must be at v1.20.0 baseline (D-03 discriminated union present;
# interface-style schedule absent).
grep -q "type CronMonitorSchedule" "$ROOT/cron-monitor.ts" \
  || { echo "cron-monitor.ts NOT updated to v1.20.0 (no discriminated-union schedule type)"; exit 1; }
grep -q "interface CronMonitorSchedule" "$ROOT/cron-monitor.ts" \
  && { echo "cron-monitor.ts still at v1.19.0 (old interface shape present)"; exit 1; } || true

# 0021 must not ship the .test.ts companion.
test ! -e "$ROOT/queue-monitor.test.ts" || { echo "queue-monitor.test.ts incorrectly installed (template-only)"; exit 1; }

grep -q '^version: 1.20.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.20.0"; exit 1; }

echo "fixture 0021/01 OK — cron-monitor.ts updated to v1.20.0, queue-monitor.ts added, version 1.20.0"
