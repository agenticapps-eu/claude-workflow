// SPDX-License-Identifier: MIT
//
// check-credit.ts — openrouter-monitor handler.
//
// Polls https://openrouter.ai/api/v1/key on the schedule defined in
// wrangler.toml ([triggers] crons = ["*/15 * * * *"]). Emits:
//
//   ALWAYS                        logEvent("openrouter.credit_pulse", info)
//   >= WARNING_RATIO && < CRIT    logEvent("openrouter.credit_low",   warn)
//   >= CRITICAL_RATIO             captureError(OpenRouterBudgetCriticalError)
//   non-2xx response               captureError(OpenRouterHealthcheckFailedError, http)
//   fetch rejected (network)      captureError(OpenRouterHealthcheckFailedError, network)
//   res.json() rejected (parse)   captureError(OpenRouterHealthcheckFailedError, parse)
//   inverted thresholds (misconfig)
//                                  logEvent("openrouter.misconfigured_thresholds", warn) + fallback
//
// §10.6 destination-independence: ZERO direct Sentry SDK calls. All
// emissions go through logEvent/captureError from ./observability (the
// bundled wrapper). The composition chain (withSentry → withObservability-
// Scheduled → withCronMonitor) is wired in index.ts.
//
// Architecture: ADR-0030 (SDK-first OpenRouter integration).
// Runbook:      add-observability/openrouter-integration.md
// Heartbeat:    withCronMonitor (ADR-0029 Guarded Shape A).

import { logEvent, captureError } from "./observability";

/**
 * Fires when OpenRouter spend reaches >= OPENROUTER_CRITICAL_RATIO of the
 * org's budget cap. Sentry should alert on this issue type.
 */
export class OpenRouterBudgetCriticalError extends Error {
  constructor(public readonly used_ratio: number) {
    super(`OpenRouter budget critical: ${(used_ratio * 100).toFixed(1)}% used`);
    this.name = "OpenRouterBudgetCriticalError";
  }
}

/**
 * Fires when the healthcheck against /api/v1/key fails — either by HTTP
 * status (`http`), network rejection (`network`), or body parse failure
 * (`parse`). Sentry should alert if these fire repeatedly.
 *
 * Conventions for `status` per `cause_kind`:
 *   - "http"     → the actual HTTP status (e.g. 401, 429, 500).
 *   - "network"  → 0 (no response received).
 *   - "parse"    → -1 (response received but unparseable).
 */
export class OpenRouterHealthcheckFailedError extends Error {
  constructor(
    public readonly status: number,
    public readonly cause_kind: "http" | "network" | "parse" = "http",
  ) {
    const kindLabel =
      cause_kind === "network"
        ? "network failure"
        : cause_kind === "parse"
          ? "malformed response body"
          : `HTTP ${status}`;
    super(`OpenRouter /api/v1/key healthcheck failed: ${kindLabel}`);
    this.name = "OpenRouterHealthcheckFailedError";
  }
}

// Env extends Record<string, unknown> so it satisfies the constraint on
// ScheduledFn<E> in cron-monitor.ts (`E extends Record<string, unknown>`) —
// without this, index.ts has to cast `checkCredit as never` to wire the
// composition chain. Stage 2 M-1+M-3 fix: type the handler signature
// properly so the cast disappears.
interface Env extends Record<string, unknown> {
  OPENROUTER_API_KEY: string;
  OPENROUTER_WARNING_RATIO?: string;
  OPENROUTER_CRITICAL_RATIO?: string;
}

const DEFAULT_WARNING_RATIO = 0.85;
const DEFAULT_CRITICAL_RATIO = 0.95;

/**
 * Parse a string env-var as a (0, 1] ratio. Falls back to `fallback` when:
 *   - undefined / empty
 *   - not a finite number (e.g. "not-a-number")
 *   - has trailing garbage (e.g. "0.85 # comment" — Number() rejects, parseFloat
 *     would silently accept the leading 0.85)
 *   - zero or negative (zero would spam credit_low on every pulse since
 *     `used_ratio >= 0` is always true for any non-negative spend)
 *   - > 1 (ratios above 1 are nonsensical for a usage/limit fraction)
 */
function parseRatio(raw: string | undefined, fallback: number): number {
  if (raw === undefined || raw === "") return fallback;
  // Number() rejects trailing garbage that parseFloat would silently truncate.
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 && n <= 1 ? n : fallback;
}

export async function checkCredit(
  _controller: ScheduledController,
  env: Env,
  _ctx: ExecutionContext,
): Promise<void> {
  let warningRatio = parseRatio(env.OPENROUTER_WARNING_RATIO, DEFAULT_WARNING_RATIO);
  let criticalRatio = parseRatio(env.OPENROUTER_CRITICAL_RATIO, DEFAULT_CRITICAL_RATIO);

  // Misconfig: inverted thresholds → log + fall back to defaults so
  // operators get a signal that their env vars are wrong without losing
  // the credit-check itself.
  if (warningRatio >= criticalRatio) {
    logEvent({
      event: "openrouter.misconfigured_thresholds",
      severity: "warn",
      attrs: {
        warningRatio,
        criticalRatio,
        fallback_warning: DEFAULT_WARNING_RATIO,
        fallback_critical: DEFAULT_CRITICAL_RATIO,
      },
    });
    warningRatio = DEFAULT_WARNING_RATIO;
    criticalRatio = DEFAULT_CRITICAL_RATIO;
  }

  // ─── Fetch /api/v1/key ──────────────────────────────────────────────────
  // Separate try/catch for network errors (fetch reject = no response).
  // 10s timeout: Cloudflare Workers' scheduled handler wall-clock is 30s, so
  // a stalled connection would already get killed — but an explicit timeout
  // surfaces the failure cleanly through the existing network-error path
  // (OpenRouterHealthcheckFailedError(0, "network")) instead of an opaque kill.
  let res: Response;
  try {
    res = await fetch("https://openrouter.ai/api/v1/key", {
      headers: { Authorization: `Bearer ${env.OPENROUTER_API_KEY}` },
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    captureError(new OpenRouterHealthcheckFailedError(0, "network"), {
      event: "openrouter.healthcheck_failed",
      severity: "error",
      attrs: {
        status: 0,
        cause: "network",
        message: err instanceof Error ? err.message : String(err),
      },
    });
    return;
  }

  if (!res.ok) {
    // Covers 401 / 429 / 500 / any non-2xx (D-15 fixtures 5/6/7).
    captureError(new OpenRouterHealthcheckFailedError(res.status, "http"), {
      event: "openrouter.healthcheck_failed",
      severity: "error",
      attrs: { status: res.status, cause: "http" },
    });
    return;
  }

  // ─── Parse body ─────────────────────────────────────────────────────────
  // Separate try/catch for malformed body (res.json() throws on bad JSON).
  let body: { data?: { usage?: number; limit?: number | null } };
  try {
    body = (await res.json()) as { data?: { usage?: number; limit?: number | null } };
  } catch (err) {
    captureError(new OpenRouterHealthcheckFailedError(-1, "parse"), {
      event: "openrouter.healthcheck_failed",
      severity: "error",
      attrs: {
        status: -1,
        cause: "parse",
        message: err instanceof Error ? err.message : String(err),
      },
    });
    return;
  }

  // Contract check: OpenRouter's documented /api/v1/key shape ALWAYS includes
  // `data`. A 200 with body `{}` / `{"error":"..."}` / `{"data":null}` means
  // the contract is broken (key revoked mid-flight, deprecated endpoint,
  // partial outage with maintenance JSON). Without this guard, body.data?.x
  // optional-chains would silently produce used=0/limit=0/ratio=0 — a
  // false-healthy pulse. Surface as a parse-class failure so operators get
  // a real alert instead of a clean Axiom signal.
  if (!body.data || typeof body.data !== "object") {
    captureError(new OpenRouterHealthcheckFailedError(-1, "parse"), {
      event: "openrouter.healthcheck_failed",
      severity: "error",
      attrs: {
        status: -1,
        cause: "parse",
        message: "200 OK but body.data missing or non-object — OpenRouter contract broken",
      },
    });
    return;
  }

  const used = body.data.usage ?? 0;
  // OpenRouter returns `limit: null` for unlimited keys. Treat as ratio 0
  // (pulse only — no warn/critical for unbounded budgets).
  const limit = body.data.limit ?? 0;
  const used_ratio = limit > 0 ? used / limit : 0;

  // Always emit pulse for the Axiom time-series.
  logEvent({
    event: "openrouter.credit_pulse",
    severity: "info",
    attrs: { used, limit, used_ratio },
  });

  if (used_ratio >= criticalRatio) {
    captureError(new OpenRouterBudgetCriticalError(used_ratio), {
      event: "openrouter.credit_critical",
      severity: "error",
      attrs: { used, limit, used_ratio, threshold: criticalRatio },
    });
  } else if (used_ratio >= warningRatio) {
    // Severity literal MUST be "warn" not "warning" (matches Severity union
    // in ./observability — codex HIGH-4 fix).
    logEvent({
      event: "openrouter.credit_low",
      severity: "warn",
      attrs: { used, limit, used_ratio, threshold: warningRatio },
    });
  }
}
