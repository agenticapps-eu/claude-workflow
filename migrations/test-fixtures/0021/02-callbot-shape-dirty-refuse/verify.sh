#!/usr/bin/env bash
# Verify fixture 0021/02: engine REFUSEs on hand-modified cron-monitor.ts;
# emits .observability-0021.patch; exits non-zero.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
ROOT="src/lib/observability"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
# REFUSE path: exit non-zero (Plan 05 documents exit 2 as the canonical REFUSE code).
[ "$rc" -ne 0 ] || { echo "expected engine to REFUSE (non-zero exit), got $rc"; exit 1; }

# Patch file must exist with cron-monitor.ts diff content.
test -f .observability-0021.patch || { echo ".observability-0021.patch not emitted"; exit 1; }
grep -q "cron-monitor.ts" .observability-0021.patch \
  || { echo ".observability-0021.patch does not mention cron-monitor.ts"; exit 1; }

# The hand-modified cron-monitor.ts must remain untouched (engine refuses before write).
grep -q "_localPatchSentinel" "$ROOT/cron-monitor.ts" \
  || { echo "engine should NOT have rewritten cron-monitor.ts (LOCAL-PATCH stripped)"; exit 1; }

# queue-monitor.ts must NOT be installed on a REFUSE.
test ! -e "$ROOT/queue-monitor.ts" \
  || { echo "queue-monitor.ts should not be installed when engine refuses"; exit 1; }

# SKILL.md version unchanged.
grep -q '^version: 1.19.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version should remain 1.19.0 on REFUSE"; exit 1; }

echo "fixture 0021/02 OK — engine REFUSEd on dirty cron-monitor.ts; patch emitted"
