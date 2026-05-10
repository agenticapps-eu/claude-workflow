/**
 * Observability middleware — AgenticApps spec §10.4 #1 for Supabase Edge.
 *
 * Each Edge Function wraps its handler with `withObservability(handler)`:
 *
 *   import { withObservability } from "../_shared/observability/middleware.ts"
 *
 *   Deno.serve(withObservability(async (req) => {
 *     // your handler logic
 *     return new Response("ok")
 *   }))
 *
 * The middleware:
 *   1. Calls init() (idempotent)
 *   2. Parses inbound traceparent or generates a fresh trace context
 *   3. Binds the trace context for the request lifetime via AsyncLocalStorage
 *   4. Captures unhandled errors via captureError before re-raising
 *   5. Echoes traceparent on the response
 *   6. Calls flush() before returning so Sentry events are sent before
 *      the isolate is potentially torn down
 */

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
      let response: Response;
      try {
        response = await handler(req);
      } catch (err) {
        captureError(err, {
          event: "unhandled_request_error",
          severity: "error",
          attrs: { method: req.method, path: url.pathname },
        });
        // Flush before re-raising so Sentry receives the exception.
        await flush(1000);
        throw err;
      }

      // Flush before returning. Cap at 2s to avoid blocking the response.
      await flush(2000);

      // Echo traceparent on response.
      const headers = new Headers(response.headers);
      headers.set("traceparent", formatTraceparent(traceCtx));
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    });
  };
}
