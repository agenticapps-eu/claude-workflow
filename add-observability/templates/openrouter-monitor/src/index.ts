// SPDX-License-Identifier: MIT
//
// openrouter-monitor — entry point.
//
// Composition chain (REQUIRED — codex HIGH-3 fix; see ADR-0030):
//
//   withSentry(env => ({...}))(
//     withObservabilityScheduled(           // ← calls init(env, ctx)
//       withCronMonitor(                    // ← Sentry Crons heartbeat
//         checkCredit,                      // ← the handler
//         { monitorSlug: "openrouter-credit-check" }
//       )
//     )
//   )
//
// Why all three layers are mandatory:
//   - withSentry            initialises Sentry.init for the SDK side
//   - withObservabilityScheduled calls our wrapper's init() which configures
//                           the destinations registry. Without it,
//                           logEvent/captureError no-op SILENTLY.
//   - withCronMonitor       gives the monitor its own Sentry Crons heartbeat
//                           (Guarded Shape A from ADR-0029 — the cron always
//                           runs even if Sentry transport fails pre-callback).
//
// The monitor makes NO LLM calls itself — Sentry's openAIIntegration is
// NOT added here (and not needed). Sentry.init is only here so the
// destinations registry has somewhere to forward errors + breadcrumbs.

import { withSentry } from "@sentry/cloudflare";
import { withObservabilityScheduled } from "./observability/middleware";
import { withCronMonitor } from "./observability/cron-monitor";
import { checkCredit } from "./check-credit";

// Env extends Record<string, unknown> so it's compatible with the generic
// constraints on withCronMonitor / withObservabilityScheduled, which are
// designed to accept any Cloudflare env binding.
interface Env extends Record<string, unknown> {
  OPENROUTER_API_KEY: string;
  OPENROUTER_WARNING_RATIO?: string;
  OPENROUTER_CRITICAL_RATIO?: string;
  SENTRY_DSN: string;
  DEPLOY_ENV?: string;
  SERVICE_NAME?: string;
}

export default withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    environment: env.DEPLOY_ENV ?? "production",
    release: env.SERVICE_NAME ?? "openrouter-monitor",
    tracesSampleRate: 0.1,
    sendDefaultPii: false,
  }),
  {
    scheduled: withObservabilityScheduled(
      withCronMonitor(checkCredit as never, {
        monitorSlug: "openrouter-credit-check",
        handlerName: "scheduled",
      }),
    ),
  } as ExportedHandler<Env>,
);
