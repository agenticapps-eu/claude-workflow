//
// withCronMonitor (Pages Functions variant) — Sentry Crons heartbeat wrapper
// for an externally-triggered Pages Function or any async cron-like work
// the operator runs. Per CONTEXT D5c, Pages Functions don't have scheduled
// handlers; this wrapper accepts a generic () => Promise<R> and is invoked
// by whatever externally triggers the work (e.g. a parallel Worker on cron
// trigger, or Cloudflare Workflows). See CONTEXT D5c, D6, D11, D12.
//
// Shape diverges from ts-cloudflare-worker:
//   - handler is a thunk `() => Promise<R>` (no ScheduledController, no ctx).
//   - The wrapper returns `(env) => Promise<R>` — env is the SECOND arg
//     (after the handler is curried in) and must be passed explicitly by
//     the external trigger.
//   - There is no standard innermost composition (D5c) — operator invokes
//     externally.
//
// Phase 23 / ADR-0029: refactored from hand-rolled captureCheckIn lifecycle to
// Guarded Shape A — composes Sentry.withMonitor with a handlerStarted flag so
// a pre-callback transport failure falls back to unmonitored execution (cron
// always runs). Post-callback errors propagate to the caller. See D-08.
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
  /** Handler name for env-var key derivation AND auto-derive shape.
   *  Defaults to "scheduled" per D6 row 2 / G4. */
  handlerName?: string;
  /** Cron schedule metadata forwarded to Sentry as `monitorConfig.schedule`. */
  schedule?: CronMonitorSchedule;
  /** Forwarded to Sentry as `monitorConfig.maxRuntime` (D12). Metadata-only;
   *  not enforced client-side (see CONTEXT N5). */
  maxRuntimeSeconds?: number;
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

const SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";

// Phase 25 D-19 (cf-worker + cf-pages export contract) — exported so Plan 04's
// cf-pages queue-monitor.ts can re-import (D-07). Signature kept wide
// (Record<string, unknown>) per cf-pages withCronMonitor shape (no D-05 narrowing here).
export function isConfigured(env: Record<string, unknown>): boolean {
  return typeof env.SENTRY_DSN === "string" && (env.SENTRY_DSN as string).length > 0;
}

/**
 * D6 — 3-source slug resolution (precedence: explicit > env > auto-derive).
 * Pages auto-shape: `${SERVICE_NAME ?? "service"}:${handlerName ?? "scheduled"}`
 * (per D6 row 2 + G4 — no controller.cron available outside a scheduled handler).
 */
function resolveSlug(
  config: CronMonitorConfig | undefined,
  env: Record<string, unknown>,
): string {
  // 1. Explicit.
  if (config?.monitorSlug) return config.monitorSlug;

  // 2. Env var: SENTRY_CRON_MONITOR_SLUG_<HANDLER> (uppercased, hyphens → underscores).
  const handlerName = config?.handlerName ?? "scheduled";
  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = env[envKey];
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;

  // 3. Auto-derive — pages uses handlerName since there is no runtime cron expr.
  const serviceName = typeof env.SERVICE_NAME === "string" ? env.SERVICE_NAME : "service";
  return `${serviceName}:${handlerName}`;
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
// cf-pages queue-monitor.ts can re-import (D-07). Body unchanged; only the
// `export` keyword is added.
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
 * withCronMonitor — wraps a generic `() => Promise<R>` thunk with Sentry Crons
 * heartbeats via `Sentry.withMonitor` for Pages Functions cron-like work.
 *
 * Unlike the Worker variant, env is NOT ambient — Pages Functions receive env
 * via the request context, so the wrapper's returned function takes env as
 * its single argument and forwards control to the inner handler.
 *
 * Guarded Shape A (ADR-0029 / D-08):
 *  - No-ops when `SENTRY_DSN` is unset (fail-safe per R02).
 *  - Slug resolves per D6 (explicit > env > auto-derive on handlerName).
 *  - `monitorConfig` (schedule + maxRuntime) forwarded as Sentry's 3rd arg.
 *  - Pre-callback transport failure → falls back to unmonitored handler run
 *    (cron always executes — Guarded Shape A guarantee).
 *  - Post-callback errors (handler throw OR ok/error check-in transport) →
 *    propagate to outer caller (no longer swallowed; SENTRY_DEBUG removed).
 */
export function withCronMonitor<R>(
  handler: () => Promise<R>,
  config?: CronMonitorConfig,
): (env: Record<string, unknown>) => Promise<R> {
  return async (env) => {
    if (!isConfigured(env)) {
      // Fail-safe: no DSN → no checkins, handler runs unchanged.
      return handler();
    }

    const monitorSlug = resolveSlug(config, env);
    const monitorConfig = buildMonitorConfig(config);

    // Guarded Shape A (ADR-0029 / D-08):
    // handlerStarted distinguishes pre-callback transport failure (fall back to
    // unmonitored) from post-callback errors (propagate to caller).
    let handlerStarted = false;
    try {
      return await Sentry.withMonitor(
        monitorSlug,
        () => {
          handlerStarted = true;
          return handler();
        },
        monitorConfig,
      ) as R;
    } catch (err) {
      if (!handlerStarted) {
        // Sentry transport failed before handler ran — fall back to unmonitored.
        return handler();
      }
      // handler-thrown OR post-callback errors propagate to outer caller.
      throw err;
    }
  };
}
