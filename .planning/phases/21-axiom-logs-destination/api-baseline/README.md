# API baseline — byte-identity proof (P1.3)

These `.d.ts` snapshots capture each stack wrapper's **public exported type
surface** at the 1.15.0 baseline (from `main`). After a refactor, regenerate
the same `.d.ts` from the working tree and diff against the snapshot here; the
public surface MUST be identical (a new internal module like
`destinations/registry` is fine — only the wrapper's exported function
signatures and exported types are gated).

## Method (ts-cloudflare-worker)

1. `git show main:add-observability/templates/ts-cloudflare-worker/lib-observability.ts`
   into a temp file; substitute the `{{TOKEN}}` placeholders with the same
   harness defaults `run-template-tests.sh` uses (SERVICE_NAME=test-service,
   ENV_VAR_DSN=SENTRY_DSN, ENV_VAR_ENV=DEPLOY_ENV, ENV_VAR_SERVICE=SERVICE_NAME,
   sample rates 0.1, the standard REDACTED_KEYS list).
2. Provide minimal ambient shims for the external imports
   (`@sentry/cloudflare`, `node:async_hooks`, the Workers global
   `ExecutionContext`, `crypto`) so `tsc` can emit declarations.
3. Generate declarations:

   ```bash
   tsc --declaration --emitDeclarationOnly --skipLibCheck \
       --target ES2022 --module ESNext --moduleResolution bundler \
       --lib ES2022,DOM --outDir <out> index.ts shims.d.ts
   ```

4. Snapshot the emitted `index.d.ts` as `ts-cloudflare-worker.d.ts`.

## P1 result

The refactored wrapper (registry-dispatched `logEvent`/`captureError`) emits a
`.d.ts` whose public surface is **byte-identical** to this baseline — empty
diff. The added `destinations/registry.d.ts` is a new internal module and is
not part of the wrapper's exported surface.

## P2 result — TS stack baselines (post-P2 byte-identity fixes)

`ts-supabase-edge.txt`, `ts-react-vite.txt`, and `ts-cloudflare-pages.txt`
capture the post-P2 public export surfaces (grep-extracted manifest form).

- **ts-supabase-edge** — `init(): void` (zero-arg, byte-identical to main).
  `_resetForTest` is an `@internal` test-only helper, underscore-prefixed,
  not part of the spec §10 contract surface.
- **ts-react-vite** — `init(opts: InitOptions = {}): void` with `InitOptions`
  containing only `initialContext?: TraceContext` (byte-identical to main;
  `testEnv` field removed). `_resetForTest` is `@internal` test-only.
- **ts-cloudflare-pages** — `init(env: InitEnv, ctx: ExecutionContext): void`,
  own full implementation (stale `inherits_wrapper_from` directive removed
  from meta.yaml in the same commit).
