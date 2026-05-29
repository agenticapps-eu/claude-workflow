#!/usr/bin/env bash
# Verify fixture 03: refuse path. Engine exits 2 (refused); cron-monitor.ts +
# healthz-snippet.ts NOT created; middleware.ts unchanged (hand-edit intact);
# .observability-0019.patch emitted; SKILL.md version NOT bumped.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

ROOT="src/lib/observability"

# Precondition — hand-edit marker present.
grep -q 'HAND-MODIFIED' "$ROOT/middleware.ts" \
  || { echo "fixture 03 precondition: hand-edit marker missing"; exit 1; }

cp "$ROOT/middleware.ts" /tmp/0019f03-middleware.before

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "expected engine exit 2 (refuse), got $rc"; exit 1; }

# No new files written into the wrapper.
test ! -e "$ROOT/cron-monitor.ts" \
  || { echo "REFUSE VIOLATION: cron-monitor.ts written despite dirty wrapper"; exit 1; }
test ! -e "$ROOT/healthz-snippet.ts" \
  || { echo "REFUSE VIOLATION: healthz-snippet.ts written despite dirty wrapper"; exit 1; }

# middleware.ts unchanged (engine did not rewrite the wrapper).
diff -q /tmp/0019f03-middleware.before "$ROOT/middleware.ts" >/dev/null \
  || { echo "REFUSE VIOLATION: middleware.ts was rewritten"; exit 1; }

# Recovery patch emitted.
test -f "$ROOT/.observability-0019.patch" \
  || { echo "refuse-path .observability-0019.patch not generated"; exit 1; }
test -s "$ROOT/.observability-0019.patch" \
  || { echo ".observability-0019.patch is empty"; exit 1; }

# Version NOT bumped on the refuse path.
grep -q '^version: 1.17.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "REFUSE VIOLATION: version bumped despite refuse"; exit 1; }

rm -f /tmp/0019f03-middleware.before
echo "fixture 03 OK — refused, no new files, middleware.ts intact, patch emitted, version unchanged"
