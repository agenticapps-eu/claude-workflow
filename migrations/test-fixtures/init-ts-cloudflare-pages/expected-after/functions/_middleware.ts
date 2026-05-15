// agenticapps:observability:start
//
// Pages Functions middleware — materialised by `/add-observability init`.
// Source template: add-observability/templates/ts-cloudflare-pages/_middleware.ts
// Parameters substituted:
//   SERVICE_NAME=fixture-pages
//   ENV_VAR_DSN=SENTRY_DSN
//   ENV_VAR_ENV=DEPLOY_ENV
//   ENV_VAR_SERVICE=SERVICE_NAME
//   DESTINATION=sentry
//   DEBUG_SAMPLE_RATE=0.1
//   TRACE_SAMPLE_RATE=0.1
//   REDACTED_KEYS=["password","token","api_key","card_number","cvv","ssn"]
//
// Cloudflare Pages auto-loads functions/_middleware.ts before any matching
// onRequest* handler. This file IS the mount point — no per-route wrap
// needed in route handlers.
//
// Fixture stub — the real init produces ~3k of token-substituted template
// content (see add-observability/templates/ts-cloudflare-pages/_middleware.ts).
// This file is the structural placeholder used by run-tests.sh comparisons.

import {
  init,
  parseTraceparent,
  newRootContext,
  formatTraceparent,
  runWithContext,
  captureError,
} from "./_lib/observability";

interface Env {
  SENTRY_DSN?: string;
  DEPLOY_ENV?: string;
  SERVICE_NAME?: string;
}

export const onRequest: PagesFunction<Env> = async (context) => {
  init(context.env as never, context as unknown as ExecutionContext);

  const request = context.request;
  const traceCtx = parseTraceparent(request.headers.get("traceparent")) ?? newRootContext();
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
// agenticapps:observability:end
