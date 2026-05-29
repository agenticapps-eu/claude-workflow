//
// ╔════════════════════════════════════════════════════════════════════╗
// ║ WARNING — healthz snippet is a TEMPLATE, not a library.            ║
// ║                                                                    ║
// ║ Before mounting:                                                   ║
// ║  1. Copy this file into your routes layer (e.g. routes/healthz.ts) ║
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
// healthz-snippet.ts — copy-only healthz handler for ts-cloudflare-worker.
//
// Per phase-22 CONTEXT D9 the healthz endpoint is NOT wrapped by
// withObservability (no span overhead on the heartbeat). Per PLAN R06 the
// handler is fail-closed when zero probes are configured: an unadapted
// snippet reports degraded with a clear `reason` field rather than
// reporting "ok" and lulling the operator into thinking dependencies are
// being monitored.
//
// Adaptation pattern (Worker bindings declared in wrangler.toml):
//
//   - Add a KV namespace binding named OBSERVABILITY_KV; the probe calls
//     `get("healthz-probe")` — a missing key returns null, which is fine.
//     A throw (KV outage) flips the check to false.
//   - Add a service binding named SERVICE_BINDING pointing at your other
//     worker; the probe fetches `https://internal/healthz` on it. Any
//     5xx response or a fetch throw flips the check to false.
//   - Drop probes you don't have; add probes you do. The handler treats
//     every key on HealthzEnv as a probe and aggregates them.
//
// Mount in your worker entry:
//
//   import { healthzHandler } from "./routes/healthz";
//
//   export default {
//     async fetch(req: Request, env: HealthzEnv, ctx: ExecutionContext) {
//       const url = new URL(req.url);
//       if (url.pathname === "/healthz") return healthzHandler(req, env);
//       return new Response("ok");
//     },
//   };
//

// ─── Public types ─────────────────────────────────────────────────────────────

/** D-03 default per-probe timeout in ms; override via healthzHandler 3rd arg. */
export const DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000;

/**
 * Bindings the healthz handler can probe. Both are optional — the operator
 * adds the bindings they actually use in their wrangler.toml. Any probe
 * left unconfigured is silently skipped (its key never appears in `checks`).
 *
 * Extend this interface with additional bindings (D1, R2, queues, etc.)
 * and add a probe branch in `healthzHandler` for each.
 */
export interface HealthzEnv {
  /** KV namespace; probe = `get("healthz-probe")`. Treat any throw as fail. */
  OBSERVABILITY_KV?: { get: (key: string, signal?: AbortSignal) => Promise<string | null> };
  /** Service binding to another worker; probe = fetch on its /healthz. */
  SERVICE_BINDING?: { fetch: (req: Request) => Promise<Response> };
}

// ─── Handler ─────────────────────────────────────────────────────────────────

/**
 * Cloudflare Worker healthz handler. Aggregates dep probes into a single
 * JSON response.
 *
 * Returns:
 *   200 + {status:"ok", checks:{...:true}}            all probes passed
 *   503 + {status:"degraded", checks:{...}}           one+ probes failed
 *   503 + {status:"degraded", reason, checks:{}}      no probes configured (R06)
 *
 * The handler swallows any per-probe exception and records the probe as
 * `false` or `"timeout"`; an exception in one probe never short-circuits
 * the others.
 *
 * D-03 (Worker keeps 3rd-arg override per codex MEDIUM-5): Worker's
 * scheduled/fetch handler signature supports a 3rd opts arg. Pass
 * `{ probeTimeoutMs: N }` to override the default 2000ms timeout.
 */
export async function healthzHandler(
  _req: Request,
  env: HealthzEnv,
  opts?: { probeTimeoutMs?: number },
): Promise<Response> {
  const checks: Record<string, boolean | "timeout"> = {};
  const probeTimeoutMs = opts?.probeTimeoutMs ?? DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS;

  if (env.OBSERVABILITY_KV) {
    // Per gemini MEDIUM-1: AbortController + setTimeout + try/finally pattern.
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
        env.OBSERVABILITY_KV!.get("healthz-probe", controller.signal)
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

  if (env.SERVICE_BINDING) {
    // Service binding fetch accepts signal directly via Request options.
    const controller = new AbortController();
    const timeoutId = setTimeout(
      () => controller.abort(new DOMException("probe timeout", "TimeoutError")),
      probeTimeoutMs,
    );
    try {
      const res = await env.SERVICE_BINDING.fetch(
        new Request("https://internal/healthz", { signal: controller.signal }),
      );
      checks.serviceBinding = res.status < 500;
    } catch (e) {
      checks.serviceBinding =
        e instanceof DOMException &&
        (e.name === "TimeoutError" || e.name === "AbortError")
          ? "timeout"
          : false;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  // R06 — fail-closed when no probes are configured. An unadapted snippet
  // would otherwise return 200/ok and silently mask a missing monitoring
  // surface; instead it returns 503 with a clear reason pointing at the
  // adaptation step.
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
}
