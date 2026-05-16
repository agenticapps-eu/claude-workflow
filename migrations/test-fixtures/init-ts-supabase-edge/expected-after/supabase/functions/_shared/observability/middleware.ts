// agenticapps:observability:start
//
// Observability middleware — materialised by `/add-observability init`.
// Source template: add-observability/templates/ts-supabase-edge/middleware.ts
//
// Exports `withObservability(handler)` — wraps a Deno.serve handler to
// initialise observability, propagate traceparent, capture errors, and
// flush emissions before returning.
//
// Fixture stub — the real init produces ~3k of token-substituted template
// content (see add-observability/templates/ts-supabase-edge/middleware.ts).
// This file is the structural placeholder used by run-tests.sh comparisons.

import {
  init,
  flush,
  parseTraceparent,
  newRootContext,
  formatTraceparent,
  runWithContext,
  captureError,
  type TraceContext,
} from "./index.ts";

type Handler = (req: Request) => Response | Promise<Response>;

export function withObservability(handler: Handler): Handler {
  return async (req: Request) => {
    init();
    const traceCtx: TraceContext =
      parseTraceparent(req.headers.get("traceparent")) ?? newRootContext();
    const url = new URL(req.url);
    const spanName = `${req.method} ${url.pathname}`;
    return runWithContext(traceCtx, spanName, async () => {
      try {
        const response = await handler(req);
        await flush(2000);
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
          attrs: { method: req.method, path: url.pathname },
        });
        await flush(1000);
        throw err;
      }
    });
  };
}
// agenticapps:observability:end
