#!/usr/bin/env bash
# Verify fixture 11: engine recognises NO wrapper roots; no cron-monitor.ts
# written anywhere; version bumps to 1.18.0; exit 0.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

# Critical: NO cron-monitor.ts must be written anywhere in the project.
if find . -name cron-monitor.ts -type f 2>/dev/null | grep -q .; then
  echo "T-25-04 regression: engine wrote cron-monitor.ts despite no valid wrapper anchor"
  find . -name cron-monitor.ts -type f
  exit 1
fi
if find . -name queue-monitor.ts -type f 2>/dev/null | grep -q .; then
  echo "T-25-04 regression: engine wrote queue-monitor.ts despite no valid wrapper anchor"
  find . -name queue-monitor.ts -type f
  exit 1
fi

# Version still bumps to 1.18.0 — engine treats no-wrapper-found as on-track.
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0 (no-wrapper path should still bump)"; exit 1; }

# Stray files unchanged.
test -f dist/index.ts || { echo "stray dist/index.ts disappeared"; exit 1; }
test -f src/utils/index.ts || { echo "stray src/utils/index.ts disappeared"; exit 1; }

echo "fixture 11 OK — stray index.ts files correctly skipped"
