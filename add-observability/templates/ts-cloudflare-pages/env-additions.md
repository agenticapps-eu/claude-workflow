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

## Verification

```bash
test -f functions/_middleware.ts
test -f functions/_lib/observability/index.ts
grep -q 'compatibility_flags.*nodejs_compat' wrangler.toml
grep -q '^SENTRY_DSN=' .dev.vars
```
