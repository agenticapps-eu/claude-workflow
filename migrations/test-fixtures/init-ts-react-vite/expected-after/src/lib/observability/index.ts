// agenticapps:observability:start
//
// Observability wrapper — materialised by `/add-observability init`.
// Source template: add-observability/templates/ts-react-vite/lib-observability.ts
// Parameters substituted:
//   SERVICE_NAME=fixture-vite
//   ENV_VAR_DSN=VITE_SENTRY_DSN
//   ENV_VAR_ENV=VITE_DEPLOY_ENV
//   ENV_VAR_SERVICE=VITE_SERVICE_NAME
//   DESTINATION=sentry
//   DEBUG_SAMPLE_RATE=0.1
//   TRACE_SAMPLE_RATE=0.1
//   REDACTED_KEYS=["password","token","api_key","card_number","cvv","ssn","credit_card"]
//
// Fixture stub — the real init produces ~12k of token-substituted template
// content (see add-observability/templates/ts-react-vite/lib-observability.ts).
// init() installs the global fetch interceptor (window.fetch =
// instrumentedFetch(originalFetch)) — this is the §10.7 obligation (2)
// satisfaction point for the browser stack.
// This file is the structural placeholder used by run-tests.sh comparisons.

export { ObservabilityErrorBoundary } from "./ErrorBoundary";

export function init(): void {
  // Real implementation: monkey-patches window.fetch with traceparent injection.
}

export function captureError(_err: unknown, _attrs?: Record<string, unknown>): void {}

export function logEvent(_name: string, _attrs?: Record<string, unknown>): void {}

export function startSpan(_name: string, _attrs?: Record<string, unknown>) {
  return { end: () => {}, setAttribute: (_k: string, _v: unknown) => {} };
}
// agenticapps:observability:end
