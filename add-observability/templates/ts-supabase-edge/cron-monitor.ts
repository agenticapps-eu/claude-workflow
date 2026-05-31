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
// Phase 23 / ADR-0029: refactored from hand-rolled captureCheckIn lifecycle to
// GUARDED Shape A — composes Sentry.withMonitor (via _withMonitorImpl seam) with
// a handlerStarted flag so a pre-callback transport failure falls back to
// unmonitored execution (cron always runs). Post-callback errors propagate to
// the outer withObservability. See D-08 + codex MEDIUM-4.
//
// Env access uses `Deno.env.get(...)` per the rest of this stack. The lookup
// is guarded so the wrapper can be loaded under a non-Deno runtime without
// throwing at import time — the underlying capability is detected at call time.
//

// Import via the stack's npm: specifier — matches destinations/sentry.ts
// (`npm:@sentry/deno@^8.0.0`) so deno test resolves the same module the
// runtime uses.
import * as Sentry from "npm:@sentry/deno@^8.0.0";
const { captureCheckIn: sentryCaptureCheckIn } = Sentry as unknown as {
  captureCheckIn: (...args: unknown[]) => unknown;
};

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

// ─── Public wrapper ───────────────────────────────────────────────────────────

/**
 * withCronMonitor — wraps a Deno-style `(req: Request) => Promise<Response>`
 * handler with Sentry Crons heartbeats via `Sentry.withMonitor` for Supabase
 * Edge functions invoked by `pg_cron`.
 *
 * Per CONTEXT D5b, compose as:
 *
 *   Deno.serve(withObservability(withCronMonitor(handler, { monitorSlug })))
 *
 * GUARDED Shape A (ADR-0029 / D-08):
 *  - No-ops when `SENTRY_DSN` is unset (fail-safe per R02).
 *  - Slug resolves per D6 (explicit > env > auto-derive on handlerName).
 *  - `monitorConfig` (schedule + maxRuntime) forwarded as Sentry's 3rd arg.
 *  - Pre-callback transport failure → falls back to unmonitored handler run
 *    (cron always executes — Guarded Shape A guarantee).
 *  - Post-callback errors (handler throw OR ok/error check-in transport) →
 *    propagate to outer withObservability (no longer swallowed).
 *  - Uses `_withMonitorImpl` seam (codex MEDIUM-4 / R-rev-6) so Deno tests
 *    can inject a fake without module-boundary mocking.
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

    // GUARDED Shape A (ADR-0029 / D-08):
    // handlerStarted distinguishes pre-callback transport failure (fall back to
    // unmonitored) from post-callback errors (propagate to outer wrapper).
    let handlerStarted = false;
    try {
      return await _withMonitorImpl(
        monitorSlug,
        () => {
          handlerStarted = true;
          return handler(req);
        },
        monitorConfig,
      ) as Response;
    } catch (err) {
      if (!handlerStarted) {
        // Sentry transport failed before handler ran — fall back to unmonitored.
        return handler(req);
      }
      // handler-thrown OR post-callback errors propagate to outer withObservability.
      throw err;
    }
  };
}
