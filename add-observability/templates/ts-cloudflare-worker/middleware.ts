/**
 * Observability middleware — AgenticApps spec §10 v0.2.0
 *
 * Wraps a Cloudflare Workers fetch handler so that every request:
 *   1. Parses inbound `traceparent` (or generates a fresh trace context).
 *   2. Binds the trace context for the request lifetime via AsyncLocalStorage.
 *   3. Initializes Sentry once per Worker invocation.
 *   4. Captures unhandled errors via captureError before re-throwing.
 *
 * Use as: `export default withObservability(handler)`.
 *
 * For scheduled / queue / email handlers, use the corresponding
 * `withObservabilityScheduled`, etc. wrappers below.
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
} from "./index";

// ─── Fetch handler ─────────────────────────────────────────────────────────

type FetchHandler<Env = unknown> = (
  request: Request,
  env: Env,
  ctx: ExecutionContext,
) => Response | Promise<Response>;

export function withObservability<Env extends Record<string, unknown>>(
  handler: FetchHandler<Env>,
): FetchHandler<Env> {
  return async (request, env, ctx) => {
    init(env as never, ctx);

    const traceCtx: TraceContext =
      parseTraceparent(request.headers.get("traceparent")) ?? newRootContext();

    const url = new URL(request.url);
    const spanName = `${request.method} ${url.pathname}`;

    return runWithContext(traceCtx, spanName, async () => {
      try {
        const response = await handler(request, env, ctx);
        // Echo traceparent on response so downstream callers can chain.
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
}

// ─── Scheduled handler ─────────────────────────────────────────────────────

type ScheduledHandler<Env = unknown> = (
  event: ScheduledEvent,
  env: Env,
  ctx: ExecutionContext,
) => void | Promise<void>;

export function withObservabilityScheduled<Env extends Record<string, unknown>>(
  handler: ScheduledHandler<Env>,
): ScheduledHandler<Env> {
  return async (event, env, ctx) => {
    init(env as never, ctx);
    const traceCtx = newRootContext();
    const spanName = `cron ${event.cron}`;

    return runWithContext(traceCtx, spanName, async () => {
      try {
        await handler(event, env, ctx);
      } catch (err) {
        captureError(err, {
          event: "unhandled_scheduled_error",
          severity: "error",
          attrs: { cron: event.cron, scheduledTime: event.scheduledTime },
        });
        throw err;
      }
    });
  };
}

// ─── Outbound fetch interceptor ───────────────────────────────────────────

/**
 * Wrap a global `fetch` such that all outbound requests carry the
 * active `traceparent`. Apply once at Worker boot:
 *
 *     globalThis.fetch = instrumentedFetch(globalThis.fetch);
 *
 * Or use the helper directly: `tracedFetch(url, init)`.
 */
export function instrumentedFetch(originalFetch: typeof fetch): typeof fetch {
  return ((input, init) => {
    const ctx = getActiveContext();
    if (!ctx) return originalFetch(input, init);

    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    headers.set("traceparent", formatTraceparent(ctx));

    if (input instanceof Request) {
      return originalFetch(new Request(input, { ...init, headers }));
    }
    return originalFetch(input, { ...init, headers });
  }) as typeof fetch;
}

export const tracedFetch: typeof fetch = instrumentedFetch(globalThis.fetch.bind(globalThis));

// ─── Queue handler (optional — uncomment if used) ─────────────────────────

// type QueueHandler<Body = unknown, Env = unknown> = (
//   batch: MessageBatch<Body>,
//   env: Env,
//   ctx: ExecutionContext,
// ) => void | Promise<void>;
//
// export function withObservabilityQueue<Body, Env extends Record<string, unknown>>(
//   handler: QueueHandler<Body, Env>,
// ): QueueHandler<Body, Env> {
//   return async (batch, env, ctx) => {
//     init(env as never, ctx);
//     const traceCtx = newRootContext();
//     const spanName = `queue ${batch.queue}`;
//     return runWithContext(traceCtx, spanName, async () => {
//       try {
//         await handler(batch, env, ctx);
//       } catch (err) {
//         captureError(err, {
//           event: "unhandled_queue_error",
//           severity: "error",
//           attrs: { queue: batch.queue, messages: batch.messages.length },
//         });
//         throw err;
//       }
//     });
//   };
// }
