#!/usr/bin/env bash
# Verify fixture 05: 3 cf-worker roots migrated, react-vite root skipped (D10).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

WORKER_ROOTS=(
  "services/worker-a/.observability"
  "services/worker-b/.observability"
  "services/worker-c/.observability"
)
REACT_ROOT="apps/web/.observability"

set +e
out=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; printf '%s\n' "$out" | head -10; exit 1; }

# All 3 worker roots got cron-monitor.ts + healthz-snippet.ts.
for d in "${WORKER_ROOTS[@]}"; do
  test -f "$d/cron-monitor.ts" \
    || { echo "worker root $d missing cron-monitor.ts"; exit 1; }
  test -f "$d/healthz-snippet.ts" \
    || { echo "worker root $d missing healthz-snippet.ts"; exit 1; }
done

# React-vite root got NEITHER (D10 skip).
test ! -e "$REACT_ROOT/cron-monitor.ts" \
  || { echo "react-vite root incorrectly got cron-monitor.ts (D10 skip violated)"; exit 1; }
test ! -e "$REACT_ROOT/healthz-snippet.ts" \
  || { echo "react-vite root incorrectly got healthz-snippet.ts (D10 skip violated)"; exit 1; }

# Engine output should mention the react-vite skip explicitly.
echo "$out" | grep -qE 'react-vite|D10|unsupported' \
  || { echo "engine output missing react-vite skip notice"; exit 1; }

# Version bumped to 1.18.0.
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0"; exit 1; }

echo "fixture 05 OK — 3 workers migrated, react-vite skipped (D10), version 1.18.0"
