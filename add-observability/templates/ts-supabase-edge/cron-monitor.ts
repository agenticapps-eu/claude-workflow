//
// withCronMonitor (Supabase Edge variant) — Sentry Crons heartbeat wrapper for
// a Deno-style HTTP handler (Request → Response) called by `pg_cron`.
//
// Per CONTEXT D5b, the Supabase Edge stack composes as:
//
//   Deno.serve(withObservability(withCronMonitor(handler, { monitorSlug })))
//
// There is NO `withObservabilityScheduled` (Supabase Edge functions are HTTP
// handlers, not scheduled handlers) and NO `withSentry` SDK wrap (Sentry init
// happens inline in the existing wrapper's `init()`); the layering is 2-deep,
// not 3-deep like the Worker stack.
//
// Sentry SDK interaction is wrapped in try/swallow + opt-in debug log so an
// SDK throw during captureCheckIn doesn't break the cron — the heartbeat is
// not in the critical path. See PLAN R02/R03/R04.
//
// Env access uses `Deno.env.get(...)` per the rest of this stack. The lookup
// is guarded so the wrapper can be loaded under a non-Deno runtime (e.g.
// vitest, if a downstream project ever wants to unit-test it in Node) without
// throwing at import time — the underlying capability is detected at call
// time.
//

// Import via the stack's npm: specifier — matches destinations/sentry.ts
// (`npm:@sentry/deno@^8.0.0`) so deno test resolves the same module the
// runtime uses.
import * as Sentry from "npm:@sentry/deno@^8.0.0";
const { captureCheckIn: sentryCaptureCheckIn } = Sentry as unknown as {
  captureCheckIn: (...args: unknown[]) => unknown;
};

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

// ─── Test seam ────────────────────────────────────────────────────────────────

/**
 * Module-level seam for the Sentry boundary call. Defaults to the real SDK;
 * tests substitute via `_setCaptureCheckInForTest`. Mirrors the existing
 * `_resetForTest` pattern in this stack's `index.ts` — avoids monkey-patching
 * the `npm:@sentry/deno` module under `deno test`, which has no vi.mock
 * equivalent.
 *
 * NOTE: tests using this seam MUST NOT run with `--parallel` because the
 * seam is module-level. The default `deno test` execution is serial.
 */
type CaptureCheckInFn = (
  checkin: { monitorSlug?: string; status?: string; checkInId?: string },
  monitorConfig?: { schedule?: CronMonitorSchedule; maxRuntime?: number },
) => unknown;

let captureCheckInFn: CaptureCheckInFn = sentryCaptureCheckIn as unknown as CaptureCheckInFn;

/** @internal — test-only export. Pass `null` to restore the real SDK call. */
export function _setCaptureCheckInForTest(fn: CaptureCheckInFn | null): void {
  captureCheckInFn = fn === null
    ? (sentryCaptureCheckIn as unknown as CaptureCheckInFn)
    : fn;
}

// Deno-friendly test seam (codex MEDIUM-4 / R-rev-6): the existing Supabase
// suite avoids module-boundary mocking under `deno test`. This seam lets tests
// inject a fake `withMonitor` without breaking that pattern. Production code
// uses `Sentry.withMonitor` via the default reference below.
// deno-lint-ignore no-explicit-any
type WithMonitorFn = (slug: string, cb: () => any, monitorConfig?: unknown) => Promise<unknown>;
// deno-lint-ignore no-explicit-any
let _withMonitorImpl: WithMonitorFn = (Sentry as any).withMonitor as WithMonitorFn;

/** @internal — test-only export. Sets the `withMonitor` implementation used
 *  inside `withCronMonitor`. Restores to `Sentry.withMonitor` by default. */
// deno-lint-ignore no-explicit-any
export function _setWithMonitorForTest(impl: WithMonitorFn): void {
  _withMonitorImpl = impl;
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

const SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";

/** Guarded Deno.env.get — returns undefined under non-Deno runtimes. */
function denoEnv(key: string): string | undefined {
  try {
    // deno-lint-ignore no-explicit-any
    const env = (globalThis as any).Deno?.env;
    if (env && typeof env.get === "function") {
      const v = env.get(key);
      return typeof v === "string" ? v : undefined;
    }
    return undefined;
  } catch {
    return undefined;
  }
}

function isConfigured(): boolean {
  const dsn = denoEnv("SENTRY_DSN");
  return typeof dsn === "string" && dsn.length > 0;
}

function isDebug(): boolean {
  return denoEnv("SENTRY_DEBUG") === "1";
}

/**
 * D6 — 3-source slug resolution (precedence: explicit > env > auto-derive).
 * Supabase-edge auto-shape: `${SERVICE_NAME ?? "service"}:${handlerName ?? "scheduled"}`
 * (per D6 row 2 + G4 — Edge functions have no runtime cron expression).
 */
function resolveSlug(config: CronMonitorConfig | undefined): string {
  // 1. Explicit.
  if (config?.monitorSlug) return config.monitorSlug;

  // 2. Env var: SENTRY_CRON_MONITOR_SLUG_<HANDLER> (uppercased, hyphens → underscores).
  const handlerName = config?.handlerName ?? "scheduled";
  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = denoEnv(envKey);
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;

  // 3. Auto-derive — supabase-edge uses handlerName since there is no runtime cron expr.
  const serviceName = denoEnv("SERVICE_NAME") ?? "service";
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
 * `args.some((a) => a instanceof Error)`).
 */
function debugLog(msg: string, err: unknown): void {
  if (isDebug()) {
    // eslint-disable-next-line no-console
    console.error(msg, err);
  }
}

// ─── Public wrapper ───────────────────────────────────────────────────────────

/**
 * withCronMonitor — wraps a Deno-style `(req: Request) => Promise<Response>`
 * handler with Sentry Crons heartbeats (in_progress → ok | error) for
 * Supabase Edge functions invoked by `pg_cron`.
 *
 * Per CONTEXT D5b, compose as:
 *
 *   Deno.serve(withObservability(withCronMonitor(handler, { monitorSlug })))
 *
 * `withCronMonitor` is INNERMOST so its try/catch runs first and the rethrown
 * error still propagates to the outer `withObservability` capture path.
 *
 * Behaviour:
 *  - No-ops when `SENTRY_DSN` is unset (fail-safe per PLAN R02).
 *  - Slug resolves per D6 (explicit > env > auto-derive on handlerName).
 *  - `monitorConfig` (schedule + maxRuntime) is forwarded as Sentry's 2nd arg
 *    on the in_progress checkin only; subsequent ok/error checkins pass only
 *    the first arg (Sentry treats the monitor as already-configured).
 *  - SDK exceptions during checkin are caught and swallowed; opt-in
 *    `SENTRY_DEBUG=1` surfaces them via `console.error`.
 *  - Handler exceptions are re-thrown after the error checkin so the outer
 *    `withObservability` still captures them.
 */
export function withCronMonitor(
  handler: (req: Request) => Promise<Response>,
  config?: CronMonitorConfig,
): (req: Request) => Promise<Response> {
  return async (req) => {
    if (!isConfigured()) {
      // Fail-safe: no DSN → no checkins, handler runs unchanged.
      return handler(req);
    }

    const monitorSlug = resolveSlug(config);
    const monitorConfig = buildMonitorConfig(config);

    // in_progress checkin — captures checkInId for the completion call.
    let checkInId: string | undefined;
    try {
      const ret = monitorConfig !== undefined
        ? captureCheckInFn({ monitorSlug, status: "in_progress" }, monitorConfig)
        : captureCheckInFn({ monitorSlug, status: "in_progress" });
      checkInId = ret as unknown as string;
    } catch (e) {
      debugLog("[withCronMonitor] in_progress checkin failed:", e);
    }

    try {
      const res = await handler(req);
      if (checkInId !== undefined) {
        try {
          // No monitorConfig on completion — only in_progress upserts.
          captureCheckInFn({ checkInId, monitorSlug, status: "ok" });
        } catch (e) {
          debugLog("[withCronMonitor] ok checkin failed:", e);
        }
      }
      return res;
    } catch (err) {
      if (checkInId !== undefined) {
        try {
          captureCheckInFn({ checkInId, monitorSlug, status: "error" });
        } catch (e) {
          debugLog("[withCronMonitor] error checkin failed:", e);
        }
      }
      // Re-throw original — outer withObservability captures it.
      throw err;
    }
  };
}
