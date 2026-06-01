# Environment additions — openrouter-monitor

The openrouter-monitor template ships as a self-contained Cloudflare Worker
scaffold. Most operator-facing env guidance lives in `README.md`. This file
captures the Phase 26 DEF-1 wiring snippet for `buildSentryOptions(env)` and
keeps it byte-symmetric with `ts-cloudflare-worker/env-additions.md` for the
add-observability skill's documentation parity (Phase 25 D-21 contract).

## Sentry integration

`src/observability/index.ts` exports `buildSentryOptions(env)` (Phase 26 DEF-1) —
an ENV-PURE helper that surfaces `TRACE_SAMPLE_RATE` and the env-derived
service name + environment to `@sentry/cloudflare`'s per-request
`withSentry(optionsFactory, handler)` wrapper. Wire it at your entry file:

```typescript
import { withSentry } from "@sentry/cloudflare";
import { withObservabilityScheduled } from "./observability/middleware";
import { buildSentryOptions } from "./observability";

const handler = { /* fetch, scheduled, queue, etc. */ };
export default withSentry(env => buildSentryOptions(env), withObservabilityScheduled(handler));
```

The openrouter-monitor's own `src/index.ts:46-66` follows this pattern manually
today (env-derived `environment` and `release`); `buildSentryOptions` factors
that pattern into a reusable helper that maintenance forks can adopt.

The helper reads directly from `env` (does NOT depend on `init()` running
first) — safe to invoke from `withSentry`'s options factory regardless of
when the inner handler's `init(env, ctx)` runs. Requires
`@sentry/cloudflare >= 8.0.0` (already declared in `package.json`).
See `docs/decisions/0034-observability-init-singleton-invariant.md` for the
runtime model (Cloudflare warm-isolate reuse) that motivates env-purity.
