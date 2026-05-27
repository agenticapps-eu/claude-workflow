# Environment additions — ts-react-vite

The `add-observability` skill writes the following stubs into the
project. Values left blank or marked `# REQUIRED` must be filled in
before deploy.

## `.env` (and `.env.production`, `.env.staging` per Vite convention)

```
VITE_SERVICE_NAME={{SERVICE_NAME}}
VITE_DEPLOY_ENV=dev
VITE_SENTRY_DSN=
```

Vite exposes only `VITE_`-prefixed vars to client code at build time.
The DSN is bundled into the production JS — this is intentional and
safe: Sentry browser DSNs are public keys by design, not secrets.

For a more granular cost story per environment, set different DSNs
(or different Sentry projects) in `.env.production` vs `.env.staging`:

```
# .env.staging
VITE_DEPLOY_ENV=staging
VITE_SENTRY_DSN=https://staging-key@org.ingest.sentry.io/staging-proj

# .env.production
VITE_DEPLOY_ENV=prod
VITE_SENTRY_DSN=https://prod-key@org.ingest.sentry.io/prod-proj
```

## `package.json`

The skill adds the dependency:

```json
{
  "dependencies": {
    "@sentry/react": "^8.0.0"
  }
}
```

Run your package manager (`npm install` / `pnpm install` / `bun install`)
after init to fetch the SDK.

## Wiring `init()` and `<ObservabilityErrorBoundary>`

The skill rewrites `src/main.tsx` (or equivalent) to call init at the
React-root mount and wrap the app in the error boundary. The expected
shape after init:

```tsx
import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { init, ObservabilityErrorBoundary } from "./lib/observability"
import App from "./App"
import "./index.css"

init()

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ObservabilityErrorBoundary>
      <App />
    </ObservabilityErrorBoundary>
  </StrictMode>,
)
```

The `init()` call MUST happen before `createRoot(...).render(...)` so
the global `fetch` interceptor is installed before the first network
request fires.

## TanStack Query / Router integration (optional)

If the project uses TanStack Query or TanStack Router (cparx + fx-signals
do), open a span at the route-change boundary or query-invocation
boundary for richer traces:

```ts
// In src/router.ts
import { startSpan } from "./lib/observability"

router.subscribe("onBeforeNavigate", ({ toLocation }) => {
  const span = startSpan(`route ${toLocation.pathname}`, { route: toLocation.pathname })
  router.subscribe("onLoad", () => span.end(), { once: true })
})
```

Not auto-wired by the skill — it's project-specific.

## Axiom (logs destination — browser, proxy-only)

The browser MUST NOT receive an Axiom ingest-write token — it would be
bundled into the production JS and visible to anyone who opens DevTools.
The browser adapter is therefore console-only by default and activates
only when a **same-origin proxy URL** is configured.

| Var | Where | Required | Example |
|---|---|---|---|
| `VITE_AXIOM_PROXY_URL` | `.env` / `.env.production` | optional | `/api/log` |

Do **NOT** add `VITE_AXIOM_TOKEN` or `VITE_AXIOM_DATASET` to your Vite env
files — those would be bundled into client JS and exfiltrated. The ingest
token lives server-side only, inside the proxy handler.

**`VITE_AXIOM_PROXY_URL`** is a same-origin path (or full URL to a
same-origin endpoint) that accepts `POST` with a JSON body of
`[envelope, ...]` and forwards it to the Axiom ingest API with the
`Authorization: Bearer <token>` header added server-side. If unset,
`isConfigured()` returns false, `forRole("logs")` returns null, and log
events are console-only (the existing behaviour is preserved unchanged).

**`OBS_DESTINATIONS`** is not applicable in the browser bundle — the role
map is baked at build time and cannot be overridden via a runtime env var
in a Vite app.

**Fail-safe:** if `VITE_AXIOM_PROXY_URL` is absent (or `VITE_SENTRY_DSN` is
absent), the wrapper falls back to console-only emission (§10.5 fail-safe
preserved — no events are lost and the app continues).

### Same-origin proxy example

A minimal Hono (or Express) `/api/log` handler that holds the secret
server-side and proxies the body to Axiom:

```ts
// Hono (e.g. Cloudflare Worker, Bun, Node) — server-side only
import { Hono } from "hono";

const app = new Hono();

app.post("/api/log", async (c) => {
  const token   = process.env.AXIOM_TOKEN   ?? c.env?.AXIOM_TOKEN;
  const dataset = process.env.AXIOM_DATASET ?? c.env?.AXIOM_DATASET;
  if (!token || !dataset) return c.json({ error: "axiom not configured" }, 500);

  const body = await c.req.text();
  const url  = `https://api.axiom.co/v1/datasets/${dataset}/ingest`;

  const resp = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body,
  });
  return c.json({ ok: resp.ok }, resp.ok ? 200 : 502);
});

export default app;
```

```ts
// Express (Node) equivalent
import express from "express";

const router = express.Router();

router.post("/api/log", express.text({ type: "application/json" }), async (req, res) => {
  const { AXIOM_TOKEN: token, AXIOM_DATASET: dataset } = process.env;
  if (!token || !dataset) { res.status(500).json({ error: "axiom not configured" }); return; }

  const url  = `https://api.axiom.co/v1/datasets/${dataset}/ingest`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: req.body,
  });
  res.status(resp.ok ? 200 : 502).json({ ok: resp.ok });
});
```

Set `AXIOM_TOKEN` and `AXIOM_DATASET` as server-side secrets (e.g. in
`.env.server`, fly secrets, or a KV binding) — never in `.env` where Vite
would bundle them.

> **Hardening:** an open `/api/log` proxy is an abuse-amplification vector —
> any browser tab (or script) can POST arbitrary payloads to your Axiom dataset.
> The proxy SHOULD enforce: (a) a request body-size cap (e.g. `express.text({ limit: "64kb" })`
> or Hono's `bodyLimit` middleware); (b) basic rate-limiting per IP; and (c) if
> the app has authentication, require a valid session before forwarding.

## `.gitignore`

The skill adds:

```
.scan-report.md
```

## Verification

After init:

```bash
# 1. Wrapper exists
test -f src/lib/observability/index.ts
test -f src/lib/observability/ErrorBoundary.tsx

# 2. Init is wired in entry file
grep -q 'init()' src/main.tsx
grep -q 'ObservabilityErrorBoundary' src/main.tsx

# 3. Required exports present
grep -q 'export function logEvent\b' src/lib/observability/index.ts
grep -q 'export function captureError\b' src/lib/observability/index.ts
grep -q 'export function startSpan\b' src/lib/observability/index.ts

# 4. Env stubs present
grep -q '^VITE_SERVICE_NAME' .env
grep -q '^VITE_SENTRY_DSN' .env

# 5. Builds clean (Vite catches type errors)
npm run build
```
