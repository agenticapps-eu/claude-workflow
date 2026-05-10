/**
 * Pages Functions middleware — AgenticApps spec §10.4 #1.
 *
 * Cloudflare Pages auto-loads `functions/_middleware.ts` (and any
 * per-folder `_middleware.ts`) and runs it before any matching
 * `onRequest*` handler. This file is the AgenticApps observability
 * middleware in PagesFunction shape.
 *
 * Use as: this file IS the middleware mount. Pages's runtime wires it
 * automatically; no explicit `withObservability(...)` call needed in
 * route handlers.
 *
 * The wrapper module (`./_lib/observability/index.ts`) is identical to
 * the ts-cloudflare-worker template after parameter substitution.
 */

import {
  init,
  parseTraceparent,
  newRootContext,
  formatTraceparent,
  runWithContext,
  captureError,
  getActiveContext,
  type TraceContext,
} from "./_lib/observability";

// ─── Types ─────────────────────────────────────────────────────────────────

interface Env {
  {{ENV_VAR_DSN}}?: string;
  {{ENV_VAR_ENV}}?: string;
  {{ENV_VAR_SERVICE}}?: string;
}

type PagesContext = EventContext<Env, string, unknown>;

// ─── Middleware ────────────────────────────────────────────────────────────

export const onRequest: PagesFunction<Env> = async (context) => {
  init(context.env as never, context as unknown as ExecutionContext);

  const request = context.request;
  const traceCtx: TraceContext =
    parseTraceparent(request.headers.get("traceparent")) ?? newRootContext();

  const url = new URL(request.url);
  const spanName = `${request.method} ${url.pathname}`;

  return runWithContext(traceCtx, spanName, async () => {
    try {
      const response = await context.next();
      const headers = new Headers(response.headers);
      headers.set("traceparent", formatTraceparent(traceCtx));
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    } catch (err) {
      captureError(err, {
        event: "unhandled_request_error",
        severity: "error",
        attrs: { method: request.method, path: url.pathname },
      });
      throw err;
    }
  });
};

// ─── Outbound fetch interceptor ───────────────────────────────────────────
// Pages Functions run on the Workers runtime, so the same monkey-patch
// works. Apply at module-load time (top of this file is fine):

const origFetch = globalThis.fetch;
globalThis.fetch = ((input, init) => {
  const ctx = getActiveContext();
  if (!ctx) return origFetch(input, init);

  const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
  headers.set("traceparent", formatTraceparent(ctx));

  if (input instanceof Request) {
    return origFetch(new Request(input, { ...init, headers }));
  }
  return origFetch(input, { ...init, headers });
}) as typeof fetch;
