#!/usr/bin/env bash
# Verify fixture 12: engine drops dist/server/ candidate via codex M-2 dist-path
# filter even though sibling middleware.ts is present.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

# Critical: dist/server/ must NOT receive a cron-monitor.ts or queue-monitor.ts.
test ! -e dist/server/cron-monitor.ts || { echo "codex M-2 regression: engine wrote cron-monitor.ts under dist/server/"; exit 1; }
test ! -e dist/server/queue-monitor.ts || { echo "codex M-2 regression: engine wrote queue-monitor.ts under dist/server/"; exit 1; }
test ! -e dist/server/healthz-snippet.ts || { echo "codex M-2 regression: engine wrote healthz-snippet.ts under dist/server/"; exit 1; }

# No cron-monitor.ts anywhere else either (no other wrapper exists in this fixture).
if find . -name cron-monitor.ts -type f 2>/dev/null | grep -q .; then
  echo "codex M-2 regression: engine wrote cron-monitor.ts somewhere in fixture 12"
  find . -name cron-monitor.ts -type f
  exit 1
fi

# Version still bumps to 1.18.0 — engine treats no-wrapper-found (after filter) as on-track.
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0 (no-wrapper path should still bump)"; exit 1; }

# The dist-shaped pair is unchanged.
test -f dist/server/index.ts || { echo "dist/server/index.ts disappeared"; exit 1; }
test -f dist/server/middleware.ts || { echo "dist/server/middleware.ts disappeared"; exit 1; }

echo "fixture 12 OK — dist/server/ anchor-pair correctly rejected by dist-path filter (codex M-2)"
