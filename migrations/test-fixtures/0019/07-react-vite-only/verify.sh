#!/usr/bin/env bash
# Verify fixture 07 (R09 binding): react-vite-only → engine classifies as
# unsupported (D10), writes no new files, exits 0; version bumps because the
# project is on-track (no migratable stacks present means nothing to do, but
# the project is still considered "up to date" against 0019).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

ROOT="src/lib/observability"

set +e
out=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; printf '%s\n' "$out" | head -10; exit 1; }

# No cron-monitor.{ts,go} or healthz-snippet.{ts,go} files anywhere — verify
# by listing the project tree and grepping. (find against the cwd is enough
# since the fixture sandbox is the CWD.)
hits=$(find . -type f \( -name 'cron-monitor.ts' -o -name 'cron_monitor.go' -o -name 'healthz-snippet.ts' -o -name 'healthz_snippet.go' \) 2>/dev/null | head -1)
[ -z "$hits" ] || { echo "react-vite-only VIOLATION: new files found at $hits"; exit 1; }

# No refuse artefacts.
test ! -e "$ROOT/.observability-0019.patch" \
  || { echo "react-vite-only VIOLATION: .observability-0019.patch emitted (refuse path was not taken)"; exit 1; }

# Engine output mentions the react-vite skip / unsupported notice.
echo "$out" | grep -qE 'react-vite|D10|unsupported|no materialised' \
  || { echo "engine output missing react-vite / unsupported skip notice"; exit 1; }

# Version bumped to 1.18.0 (the engine treats the project as 0019-resolved).
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0"; exit 1; }

echo "fixture 07 OK — react-vite-only: skipped (D10), no files written, version 1.18.0"
