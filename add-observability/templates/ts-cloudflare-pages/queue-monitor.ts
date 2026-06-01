//
// withQueueMonitor — Sentry Crons heartbeat wrapper for Cloudflare Queue
// consumer handlers. Mirrors withCronMonitor (cron-monitor.ts) line-for-line;
// only the handler signature differs (MessageBatch first-arg instead of
// ScheduledController).
//
// Phase 25 D-07 / ADR-0033 — new export sibling to withCronMonitor. Composes
// INNERMOST per D5a:
//   withSentry(env)(withObservabilityScheduled(withQueueMonitor(handler, {...})))
//
// D-08 — Guarded Shape A (ADR-0029): handlerStarted flag distinguishes pre-callback
// Sentry transport failure (fall back to unmonitored — queue always runs) from
// post-callback errors (propagate to outer wrapper). Both ASYNC rejections AND
// SYNCHRONOUS throws after handlerStarted=true correctly propagate (codex M-6 corner).
//
// D-09 — 3-source slug resolution (mirrors withCronMonitor D6): explicit
// config.monitorSlug > env var SENTRY_CRON_MONITOR_SLUG_<HANDLER> > auto-derive
// `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`. Reuses the shared
// SENTRY_CRON_MONITOR_SLUG_ prefix. Default handlerName: "queue" → env key
// SENTRY_CRON_MONITOR_SLUG_QUEUE.
//
// D-10 — multi-queue handlers (dispatchers that route by batch.queue) MUST
// pass explicit monitorSlug. The env-key form cannot disambiguate, and the
// auto-derived form produces per-queue slugs the operator may not have
// provisioned in Sentry. Silent + docs policy mirrors Phase 22 D11. There is
// no compile-time overload and no runtime warning — this comment IS the
// enforcement. The canonical phrase "MUST pass explicit monitorSlug" appears
// in this jsdoc and is the anchor for the D-10 regex assertion in
// queue-monitor.test.ts (Plan 01 Task 1.4).
//

import * as Sentry from "@sentry/cloudflare";
// D-19 (CONTEXT.md revised export contract) — re-import CronMonitorConfig + the
// two value-level helpers from ./cron-monitor. Plan 03 Task 3.1 added the
// `export` keyword to both helpers in cron-monitor.ts so this import compiles.
// NO inline duplication — both files always co-copy via migrations 0019 and 0021.
import { type CronMonitorConfig, buildMonitorConfig, isConfigured } from "./cron-monitor";

// ─── Internal helpers ─────────────────────────────────────────────────────────

const SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";

/**
 * D-09 — 3-source slug resolution (precedence: explicit > env > auto-derive).
 * Queue auto-shape: `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`.
 * D-10: multi-queue dispatchers MUST pass explicit monitorSlug — env-key
 * form cannot disambiguate, and the auto-derived form will produce per-queue
 * slugs that the operator may not have provisioned in Sentry.
 */
function resolveQueueSlug<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(
  config: CronMonitorConfig | undefined,
  env: E,
  batch: MessageBatch<unknown>,
): string {
  // 1. Explicit.
  if (config?.monitorSlug) return config.monitorSlug;

  // 2. Env var: SENTRY_CRON_MONITOR_SLUG_<HANDLER> (uppercased, hyphens → underscores).
  const handlerName = config?.handlerName ?? "queue";
  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = (env as unknown as Record<string, unknown>)[envKey];
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;

  // 3. Auto-derive — queue uses the runtime-provided queue name.
  const serviceName = typeof env.SERVICE_NAME === "string" ? env.SERVICE_NAME : "service";
  return `${serviceName}:queue:${batch.queue}`;
}

// ─── Public wrapper ───────────────────────────────────────────────────────────

/**
 * withQueueMonitor — wraps a Cloudflare Queue consumer handler with Sentry
 * Crons heartbeats via Sentry.withMonitor. Per D5a, composes INNERMOST so
 * errors propagate to the outer withObservabilityScheduled capture path.
 *
 * D-10 multi-queue dispatcher policy: handlers that route by `batch.queue`
 * (i.e., the same Worker handles N queues and the per-queue logic branches
 * on batch.queue) MUST pass explicit monitorSlug. The default auto-derived
 * slug produces per-queue identifiers that may not exist server-side. There
 * is no compile-time enforcement — this contract is documented here only
 * (silent + docs policy, mirrors Phase 22 D11).
 *
 * Guarded Shape A (ADR-0029 / D-08):
 *  - No-ops when SENTRY_DSN is unset (fail-safe per R02).
 *  - Slug resolves per D-09 (explicit > env > auto-derive).
 *  - monitorConfig (schedule + maxRuntime) forwarded as Sentry's 3rd arg.
 *  - Pre-callback transport failure → falls back to unmonitored handler run
 *    (queue always executes — Guarded Shape A guarantee).
 *  - Post-callback errors (handler throw — async OR sync — OR ok/error
 *    check-in transport) → propagate to outer wrapper.
 */
export function withQueueMonitor<
  E extends { SENTRY_DSN?: string; SERVICE_NAME?: string },
  Msg = unknown,
>(
  handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>,
  config?: CronMonitorConfig,
): (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => Promise<void> {
  return async (batch, env, ctx) => {
    if (!isConfigured(env)) {
      // Fail-safe: no DSN → no checkins, handler runs unchanged.
      await handler(batch, env, ctx);
      return;
    }

    const monitorSlug = resolveQueueSlug(config, env, batch);
    const monitorConfig = buildMonitorConfig(config);

    // Guarded Shape A (ADR-0029 / D-08):
    // handlerStarted distinguishes "Sentry transport failed before callback ran"
    // (pre-callback: fall back to unmonitored handler — queue always runs) from
    // "error thrown after callback completed" (post-callback: propagate as before).
    // Codex M-6: both async REJECTION and synchronous THROW after handlerStarted=true
    // propagate correctly — sync throws inside the inner callback bubble through
    // Sentry.withMonitor and land in this catch with handlerStarted already true.
    let handlerStarted = false;
    try {
      await Sentry.withMonitor(
        monitorSlug,
        () => {
          handlerStarted = true;
          return handler(batch, env, ctx);
        },
        monitorConfig,
      );
    } catch (err) {
      if (!handlerStarted) {
        // Sentry transport failed before handler ran — fall back to unmonitored.
        await handler(batch, env, ctx);
        return;
      }
      // handler-thrown (async OR sync, post-callback) OR post-callback Sentry
      // errors propagate to outer wrapper.
      throw err;
    }
  };
}
