# 0033 — withQueueMonitor + Migration 0021 (re-rev) for Cloudflare Queue consumers

**Status**: Accepted  **Date**: 2026-05-31  **Phase**: 25-fix-0019-engine-and-cron-wrappers

## Context

Phase 22 shipped `withCronMonitor` for Cloudflare scheduled handlers (cron triggers). Cloudflare Queue consumer handlers (`(batch: MessageBatch<Body>, env: Env, ctx: ExecutionContext) => void | Promise<void>`) have no parallel Sentry Crons heartbeat wrapper. callbot hand-rolled a `withMonitor` helper for queue handlers in `apps/backend/src/index.ts` — duplicative, drift-prone, and inconsistent with the established `withCronMonitor` convention. Issue #56 Finding 4.

Separately, the migration 0019 runner's `from_version: 1.17.0` exact-match contract (`migrations/README.md:60-99`) means re-revving 0019 cannot deliver `queue-monitor.{ts,go}` to projects already at v1.19.0 (callbot included). A project at v1.19.0 has already run migration 0019; the runner will not re-trigger it regardless of whether the engine is re-rev'd. There is no `--force` flag. The only supported forward path for already-migrated projects is a new migration with `from_version: 1.19.0`.

## Decision

Two complementary deliverables:

**(i) New `withQueueMonitor` export in TWO TS templates — cf-worker AND cf-pages ONLY** (codex H-6: Supabase Edge runs on Deno; `MessageBatch` + `ExecutionContext` are Workers-runtime types with no Cloudflare-Queue equivalent on the Deno/Supabase platform). Signature mirrors Cloudflare's canonical `QueueHandler<Env, Message, Props>`:

```typescript
export function withQueueMonitor<
  E extends { SENTRY_DSN?: string; SERVICE_NAME?: string },
  Msg = unknown,
>(
  handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>,
  config?: CronMonitorConfig,
): (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => Promise<void>
```

Guarded Shape A semantics (ADR-0029): `handlerStarted` flag distinguishes pre-callback Sentry transport failure (fall back to unmonitored handler — queue consumer ALWAYS runs) from post-callback errors (propagate). Slug resolution mirrors `withCronMonitor`'s D6 3-source policy: explicit `config.monitorSlug` > env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` (uppercase, hyphens → underscores) > auto-derive `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`. Default handler name `"queue"`. Multi-queue handlers dispatching on `batch.queue` MUST set `monitorSlug` explicitly (silent + docs policy per D-10; mirrors Phase 22 D11). `withQueueMonitor` re-imports `CronMonitorConfig` (type), `buildMonitorConfig` (value), and `isConfigured` (value) from `./cron-monitor` via a single import line (D-19 helper export contract).

**(ii) New Migration 0021 (`from_version: 1.19.0` → `to_version: 1.20.0`) — re-rev with dirty detection** (NOT additive-only) ships updated `cron-monitor.ts` AND new `queue-monitor.ts` to already-migrated v1.19.0 projects. See **Migration delivery** subsection below.

## Migration delivery (re-rev rationale per D-02b post-codex-review — codex H-7)

An additive-only Migration 0021 that only shipped `queue-monitor.ts` would leave callbot's v1.19.0 `cron-monitor.ts` at the pre-Phase-25 broken state (the `interface CronMonitorSchedule { type: "crontab" | "interval"; value: string }` shape that forces the `as Record<string, unknown>` LOCAL-PATCH). Findings 2 (broken schedule type) and 3 (strict-Env cast) of issue #56 would not close for v1.19.0 consumers. An additive-only migration would also leave the generic narrowing (D-05) unapplied to callbot's `withCronMonitor`, meaning the LOCAL-PATCH remains necessary even after migration.

The re-rev shape ships BOTH the updated `cron-monitor.ts` (D-03 discriminated-union schedule type for all three TS stacks; D-05 narrowed generic for cf-worker + openrouter; D-19 helper exports `buildMonitorConfig` + `isConfigured` for cf-worker + cf-pages) AND the new `queue-monitor.ts` (cf-worker + cf-pages only). Engine mirrors 0019's `canonicalize_awk` content-hash + all-clean-gate + per-root apply pattern (per `migrations/0019-sentry-crons-and-healthz.md:260` anti-pattern: "Mirror, not fork, 0017's canonicaliser").

**Twofold idempotency (codex M-8):** SKIP only when BOTH (a) `queue-monitor.ts` is present AND (b) `cron-monitor.ts` canonical-hash matches the v1.20.0 baseline. Single-condition idempotency on `cron-monitor.ts` alone would cause the engine to SKIP on a v1.19.0 project where `cron-monitor.ts` was hand-modified to match the v1.20.0 hash but `queue-monitor.ts` was never added.

**Refuse on dirty cron-monitor.ts:** callbot's LOCAL-PATCH at `cron-monitor.ts:141-149` (the `as Record<string, unknown>` cast pattern) produces a canonical hash that matches NEITHER the v1.19.0 baseline NOR the v1.20.0 template baseline. Engine REFUSEs and emits `.observability-0021.patch` with the diff. The honest user story: callbot drops the LOCAL-PATCH first (no longer needed because D-03 + D-05 fix the underlying type issues IN THE TEMPLATE), then re-runs 0021. This is the supported upgrade path; it is documented in `0021-with-cron-and-queue-updates.md`'s "Recovery" section.

## Alternatives Rejected

| Alternative | Reason Rejected |
|-------------|-----------------|
| **Re-shape `withCronMonitor` to accept `MessageBatch` OR `ScheduledController`** | Phase 22 D1 separate-wrapper precedent applies. A combined handler-type union makes the API confusing (which callback shape am I writing? what do the slug-resolution rules apply to?). Separate wrapper keeps the API surface frozen and lets queue-specific knobs land without churning the cron wrapper. |
| **Extend cron's name** (e.g., `withCronOrQueueMonitor`) | Confusing name. Makes the API surface feel bolted-on. cf-worker users discovering the API via IntelliSense would see an oddly-named export. |
| **Ship queue-monitor only in 0019 re-rev** | Runner contract prevents reaching v1.19.0 projects (`from_version: 1.17.0` exact-match). Projects at v1.18.0 or v1.19.0 cannot re-trigger 0019. |
| **Skip migration, document manual copy** | Friction. The whole point of the migration runner is to eliminate manual steps. Callbot and future cf-worker consumers at v1.19.0 would need to hand-copy the file — exactly the situation the runner exists to avoid. |
| **Add `--force` flag to 0019** | The `--force` flag does not exist today (verified in research). Expanding the engine surface for a one-off workaround adds maintenance debt. |
| **Ship `ts-supabase-edge/queue-monitor.ts` for symmetry** | Non-functional in Deno-runtime template per codex H-6. `MessageBatch` and `ExecutionContext` are Workers-runtime types; there is no Cloudflare-Queue equivalent on the Supabase Edge/Deno platform. Shipping a file that cannot be used in its target runtime is worse than not shipping it. |
| **Additive-only 0021 (queue-monitor.ts only)** | Fails to close findings 2 and 3 for v1.19.0 consumers per codex H-7. Leaves callbot's `cron-monitor.ts` at the broken pre-Phase-25 state — the `as Record<string, unknown>` LOCAL-PATCH remains necessary. The honest migration story for callbot requires delivering BOTH the updated `cron-monitor.ts` AND the new `queue-monitor.ts`. |

## Consequences

- Cloudflare Queue consumer handlers on cf-worker + cf-pages now have heartbeat parity with scheduled handlers. callbot can replace its local `withMonitor` helper with the upstream `withQueueMonitor`.
- v1.19.0 projects pick up updated `cron-monitor.ts` + new `queue-monitor.ts` via Migration 0021 (no manual recovery required, modulo the LOCAL-PATCH drop). The LOCAL-PATCH drop is not friction — it is the correct resolution of Finding 3: the patch was a workaround for a bug in the template; the re-rev template ships without the bug.
- `claude-workflow` bumps 1.19.0 → 1.20.0 (minor, two migration deltas: 0019 re-rev + new 0021 with dirty detection). `add-observability` bumps 0.8.0 → 0.9.0 (minor, narrowed template surface changes: D-03 × 4 sites; D-05 cf-worker + openrouter only; D-07 cf-worker + cf-pages only; D-19 helper exports cf-worker + cf-pages + openrouter; D-21 bundled refresh).
- Multi-queue handlers dispatching on `batch.queue` MUST set `monitorSlug` explicitly (silent + docs policy, mirrors Phase 22 D11). `withQueueMonitor`'s doc comment carries the canonical policy phrase.
- Supabase Edge unaffected. The platform mismatch is documented in this ADR and in `migrations/0019-sentry-crons-and-healthz.md`. If a Deno-Queue-equivalent surfaces, a separate Phase addresses it.
- Extends ADR-0029 (Guarded Shape A composition pattern). The `handlerStarted` guard is the same flag semantics as `withCronMonitor`; test surface mirrors the cron test suite (D-17 behavioural-parity tests, including codex M-6 synchronous-throw post-callback test).
