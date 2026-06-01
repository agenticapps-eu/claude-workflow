#!/usr/bin/env bash
# Verify fixture 0021/03: engine SKIP_ALREADYs (exit 0, no files rewritten).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
ROOT="src/lib/observability"

# Snapshot mtimes BEFORE engine runs.
cm_mtime_before=$(stat -f %m "$ROOT/cron-monitor.ts" 2>/dev/null || stat -c %Y "$ROOT/cron-monitor.ts")
qm_mtime_before=$(stat -f %m "$ROOT/queue-monitor.ts" 2>/dev/null || stat -c %Y "$ROOT/queue-monitor.ts")

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected SKIP_ALREADY (exit 0), got $rc"; exit 1; }

# Files must be unchanged (mtime invariance — idempotent skip).
cm_mtime_after=$(stat -f %m "$ROOT/cron-monitor.ts" 2>/dev/null || stat -c %Y "$ROOT/cron-monitor.ts")
qm_mtime_after=$(stat -f %m "$ROOT/queue-monitor.ts" 2>/dev/null || stat -c %Y "$ROOT/queue-monitor.ts")
[ "$cm_mtime_before" = "$cm_mtime_after" ] \
  || { echo "cron-monitor.ts was rewritten during SKIP_ALREADY (codex M-8 regression)"; exit 1; }
[ "$qm_mtime_before" = "$qm_mtime_after" ] \
  || { echo "queue-monitor.ts was rewritten during SKIP_ALREADY"; exit 1; }

# Version stays 1.20.0.
grep -q '^version: 1.20.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version should remain 1.20.0"; exit 1; }

echo "fixture 0021/03 OK — twofold-idempotency SKIP (no rewrites; version 1.20.0)"
