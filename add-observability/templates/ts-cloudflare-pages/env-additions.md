# Environment additions — ts-cloudflare-pages

Pages Functions share the Workers runtime's env model. The skill writes
the same stubs as ts-cloudflare-worker, with two Pages-specific notes
called out below.

## `wrangler.toml`

```toml
compatibility_flags = ["nodejs_compat"]

[vars]
SERVICE_NAME = "{{SERVICE_NAME}}"
DEPLOY_ENV   = "dev"
```

For Pages projects (vs. plain Workers), `wrangler.toml` is optional —
many Pages setups configure env vars via the Cloudflare dashboard
instead. If `wrangler.toml` is missing, the skill creates a minimal one
with just the observability vars; the user can move them to the
dashboard later if preferred.

## `.dev.vars` (local development)

```
SENTRY_DSN=                                # REQUIRED — paste from Sentry
```

## Production secrets (via Cloudflare Pages dashboard)

`SENTRY_DSN` is set via `wrangler pages secret put` or the dashboard:

```bash
wrangler pages secret put SENTRY_DSN --project-name {{SERVICE_NAME}}
```

In the dashboard: **Workers & Pages → {{SERVICE_NAME}} → Settings →
Environment variables → Production → Add variable** and tick
"Encrypt".

## Sentry integration

`lib-observability.ts` exports `buildSentryOptions(env)` (Phase 26 DEF-1) — an
ENV-PURE helper that surfaces `TRACE_SAMPLE_RATE` and the env-derived
service name + environment to `@sentry/cloudflare`'s per-request
`withSentry(optionsFactory, handler)` wrapper. Wire it at your entry file:

```typescript
// Paths assume the scaffolded Pages layout: wrapper lands at
// `functions/_lib/observability/index.ts` (INIT.md §Phase 5 cf-pages, line
// ~533). Pages Functions usually wire observability via `_middleware.ts`
// rather than an entry-file `withSentry` wrap — this snippet covers the
// less common case where you want explicit `withSentry` per route. Adjust
// the relative path to `./_lib/observability/...` if your route file lives
// deeper in `functions/`.
import { withSentry } from "@sentry/cloudflare";
import { withObservability } from "./_lib/observability/middleware";
import { buildSentryOptions } from "./_lib/observability";

const handler = { /* fetch, scheduled, queue, etc. */ };
export default withSentry(env => buildSentryOptions(env), withObservability(handler));
```

The helper reads directly from `env` (does NOT depend on `init()` running
first) — safe to invoke from `withSentry`'s options factory regardless of
when the inner handler's `init(env, ctx)` runs. Requires
`@sentry/cloudflare >= 8.0.0` (already declared in `package.json`).
See `docs/decisions/0034-observability-init-singleton-invariant.md` for the
runtime model (Cloudflare warm-isolate reuse) that motivates env-purity.

## `package.json`

```json
{
  "dependencies": {
    "@sentry/cloudflare": "^8.0.0"
  }
}
```

## Wiring

Pages Functions automatically loads `functions/_middleware.ts` for every
request that resolves to a Pages Function. The skill writes that file
directly — no explicit middleware-wrap call in route handlers is needed.

If the project already has a `functions/_middleware.ts`, the skill
either prepends ours and chains via `context.next()`, or composes the
two via export chaining (see Pages Functions docs on
`onRequest`-as-array).

## Axiom (logs destination — default)

When `logs=axiom` is active (the default role map), set the following in
addition to the Sentry vars above.

| Var | Where | Required | Example |
|---|---|---|---|
| `AXIOM_TOKEN` | Cloudflare Pages secret (`wrangler pages secret put`) | required if logs=axiom | `xaat-...` (ingest-scoped) |
| `AXIOM_DATASET` | `wrangler.toml` `[vars]` or Pages dashboard | required if logs=axiom | `myapp-prod` |
| `AXIOM_INGEST_URL` | `wrangler.toml` `[vars]` or Pages dashboard | optional | `https://api.eu.axiom.co/v1/datasets/<ds>/ingest` |
| `OBS_DESTINATIONS` | `wrangler.toml` `[vars]` or `.dev.vars` | optional | `errors=sentry,logs=axiom` (overrides baked default) |

**`AXIOM_TOKEN`** must be an ingest-scoped token. Set it as a Pages secret so
it never appears in `wrangler.toml` or the dashboard plaintext:

```bash
wrangler pages secret put AXIOM_TOKEN --project-name {{SERVICE_NAME}}
```

**`AXIOM_INGEST_URL`** only needs to be set if you are using a non-default
Axiom region (e.g. EU: `https://api.eu.axiom.co/v1/datasets/<ds>/ingest`) or
a self-hosted Axiom instance. Omit for the standard US endpoint.

**`OBS_DESTINATIONS`** overrides the baked default role map at runtime. The
default (`errors=sentry,logs=axiom`) is compiled in at scaffold time; use
this var only when you need to change the mapping without re-scaffolding.

**Fail-safe:** if both `SENTRY_DSN` and `AXIOM_TOKEN`/`AXIOM_DATASET` are
absent, the wrapper falls back to console-only emission (§10.5 fail-safe
preserved — no events are lost and the app continues).

## Verification

```bash
test -f functions/_middleware.ts
test -f functions/_lib/observability/index.ts
grep -q 'compatibility_flags.*nodejs_compat' wrangler.toml
grep -q '^SENTRY_DSN=' .dev.vars
```
