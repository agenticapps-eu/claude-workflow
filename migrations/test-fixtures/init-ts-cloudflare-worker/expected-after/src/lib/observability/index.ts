// agenticapps:observability:start
//
// Observability wrapper — materialised by `/add-observability init`.
// Source template: add-observability/templates/ts-cloudflare-worker/lib-observability.ts
// Parameters substituted:
//   SERVICE_NAME=fixture-worker
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

export { withObservability, withObservabilityScheduled } from "./middleware";
export { init, captureError, flush, type TraceContext } from "./wrapper-impl";
// agenticapps:observability:end
