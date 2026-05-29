//
// ╔════════════════════════════════════════════════════════════════════╗
// ║ WARNING — healthz snippet is a TEMPLATE, not a library.            ║
// ║                                                                    ║
// ║ Before mounting:                                                   ║
// ║  1. Copy this file into your Pages Functions tree as               ║
// ║     functions/healthz.ts — the filename IS the route.              ║
// ║  2. ADAPT the dependency probes to YOUR project's actual bindings. ║
// ║     Unadapted probes for non-existent deps will report degraded.   ║
// ║     Zero probes configured → endpoint returns 503 (fail-closed).   ║
// ║  3. Review SECURITY: per-check breakdown leaks internal topology.  ║
// ║     For public endpoints, consider `?detail=true` opt-in (T14      ║
// ║     runbook describes the gating pattern).                         ║
// ║                                                                    ║
// ║ Do NOT import this file directly from elsewhere in your app.       ║
// ╚════════════════════════════════════════════════════════════════════╝
//
// healthz-snippet.ts — copy-only healthz handler for ts-cloudflare-pages.
//
// Per phase-22 CONTEXT D9 the healthz endpoint is NOT wrapped by
// withObservability (no span overhead on the heartbeat). Per PLAN R06 the
// handler is fail-closed when zero probes are configured.
//
// Pages Functions are file-system-routed: drop this file at
// `functions/healthz.ts` and the runtime will mount it at /healthz. The
// export shape is the standard Pages function (`onRequest`), NOT a bare
// handler — that's why the test invokes it with an EventContext-shaped
// object rather than `(req, env)`.
//
// Adaptation pattern (Pages bindings declared in the Pages project's
// settings or wrangler.toml):
//
//   - Add a KV namespace binding named OBSERVABILITY_KV; the probe calls
//     `get("healthz-probe")` — missing key returns null (fine); throw == fail.
//   - Add a D1 database binding named DB; the probe runs `SELECT 1`.
//     A prepare-throw or first-throw flips the check to false.
//   - Drop probes you don't have; add probes you do. The handler treats
//     every key on HealthzEnv as a probe and aggregates them.
//

// ─── PagesFunction type shim ──────────────────────────────────────────────────
// We don't depend on @cloudflare/workers-types here to keep the template
// dependency-free. The runtime supplies a richer EventContext; this minimal
// shape captures the surface our handler reads.

interface MinimalEventContext<Env> {
  request: Request;
  env: Env;
}

// Pages' canonical `PagesFunction` alias, simplified to the fields we touch.
export type PagesFunction<Env> = (ctx: MinimalEventContext<Env>) => Promise<Response>;

// ─── Public types ─────────────────────────────────────────────────────────────

/** D-03 default per-probe timeout in ms. Override via context.env.HEALTHZ_PROBE_TIMEOUT_MS. */
export const DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000;

/**
 * Bindings the healthz handler can probe. Both are optional — the operator
 * adds the bindings they actually use in their Pages project settings.
 * Any probe left unconfigured is silently skipped.
 *
 * Extend with additional bindings (R2, queues, AI, etc.) and add a probe
 * branch in `onRequest` for each.
 */
export interface HealthzEnv {
  /** D-03 (narrowed for Pages per codex MEDIUM-5): configure timeout via env var.
   * onRequest signature is runtime-fixed — operators configure timeout via env var,
   * not function args. Worker keeps the 3rd-arg path. */
  HEALTHZ_PROBE_TIMEOUT_MS?: string;
  /** KV namespace; probe = `get("healthz-probe")`. Treat any throw as fail. */
  OBSERVABILITY_KV?: { get: (key: string) => Promise<string | null> };
  /** D1 database; probe = `prepare("SELECT 1").first()`. */
  DB?: {
    prepare: (query: string) => {
      first: () => Promise<unknown>;
    };
  };
}

// ─── Handler ─────────────────────────────────────────────────────────────────

/**
 * Pages Functions healthz handler. Aggregates dep probes into a single
 * JSON response.
 *
 * Returns:
 *   200 + {status:"ok", checks:{...:true}}            all probes passed
 *   503 + {status:"degraded", checks:{...}}           one+ probes failed
 *   503 + {status:"degraded", reason, checks:{}}      no probes configured (R06)
 *
 * Per-probe exceptions are swallowed and recorded as `false` or `"timeout"`;
 * a single probe blowing up never short-circuits the others.
 *
 * D-03 (narrowed for Pages per codex MEDIUM-5): onRequest signature is
 * runtime-fixed — operators configure timeout via env var, not function args.
 * Worker keeps the 3rd-arg path.
 */
export const onRequest: PagesFunction<HealthzEnv> = async (context) => {
  const { env } = context;
  const checks: Record<string, boolean | "timeout"> = {};

  // D-03 (narrowed for Pages per codex MEDIUM-5): onRequest signature is runtime-fixed —
  // operators configure timeout via env var, not function args. Worker keeps the 3rd-arg path.
  const probeTimeoutMs =
    Number(env.HEALTHZ_PROBE_TIMEOUT_MS) || DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS;

  if (env.OBSERVABILITY_KV) {
    // Per gemini MEDIUM-1: AbortController + setTimeout + try/finally + clearTimeout.
    // NOT Promise.race + abort-rejection — prevents unhandled promise rejections.
    const controller = new AbortController();
    const timeoutId = setTimeout(
      () => controller.abort(new DOMException("probe timeout", "TimeoutError")),
      probeTimeoutMs,
    );
    try {
      await new Promise<void>((resolve, reject) => {
        controller.signal.addEventListener("abort", () =>
          reject(new DOMException("aborted", "TimeoutError")),
        );
        env.OBSERVABILITY_KV!.get("healthz-probe")
          .then(() => resolve())
          .catch(reject);
      });
      checks.kv = true;
    } catch (e) {
      checks.kv =
        e instanceof DOMException &&
        (e.name === "TimeoutError" || e.name === "AbortError")
          ? "timeout"
          : false;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  if (env.DB) {
    const controller = new AbortController();
    const timeoutId = setTimeout(
      () => controller.abort(new DOMException("probe timeout", "TimeoutError")),
      probeTimeoutMs,
    );
    try {
      // `prepare` itself can throw synchronously on some bindings; the
      // outer try covers both that and the first() rejection.
      await new Promise<void>((resolve, reject) => {
        controller.signal.addEventListener("abort", () =>
          reject(new DOMException("aborted", "TimeoutError")),
        );
        try {
          env.DB!.prepare("SELECT 1")
            .first()
            .then(() => resolve())
            .catch(reject);
        } catch (syncErr) {
          reject(syncErr);
        }
      });
      checks.db = true;
    } catch (e) {
      checks.db =
        e instanceof DOMException &&
        (e.name === "TimeoutError" || e.name === "AbortError")
          ? "timeout"
          : false;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  // R06 — fail-closed when no probes are configured.
  const probeNames = Object.keys(checks);
  if (probeNames.length === 0) {
    return new Response(
      JSON.stringify({
        status: "degraded",
        reason:
          "no probes configured — adapt healthz-snippet.ts to your dependencies",
        checks: {},
      }),
      { status: 503, headers: { "content-type": "application/json" } },
    );
  }

  const allOk = probeNames.every((k) => checks[k] === true);
  return new Response(
    JSON.stringify({ status: allOk ? "ok" : "degraded", checks }),
    {
      status: allOk ? 200 : 503,
      headers: { "content-type": "application/json" },
    },
  );
};
