//
// ╔════════════════════════════════════════════════════════════════════╗
// ║ WARNING — healthz snippet is a TEMPLATE, not a library.            ║
// ║                                                                    ║
// ║ Before mounting:                                                   ║
// ║  1. Copy this file into your edge function tree as                 ║
// ║     supabase/functions/healthz/index.ts and instantiate the        ║
// ║     supabase client in your `Deno.serve` entry, then pass it to    ║
// ║     this handler via the `deps` object.                            ║
// ║  2. ADAPT the dependency probes to YOUR project's actual deps.     ║
// ║     Unadapted probes for non-existent deps will report degraded.   ║
// ║     Zero probes configured → endpoint returns 503 (fail-closed).   ║
// ║  3. Review SECURITY: per-check breakdown leaks internal topology.  ║
// ║     For public endpoints, consider `?detail=true` opt-in (T14      ║
// ║     runbook describes the gating pattern).                         ║
// ║                                                                    ║
// ║ Do NOT import this file directly from elsewhere in your app.       ║
// ╚════════════════════════════════════════════════════════════════════╝
//
// healthz-snippet.ts — copy-only healthz handler for ts-supabase-edge.
//
// Per phase-22 CONTEXT D9 the healthz endpoint is NOT wrapped by
// withObservability (no span overhead on the heartbeat). Per PLAN R06 the
// handler is fail-closed when zero probes are configured.
//
// Adaptation pattern:
//
//   import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
//   import healthzHandler from "./healthz-snippet.ts";
//
//   Deno.serve((req) => {
//     const url = new URL(req.url);
//     if (url.pathname.endsWith("/healthz")) {
//       const supabase = createClient(
//         Deno.env.get("SUPABASE_URL") ?? "",
//         Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
//       );
//       return healthzHandler(req, { supabase });
//     }
//     return new Response("ok");
//   });
//
// The probe uses `from(table).select("*").limit(0)` — the limit-0 form
// keeps the round-trip cheap (no row payload), and the supabase-js client
// returns `{error: null}` on success / `{error: {...}}` on failure. The
// client is dependency-injected via `deps.supabase` rather than imported
// at module scope so tests can supply a stub without monkey-patching the
// npm: specifier.
//

// ─── Public types ─────────────────────────────────────────────────────────────

/** D-03 default per-probe timeout in ms.
 * D-03 (narrowed for Supabase-Edge per codex MEDIUM-5): Deno runtime + restrictive
 * test seam → env-var configuration matches Pages pattern. Worker keeps 3rd-arg path.
 * Override via Deno.env.get("HEALTHZ_PROBE_TIMEOUT_MS"). */
export const DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000;

/**
 * Supabase-js probe surface — narrowed to the chain `from(table).select(s).limit(n)`
 * which is the only path this handler exercises. Operators pass a real
 * `SupabaseClient` here; tests pass a stub with the same shape.
 *
 * The probe table is hard-coded below to "_healthz_probe" — adapt it to a
 * table you actually have. A non-existent table will produce
 * `{error: {message: "relation does not exist"}}` and the probe will
 * correctly flip to false.
 */
export interface SupabaseProbeClient {
  from(table: string): {
    select(columns: string): {
      limit(count: number): Promise<{ error: unknown }>;
    };
  };
}

export interface HealthzDeps {
  /** supabase-js client; probe = `from("_healthz_probe").select("*").limit(0)`. */
  supabase?: SupabaseProbeClient;
}

// ─── Handler ─────────────────────────────────────────────────────────────────

/**
 * Supabase Edge healthz handler. Aggregates dep probes into a single
 * JSON response.
 *
 * Returns:
 *   200 + {status:"ok", checks:{...:true}}            all probes passed
 *   503 + {status:"degraded", checks:{...}}           one+ probes failed
 *   503 + {status:"degraded", reason, checks:{}}      no probes configured (R06)
 *
 * The supabase probe treats both a returned error object AND a thrown
 * promise as "failed" — supabase-js wraps most failures in `{error: ...}`
 * but transport-level explosions throw outright.
 *
 * D-03 (narrowed for Supabase-Edge per codex MEDIUM-5): Deno runtime + restrictive
 * test seam → env-var configuration matches Pages pattern. Worker keeps 3rd-arg path.
 */
export default async function healthzHandler(
  _req: Request,
  deps: HealthzDeps,
): Promise<Response> {
  const checks: Record<string, boolean | "timeout"> = {};

  // D-03 (narrowed for Supabase-Edge per codex MEDIUM-5): env-var config via Deno.env.
  const probeTimeoutMs =
    Number(Deno.env.get("HEALTHZ_PROBE_TIMEOUT_MS")) || DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS;

  if (deps.supabase) {
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
        deps.supabase!
          .from("_healthz_probe")
          .select("*")
          .limit(0)
          .then(({ error }) => {
            if (error == null) resolve();
            else reject(new Error("supabase probe error"));
          })
          .catch(reject);
      });
      checks.supabase = true;
    } catch (e) {
      checks.supabase =
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
}
