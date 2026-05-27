/**
 * Axiom destination adapter — AgenticApps spec §10.8.
 *
 * Phase 21 (P2.2). A LOGS/ANALYTICS sink (NO `errors` role — see
 * ADAPTER_SUPPORTED_ROLES in registry.ts, which is why resolveConfig rejects
 * `errors=axiom`). `emit(envelope)` POSTs a single-element batch to the Axiom
 * ingest endpoint; `captureException` is a no-op by contract.
 *
 * Egress safety (review #2, never-throw + fire-and-forget):
 *   - The POST is wrapped so it CANNOT throw into app code. On rejection OR a
 *     non-2xx response it emits at most ONE rate-limited `console.warn` per
 *     cooldown window ("axiom: log delivery failing").
 *   - When a `ctx.waitUntil` binding is available the promise is handed to it
 *     so the platform keeps the Worker alive until egress settles; otherwise
 *     the promise is detached with `void p.catch(warnOnce)` so a rejection can
 *     never surface as an unhandled rejection.
 *
 * Fetch injection (test seam, documented for P2 replication): the egress fetch
 * is resolved once at `init` time from `env.__fetch ?? globalThis.fetch`. The
 * env is already the adapter's only configuration source, so tests inject a
 * fake by setting `__fetch` on the InitEnv — no global patching, no
 * module-level mutable seam.
 */

import type { Envelope } from "../index";
import type { Destination, ExecutionContext, Role } from "./registry";

const AXIOM_ROLES: ReadonlyArray<Role> = ["logs", "analytics"];

const WARN_COOLDOWN_MS = 60_000;

type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export function createAxiomAdapter(): Destination {
  let token = "";
  let ingestUrl = "";
  let fetchImpl: FetchLike | null = null;
  let waitUntilFn: ((p: Promise<unknown>) => void) | null = null;

  // Rate-limited delivery-failure warning. Collapses a burst of failures into
  // a single warn per cooldown window, reporting how many were suppressed.
  let lastWarnAt = 0;
  let suppressed = 0;
  const warnOnce = (): void => {
    const now = Date.now();
    if (now - lastWarnAt >= WARN_COOLDOWN_MS) {
      const extra = suppressed > 0 ? ` (${suppressed} suppressed)` : "";
      console.warn(`axiom: log delivery failing${extra}`);
      lastWarnAt = now;
      suppressed = 0;
    } else {
      suppressed += 1;
    }
  };

  return {
    name: "axiom",
    supportedRoles: AXIOM_ROLES,

    isConfigured(env): boolean {
      const e = env as Record<string, unknown>;
      return Boolean(e.AXIOM_TOKEN) && Boolean(e.AXIOM_DATASET);
    },

    init(env, ctx?: ExecutionContext): void {
      const e = env as Record<string, unknown>;
      token = typeof e.AXIOM_TOKEN === "string" ? e.AXIOM_TOKEN : "";
      const dataset = typeof e.AXIOM_DATASET === "string" ? e.AXIOM_DATASET : "";
      ingestUrl =
        typeof e.AXIOM_INGEST_URL === "string" && e.AXIOM_INGEST_URL !== ""
          ? e.AXIOM_INGEST_URL
          : `https://api.axiom.co/v1/datasets/${dataset}/ingest`;

      // Resolve egress fetch once: injected fake (tests) → global fetch.
      const injected = e.__fetch;
      fetchImpl =
        typeof injected === "function"
          ? (injected as FetchLike)
          : typeof globalThis.fetch === "function"
            ? (globalThis.fetch.bind(globalThis) as FetchLike)
            : null;

      try {
        waitUntilFn = ctx ? (p) => ctx.waitUntil(p) : null;
      } catch {
        waitUntilFn = null;
      }
    },

    emit(envelope: Envelope): void {
      if (!fetchImpl || token === "" || ingestUrl === "") return;
      const doFetch = fetchImpl;

      // Build the never-throwing egress promise. A rejection OR a non-2xx
      // response both route to warnOnce; nothing escapes.
      const p: Promise<void> = (async () => {
        try {
          const res = await doFetch(ingestUrl, {
            method: "POST",
            headers: {
              authorization: `Bearer ${token}`,
              "content-type": "application/json",
            },
            body: JSON.stringify([envelope]),
          });
          if (!res || res.status < 200 || res.status >= 300) warnOnce();
        } catch {
          warnOnce();
        }
      })();

      // Fire-and-forget: prefer waitUntil so the platform awaits egress; else
      // detach. `p` already never rejects, but the extra .catch is belt-and-
      // braces against an unexpected throw inside warnOnce.
      if (waitUntilFn) {
        try {
          waitUntilFn(p);
        } catch {
          void p.catch(() => {});
        }
      } else {
        void p.catch(() => {});
      }
    },

    captureException(_err: unknown, _envelope: Envelope): void {
      /* Axiom never captures errors — no-op by contract (no errors role). */
    },
  };
}
