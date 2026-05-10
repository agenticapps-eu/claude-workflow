# Scan checklist — C1 through C4

Machine-readable encoding of AgenticApps spec §10.4 (mandatory
instrumentation points). The scan procedure (`scan/SCAN.md`) reads this
file to classify findings.

Each item has:
- **Spec citation** — pointer to §10.x of the core spec.
- **Languages** — which stacks the rule applies to.
- **Detection** — what the scanner looks for.
- **Conformance signal** — what makes a found site conformant.
- **Confidence** — how mechanical the rule is; drives the gap-rank.

---

## C1 — Handler entry

**Spec**: §10.4 #1
**Languages**: typescript, go, deno
**Applies to**: HTTP handlers, fetch handlers, edge function entry
points, scheduled task entry points, queue consumer entry points.

**Detection**:

- **Go**: function with signature `func(http.ResponseWriter, *http.Request)`,
  OR registered via `mux.HandleFunc(...)`, OR a `func(w, r)` argument
  position to chi `Get/Post/Put/Patch/Delete/Method`, OR a `Handler`
  method on a handler struct.
- **TypeScript (Cloudflare Worker)**: `export default { fetch }` shape,
  OR `addEventListener("fetch", ...)`, OR Hono/Express/Itty route handlers.
- **TypeScript (Cloudflare Pages)**: any export named `onRequest`,
  `onRequestGet`, `onRequestPost`, `onRequestPut`, `onRequestPatch`,
  `onRequestDelete`.
- **TypeScript (Supabase Edge)**: argument to `Deno.serve(...)`.
- **TypeScript (React/Vite)**: NOT applicable — frontend has no
  "handler" concept. Use route loaders or user-action handlers as
  proxies if needed; not enforced as C1.

**Conformance signal**:

- The handler's body is wrapped by middleware (e.g. `chimw.Use(observability.Middleware)`),
  OR the handler explicitly calls `startSpan(...)` / `StartSpan(...)`
  in its first non-trivial statement,
  OR the handler is wrapped by `withObservability(handler)`.

**Confidence**: **high** (every handler MUST start a span per §10.4 #1).

**Skip conditions**:
- Health-check endpoints (`/health`, `/ready`, `/_health`) — explicitly
  noted as low-cost and frequently called; instrumenting them inflates
  the event volume without value. Treat as conformant by exception.
- Test handlers in `*_test.go` / `*.test.ts`.

---

## C2 — Outbound call without traceparent propagation

**Spec**: §10.4 #2 + §10.3
**Languages**: typescript, go, deno
**Applies to**: outbound HTTP, RPC, or cross-service database calls.

**Detection**:

- **Go**:
  - `&http.Client{...}` literal where `Transport` is not wrapped in `observability.NewTracingTransport(...)`.
  - `http.Get(...)`, `http.Post(...)`, `http.PostForm(...)` — these use `http.DefaultClient`, which the wrapper expects to be transport-wrapped at boot.
  - `pgx.Connect(...)`, `pgxpool.New(...)` — DB connections crossing service boundaries; trace propagation here is OPTIONAL today (deferred to v0.3.0). Note as low-confidence.

- **TypeScript (any runtime)**:
  - `fetch(...)` calls in code that doesn't run after `globalThis.fetch = instrumentedFetch(globalThis.fetch)`.
  - `axios.create(...)`, `ofetch.create(...)`, custom HTTP client factories where the request interceptor isn't `traceparent`-aware.

**Conformance signal — high-confidence (v0.2.1 transport-composition rule)**:

When the existing code has a custom transport / interceptor / wrapper:

- **Go**: `cfg.HTTPClient = &http.Client{Transport: someCustomTransport}` is non-conformant.
  Conformant form: `cfg.HTTPClient = &http.Client{Transport: observability.NewTracingTransport(someCustomTransport)}`.
  The conformance signal is the **composition** of `NewTracingTransport` with the existing transport, NOT replacement.
- **TypeScript**: similarly, an axios `request.use(interceptor)` chain that includes a `traceparent`-setting interceptor satisfies the rule.

When no custom transport is present:

- The conformance signal is the bare wrap: `observability.NewTracingTransport(http.DefaultTransport)` for Go, or `instrumentedFetch(globalThis.fetch)` for TS.

**Confidence**:
- **high** when the call is cross-service (calls into Supabase REST, OpenRouter, third-party APIs by URL match against a known list).
- **medium** when the call is in-process or test-scope (e.g. internal `httptest.Server` calls, ngrok dev tunnels).
- **low** for database driver instantiations; deferred to v0.3.0.

**Skip conditions**:
- Test files (`*_test.go`, `*.test.ts`).
- Anything inside `node_modules/`, `vendor/`.

---

## C3 — Caught error without `captureError`

**Spec**: §10.4 #3
**Languages**: typescript, go, deno
**Applies to**: error-handling sites that handle a non-trivial error.

**Detection**:

- **Go**:
  - `if err != nil { ... }` blocks where the body does NOT call `observability.CaptureError(...)`.
  - `defer func() { if r := recover(); r != nil { ... } }()` blocks that don't capture.
  - `errgroup.Group.Go(...)` callbacks returning `error`.

- **TypeScript / Deno**:
  - `try { ... } catch (err) { ... }` where the catch body doesn't call `captureError(err, ...)`.
  - `.catch(err => ...)` Promise tails ditto.
  - React `componentDidCatch` lifecycle (the spec template provides
    `ObservabilityErrorBoundary`; non-conformant if a project rolls its
    own boundary without delegating to `captureError`).

**Trivial-error escape hatch (per `policy.md` § "Trivial errors")**:

The following error shapes do NOT require `captureError`:

- **Go**: `pgx.ErrNoRows`, `sql.ErrNoRows`, `context.Canceled`, `context.DeadlineExceeded`.
- **HTTP-handler-bound 4xx returns**: a handler that classifies bad
  input and returns `http.StatusBadRequest` / `http.StatusNotFound` /
  `http.StatusUnprocessableEntity` is conformant if the error is the
  cause of the 4xx response and the response is the only externally
  visible effect.
- Project-specific entries listed in `policy.md` § "Trivial errors".

**Conformance signal**:

- A call to `captureError(...)` / `CaptureError(...)` inside the error
  branch, OR
- The error matches the trivial-error list and is rethrown / returned
  as a 4xx without further side effects.

**Confidence**: **high** for non-trivial; trivial-list matches are
conformant.

---

## C4 — Business event without `logEvent` (heuristic)

**Spec**: §10.4 #4
**Languages**: typescript, go, deno

**Detection (naming heuristic)**:

Function or method names matching any of these patterns are flagged as
probable business events:

- `*Created` / `Create*`
- `*Submitted` / `Submit*`
- `*Updated` / `Update*` (only in handlers, not in CRUD utilities)
- `*Deleted` / `Delete*`
- `pay*` / `Pay*` / `*Payment*`
- `signup*` / `Signup*` / `*SignUp*`
- `auth*` / `*Login*` / `*Logout*`
- `subscribe*` / `Subscribe*`
- `cancel*` / `Cancel*` (in subscription contexts)
- `promote*` / `*Promote*` (in privilege-elevation contexts)
- `invite*` / `Invite*`
- `interest*` / `Interest*` (cparx-specific; project-extensible)

**Detection (route heuristic)**:

For HTTP handlers, the route pattern can also signal: `POST /api/auth/signup/*`,
`POST /api/cases/*/submit`, `PUT /api/.../interest`, `POST /api/admin/*`.

**Conformance signal**:

- A call to `logEvent(...)` / `LogEvent(...)` within the function body
  whose `event` field matches a name in the project's
  `docs/observability-events.md` enumeration (or, if no enumeration
  exists, any snake_case event name with severity `info` or higher).

**Confidence**: **medium** (heuristic — naming is signal, not proof).
The user reviews and confirms before `scan-apply` writes them.

**Skip conditions**:

- Functions in `*_test.go` / `*.test.ts`.
- Generated code (sqlc-generated, codegen output).
- Internal utilities that LOOK business-event-shaped but are
  building-blocks (e.g. `createTimer`, `submitToQueue` for an internal
  queue). Use code-context judgment; ask the user when ambiguous.

---

## Confidence-rank summary

| Confidence | Auto-apply? | Examples |
|---|---|---|
| high | yes (with consent per file) | Handler with no span; outbound call with no traceparent (cross-service); non-trivial caught error with no captureError |
| medium | review only | Probable business event by naming heuristic |
| low | suggestion only | DB driver call (deferred to v0.3.0); ambiguous business-event candidates |

The `scan-apply` subcommand defaults to `--confidence high`; users opt
into medium/low explicitly.
