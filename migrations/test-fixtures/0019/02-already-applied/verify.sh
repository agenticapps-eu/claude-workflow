#!/usr/bin/env bash
# Verify fixture 02: pre-existing cron-monitor.ts is detected by the
# idempotency check; engine writes no files; placeholder bytes unchanged;
# version is bumped (a project flagged "already applied" at all roots is
# treated as on-track and allowed to advance to 1.18.0).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

ROOT="src/lib/observability"

# Capture pre-run hash from the witness file.
before_hash=$(cat .fixture-02-cron-hash)

set +e
out=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; printf '%s\n' "$out" | head -5; exit 1; }

# Placeholder cron-monitor.ts bytes unchanged.
if command -v sha256sum >/dev/null 2>&1; then
  after_hash=$(sha256sum "$ROOT/cron-monitor.ts" | awk '{print $1}')
else
  after_hash=$(shasum -a 256 "$ROOT/cron-monitor.ts" | awk '{print $1}')
fi
[ "$before_hash" = "$after_hash" ] \
  || { echo "IDEMPOTENCY VIOLATION: cron-monitor.ts bytes changed"; exit 1; }

# Sentinel comment must still be present (defence-in-depth against unlucky hash collisions).
grep -q 'FIXTURE_02_SENTINEL' "$ROOT/cron-monitor.ts" \
  || { echo "IDEMPOTENCY VIOLATION: placeholder sentinel lost"; exit 1; }

# Engine did NOT install healthz-snippet.ts either (idempotency check on
# cron-monitor presence short-circuits the whole root).
test ! -e "$ROOT/healthz-snippet.ts" \
  || { echo "IDEMPOTENCY VIOLATION: healthz-snippet.ts written despite already-applied"; exit 1; }

# Engine output signals idempotent no-op (the wrapper was detected as already
# migrated by the cron-monitor.ts presence check).
echo "$out" | grep -qE "already migrated|idempotent no-op|already-applied" \
  || { echo "engine output missing idempotent no-op notice"; exit 1; }

# Version bumped to 1.18.0 (all roots resolved → safe to advance).
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0"; exit 1; }

echo "fixture 02 OK — pre-existing cron-monitor.ts preserved, version 1.18.0"
