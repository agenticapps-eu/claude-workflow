# Per-language detection patterns

Concrete patterns the scan procedure uses to find candidate sites for
each checklist item (C1-C4). Patterns favor `Grep` (ripgrep) since the
scan skill drives Claude Code's tools; AST-aware refinement happens by
having you (the agent) `Read` the candidate file's surrounding lines
and apply judgment.

For each pattern, "False-positive risk" describes when to downgrade
confidence after inspection.

---

## C1 — Handler entry

### Go

**Grep patterns** (run from the module root):

```regex
# Std http handler signature
func\s+\w+\s*\(\s*\w+\s+http\.ResponseWriter\s*,\s*\w+\s+\*http\.Request\s*\)

# Chi router registrations
r\.(Get|Post|Put|Patch|Delete|Method)\s*\(\s*"[^"]+"

# Std mux registrations
mux\.HandleFunc\s*\(

# Method receivers that look like handlers
func\s+\(\w+\s+\*?\w+\)\s+\w+\s*\(\s*\w+\s+http\.ResponseWriter
```

**File globs**: `**/*.go`, excluding `**/*_test.go`, `**/vendor/**`.

**Surrounding-context check**:

- If the file imports `github.com/agenticapps/.../observability` AND the
  handler's first non-trivial line is `observability.StartSpan(...)` or
  the handler is registered under a chi router that uses `observability.Middleware`,
  the site is conformant.
- If `chimw.Recoverer` and `observability.Middleware` BOTH appear in
  the same `r.Use(...)` chain near the router setup, all chi-registered
  handlers in that file (and its imported handler packages) are
  conformant by middleware coverage.

**False-positive risk**: handler functions in test helpers (`*_test_helpers.go`)
that look like handlers but are scaffolding. Use the `_test_helpers`,
`testdata`, `testfixture` filename heuristic to skip.

### TypeScript (Cloudflare Worker)

**Grep patterns**:

```regex
# Default-export fetch handler
export\s+default\s+\{\s*async?\s+fetch\s*\(

# Hono/Express-style route registration
app\.(get|post|put|patch|delete|all)\s*\(\s*['"`]

# Itty-router pattern
router\.(get|post|put|patch|delete|all)\s*\(

# Worker addEventListener
addEventListener\s*\(\s*['"`]fetch['"`]
```

**File globs**: `**/*.ts`, `**/*.tsx`, excluding `**/*.test.ts`,
`**/node_modules/**`, `**/dist/**`.

**Surrounding-context check**: if the file or any imported entry-point
file calls `withObservability(handler)`, treat handlers as covered.

### TypeScript (Cloudflare Pages)

**Grep patterns**:

```regex
# PagesFunction handler exports
export\s+const\s+(onRequest|onRequestGet|onRequestPost|onRequestPut|onRequestPatch|onRequestDelete)\s*[:=]
```

**File globs**: `functions/**/*.ts`, excluding `functions/**/*.test.ts`,
`functions/_lib/**`, `functions/_middleware.ts` itself.

**Surrounding-context check**: the presence of `functions/_middleware.ts`
that exports `onRequest` and is the AgenticApps observability middleware
(grep for `runWithContext` import) covers ALL Pages Functions in the
project. If that file exists, treat all Function handlers as conformant.

### TypeScript (Supabase Edge)

**Grep patterns**:

```regex
# Deno.serve handler argument
Deno\.serve\s*\(
```

**File globs**: `supabase/functions/*/index.ts`, excluding `supabase/functions/_shared/**`,
`supabase/functions/_health/**`.

**Surrounding-context check**: if the `Deno.serve(...)` argument is
`withObservability(handler)`, conformant.

### TypeScript (React/Vite)

C1 does NOT apply to frontend. Skip silently.

---

## C2 — Outbound call without traceparent

### Go

**Grep patterns**:

```regex
# Bare http.Client literal
&http\.Client\s*\{

# DefaultClient usage
http\.(Get|Post|PostForm|Head|Do)\s*\(

# pgxpool / pgx for DB connections
pgxpool\.(New|NewWithConfig)\s*\(
pgx\.(Connect|ConnectConfig)\s*\(
```

**Surrounding-context check** (the v0.2.1 composition rule):

For each `&http.Client{` or transport assignment:

1. Read the surrounding 5-10 lines to find `Transport:` field.
2. If `Transport` is set to a value that calls `observability.NewTracingTransport(...)` somewhere in the chain, conformant.
3. If `Transport` is set to a custom transport WITHOUT `NewTracingTransport` composition, **high-confidence gap** — propose composing.
4. If `Transport` is unset (uses `http.DefaultTransport`) AND `http.DefaultClient.Transport` was wrapped at main(), conformant by default.
5. If `Transport` is unset and `http.DefaultClient.Transport` is NOT wrapped at main(), **high-confidence gap** — propose either wrapping `DefaultClient.Transport` at boot or wrapping per-client.

For `http.DefaultClient.Transport` assignment in `cmd/*/main.go`:

- If present and calls `observability.NewTracingTransport(...)`, conformant.
- If absent, **high-confidence gap** at top of `main.go`.

For `pgxpool.New(...)`: low-confidence, deferred to v0.3.0.

### TypeScript

**Grep patterns**:

```regex
# Direct fetch
\bfetch\s*\(

# axios
axios\.(get|post|put|patch|delete|create|request)\s*\(
import\s+axios

# ofetch / ky / undici clients
import\s+\{[^}]*ofetch[^}]*\}\s+from\s+['"]ofetch['"]
new\s+(Ofetch|HTTPClient|Got)\s*\(
```

**Surrounding-context check**:

- If a file or its imported boot file calls
  `globalThis.fetch = instrumentedFetch(globalThis.fetch)` (or its
  equivalent), all `fetch(...)` calls in the project are covered.
- Per-client transport wrapping (axios interceptors etc.) needs
  per-client review.

### Deno (Supabase Edge)

Same patterns as TypeScript above. Note that Edge Functions don't have
a single boot point that wraps `globalThis.fetch` — each function's
`withObservability(handler)` does the binding inside its scope. Outbound
fetch INSIDE the wrapped handler is covered; outbound fetch BEFORE the
wrap (e.g. at module top-level) is not.

---

## C3 — Caught error without `captureError`

### Go

**Grep patterns**:

```regex
# Standard error check
if\s+err\s*!=\s*nil\s*\{

# Errgroup callback returning error
errgroup\.Group\.Go\s*\(

# Defer recover patterns
defer\s+func\s*\(\s*\)\s*\{[^}]*recover\s*\(\s*\)
```

**For each `if err != nil` finding**:

1. Read the body of the `if` block.
2. Determine if `err` matches a trivial-error pattern (`pgx.ErrNoRows`,
   `errors.Is(err, sql.ErrNoRows)`, `errors.Is(err, context.Canceled)`,
   `errors.Is(err, context.DeadlineExceeded)`, project's `policy.md`
   trivial list).
3. If trivial AND the body either returns the error to a caller OR
   returns an HTTP 4xx response, conformant.
4. If non-trivial AND the body does NOT call `observability.CaptureError(...)`,
   **high-confidence gap**.

### TypeScript / Deno

**Grep patterns**:

```regex
# try/catch
try\s*\{[\s\S]*?\}\s*catch\s*\(\s*\w+

# Promise .catch
\.catch\s*\(\s*\(?\s*\w+

# React error boundary lifecycle
componentDidCatch\s*\(
```

**For each catch / `.catch` finding**:

1. Read the catch body.
2. If the body calls `captureError(err, ...)` or rethrows after a
   `captureError`, conformant.
3. If the body throws a typed app error (e.g. `BadRequestError`,
   `NotFoundError`) that the framework converts to a 4xx, conformant by
   trivial-error policy.
4. Otherwise, **high-confidence gap**.

---

## C4 — Business event (heuristic)

### Naming patterns (any language)

```regex
# Function declarations
function\s+(create|submit|update|delete|pay|signup|signUp|auth|login|logout|subscribe|cancel|promote|invite)\w*

# Method declarations
\b(Create|Submit|Update|Delete|Pay|Signup|SignUp|Auth|Login|Logout|Subscribe|Cancel|Promote|Invite)\w*\s*\(

# Go method receivers
func\s+\(\w+\s+\*?\w+\)\s+(Create|Submit|Pay|Signup|Auth|Login|Subscribe|Cancel|Promote|Invite)\w*\s*\(

# Route handlers (HTTP methods + meaningful paths)
r\.(Post|Put|Patch)\s*\(\s*['"`][^'"`]*?(submit|signup|pay|invite|interest|promote|cancel)
```

**For each match**:

1. Read the function body to confirm it does business-state-changing
   work (writes to DB, calls external API, mutates user/case state).
2. Check whether `logEvent(...)` / `LogEvent(...)` is called anywhere
   in the body with a snake_case `event` name that plausibly
   corresponds to the function's purpose.
3. If yes, conformant.
4. If no, **medium-confidence finding** — propose adding a
   `LogEvent(ctx, Envelope{Event: "<derived_name>", Severity: "info", Attrs: {...}})`
   call near the success path.

### Project-specific extensions

Read `<wrapper-dir>/policy.md` for project-specific event-name
patterns. cparx, fx-signals, and similar projects MAY extend this list
in their own policy file; the scanner reads and applies them.

---

## Cross-cutting skip rules

For every checklist:

- Skip files in `**/node_modules/**`, `**/vendor/**`, `**/.git/**`,
  `**/dist/**`, `**/build/**`, `**/.next/**`, `**/.nuxt/**`,
  `**/.svelte-kit/**`, `**/coverage/**`.
- Skip generated code (`*_generated.go`, `*.gen.ts`, anything matching
  `// Code generated .* DO NOT EDIT.` in the header).
- Skip test files unless explicitly requested.
- Skip the wrapper module itself (`<wrapper-dir>/**`) — it IS the
  observability primitives, instrumenting it would be circular.

## Confidence demotion rules

After a high-confidence gap is identified, demote to medium if:

- The file is in a directory matching `internal/test*`, `testing/`,
  `e2e/`, `fixtures/`.
- The function is unexported (lowercase first letter in Go, `_`-prefix
  in TS) AND only called from tests or other internal helpers.
- The handler is registered under a sub-router that has its own
  `observability.Middleware` `Use(...)` (i.e. covered by middleware).

Demote to low if:

- The file's last modification timestamp is more than 12 months old
  AND the gap is not in a security-sensitive surface (auth, payments).
  Rationale: stale code rarely needs retroactive instrumentation.
