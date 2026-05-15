// agenticapps:observability:start
//
// Observability middleware — materialised by `/add-observability init`.
// Source template: add-observability/templates/ts-cloudflare-worker/middleware.ts
//
// Fixture stub — the real init produces ~5k of token-substituted template
// content (see add-observability/templates/ts-cloudflare-worker/middleware.ts:35,78
// for the actual withObservability + withObservabilityScheduled exports).

export function withObservability<Env extends Record<string, unknown>>(
  handler: (request: Request, env: Env, ctx: ExecutionContext) => Response | Promise<Response>,
): (request: Request, env: Env, ctx: ExecutionContext) => Promise<Response> {
  return async (request, env, ctx) => handler(request, env, ctx);
}

export function withObservabilityScheduled<Env extends Record<string, unknown>>(
  handler: (event: ScheduledEvent, env: Env, ctx: ExecutionContext) => void | Promise<void>,
): (event: ScheduledEvent, env: Env, ctx: ExecutionContext) => Promise<void> {
  return async (event, env, ctx) => { await handler(event, env, ctx); };
}
// agenticapps:observability:end
