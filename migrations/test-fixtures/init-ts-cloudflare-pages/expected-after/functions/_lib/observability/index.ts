// agenticapps:observability:start
//
// Observability wrapper — materialised by `/add-observability init`.
// Source template: add-observability/templates/ts-cloudflare-worker/lib-observability.ts
// (ts-cloudflare-pages inherits the wrapper from ts-cloudflare-worker per
// templates/ts-cloudflare-pages/meta.yaml `inherits_wrapper_from`.)
// Parameters substituted:
//   SERVICE_NAME=fixture-pages
//   ENV_VAR_DSN=SENTRY_DSN
//   ENV_VAR_ENV=DEPLOY_ENV
//   ENV_VAR_SERVICE=SERVICE_NAME
//   DESTINATION=sentry
//   DEBUG_SAMPLE_RATE=0.1
//   TRACE_SAMPLE_RATE=0.1
//   REDACTED_KEYS=["password","token","api_key","card_number","cvv","ssn","secret","client_secret","refresh_token","access_token"]
//
// Fixture stub — the real init produces ~12k of token-substituted template
// content (see add-observability/templates/ts-cloudflare-worker/lib-observability.ts).
// This file is the structural placeholder used by run-tests.sh comparisons.

export function init(_env: never, _ctx: ExecutionContext): void {}
export function parseTraceparent(_h: string | null): TraceContext | null { return null; }
export function newRootContext(): TraceContext { return {} as TraceContext; }
export function formatTraceparent(_c: TraceContext): string { return ""; }
export function runWithContext<T>(_c: TraceContext, _n: string, fn: () => Promise<T>): Promise<T> { return fn(); }
export function captureError(_err: unknown, _env: Envelope): void {}
export function getActiveContext(): TraceContext | null { return null; }
export type TraceContext = { traceId?: string; spanId?: string };
export type Envelope = { event: string; severity: string; attrs?: Record<string, unknown> };
// agenticapps:observability:end
