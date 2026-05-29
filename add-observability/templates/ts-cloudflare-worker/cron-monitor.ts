//
// withCronMonitor — Sentry Crons heartbeat wrapper for Cloudflare Worker
// scheduled handlers. See ../../.planning/phases/22-sentry-crons-healthz/CONTEXT.md
// (D1 separate wrapper, D5a composition order, D6 3-source slug resolution,
// D11 multi-cron explicit-slug requirement, D12 monitorConfig forwarding).
//
// Composes INNERMOST per D5a:
//   withSentry(env)(withObservabilityScheduled(withCronMonitor(handler, {...})))
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

function isConfigured(env: Record<string, unknown>): boolean {
  return typeof env.SENTRY_DSN === "string" && (env.SENTRY_DSN as string).length > 0;
}

function isDebug(env: Record<string, unknown>): boolean {
  return env.SENTRY_DEBUG === "1";
}

/**
 * D6 — 3-source slug resolution (precedence: explicit > env > auto-derive).
 * Worker auto-shape: `${SERVICE_NAME ?? "service"}:${controller.cron}`.
 * D11: multi-cron workers MUST pass explicit `monitorSlug` — env-key form
 * cannot disambiguate, and the auto-derived form will produce per-cron
 * slugs that the operator may not have provisioned in Sentry.
 */
function resolveSlug<E extends Record<string, unknown>>(
  config: CronMonitorConfig | undefined,
  env: E,
  controller: ScheduledController,
): string {
  // 1. Explicit.
  if (config?.monitorSlug) return config.monitorSlug;

  // 2. Env var: SENTRY_CRON_MONITOR_SLUG_<HANDLER> (uppercased, hyphens → underscores).
  const handlerName = config?.handlerName ?? "scheduled";
  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = env[envKey];
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
 * withCronMonitor — wraps a Cloudflare Worker `scheduled` handler with Sentry
 * Crons heartbeats (in_progress → ok | error). Per D5a, this wrapper composes
 * INNERMOST so its try/catch runs first and the rethrown error still
 * propagates to the outer `withObservabilityScheduled` capture path.
 *
 * Behaviour:
 *  - No-ops when `SENTRY_DSN` is unset (fail-safe per PLAN R02).
 *  - Slug resolves per D6 (explicit > env > auto-derive).
 *  - `monitorConfig` (schedule + maxRuntime) is forwarded as Sentry's 2nd arg
 *    on the in_progress checkin only; subsequent ok/error checkins pass
 *    only the first arg (Sentry treats the monitor as already-configured).
 *  - SDK exceptions during checkin are caught and swallowed; opt-in
 *    `SENTRY_DEBUG=1` surfaces them via `console.error`.
 *  - Handler exceptions are re-thrown after the error checkin so the outer
 *    wrapper still captures them.
 */
export function withCronMonitor<E extends Record<string, unknown>>(
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
      await handler(controller, env, ctx);
      if (checkInId !== undefined) {
        try {
          // No monitorConfig on completion — only in_progress upserts.
          captureCheckIn({ checkInId, monitorSlug, status: "ok" });
        } catch (e) {
          debugLog(env, "[withCronMonitor] ok checkin failed:", e);
        }
      }
    } catch (err) {
      if (checkInId !== undefined) {
        try {
          captureCheckIn({ checkInId, monitorSlug, status: "error" });
        } catch (e) {
          debugLog(env, "[withCronMonitor] error checkin failed:", e);
        }
      }
      // Re-throw original — outer withObservabilityScheduled catches it.
      throw err;
    }
  };
}
