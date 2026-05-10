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
