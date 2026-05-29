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
// Sentry SDK interaction is wrapped in try/swallow + opt-in debug log
// so an SDK throw during captureCheckIn doesn't break the cron — the
// heartbeat is not in the critical path. See PLAN R02/R03/R04.
//

import { captureCheckIn } from "@sentry/cloudflare";

// ─── Public types ─────────────────────────────────────────────────────────────

export interface CronMonitorSchedule {
  type: "crontab" | "interval";
  value: string;
}

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

function isConfigured(env: Record<string, unknown>): boolean {
  return typeof env.SENTRY_DSN === "string" && (env.SENTRY_DSN as string).length > 0;
}

function isDebug(env: Record<string, unknown>): boolean {
  return env.SENTRY_DEBUG === "1";
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
function buildMonitorConfig(
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

/**
 * R04 — surface swallowed errors only when `SENTRY_DEBUG=1`.
 * The Error object reaches the log call's argument list (test asserts via
 * `expect.arrayContaining([expect.any(Error)])`).
 */
function debugLog(env: Record<string, unknown>, msg: string, err: unknown): void {
  if (isDebug(env)) {
    // eslint-disable-next-line no-console
    console.error(msg, err);
  }
}

// ─── Public wrapper ───────────────────────────────────────────────────────────

/**
 * withCronMonitor — wraps a generic `() => Promise<R>` thunk with Sentry Crons
 * heartbeats (in_progress → ok | error) for Pages Functions cron-like work.
 *
 * Unlike the Worker variant, env is NOT ambient — Pages Functions receive env
 * via the request context, so the wrapper's returned function takes env as
 * its single argument and forwards control to the inner handler.
 *
 * Behaviour:
 *  - No-ops when `SENTRY_DSN` is unset (fail-safe per PLAN R02).
 *  - Slug resolves per D6 (explicit > env > auto-derive on handlerName).
 *  - `monitorConfig` (schedule + maxRuntime) is forwarded as Sentry's 2nd arg
 *    on the in_progress checkin only; subsequent ok/error checkins pass
 *    only the first arg (Sentry treats the monitor as already-configured).
 *  - SDK exceptions during checkin are caught and swallowed; opt-in
 *    `SENTRY_DEBUG=1` surfaces them via `console.error`.
 *  - Handler exceptions are re-thrown after the error checkin so the outer
 *    caller still observes them.
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

    // in_progress checkin — captures checkInId for the completion call.
    let checkInId: string | undefined;
    try {
      checkInId =
        monitorConfig !== undefined
          ? (captureCheckIn(
              { monitorSlug, status: "in_progress" },
              monitorConfig,
            ) as string)
          : (captureCheckIn({ monitorSlug, status: "in_progress" }) as string);
    } catch (e) {
      debugLog(env, "[withCronMonitor] in_progress checkin failed:", e);
    }

    try {
      const result = await handler();
      if (checkInId !== undefined) {
        try {
          // No monitorConfig on completion — only in_progress upserts.
          captureCheckIn({ checkInId, monitorSlug, status: "ok" });
        } catch (e) {
          debugLog(env, "[withCronMonitor] ok checkin failed:", e);
        }
      }
      return result;
    } catch (err) {
      if (checkInId !== undefined) {
        try {
          captureCheckIn({ checkInId, monitorSlug, status: "error" });
        } catch (e) {
          debugLog(env, "[withCronMonitor] error checkin failed:", e);
        }
      }
      // Re-throw original — outer caller observes the original error.
      throw err;
    }
  };
}
