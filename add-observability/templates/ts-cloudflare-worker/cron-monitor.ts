//
// withCronMonitor — Sentry Crons heartbeat wrapper for Cloudflare Worker
// scheduled handlers. See ../../.planning/phases/22-sentry-crons-healthz/CONTEXT.md
// (D1 separate wrapper, D5a composition order, D6 3-source slug resolution,
// D11 multi-cron explicit-slug requirement, D12 monitorConfig forwarding).
//
// Composes INNERMOST per D5a:
//   withSentry(env)(withObservabilityScheduled(withCronMonitor(handler, {...})))
//
// Phase 23 / ADR-0029: refactored from hand-rolled captureCheckIn lifecycle to
// Guarded Shape A — composes Sentry.withMonitor with a handlerStarted flag so
// a pre-callback transport failure falls back to unmonitored execution (cron
// always runs). Post-callback errors propagate to the outer wrapper. See D-08.
//

import * as Sentry from "@sentry/cloudflare";

// ─── Public types ─────────────────────────────────────────────────────────────

/**
 * Discriminated-union schedule type — structurally compatible with
 * Sentry's `MonitorSchedule` (see @sentry/core/types-hoist/checkin.d.ts).
 * Phase 25 D-03 / ADR-0032 — replaces the prior interface that forced
 * consumers to cast interval values from string to number.
 */
export type CronMonitorSchedule =
  | { type: "crontab"; value: string }
  | { type: "interval"; value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" };

export interface CronMonitorConfig {
  /** Explicit monitor slug — wins over env + auto-derive (D6 source 1). */
  monitorSlug?: string;
  /** Handler name for env-var key derivation. Defaults to "scheduled". */
  handlerName?: string;
  /** Cron schedule metadata forwarded to Sentry as `monitorConfig.schedule`. */
  schedule?: CronMonitorSchedule;
  /** Forwarded to Sentry as `monitorConfig.maxRuntime` (D12). Metadata-only;
   *  not enforced client-side (see CONTEXT N5). */
  maxRuntimeSeconds?: number;
}

type ScheduledFn<E> = (
  controller: ScheduledController,
  env: E,
  ctx: ExecutionContext,
) => void | Promise<void>;

// ─── Internal helpers ─────────────────────────────────────────────────────────

const SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";

// Phase 25 D-19 (cf-worker + cf-pages export contract) + D-05 (narrowed generic)
// — exported so Plan 04's queue-monitor.ts can re-import (D-07).
export function isConfigured(env: { SENTRY_DSN?: string }): boolean {
  return typeof env.SENTRY_DSN === "string" && env.SENTRY_DSN.length > 0;
}

/**
 * D6 — 3-source slug resolution (precedence: explicit > env > auto-derive).
 * Worker auto-shape: `${SERVICE_NAME ?? "service"}:${controller.cron}`.
 * D11: multi-cron workers MUST pass explicit `monitorSlug` — env-key form
 * cannot disambiguate, and the auto-derived form will produce per-cron
 * slugs that the operator may not have provisioned in Sentry.
 */
function resolveSlug<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(
  config: CronMonitorConfig | undefined,
  env: E,
  controller: ScheduledController,
): string {
  // 1. Explicit.
  if (config?.monitorSlug) return config.monitorSlug;

  // 2. Env var: SENTRY_CRON_MONITOR_SLUG_<HANDLER> (uppercased, hyphens → underscores).
  const handlerName = config?.handlerName ?? "scheduled";
  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  // Phase 25 D-05 / ADR-0032 — narrowed generic accepts strict-typed Env interfaces
  // (no index signature required). Internal lookup casts to Record at the access
  // site because env-key names are dynamic (not statically known in the generic).
  const fromEnv = (env as unknown as Record<string, unknown>)[envKey];
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;

  // 3. Auto-derive — worker uses the runtime-provided cron expression.
  const serviceName = typeof env.SERVICE_NAME === "string" ? env.SERVICE_NAME : "service";
  const cronExpr = controller.cron || "scheduled";
  return `${serviceName}:${cronExpr}`;
}

/**
 * D12 / R03 — build Sentry's monitorConfig 2nd arg. Returns `undefined` when
 * neither `schedule` nor `maxRuntimeSeconds` is set so the wrapper omits the
 * 2nd arg entirely on the in_progress call (and unconditionally on ok/error).
 *
 * Sentry's field name is `maxRuntime`, not `maxRuntimeSeconds` — the wrapper
 * exposes the longer/clearer name and renames at the boundary.
 */
// Phase 25 D-19 (cf-worker + cf-pages export contract) — exported so Plan 04's
// queue-monitor.ts can re-import (D-07). Body unchanged; only the `export`
// keyword is added.
export function buildMonitorConfig(
  config: CronMonitorConfig | undefined,
): { schedule?: CronMonitorSchedule; maxRuntime?: number } | undefined {
  if (!config) return undefined;
  const hasSchedule = config.schedule !== undefined;
  const hasMaxRuntime = config.maxRuntimeSeconds !== undefined;
  if (!hasSchedule && !hasMaxRuntime) return undefined;
  const out: { schedule?: CronMonitorSchedule; maxRuntime?: number } = {};
  if (hasSchedule) out.schedule = config.schedule;
  if (hasMaxRuntime) out.maxRuntime = config.maxRuntimeSeconds;
  return out;
}

// ─── Public wrapper ───────────────────────────────────────────────────────────

/**
 * withCronMonitor — wraps a Cloudflare Worker `scheduled` handler with Sentry
 * Crons heartbeats via `Sentry.withMonitor`. Per D5a, composes INNERMOST so
 * errors propagate to the outer `withObservabilityScheduled` capture path.
 *
 * Guarded Shape A (ADR-0029 / D-08):
 *  - No-ops when `SENTRY_DSN` is unset (fail-safe per R02).
 *  - Slug resolves per D6 (explicit > env > auto-derive).
 *  - `monitorConfig` (schedule + maxRuntime) forwarded as Sentry's 3rd arg.
 *  - Pre-callback transport failure → falls back to unmonitored handler run
 *    (cron always executes — Guarded Shape A guarantee).
 *  - Post-callback errors (handler throw OR ok/error check-in transport) →
 *    propagate to outer wrapper (no longer swallowed; SENTRY_DEBUG removed).
 */
export function withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(
  handler: ScheduledFn<E>,
  config?: CronMonitorConfig,
): ScheduledFn<E> {
  return async (controller, env, ctx) => {
    if (!isConfigured(env)) {
      // Fail-safe: no DSN → no checkins, handler runs unchanged.
      await handler(controller, env, ctx);
      return;
    }

    const monitorSlug = resolveSlug(config, env, controller);
    const monitorConfig = buildMonitorConfig(config);

    // Guarded Shape A (ADR-0029 / D-08):
    // handlerStarted distinguishes "Sentry transport failed before callback ran"
    // (pre-callback: fall back to unmonitored handler — cron always runs) from
    // "error thrown after callback completed" (post-callback: propagate as before).
    let handlerStarted = false;
    try {
      await Sentry.withMonitor(
        monitorSlug,
        () => {
          handlerStarted = true;
          return handler(controller, env, ctx);
        },
        monitorConfig,
      );
    } catch (err) {
      if (!handlerStarted) {
        // Sentry transport failed before handler ran — fall back to unmonitored.
        await handler(controller, env, ctx);
        return;
      }
      // handler-thrown OR post-callback errors propagate to outer wrapper.
      throw err;
    }
  };
}
