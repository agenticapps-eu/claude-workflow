# Environment additions — go-fly-http

The `add-observability` skill writes the following stubs into the
project. Values left blank or marked `# REQUIRED` must be filled in
before deploy.

## `fly.toml`

The skill appends (or merges) under `[env]`:

```toml
[env]
SERVICE_NAME = "{{SERVICE_NAME}}"
DEPLOY_ENV   = "dev"                       # override per environment / via fly secrets
```

For per-environment apps, set `DEPLOY_ENV` via Fly's environment override
mechanism rather than committing it.

## Production secrets

`SENTRY_DSN` is set as a Fly secret (never committed):

```bash
fly secrets set SENTRY_DSN="https://<key>@<org>.ingest.sentry.io/<project>"
```

For multi-app projects (e.g. staging vs prod):

```bash
fly secrets set SENTRY_DSN="..." -a {{SERVICE_NAME}}-staging
fly secrets set SENTRY_DSN="..." -a {{SERVICE_NAME}}
```

## Local development

For `go run` / `air` / local testing, set the env vars in a `.env.local`
or via direnv:

```
SERVICE_NAME={{SERVICE_NAME}}
DEPLOY_ENV=dev
SENTRY_DSN=                                # REQUIRED for production parity testing
```

`SENTRY_DSN` MAY be left blank locally — the wrapper degrades gracefully
to stdout-only emission if the DSN is missing.

## `go.mod`

The skill adds the dependency:

```go
require github.com/getsentry/sentry-go v0.31.0
```

After init, run:

```bash
go mod tidy
```

## Wiring `Init()` and `Middleware`

The skill rewrites the entry file to call `observability.Init()` once
and wrap the top-level handler with `observability.Middleware`. The
expected shape after init:

```go
package main

import (
    "log"
    "net/http"

    "{{MODULE_PATH}}"  // generated package path
)

func main() {
    observability.Init()

    mux := http.NewServeMux()
    // ... register handlers ...

    srv := &http.Server{
        Addr:    ":8080",
        Handler: observability.Middleware(mux),
    }
    log.Fatal(srv.ListenAndServe())
}
```

For chi:

```go
r := chi.NewRouter()
r.Use(observability.Middleware)
```

## Outbound HTTP client wiring

To propagate `traceparent` on outbound calls, wrap the HTTP transport at
boot:

```go
http.DefaultClient.Transport = observability.NewTracingTransport(http.DefaultTransport)
```

Or per-client:

```go
client := &http.Client{
    Transport: observability.NewTracingTransport(nil),
}
```

The skill's scan subcommand flags outbound `http.Get` / `http.Post` /
`client.Do` call sites that don't use a tracing transport as
medium-confidence findings.

## Axiom (logs destination — default)

When `logs=axiom` is active (the default role map), set the following in
addition to the Sentry vars above.

| Var | Where | Required | Example |
|---|---|---|---|
| `AXIOM_TOKEN` | fly secrets | required if logs=axiom | `xaat-...` (ingest-scoped) |
| `AXIOM_DATASET` | `fly.toml` `[env]` | required if logs=axiom | `myapp-prod` |
| `AXIOM_INGEST_URL` | `fly.toml` `[env]` | optional | `https://api.eu.axiom.co/v1/datasets/<ds>/ingest` |
| `OBS_DESTINATIONS` | `fly.toml` `[env]` or fly secrets | optional | `errors=sentry,logs=axiom` (overrides baked default) |

**`AXIOM_TOKEN`** must be an ingest-scoped token. Set it as a Fly secret so
it never appears in `fly.toml`:

```bash
fly secrets set AXIOM_TOKEN="xaat-..." -a {{SERVICE_NAME}}
```

**`AXIOM_INGEST_URL`** only needs to be set if you are using a non-default
Axiom region (e.g. EU: `https://api.eu.axiom.co/v1/datasets/<ds>/ingest`) or
a self-hosted Axiom instance. Omit for the standard US endpoint.

**`OBS_DESTINATIONS`** overrides the baked default role map at runtime. The
default (`errors=sentry,logs=axiom`) is compiled in at scaffold time; use
this var only when you need to change the mapping without re-scaffolding (e.g.
temporarily disable Axiom with `logs=none`).

**Fail-safe:** if both `SENTRY_DSN` and `AXIOM_TOKEN`/`AXIOM_DATASET` are
absent, the wrapper falls back to stdout-only emission (§10.5 fail-safe
preserved — no events are lost and the service continues).

## `.gitignore`

The skill adds:

```
.scan-report.md
```

## Verification

After init:

```bash
# 1. Wrapper exists
test -f internal/observability/observability.go
test -f internal/observability/middleware.go

# 2. Init is wired in entry file
grep -q 'observability.Init()' cmd/server/main.go

# 3. Middleware wraps the top-level handler
grep -q 'observability.Middleware' cmd/server/main.go

# 4. fly.toml has the env vars
grep -q '^SERVICE_NAME' fly.toml
grep -q '^DEPLOY_ENV' fly.toml

# 5. Builds clean
go build ./...
```
