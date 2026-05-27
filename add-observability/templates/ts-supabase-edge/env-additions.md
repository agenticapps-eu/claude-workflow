# Environment additions — ts-supabase-edge

## `supabase/.env` (local development)

Loaded by `supabase functions serve` for local Edge Function dev:

```
SERVICE_NAME={{SERVICE_NAME}}
DEPLOY_ENV=dev
SENTRY_DSN=                                # REQUIRED for production parity
```

## Production secrets

Edge Function secrets are set via the Supabase CLI:

```bash
supabase secrets set SERVICE_NAME={{SERVICE_NAME}}
supabase secrets set DEPLOY_ENV=prod
supabase secrets set SENTRY_DSN="https://<key>@<org>.ingest.sentry.io/<proj>"
```

These secrets are scoped to the entire project — every Edge Function in
the project reads from the same set. To use different DSNs per
environment, configure separate Supabase projects (staging vs prod).

## `supabase/functions/<each-function>/index.ts`

Each function imports `withObservability` and wraps its handler:

```ts
// supabase/functions/process-document/index.ts
import { withObservability } from "../_shared/observability/middleware.ts";

Deno.serve(
  withObservability(async (req) => {
    const body = await req.json();
    // ...handler logic
    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  }),
);
```

The skill's `init` subcommand wires this for all existing functions
detected at scaffold time. The `scan` subcommand flags any function
that imports anything from `_shared/observability/` but doesn't wrap
its handler — that's a non-conformance per spec §10.4 #1.

## `supabase/functions/import_map.json` (or `deno.json`)

If the project uses an import map, the skill adds:

```json
{
  "imports": {
    "@sentry/deno": "npm:@sentry/deno@^8.0.0"
  }
}
```

If no import map exists, the wrapper uses the inline `npm:@sentry/deno`
specifier directly.

## Axiom (logs destination — default)

When `logs=axiom` is active (the default role map), set the following in
addition to the Sentry vars above.

| Var | Where | Required | Example |
|---|---|---|---|
| `AXIOM_TOKEN` | Supabase secrets (`supabase secrets set`) | required if logs=axiom | `xaat-...` (ingest-scoped) |
| `AXIOM_DATASET` | Supabase secrets | required if logs=axiom | `myapp-prod` |
| `AXIOM_INGEST_URL` | Supabase secrets | optional | `https://api.eu.axiom.co/v1/datasets/<ds>/ingest` |
| `OBS_DESTINATIONS` | Supabase secrets or `supabase/.env` | optional | `errors=sentry,logs=axiom` (overrides baked default) |

Set the Axiom secrets via the Supabase CLI (they are scoped project-wide,
shared across all Edge Functions in the project):

```bash
supabase secrets set AXIOM_TOKEN="xaat-..."
supabase secrets set AXIOM_DATASET="myapp-prod"
```

**`AXIOM_INGEST_URL`** only needs to be set if you are using a non-default
Axiom region (e.g. EU: `https://api.eu.axiom.co/v1/datasets/<ds>/ingest`) or
a self-hosted Axiom instance. Omit for the standard US endpoint.

**`OBS_DESTINATIONS`** overrides the baked default role map at runtime. The
default (`errors=sentry,logs=axiom`) is compiled in at scaffold time; use
this var only when you need to change the mapping without re-scaffolding.

**Fail-safe:** if both `SENTRY_DSN` and `AXIOM_TOKEN`/`AXIOM_DATASET` are
absent, the wrapper falls back to console-only emission (§10.5 fail-safe
preserved — no events are lost and the function continues).

## Verification

```bash
test -d supabase/functions/_shared/observability
test -f supabase/functions/_shared/observability/index.ts
test -f supabase/functions/_shared/observability/middleware.ts

# Each function imports the middleware
for f in supabase/functions/*/index.ts; do
  case "$f" in
    *_shared*|*_health*) continue ;;
  esac
  if ! grep -q 'withObservability' "$f"; then
    echo "MISSING wrap in $f"
  fi
done

# Local dev: supabase functions serve <name> picks up SENTRY_DSN
grep -q '^SENTRY_DSN=' supabase/.env
```

## Note on Deno test fixtures

The contract test fixture for this stack uses Deno's built-in test
runner (not vitest). Run it with:

```bash
cd supabase/functions/_shared/observability
deno test --allow-env --allow-net=ingest.sentry.io
```

`--allow-env` is required because the wrapper reads `Deno.env.get(...)`.
`--allow-net=ingest.sentry.io` is only needed if testing live Sentry
emission; the contract test stubs the network and works without it.
