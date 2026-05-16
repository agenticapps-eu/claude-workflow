# `init` subcommand procedure

You are running the `init` subcommand of the `add-observability` skill
against the user's current project. Your job is to **scaffold the
observability wrapper, middleware, policy.md, and CLAUDE.md metadata
block** for every stack detected in the project, satisfying spec §10.7
obligations (1) "scaffold a wrapper module per stack" and (2) "wire
trace-propagation middleware into the project's request-handling
layer". You MUST NOT proceed past a phase without the corresponding
consent gate (§10.7 obligation (4) "apply only with consent").

This is the **greenfield** entry point — use it before any
observability-related source code exists in the project. For a project
that already has partial instrumentation, run `scan` first to
understand the current state.

## Inputs

- **Project root**: the working directory (the user's open project).
- **`--stack <id>`** (optional, default: walk all detected stacks):
  limit scaffolding to a single stack ID (e.g. `--stack go-fly-http`).
  When omitted, init walks every detected stack in lexicographic order
  (per RESEARCH D3 "walk all + --stack override"). Useful for partial
  scaffolding of multi-stack monorepos (e.g. scaffold backend now,
  frontend later).
- **`--force`** (optional, **rejected at v0.3.1**; reserved for
  v0.4.0+): re-init an already-initialised stack. Per RESEARCH D5,
  v0.3.1 is strict-first-run-only. If `--force` is passed in this
  version, exit with the message "`--force` is reserved for v0.4.0+
  re-init. To refresh a stale wrapper today, `rm -rf <wrapper-dir>`
  first and re-run init."

## Outputs

- **Wrapper module(s)** materialised at each stack's
  `meta.yaml target.wrapper_path` (resolved against the **language
  module root** per spec §10.7.1, NOT against project root).
- **Middleware** materialised where applicable (per-stack — Worker,
  Pages, Supabase, Go ship middleware; Vite uses the wrapper itself).
- **`policy.md`** materialised per-stack at each stack's
  `meta.yaml target.policy_path`.
- **Entry file(s) rewritten** with the observability wrap and
  anchor-comment markers `// agenticapps:observability:start` /
  `:end` (TS variant `//`; Go variant `//`; Python `#`).
- **`observability:` metadata block** written to CLAUDE.md per spec
  §10.8 (scalar `policy:` field per v0.3.1 contract — see Phase 6
  "Schema constraint").

No source files outside the wrapper directories and the detected
entry-file(s) are modified.

## Procedure

### Phase 1 — Detect stacks

Walk the project from CWD outward, detecting language module roots and
stack types per the rules in `../scan/detectors.md`. The detection
logic is identical to `scan/SCAN.md` Phase 1 — reuse the same rules so
init and scan agree on which stacks the project has.

If `--stack <id>` was passed, filter the detection results to only
that stack. If the requested stack is not detected, exit with the
message "Stack `<id>` not detected in this project. Run
`/add-observability scan` to see the detected stack list."

If zero stacks are detected, exit with the message "No supported
stacks detected. See `add-observability/templates/` for the list of
supported stack IDs." No files modified.

### Phase 2 — Resolve targets

For each detected stack:

1. Read `add-observability/templates/<stack>/meta.yaml`.
2. Resolve `target.wrapper_path`, `target.middleware_path`,
   `target.policy_path`, and `entry_file_candidates` against the
   **module root** for that stack (NOT the project root, per spec
   §10.7.1). The module root is the directory containing the canonical
   manifest for the stack:
   - Go: `go.mod`
   - Node / TypeScript: `package.json`
   - Deno: `deno.json` or `deno.jsonc`
3. Resolve parameters per the `parameters.<NAME>.{default,derive_from}`
   rules in meta.yaml. For example, `SERVICE_NAME` for
   `ts-cloudflare-worker` derives from the `[name]` field in
   `wrangler.toml`; `MODULE_PATH` for `go-fly-http` derives from the
   module line in `go.mod`.

If a parameter has no default and `derive_from` returns empty, error
out with the message "Cannot resolve parameter `<NAME>` for stack
`<id>`. Add `<NAME>=<value>` to your project's environment, or set the
`derive_from` source (`<source-file>`)." No files modified.

**Strict first-run check (per RESEARCH D5)**: for each stack, if
`target.wrapper_path` already exists at the resolved module-root
location, exit with the message:

> Wrapper directory already exists at `<path>`. This is a strict
> first-run check (v0.3.1). To refresh, `rm -rf <wrapper-path>` and
> re-run init. Re-init via `--force` is reserved for v0.4.0+.

No files modified.

### Phase 3 — Show full plan (informational; NOT a consent gate)

Print a summary to stdout so the user knows what is about to be
proposed across the 3 consent gates that follow. No prompt at this
phase.

```
About to initialise observability scaffolding.

Stacks detected: <stack-1>, <stack-2>, ...
Module roots:
  <stack-1> @ <module-root-1>
  <stack-2> @ <module-root-2>

New files to be materialised (Phase 4 — consent gate 1 of 3):
  <stack-1>/<target.wrapper_path>
  <stack-1>/<target.middleware_path>   (if applicable)
  <stack-1>/<target.policy_path>
  ...

Entry files to be rewritten (Phase 5 — consent gate 2 of 3):
  <stack-1>/<entry-file>
  <stack-2>/<entry-file>

CLAUDE.md observability metadata block (Phase 6 — consent gate 3 of 3):
  Status: <"to add" | "to update — existing block present">

Each of the 3 phases will show its own diff and ask y/n before applying.
```

### Phase 4 — Materialise wrapper + middleware + policy (consent gate 1 of 3 — scaffold)

For each stack, in lexicographic order by stack ID:

1. Copy template files from `add-observability/templates/<stack>/`
   to the resolved target paths from Phase 2.
2. Substitute `{{PARAMETER}}` tokens using the values resolved in
   Phase 2.
3. Anchor every materialised file's content with
   `// agenticapps:observability:start` / `// :end` comments at top
   and bottom (Go `//`; TS `//`; Python `#`). These anchors are
   load-bearing for the strict-first-run check in Phase 2 of future
   re-init attempts.

**Consent prompt** (after all new files are computed but before any
write):

```
About to materialise N new files:
  <list of paths with diff for each>

Apply these N new files? [y/n]
```

**Decline path (gate 1 decline)**: print "No files changed." and exit
cleanly with code 0. No partial state — nothing was written before the
consent gate.

### Phase 5 — Rewrite entry file (consent gate 2 of 3 — entry-file)

For each stack with an `entry_file_candidates` list in meta.yaml,
scan the project for the first matching candidate path. The per-stack
rewrite shape is detailed in the stack-specific subsections below.

For each entry file:

1. Read the file.
2. Compute the rewritten content per the per-stack rewrite shape.
3. Wrap the added/modified regions in anchor comments
   `// agenticapps:observability:start` / `:end` (block boundaries
   may differ per stack — see subsections).
4. Show the unified diff to the user.

**Consent prompt** (after all entry-file diffs are computed):

```
About to rewrite N entry files:
  <unified diff for each>

Rewrite these N entry files? [y/n]
```

**Decline path (gate 2 decline)**: print:

```
Entry-file rewrites declined.

Rollback hint (run if you want to revert Phase 4's scaffold):
  rm -rf <list of wrapper dirs materialised in Phase 4>

Note: without entry-file wiring, the wrapper modules are inert
(traces are not propagated). Phase 6 (CLAUDE.md observability block)
WILL NOT run on this decline path — writing the metadata block now
would falsely claim conformance to §10.7 obligation (2). See
"Important rules" below.
```

Exit cleanly with code 0. Wrapper files from Phase 4 remain — user
follows the rollback hint OR re-runs init with all gates accepted.

#### Per-stack rewrite shapes

The exact rewrite shape per stack is authored in T5-T9 of this phase
plan (subsections appended to this file by those tasks). At the time
of writing this skeleton, the placeholders are:

- **`ts-cloudflare-worker`** — wrap `fetch` AND `scheduled` handlers
  in the default export with `withObservability(...)` /
  `withObservabilityScheduled(...)`. Queue handler is out of scope
  for v0.3.1. (T5)
- **`ts-cloudflare-pages`** — materialise `functions/_middleware.ts`
  from the template (Pages auto-loads it). Do NOT rewrite individual
  `onRequest*` exports. (T6)
- **`ts-supabase-edge`** — wrap `Deno.serve(handler)` and
  `Deno.serve(options, handler)` with `withObservability(...)`. Import
  from `../_shared/observability/middleware.ts`. (T7)
- **`ts-react-vite`** — call `init()` before
  `createRoot(...).render(...)` AND wrap the JSX in
  `<ObservabilityErrorBoundary>`. The `init()` call installs the
  global `fetch` interceptor (this is what satisfies §10.7 obligation
  (2) for browser stacks). (T8)
- **`go-fly-http`** — detect chi / gorilla / std net/http via import
  scan. Apply the appropriate middleware wrap shape at server boot.
  Call `observability.Init()` once in `main()`. (T9)

<!-- per-stack detail subsections appended below by T5-T9 -->

#### Phase 5 detail — `ts-cloudflare-worker`

Worker projects export a default `{ fetch?, scheduled?, queue? }`
object from one of `entry_file_candidates`:

```yaml
entry_file_candidates:
  - src/index.ts
  - src/worker.ts
  - worker/index.ts
  - src/main.ts
```

(per `templates/ts-cloudflare-worker/meta.yaml`). Init scans the first
matching candidate and rewrites the `export default { ... }` object.

**Wrappers** — imported from the wrapper materialised in Phase 4 at
`<module-root>/src/lib/observability/index.ts`. Per
`templates/ts-cloudflare-worker/middleware.ts:35,78`:

| Handler | Wrap |
|---------|------|
| `fetch: handler` | `fetch: withObservability(handler)` |
| `scheduled: handler` | `scheduled: withObservabilityScheduled(handler)` |

The wrapping is applied to whichever handlers the default export
actually defines — projects with only `fetch` get only the fetch
wrap; projects with `{ fetch, scheduled }` get both wraps.

**Queue handler — explicitly out of scope at v0.3.1.** The template's
queue wrapper at `templates/ts-cloudflare-worker/middleware.ts:130-138`
is commented out (future work). If init detects a `queue:` key in the
default export, print:

```
Worker exports a `queue` handler. Wrapping queue handlers requires
withObservabilityQueue, which is reserved for v0.4.0+. The fetch and
scheduled handlers (if present) have been wrapped; queue handling is
left untouched. See add-observability/templates/ts-cloudflare-worker/env-additions.md
for manual instrumentation guidance.
```

Then continue wrapping the other handlers — do NOT abort.

**Class-based exports — explicitly out of scope at v0.3.1.** If the
entry file contains `export default class extends WorkerEntrypoint`
or any class-export shape, print:

```
Worker uses a class-based default export (e.g. `extends
WorkerEntrypoint`). Class-based instrumentation requires a different
wrap shape (decorator-style) reserved for v0.4.0+. Aborting Phase 5
for this stack. The wrapper module from Phase 4 remains; you can
wire it manually per env-additions.md. CLAUDE.md observability block
write (Phase 6) is skipped to avoid false-conformance — see
"Important rules".
```

Then skip Phase 6 for this stack and treat the stack as a gate-2
decline (Phase 5 decline path).

**Rewrite shape — examples**

Before:
```typescript
import { handler } from "./handler";

export default {
  fetch: handler,
} satisfies ExportedHandler<Env>;
```

After:
```typescript
// agenticapps:observability:start
import { withObservability } from "./lib/observability";
// agenticapps:observability:end
import { handler } from "./handler";

// agenticapps:observability:start
export default {
  fetch: withObservability(handler),
} satisfies ExportedHandler<Env>;
// agenticapps:observability:end
```

Before (multi-handler):
```typescript
export default {
  fetch: async (request, env, ctx) => new Response("ok"),
  scheduled: async (event, env, ctx) => { /* cron */ },
} satisfies ExportedHandler<Env>;
```

After:
```typescript
// agenticapps:observability:start
import { withObservability, withObservabilityScheduled } from "./lib/observability";
// agenticapps:observability:end

// agenticapps:observability:start
export default {
  fetch: withObservability(async (request, env, ctx) => new Response("ok")),
  scheduled: withObservabilityScheduled(async (event, env, ctx) => { /* cron */ }),
} satisfies ExportedHandler<Env>;
// agenticapps:observability:end
```

**Anchor regions**: TWO separate anchored blocks per entry file —
one around the inserted `import` line(s), one around the modified
default-export object. The blocks must NOT straddle (i.e. each anchor
opens and closes on its own region; rewrites between the regions stay
out of the anchored zones).

**Edge cases handled by diff-preview + per-file consent**:
- Handler defined inline as an arrow function vs imported from another
  module — both supported (the diff covers the literal characters in
  the default-export object regardless of where the handler reference
  comes from).
- Mixed-handler defaults like `{ fetch: f, scheduled: s, email: e }` —
  fetch and scheduled get wrapped; email is left untouched (email
  handler wrapping is future scope).
- TypeScript `satisfies ExportedHandler<Env>` clause — preserved
  verbatim; the wrap happens on the object literal contents.

**Fixture pair** (lives at
`migrations/test-fixtures/init-ts-cloudflare-worker/{before,expected-after}/`):
- `before/`: minimal Worker with `wrangler.toml`, `package.json`,
  `src/index.ts` exporting `{ fetch, scheduled }`, empty `CLAUDE.md`.
- `expected-after/`: same files plus wrapper at
  `src/lib/observability/{index.ts, middleware.ts, policy.md}`,
  rewritten `src/index.ts` with anchored imports + anchored default
  export, and `CLAUDE.md` with the observability block.

#### Phase 5 detail — `ts-cloudflare-pages`

Pages Functions use a fundamentally different mount pattern from
Workers: Cloudflare Pages auto-loads `functions/_middleware.ts` (and any
per-folder `_middleware.ts`) and runs it before any matching
`onRequest*` handler in the same subtree. The `_middleware.ts` file IS
the middleware mount; route files do not need to be wrapped.

**Phase 5 for `ts-cloudflare-pages` is a no-op for route files.** This
is intentional and load-bearing — touching `onRequest*` exports would
duplicate instrumentation that Pages's runtime already wires via the
auto-loaded middleware.

The materialisation work for this stack happens in Phase 4. Per
`templates/ts-cloudflare-pages/meta.yaml`, Phase 4 writes three files:

| Target | Source template |
|--------|-----------------|
| `functions/_lib/observability/index.ts` | wrapper (same shape as Worker's `lib-observability.ts` after token substitution; the `meta.yaml` declares `inherits_wrapper_from: ts-cloudflare-worker`) |
| `functions/_middleware.ts` | `templates/ts-cloudflare-pages/_middleware.ts` copied verbatim, with `{{ENV_VAR_*}}` substitutions applied |
| `functions/_lib/observability/policy.md` | per-stack policy.md (see T10) |

**Phase 5 procedure for this stack**

1. Scan for an existing `functions/_middleware.ts` at the project root.
2. If **none exists**: the file materialised in Phase 4 IS the entry.
   No additional rewrite. Phase 5 prints "Entry: `functions/_middleware.ts`
   (mount-point; auto-loaded by Pages runtime — no per-route wrap needed)"
   and moves on to Phase 6.
3. If **one already exists**: do NOT overwrite. Print:

   ```
   Existing functions/_middleware.ts found.

   This stack uses the mount-point pattern — Pages auto-loads
   _middleware.ts before any matching onRequest* handler. Two
   middlewares cannot coexist at the same path; manual merge is
   required.

   Suggested merge: copy the AgenticApps observability shape from
   add-observability/templates/ts-cloudflare-pages/_middleware.ts
   (which runs init(), parses traceparent, calls context.next(), and
   echoes traceparent on the response) and chain your existing
   middleware logic INSIDE the runWithContext(...) callback before
   `await context.next()`. See Pages Functions docs on
   `onRequest`-as-array if you need to express the chain as a list.

   The Phase 4 wrapper (functions/_lib/observability/index.ts) and
   policy.md are already in place; only the mount file needs your
   merge.
   ```

   Then treat this stack as a **gate-2 decline** (Phase 5 decline path
   above): print the rollback hint and skip Phase 6 for this stack. The
   user either resolves the merge manually and re-runs init, or
   accepts the partial scaffold.

**Route files are NOT touched.** Functions under `functions/api/`,
`functions/_health/`, etc. with `onRequest`, `onRequestGet`,
`onRequestPost` exports remain untouched. The middleware intercepts
all matching requests via Pages's runtime — no per-route wrap is
needed or correct here.

**Edge cases — explicitly out of scope at v0.3.1:**

- **Per-folder `_middleware.ts`** (Pages allows nested middleware at
  `functions/admin/_middleware.ts`, etc.). Init materialises only the
  root-level `functions/_middleware.ts`; nested middleware must be
  wired manually. The root middleware runs for every request under
  `functions/`, so observability coverage is complete by default —
  per-folder middleware is a refinement (e.g. for auth scoping)
  reserved for v0.4.0+.
- **Pages projects with NO `functions/` directory** — detection
  (`meta.yaml detection.must: file_exists: functions/`) fails earlier
  in Phase 1. Such projects are pure-static-site Pages deployments
  with no server-side execution; observability does not apply.

**Anchor regions** — Phase 4 wraps the materialised `_middleware.ts`
content with `// agenticapps:observability:start` / `:end` at file top
and bottom (since the entire file is generator-owned for this stack —
unlike Worker, where only the import + default-export regions are
anchored).

**Fixture pair** (lives at
`migrations/test-fixtures/init-ts-cloudflare-pages/{before,expected-after}/`):
- `before/`: minimal Pages project with `wrangler.toml`,
  `package.json`, a route file at `functions/api/[[path]].ts`
  containing `onRequest` + `onRequestPost` exports, **no
  pre-existing `functions/_middleware.ts`**, and a `CLAUDE.md` stub.
- `expected-after/`: same files plus wrapper at
  `functions/_lib/observability/{index.ts, policy.md}`, the
  materialised `functions/_middleware.ts` mount (anchor-wrapped),
  the route file `functions/api/[[path]].ts` **byte-identical to
  `before/`** (the load-bearing assertion for this stack), and
  `CLAUDE.md` with the observability block whose `policy:` points at
  `functions/_lib/observability/policy.md`.

#### Phase 5 detail — `ts-supabase-edge`

Supabase Edge Functions run on Deno. Each function lives at
`supabase/functions/<name>/index.ts` and starts with a `Deno.serve(...)`
call. There is no per-project middleware hook — each function
independently wraps its handler with `withObservability(handler)` from
the shared module at `supabase/functions/_shared/observability/`.

**Import source** — `withObservability` is exported from
`middleware.ts`, NOT `index.ts`. Per
`templates/ts-supabase-edge/middleware.ts:4-12`, the canonical import
shape is:

```typescript
import { withObservability } from "../_shared/observability/middleware.ts"
```

`index.ts` is the wrapper module itself (re-exports the underlying
trace context + capture primitives); `middleware.ts` is where the
`withObservability` factory lives. Getting this wrong yields a runtime
import error on first deploy.

**Rewrite shape — handle BOTH `Deno.serve` signatures.** Deno's
`Deno.serve` supports two argument orders for the modern (options-first)
shape:

| Entry shape | Wrapped shape |
|-------------|---------------|
| `Deno.serve(handler)` | `Deno.serve(withObservability(handler))` |
| `Deno.serve({ port: 8000 }, handler)` | `Deno.serve({ port: 8000 }, withObservability(handler))` |
| `Deno.serve({ port, hostname }, handler)` | wrap the function-position arg regardless of which options keys appear |

**Detection rule** for the call's function-position argument:

1. Locate the first `Deno.serve(` call expression in the entry file
   (one of `entry_file_candidates` — for this stack the candidates are
   each `supabase/functions/<name>/index.ts` matching the
   `per_function_pattern.glob`).
2. Inspect the first argument:
   - If it parses as an **object literal** (starts with `{`), the
     function-position argument is the **second** argument; wrap that.
   - Otherwise, the function-position argument is the **first**
     argument; wrap that.
3. The wrap is always `withObservability(<original-arg>)` — i.e. wrap
   the function reference (named, arrow, or inline).

**Anchor regions** — TWO anchored blocks per entry file:

1. One around the inserted `import { withObservability } from
   "../_shared/observability/middleware.ts"` line at the top of the
   file (above any existing imports is fine; init places it as the
   last import).
2. One around the modified `Deno.serve(...)` call expression.

**Edge cases — explicitly out of scope at v0.3.1:**

- **Legacy `Deno.serve(handler, options)`** (handler-first,
  options-second — the deprecated Deno signature, still accepted by
  the runtime). Detection treats a non-object first argument as
  function-position, which means a project using the legacy shape
  would have its options object wrapped incorrectly. Init falls back
  to the manual-instrumentation message:

  ```
  Detected legacy Deno.serve(handler, options) signature in
  <path>. The modern signature (options-first or handler-only) is
  reserved for v0.4.0+ auto-rewrite. Phase 5 skipped for this
  function; wrap manually per
  add-observability/templates/ts-supabase-edge/env-additions.md.
  ```

  Then treat this function as a gate-2 decline (no Phase 6 write for
  this stack — see the decline contract above).
- **HTTP/2 transport options** that include a function-valued option
  (e.g. `signal`) — only the top-level `Deno.serve(...)` is parsed;
  nested option values are not inspected.

**Per-function walk** — multi-function projects have many entry files
(`supabase/functions/auth/index.ts`,
`supabase/functions/payments/index.ts`, etc.). Phase 5 walks every
`supabase/functions/*/index.ts` matching the `per_function_pattern`
(skipping `_shared/**` and `_health/**` per `meta.yaml`), shows one
unified diff per file, and prompts ONCE at the end ("Rewrite these N
entry files? [y/n]"). All-or-nothing per the gate-2 contract; partial
acceptance is not supported at v0.3.1.

**Rewrite shape — example**

Before:
```typescript
const handler = async (req: Request): Promise<Response> => {
  return new Response("ok")
}

Deno.serve(handler)
```

After:
```typescript
// agenticapps:observability:start
import { withObservability } from "../_shared/observability/middleware.ts"
// agenticapps:observability:end

const handler = async (req: Request): Promise<Response> => {
  return new Response("ok")
}

// agenticapps:observability:start
Deno.serve(withObservability(handler))
// agenticapps:observability:end
```

**Fixture pair** (lives at
`migrations/test-fixtures/init-ts-supabase-edge/{before,expected-after}/`):
- `before/`: minimal Supabase project with `supabase/config.toml`,
  `supabase/functions/hello/index.ts` containing
  `Deno.serve(handler)`, and a `CLAUDE.md` stub.
- `expected-after/`: same files plus wrapper at
  `supabase/functions/_shared/observability/{index.ts, middleware.ts,
  policy.md}`, rewritten `supabase/functions/hello/index.ts` with the
  anchored import at the top and the anchored `Deno.serve(...)` wrap,
  and `CLAUDE.md` with the observability block.

#### Phase 5 detail — `ts-react-vite`

React + Vite SPAs are browser-side: there is no HTTP middleware to
wire. Instrumentation is installed at React-root mount time via two
distinct insertions in the entry file (typically `src/main.tsx`):

1. A call to `init()` BEFORE `createRoot(...).render(...)` runs.
   `init()` installs the global `fetch` interceptor (per
   `templates/ts-react-vite/lib-observability.ts:131`: `window.fetch =
   instrumentedFetch(originalFetch)`). Without this call, §10.7
   obligation (2) "wire trace-propagation middleware" is NOT satisfied
   for browser stacks.
2. A JSX wrap of the rendered app in `<ObservabilityErrorBoundary>`.
   The boundary catches React render-time errors and forwards them to
   `captureError`.

**Canonical post-init shape** (per
`templates/ts-react-vite/env-additions.md:55-73`):

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

**There is no `ObservabilityProvider`.** Earlier drafts of this skill
referenced one; the shipped template at
`templates/ts-react-vite/ErrorBoundary.tsx` exports
`ObservabilityErrorBoundary` only. Init MUST NOT emit a `Provider`
import or JSX wrap — that would produce an import error against the
materialised wrapper.

**Wrappers materialised by Phase 4** (per
`templates/ts-react-vite/meta.yaml` `target.*`):

- `src/lib/observability/index.ts` — re-exports `init`, `captureError`,
  `startSpan`, `logEvent`, and the `ObservabilityErrorBoundary` React
  component.
- `src/lib/observability/ErrorBoundary.tsx` — the boundary
  implementation (class component with `componentDidCatch`).
- `src/lib/observability/policy.md`.

**Phase 5 produces TWO anchored regions** in the entry file:

1. **Anchored import** — around the added `import { init,
   ObservabilityErrorBoundary } from "./lib/observability"` line. The
   wrapper exports both symbols from the same module, so a single
   import line suffices.
2. **Anchored init+wrap region** — around the `init()` call AND the
   `<ObservabilityErrorBoundary>` JSX wrap of the rendered tree.

The `init()` call sits between the import block and the
`createRoot(...).render(...)` call. The `<ObservabilityErrorBoundary>`
wrap goes IMMEDIATELY around the existing top-level JSX child of
`.render(...)`:

- **`StrictMode` present** — both `init()` and the boundary go INSIDE
  `StrictMode` (the boundary wraps `<App />`, not `<StrictMode>`),
  per the canonical shape above. Rationale: `init()` is React-mount
  ordering only and is unaffected by StrictMode's
  double-invoke-in-dev; the boundary needs to be the closest ancestor
  to the app tree to catch the most errors.
- **`StrictMode` absent** — `init()` is still placed before
  `createRoot`; the boundary wraps the bare `<App />`:
  ```tsx
  createRoot(document.getElementById("root")!).render(
    <ObservabilityErrorBoundary>
      <App />
    </ObservabilityErrorBoundary>,
  )
  ```

**Entry-shape detection.** The procedure tolerates the following
naming variants for the React-DOM client API (parsed by AST or
substring match in this order):

| Order | Pattern | Receiver expression for `.render(...)` |
|-------|---------|----------------------------------------|
| 1 | `import { createRoot } from "react-dom/client"` ⇒ `createRoot(<target>)` | the `createRoot(<target>)` call |
| 2 | `import ReactDOM from "react-dom/client"; ReactDOM.createRoot(...)` | the `ReactDOM.createRoot(<target>)` call |
| 3 | `import * as ReactDOM from "react-dom/client"; ReactDOM.createRoot(...)` | same as #2 |

The anchor wrap is placed around the **argument** to `.render(...)` —
the receiver expression is irrelevant to the wrap shape.

**Edge cases handled by the procedure:**

- **Project already has an ErrorBoundary** — init inserts
  `ObservabilityErrorBoundary` as the OUTER ancestor (closer to the
  root), so it captures errors thrown by the user's inner boundary's
  fallback UI. Existing boundary code is untouched.
- **Project uses `hydrateRoot` instead of `createRoot`** (SSR-resumable
  apps) — out of scope at v0.3.1. Init prints "Detected `hydrateRoot`
  in entry file; SSR-resumable instrumentation is reserved for
  v0.4.0+. Phase 5 skipped for this stack; wrap manually per
  env-additions.md." and treats as a gate-2 decline.
- **Entry uses `ReactDOM.render` (legacy React 17)** — out of scope.
  Same fallback path as `hydrateRoot`.
- **`<App />` is wrapped in additional providers (Router, Query,
  etc.)** — the boundary is inserted INSIDE all of those, immediately
  around the app component. Rationale: providers throwing during
  setup are typically build-time errors caught by Vite; React render
  errors come from the app tree. Anchoring the boundary close to the
  app maximises useful coverage.

**Rewrite shape — example**

Before:
```tsx
import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import App from "./App"
import "./index.css"

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
```

After:
```tsx
import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
// agenticapps:observability:start
import { init, ObservabilityErrorBoundary } from "./lib/observability"
// agenticapps:observability:end
import App from "./App"
import "./index.css"

// agenticapps:observability:start
init()

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ObservabilityErrorBoundary>
      <App />
    </ObservabilityErrorBoundary>
  </StrictMode>,
)
// agenticapps:observability:end
```

**Fixture pair** (lives at
`migrations/test-fixtures/init-ts-react-vite/{before,expected-after}/`):
- `before/`: minimal Vite + React project with `package.json`,
  `vite.config.ts`, `src/main.tsx` (StrictMode + `<App />`),
  `src/App.tsx`, and a `CLAUDE.md` stub.
- `expected-after/`: same files plus wrapper at
  `src/lib/observability/{index.ts, ErrorBoundary.tsx, policy.md}`,
  rewritten `src/main.tsx` with anchored import + anchored
  `init()` + `<ObservabilityErrorBoundary>` JSX wrap (inside
  StrictMode), and `CLAUDE.md` with the observability block.

#### Phase 5 detail — `go-fly-http`

Go HTTP services use the `http.Handler` middleware pattern. The shipped
template at `templates/go-fly-http/middleware.go:38` exports
`Middleware(next http.Handler) http.Handler` — compatible with
net/http, chi, echo, gorilla/mux, and any router that accepts
`http.Handler` middleware (per template lines 33-48).

**Router detection — explicit rule.** Scan the project's Go source
files (under the module root resolved from `go.mod`) for the following
import substrings in lexical order; **first match wins**:

| Order | Import substring | Detected pattern |
|-------|------------------|------------------|
| 1 | `"github.com/go-chi/chi/v5"` or `"github.com/go-chi/chi"` | **chi** |
| 2 | `"github.com/gorilla/mux"` | **gorilla/mux** |
| 3 | (none of the above) | **std net/http** (fallback) |

**Echo, fiber, gin — explicitly out of scope at v0.3.1.** If init
detects an import for any of `"github.com/labstack/echo"`,
`"github.com/gofiber/fiber"`, or `"github.com/gin-gonic/gin"`, print:

```
Detected unsupported router (echo / fiber / gin) in <module-root>.
v0.3.1 supports auto-instrumentation for net/http, chi, and
gorilla/mux only. Other routers require manual wiring — see
add-observability/templates/go-fly-http/env-additions.md.
```

Then skip Phase 5 for this stack and treat as a gate-2 decline.

**Alias handling** — Go imports can be aliased
(e.g. `chiv5 "github.com/go-chi/chi/v5"`). The detection scans the
quoted import path, not the alias; the rewrite then uses the resolved
alias for the router constructor call (e.g. `chiv5.NewRouter()`).

**Phase 5 rewrite shape per detected pattern.** All three insert the
SAME imports at the top of the entry file:

```go
// agenticapps:observability:start
import "<MODULE_PATH>/internal/observability"
// agenticapps:observability:end
```

`MODULE_PATH` is resolved per `templates/go-fly-http/meta.yaml`
`parameters.MODULE_PATH.derive_from = "module declaration in go.mod"`.

All three also insert `observability.Init()` at the top of `main()`
(or `New()` / `NewServer()` for the `internal/server/server.go` entry
shape — first function body in the file).

The wrap site differs:

- **chi**: locate the first `chi.NewRouter()` call (or its aliased
  form). Insert `<router-var>.Use(observability.Middleware)`
  immediately AFTER the variable assignment, anchored as a single-line
  block:

  ```go
  r := chi.NewRouter()
  // agenticapps:observability:start
  r.Use(observability.Middleware)
  // agenticapps:observability:end
  ```

- **gorilla/mux**: locate the first `mux.NewRouter()` call. Same shape
  as chi — `r.Use(observability.Middleware)` immediately after, with
  anchor comments wrapping the inserted `Use` call.

- **std net/http**: locate the FIRST of
  - `http.ListenAndServe(<addr>, <handler>)` — rewrite to
    `http.ListenAndServe(<addr>, observability.Middleware(<handler>))`
    with anchor comments wrapping the rewritten call.
  - `http.Server{Handler: <handler>, ...}` (or
    `&http.Server{Handler: ..., ...}` — same shape). Rewrite the
    `Handler:` field value to
    `observability.Middleware(<handler>)`. Anchor the rewritten field
    line.

  Both shapes leave every other arg / field untouched.

**Anchor regions** — THREE anchored blocks per entry file: imports,
`observability.Init()` in `main()`, and the middleware-wrap site
(`Use` call for chi/gorilla; rewritten handler arg for std net/http).

**Edge cases handled by the procedure:**

- **Multiple routers in one entry file** (e.g. `cmd/api/main.go` boots
  both an admin router and a public router) — Phase 5 wraps only the
  FIRST router constructor call detected per the priority table. The
  second router is left unwrapped; init prints "Detected additional
  router constructor at line N; only the first is auto-wrapped at
  v0.3.1. Wrap manually if needed." (Multi-router wrapping is reserved
  for v0.4.0+.)
- **Init already present** — if `observability.Init()` already appears
  anywhere in the entry file, the procedure does not re-insert it
  (idempotency for re-runs once strict-first-run is lifted at
  v0.4.0+).
- **Custom `http.Server` constructed inside a function other than
  `main()`** (e.g. `func newServer() *http.Server`) — the
  `http.Server{Handler: ...}` rewrite happens at the literal site
  regardless of which function it's inside. `observability.Init()` is
  still inserted at the top of `main()` so the SDK is initialised
  before the server boots.

**Rewrite shapes — examples**

**chi (before):**
```go
package main

import (
  "github.com/go-chi/chi/v5"
  "net/http"
)

func main() {
  r := chi.NewRouter()
  r.Get("/", func(w http.ResponseWriter, req *http.Request) {
    w.Write([]byte("ok"))
  })
  http.ListenAndServe(":8080", r)
}
```

**chi (after):**
```go
package main

import (
  "github.com/go-chi/chi/v5"
  "net/http"
  // agenticapps:observability:start
  "example.com/fixture/internal/observability"
  // agenticapps:observability:end
)

func main() {
  // agenticapps:observability:start
  observability.Init()
  // agenticapps:observability:end

  r := chi.NewRouter()
  // agenticapps:observability:start
  r.Use(observability.Middleware)
  // agenticapps:observability:end
  r.Get("/", func(w http.ResponseWriter, req *http.Request) {
    w.Write([]byte("ok"))
  })
  http.ListenAndServe(":8080", r)
}
```

**std net/http (after):** `http.ListenAndServe` arg gets the wrap:
```go
// agenticapps:observability:start
http.ListenAndServe(":8080", observability.Middleware(mux))
// agenticapps:observability:end
```

**Fixture set** — 3 fixture pairs (one per detected pattern), each at
`migrations/test-fixtures/init-go-fly-http-<pattern>/{before,expected-after}/`
with `<pattern>` ∈ {`stdmux`, `chi`, `gorilla`}:

- `init-go-fly-http-stdmux/before/`: `go.mod`, `cmd/api/main.go` with
  `http.NewServeMux()` + `http.ListenAndServe(":8080", mux)`,
  `CLAUDE.md` stub.
- `init-go-fly-http-chi/before/`: `go.mod` with chi dep, `cmd/api/main.go`
  with `chi.NewRouter()` + `http.ListenAndServe(":8080", r)`.
- `init-go-fly-http-gorilla/before/`: `go.mod` with gorilla/mux dep,
  `cmd/api/main.go` with `mux.NewRouter()` + `http.ListenAndServe(":8080", r)`.

Each `expected-after/` shows the wrapper materialised at
`internal/observability/{observability.go, middleware.go, policy.md}`,
the entry file rewritten per the pattern's wrap shape, and `CLAUDE.md`
with the observability block whose `policy:` points at
`internal/observability/policy.md`.

### Phase 6 — Write `observability:` metadata to CLAUDE.md (consent gate 3 of 3 — CLAUDE.md)

**Prerequisite (per-stack)**: for each stack, gate 2 (Phase 5) MUST
have been accepted. Stacks in gate-2-decline state are skipped
entirely in Phase 6 — writing the metadata block while entry-file
wiring is missing would falsely claim conformance to §10.7 obligation
(2). The Phase 5 decline path establishes this rule; this prerequisite
re-states it so a future maintainer refactoring Phase 6 in isolation
preserves the cross-phase invariant.

Compute the spec §10.8 metadata block to add to CLAUDE.md. The
authoritative schema reference is
`add-observability/init/metadata-template.md` — that document is the
source of truth for field shapes, types, defaults, and the validation
contract. The procedure below describes the writer behaviour; the
template document describes the data.

**Canonical block shape** (v0.3.1 defaults):

```yaml
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: <primary-stack-wrapper-dir>/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
```

**Optional fields not emitted by default at v0.3.1:**

- `destinations: - analytics: <vendor>` — OPTIONAL per spec §10.8.
  Init omits the `analytics:` line; users who route analytics-class
  events through the wrapper add it manually.
- `enforcement.ci: <ci-workflow-path>` — OPTIONAL per spec §10.8
  line 160. Init omits this field because the current option-4 shape
  ships no auto-installed CI workflow (per PLAN T11 + the
  metadata-template.md reference). Users who wire a CI gate manually
  MAY add `ci: .github/workflows/observability.yml` (or the
  host-specific equivalent) post-init. The spec uses this field's
  presence to flag projects that have a CI gate; absence does NOT
  block migrations or scan.

**Schema constraint (v0.3.1)**: the `policy:` field is a **scalar
string path**, per spec §10.8 line 157 AND per migration 0011's
POLICY_PATH parser at `migrations/0011-observability-enforcement.md:63`
which extracts the value with `awk '{print $2; exit}'`. A multi-stack
project ships the **primary stack's** policy.md path here (primary =
first stack in lexicographic detection order). Other stacks' policy.md
files are still materialised by Phase 4 but are not referenced from
CLAUDE.md. Per-stack policy unification awaits a spec amendment.

If multi-stack, before showing the diff, print:

```
Multi-stack project detected (<stack-1>, <stack-2>, ...). The
`observability:` block's `policy:` field is scalar for v0.3.1 per spec
§10.8. Primary stack `<stack-1>`'s policy path is recorded. Other
stacks' policy.md files are materialised but not referenced from
CLAUDE.md. Per-stack policy unification awaits a spec amendment.
```

#### Add vs update vs conflict — pre-existing state detection

Before computing the diff, inspect the project's CLAUDE.md to decide
which of three paths to take. The detection logic is encoded in
`metadata-template.md` ("Add vs update vs conflict — detection paths"
section); summary:

| Pre-existing state | Path |
|--------------------|------|
| Neither anchors nor `^observability:` line present | **Add** — append the block at end of file, anchored |
| Anchor pair present AND `observability:` block inside | **Update** — replace the anchored region's body; preserve surrounding hand-written content |
| `^observability:` line present BUT no anchor pair around it | **Conflict** — print manual-merge hint; treat as gate-3 decline |

Detection commands:

```bash
HAS_ANCHORS=$(grep -c 'agenticapps:observability:start' CLAUDE.md || true)
HAS_OBS_KEY=$(grep -c '^observability:' CLAUDE.md || true)

case "$HAS_ANCHORS:$HAS_OBS_KEY" in
  0:0) MODE=add ;;
  1:*) MODE=update ;;        # anchor pair present
  0:*) MODE=conflict ;;       # unanchored observability: key
esac
```

(At v0.3.1's strict-first-run, the update path is rare — wrapper
strict-first-run typically intercepts earlier in Phase 2 — but the
metadata block can be out of date even when wrappers are valid, e.g.
after a spec_version bump. The update path is documented here so
init has a defined behaviour when it does fire.)

#### Anchor markers

Wrap the block insertion with anchor markers
`<!-- agenticapps:observability:start -->` /
`<!-- agenticapps:observability:end -->` so future updates / removals
can target the anchored region without disturbing surrounding
hand-written CLAUDE.md content.

#### Consent prompt (add or update paths)

```
About to <add | update> the observability: metadata block in CLAUDE.md.

  <unified diff>

<Add | Update> this block? [y/n]
```

#### Conflict path (unanchored existing block)

Phase 6 does NOT auto-overwrite a hand-written `observability:` block
that lacks anchor markers — that would silently destroy user-tuned
values (e.g. a custom `policy:` path, an `analytics:` destination init
wouldn't add). Print:

```
CLAUDE.md already declares an `observability:` block, but it is
not wrapped in `<!-- agenticapps:observability:start -->` /
`<!-- agenticapps:observability:end -->` anchor markers. Init will
NOT overwrite hand-curated metadata blindly.

To resolve:
  1. Verify the existing block satisfies the §10.8 schema (see
     add-observability/init/metadata-template.md for the canonical
     shape).
  2. Wrap the block with the anchor comments above and below.
  3. Re-run `/add-observability init` — Phase 6 will then detect
     the anchored block and switch to the update path.

Phase 6 is being skipped. The wrapper and entry-file scaffolding
from Phases 4-5 remain in place; only the metadata-block update is
blocked.
```

Treat as a gate-3 decline (use the decline path below, with the
conflict notice prepended). Wrapper + entry-file rewrites stay; only
the metadata write is skipped.

#### Decline path (gate 3 decline)

Reached either by user typing `n` at the consent prompt or by the
conflict path above. Print:

```
CLAUDE.md observability block not added.

WARNING: The wrapper and entry-file scaffolding is in place, but
the project's CLAUDE.md does not declare an observability:
block. Migration 0011's pre-flight (running
/update-agenticapps-workflow when on workflow v1.9.3) will fail
until either:
  - you add the block manually (see add-observability/init/metadata-template.md
    for the canonical shape), OR
  - you re-run /add-observability init and accept this gate.

The wrapper and entry-file changes from Phases 4-5 are NOT rolled
back automatically — they remain functional. Only the metadata
contract is incomplete.
```

Exit cleanly with code 0. Do NOT auto-roll-back Phases 4-5 (the
wrapper + entry rewrite are valid even without the metadata block;
only the upgrade path is blocked).

#### Post-write validation

After accepting and writing the block, Phase 6 runs the canonical
0011 POLICY_PATH parser invocation as a self-check before handing
off to Phase 7. This is the same parser migration 0011 uses to read
the project's policy path during its pre-flight, so passing here
guarantees 0011 will accept the block at next upgrade:

```bash
# Self-check: extract policy: value via the 0011 parser; assert
# it's a non-empty single-token scalar string.
POLICY_PATH=$(awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}' CLAUDE.md | tr -d '"')
[ -n "$POLICY_PATH" ] || { echo "ABORT: post-write parser check failed — policy: did not extract"; exit 1; }
echo "$POLICY_PATH" | grep -qE '^[^[:space:]]+$' || { echo "ABORT: post-write parser check failed — policy: is not a scalar single-token path"; exit 1; }
```

If either assertion fails, Phase 6 reports the failure and exits
with code 1. This is a defence-in-depth check against the writer
emitting a list-shape or quoted-with-whitespace `policy:` value
that would silently break 0011's pre-flight. Phase 9 re-runs the
same parser as part of the full structural-assertion gate before
init's final exit.

### Phase 7 — Smoke verification

For each materialised stack, run a language-native syntax check
against the materialised wrapper:

- **TypeScript**: `npx tsc --noEmit` (if tsconfig present)
- **Go**: `go build ./...`
- **Deno** (Supabase): `deno check <wrapper-path>`

If any check fails, **report but do not auto-fix**. The user reviews
the failure and decides whether to apply a fix manually or revert.
Phase 7 is read-only.

Print:

```
Smoke verification: <PASS | FAIL>
  <stack-1>: <PASS | FAIL — see <check output>>
  <stack-2>: <PASS | FAIL — see <check output>>
```

### Phase 8 — Print summary + chain hint

Summary:

```
Init complete.

<N> stacks scaffolded:
  <stack-1>: wrapper at <path>, middleware at <path>, entry-file <path> rewritten
  <stack-2>: ...

Files created:
  <count> new files
Entry files rewritten:
  <count>
CLAUDE.md observability: block <added | not added — gate 3 declined>
```

**Chain hint (RESEARCH D7)** — if a `.scan-report.md` file exists at
the project root, print:

```
Note: A pre-init scan-report (.scan-report.md) was found at the
project root. Its findings reference the pre-init code shape and are
now stale. Re-run /add-observability scan to refresh.
```

### Phase 9 — Verification before exit

Final structural assertions. Each MUST hold for init to exit code 0:

```bash
# All wrapper paths exist and have no unfilled tokens
for stack in <detected-stacks>; do
  test -f <stack>/<target.wrapper_path> || exit 1
  ! grep -q '{{[A-Z_]\+}}' <stack>/<target.wrapper_path> || exit 1
done

# Entry-file anchor blocks parse (anchor pair present + balanced)
for entry in <entry-files>; do
  start=$(grep -c 'agenticapps:observability:start' "$entry")
  end=$(grep -c 'agenticapps:observability:end' "$entry")
  test "$start" -eq "$end" || exit 1
done

# CLAUDE.md observability block validates against §10.8 schema (only
# checked if gate 3 was accepted)
if [ "$GATE_3_ACCEPTED" = "true" ]; then
  awk '/<!-- agenticapps:observability:start -->/,/<!-- agenticapps:observability:end -->/' CLAUDE.md \
    | grep -qE '^observability:' \
    && awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}' CLAUDE.md \
       | grep -qE '^[^ ]+$'   # scalar policy: value
  test $? -eq 0 || exit 1
fi
```

If any assertion fails, print the failing assertion and exit with code 1.

## Important rules

- **Strict first-run only at v0.3.1.** Never run if any stack's
  wrapper directory already exists (per Phase 2 strict-first-run
  check). `--force` is reserved for v0.4.0+.
- **Anchor comments are load-bearing.** Never edit content inside
  `// agenticapps:observability:start` / `:end` blocks by hand. That
  region is an init-rewrite-only zone — manual edits will be silently
  overwritten on re-init.
- **Anchor-comment threat model: fail-safe, not bypass-safe.** The
  anchor pair serves two roles — idempotent re-detection in Phase 2
  and block boundary in Phase 6. A malicious contributor who injects
  anchor comments around unrelated code in the wrapper directory or
  CLAUDE.md does NOT achieve silent conformance bypass: Phase 2's
  strict-first-run refuses to proceed (exit 1, "already initialised"),
  Phase 6's POLICY_PATH self-check rejects mal-shaped blocks (exit 1),
  and `add-observability scan` walks files independently of anchor
  presence. The worst an attacker achieves is denial-of-init, which
  surfaces to the user instead of silently masking gaps. Future
  refactors MUST preserve this fail-safe stance — do NOT relax the
  Phase 2 strict-first-run or the Phase 6 self-check under "improve UX
  of re-init" pressure. See `.planning/phases/15-init-and-slash-discovery/REVIEW.md`
  S2 for the full threat assessment.
- **`policy:` in CLAUDE.md is scalar at v0.3.1.** Multi-stack projects
  ship the primary stack's policy.md path only. Materialised per-stack
  policy.md files exist on disk but are not referenced from the
  observability metadata block. Spec amendment pending.
- **Consent decline NEVER produces false conformance.** A declined
  gate-2 (entry-file) MUST skip gate-3 (CLAUDE.md). A declined gate-3
  warns the user that migration 0011 pre-flight will block future
  workflow upgrades — but does NOT roll back Phases 4-5.
- **Parameter substitution uses `{{NAME}}` tokens.** Missing values
  with no `derive_from` and no `default` are errors, not warnings.

## Verification before exiting

Per Phase 9. Init exits with code 0 if and only if every structural
assertion holds. Any failure → exit code 1 + the failing assertion
printed.

## References

- Spec §10.7 (generator obligations): `agenticapps-workflow-core/spec/10-observability.md`
- Spec §10.7.1 (module-root path resolution): same file
- Spec §10.8 (project metadata): same file (scalar `policy:` at line 157)
- Migration 0011 POLICY_PATH parser: `migrations/0011-observability-enforcement.md:63`
- Phase plan: `.planning/phases/15-init-and-slash-discovery/PLAN.md`
- RESEARCH decisions (D2 hybrid consent, D3 walk-all, D4 per-stack
  policy, D5 strict first-run, D6 anchor comments, D7 chain hint):
  `.planning/phases/15-init-and-slash-discovery/RESEARCH.md`
- Per-stack rewrite shapes: T5-T9 of PLAN.md (each task appends its
  subsection to this file's Phase 5).
- Per-stack templates: `add-observability/templates/<stack-id>/`
- Sibling subcommands: `../scan/SCAN.md`, `../scan-apply/APPLY.md`
