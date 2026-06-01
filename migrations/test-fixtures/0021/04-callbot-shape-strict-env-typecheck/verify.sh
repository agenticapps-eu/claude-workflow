#!/usr/bin/env bash
# Verify fixture 0021/04 (D-18 SC5 migrated-wrapper):
#   (1) Run migrate-0021 against the seeded v1.19.0 wrapper.
#   (2) Assert cron-monitor.ts updated to v1.20.0; queue-monitor.ts added.
#   (3) Copy fixture-side smoke.ts / env.ts / types.d.ts / tsconfig.json into PWD.
#   (4) Run tsc --noEmit; expect exit 0 — END-TO-END SC5 GREEN (codex M-7).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
FIXTURE="$REPO_ROOT/migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck"
WRAPPER="wrapper"

# ── (1) Run migrate-0021 ───────────────────────────────────────────────────
set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "migrate-0021 exited $rc (expected 0)"; exit 1; }

# ── (2) Engine outputs landed ──────────────────────────────────────────────
test -f "$WRAPPER/cron-monitor.ts"   || { echo "cron-monitor.ts not updated"; exit 1; }
test -f "$WRAPPER/queue-monitor.ts"  || { echo "queue-monitor.ts not added"; exit 1; }
grep -q "type CronMonitorSchedule" "$WRAPPER/cron-monitor.ts" \
  || { echo "cron-monitor.ts not at v1.20.0 (no discriminated-union)"; exit 1; }
grep -q "withQueueMonitor" "$WRAPPER/queue-monitor.ts" \
  || { echo "queue-monitor.ts missing withQueueMonitor export"; exit 1; }

# ── (3) Stage local TS sources (types.d.ts, env.ts, smoke.ts, tsconfig.json) ─
cp "$FIXTURE/types.d.ts"      .
cp "$FIXTURE/env.ts"          .
cp "$FIXTURE/tsconfig.json"   .

# smoke.ts is generated here (it references the wrapper-relative path).
cat > smoke.ts <<'EOF'
// Migrated-wrapper smoke fixture — D-18 SC5 (codex M-7 end-to-end).
// Imports from the wrapper tree that migrate-0021 just produced; uses
// strict CallbotEnv (no index signature); compile must succeed.
import { withCronMonitor, type CronMonitorSchedule } from "./wrapper/cron-monitor";
import { withQueueMonitor } from "./wrapper/queue-monitor";
import type { CallbotEnv } from "./env";

// Item 1: withCronMonitor<CallbotEnv>.
const cronHandler = async (
  _ctrl: ScheduledController,
  env: CallbotEnv,
  _ctx: ExecutionContext,
): Promise<void> => {
  console.log(env.SERVICE_NAME);
};
export const scheduled = withCronMonitor<CallbotEnv>(cronHandler, {
  monitorSlug: "callbot:ingest",
});

// Item 3: CronMonitorSchedule interval variant (D-03).
const _interval: CronMonitorSchedule = { type: "interval", value: 15, unit: "minute" };
const _crontab:  CronMonitorSchedule = { type: "crontab",  value: "*/15 * * * *" };
void _interval; void _crontab;

// Item 2: withQueueMonitor<CallbotEnv, KompendiumEvent>.
interface KompendiumEvent { event_id: string; payload: unknown }
const queueHandler = async (
  batch: MessageBatch<KompendiumEvent>,
  env: CallbotEnv,
  _ctx: ExecutionContext,
): Promise<void> => {
  console.log(env.SUPABASE_URL, batch.queue, batch.messages.length);
};
export const queue = withQueueMonitor<CallbotEnv, KompendiumEvent>(queueHandler, {
  monitorSlug: "callbot:queue:kompendium-events",
});
EOF

# ── (4) Run tsc --noEmit; expect exit 0 ───────────────────────────────────
if ! command -v npx >/dev/null 2>&1; then
  echo "fixture 0021/04 SKIP — npx unavailable (cannot run tsc)"
  exit 0
fi

set +e
npx -y -p typescript@5 tsc --noEmit -p tsconfig.json >/tmp/tsc-0021-04.log 2>&1
tsc_rc=$?
set -e
if [ "$tsc_rc" -ne 0 ]; then
  echo "tsc --noEmit FAILED (SC5 regression):"
  cat /tmp/tsc-0021-04.log
  exit 1
fi

echo "fixture 0021/04 OK — D-18 SC5 GREEN (migrated wrapper compiles with strict CallbotEnv; codex M-7 end-to-end)"
