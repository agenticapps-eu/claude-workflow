# Environment additions — ts-cloudflare-worker

The `add-observability` skill writes the following stubs into the
project. Values left blank or marked `# REQUIRED` must be filled in
before deploy.

## `wrangler.toml`

Append (or merge) under the existing top-level config:

```toml
compatibility_flags = ["nodejs_compat"]   # required for AsyncLocalStorage

[vars]
SERVICE_NAME = "{{SERVICE_NAME}}"
DEPLOY_ENV   = "dev"                       # override per environment
```

If `compatibility_flags` already exists, the generator merges
`nodejs_compat` into the array (idempotent).

For per-environment overrides:

```toml
[env.staging.vars]
DEPLOY_ENV = "staging"

[env.production.vars]
DEPLOY_ENV = "prod"
```

## `.dev.vars` (local development)

```
SENTRY_DSN=                                # REQUIRED — paste from Sentry project settings
```

## Production secrets

`SENTRY_DSN` must be set as a Wrangler secret for staging and production:

```bash
wrangler secret put SENTRY_DSN --env staging
wrangler secret put SENTRY_DSN --env production
```

Do **not** commit the DSN to `wrangler.toml`. The DSN is treated as a
secret because it identifies the destination project; while a leaked
DSN is not catastrophic (Sentry will accept events from it), it lets
attackers inflate your event quota.

## `package.json`

The skill adds the dependency:

```json
{
  "dependencies": {
    "@sentry/cloudflare": "^8.0.0"
  }
}
```

After init, run `npm install` (or `pnpm install` / `bun install`) to
fetch the SDK.

## `.gitignore`

The skill adds:

```
.scan-report.md
```

Override with `init --track-report` if you want the conformance report
tracked in git.

## `tsconfig.json` (no changes)

The wrapper uses standard Cloudflare Workers types and `node:async_hooks`
which is provided by `nodejs_compat`. No tsconfig changes required.

## Axiom (logs destination — default)

When `logs=axiom` is active (the default role map), set the following in
addition to the Sentry vars above.

| Var | Where | Required | Example |
|---|---|---|---|
| `AXIOM_TOKEN` | wrangler secret | required if logs=axiom | `xaat-...` (ingest-scoped) |
| `AXIOM_DATASET` | `wrangler.toml` `[vars]` | required if logs=axiom | `myapp-prod` |
| `AXIOM_INGEST_URL` | `wrangler.toml` `[vars]` | optional | `https://api.eu.axiom.co/v1/datasets/<ds>/ingest` |
| `OBS_DESTINATIONS` | `wrangler.toml` `[vars]` or `.dev.vars` | optional | `errors=sentry,logs=axiom` (overrides baked default) |

**`AXIOM_TOKEN`** must be an ingest-scoped token (not an API token). Set it
as a Wrangler secret so it never lands in `wrangler.toml`:

```bash
wrangler secret put AXIOM_TOKEN --env staging
wrangler secret put AXIOM_TOKEN --env production
```

**`AXIOM_INGEST_URL`** only needs to be set if you are using a non-default
Axiom region (e.g. EU: `https://api.eu.axiom.co/v1/datasets/<ds>/ingest`) or
a self-hosted Axiom instance. Omit for the standard US endpoint.

**`OBS_DESTINATIONS`** overrides the baked default role map at runtime. The
default (`errors=sentry,logs=axiom`) is compiled in at scaffold time; use
this var only when you need to change the mapping without re-scaffolding (e.g.
temporarily disable Axiom with `logs=none`).

**Fail-safe:** if both `SENTRY_DSN` and `AXIOM_TOKEN`/`AXIOM_DATASET` are
absent, the wrapper falls back to console-only emission (§10.5 fail-safe
preserved — no events are lost and the app continues).

## Verification

After init, verify the wiring:

```bash
# 1. Compatibility flag is present
grep -q 'nodejs_compat' wrangler.toml

# 2. Wrapper exists
test -f src/lib/observability/index.ts
test -f src/lib/observability/middleware.ts

# 3. Entry file imports withObservability
grep -q 'withObservability' src/index.ts

# 4. Local dev DSN is set
grep -q '^SENTRY_DSN=' .dev.vars && [ -n "$(grep '^SENTRY_DSN=' .dev.vars | cut -d= -f2)" ]
```
