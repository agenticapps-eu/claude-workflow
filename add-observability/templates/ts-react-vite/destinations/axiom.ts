/**
 * Axiom destination adapter — AgenticApps spec §10.8 (ts-react-vite / browser).
 *
 * Phase 21 (P2.2). A LOGS/ANALYTICS sink (NO `errors` role — see
 * ADAPTER_SUPPORTED_ROLES in registry.ts, which is why resolveConfig rejects
 * `errors=axiom`). `emit(envelope)` POSTs a single-element batch; captureException
 * is a no-op by contract.
 *
 * ── BROWSER HARD RULE (review #8 — token exfil + CORS) ───────────────────────
 * The browser MUST NOT ship an Axiom ingest-write token. This adapter:
 *   - is `isConfigured()` true ONLY when `VITE_AXIOM_PROXY_URL` is set (mapped
 *     by the wrapper to `env.AXIOM_PROXY_URL`);
 *   - POSTs to that SAME-ORIGIN proxy URL with NO Authorization header — the
 *     proxy injects the ingest token server-side;
 *   - NEVER reads `VITE_AXIOM_TOKEN` / `VITE_AXIOM_DATASET` (those would leak a
 *     write token to client code).
 * If no proxy URL is configured, `isConfigured()` is false → the registry maps
 * forRole("logs") to null → `logEvent` is console-only (unchanged behaviour).
 *
 * ── Egress safety (never-throw + fire-and-forget) ────────────────────────────
 *   - Delivery is wrapped so it CANNOT throw into app code. A failed beacon /
 *     fetch rejection / non-2xx response emits at most ONE rate-limited
 *     `console.warn` per cooldown window ("axiom: log delivery failing").
 *   - Prefer `navigator.sendBeacon(url, body)` (survives page unload, the
 *     primary browser fire-and-forget primitive); fall back to a detached
 *     `fetch` with `keepalive` when sendBeacon is unavailable or returns false.
 *
 * Fetch injection (test seam): the fallback fetch is resolved once at `init`
 * from `env.__fetch ?? globalThis.fetch`. sendBeacon is read from
 * `navigator.sendBeacon` at emit time (jsdom tests stub it on navigator).
 */

import type { Envelope } from "../index";
import type { Destination, ExecutionContext, Role } from "./registry";

const AXIOM_ROLES: ReadonlyArray<Role> = ["logs", "analytics"];

const WARN_COOLDOWN_MS = 60_000;

type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export function createAxiomAdapter(): Destination {
  let proxyUrl = "";
  let fetchImpl: FetchLike | null = null;

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
      // Browser HARD RULE: configured ONLY via a same-origin proxy URL. NO
      // token. Without a proxy the adapter stays console-only (forRole→null).
      const e = env as Record<string, unknown>;
      return typeof e.AXIOM_PROXY_URL === "string" && e.AXIOM_PROXY_URL !== "";
    },

    init(env, _ctx?: ExecutionContext): void {
      const e = env as Record<string, unknown>;
      proxyUrl = typeof e.AXIOM_PROXY_URL === "string" ? e.AXIOM_PROXY_URL : "";

      const injected = e.__fetch;
      fetchImpl =
        typeof injected === "function"
          ? (injected as FetchLike)
          : typeof globalThis.fetch === "function"
            ? (globalThis.fetch.bind(globalThis) as FetchLike)
            : null;
    },

    emit(envelope: Envelope): void {
      if (proxyUrl === "") return;
      const body = JSON.stringify([envelope]);

      // Prefer sendBeacon — survives unload, the canonical browser
      // fire-and-forget primitive. NO Authorization header either way: the
      // same-origin proxy injects the ingest token server-side.
      try {
        const nav = typeof navigator !== "undefined" ? navigator : undefined;
        if (nav && typeof nav.sendBeacon === "function") {
          const blob = new Blob([body], { type: "application/json" });
          const ok = nav.sendBeacon(proxyUrl, blob);
          if (ok) return;
          // sendBeacon returned false (queue full) → fall through to fetch.
        }
      } catch {
        /* fall through to fetch */
      }

      if (!fetchImpl) {
        warnOnce();
        return;
      }
      const doFetch = fetchImpl;
      const p: Promise<void> = (async () => {
        try {
          const res = await doFetch(proxyUrl, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body,
            keepalive: true,
          });
          if (!res || res.status < 200 || res.status >= 300) warnOnce();
        } catch {
          warnOnce();
        }
      })();
      void p.catch(() => {});
    },

    captureException(_err: unknown, _envelope: Envelope): void {
      /* Axiom never captures errors — no-op by contract (no errors role). */
    },
  };
}
