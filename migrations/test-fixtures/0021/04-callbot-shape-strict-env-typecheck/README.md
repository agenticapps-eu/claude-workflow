# Fixture 0021/04 — Migrated-wrapper strict-Env typecheck (SC5 / D-18 RESHAPED)

This fixture is the **migrated-wrapper SC5 acceptance gate** per CONTEXT D-18
(post-codex-review reshape from H-1: template-import shape didn't prove the supported
migration path works; H-2: depends on `@cloudflare/workers-types` which the
harness doesn't install).

## What it proves

Per issue #56 §"Acceptance check" four items:
1. callbot can use upstream `withCronMonitor` with strict-typed Env (no Record<string, unknown> cast).
2. callbot can use upstream `withQueueMonitor` with the same strict-typed Env.
3. `CronMonitorSchedule` interval variant accepts `{ value: number; unit: ... }` (no string cast).
4. `tsc --noEmit` against the smoke.ts compiles cleanly — END-TO-END (codex M-7) through the supported 0021 migration path.

## Procedure (verify.sh)

1. Seed a post-0019 v1.19.0 consumer wrapper tree (frozen literal files; no LOCAL-PATCH so 0021 accepts).
2. Run `migrate-0021-with-cron-and-queue-updates.sh` against the seed.
3. Assert cron-monitor.ts updated (D-03 discriminated union present), queue-monitor.ts added.
4. Run `npx -p typescript@5 tsc --noEmit -p tsconfig.json` against the resulting tree using a
   callbot-shape strict Env interface (named fields only, no [k: string]).
5. tsc exits 0 — proves both `withCronMonitor<CallbotEnv>` AND `withQueueMonitor<CallbotEnv>` compile.

## Codex H-2 fix: local types.d.ts

The fixture's `tsconfig.json` references a local `types.d.ts` providing minimal ambient
declarations for `ScheduledController`, `ExecutionContext`, `MessageBatch<Body>`. This
avoids depending on `@cloudflare/workers-types` (which the harness `npx tsc` invocation
does not install).
