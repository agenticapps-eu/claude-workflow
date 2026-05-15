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

### Phase 6 — Write `observability:` metadata to CLAUDE.md (consent gate 3 of 3 — CLAUDE.md)

Compute the spec §10.8 metadata block to add to CLAUDE.md:

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

Wrap the block insertion with anchor markers
`<!-- agenticapps:observability:start -->` /
`<!-- agenticapps:observability:end -->` so future updates / removals
can target the anchored region.

**Consent prompt**:

```
About to add the observability: metadata block to CLAUDE.md.

  <unified diff>

Add this block to CLAUDE.md? [y/n]
```

**Decline path (gate 3 decline)**: print:

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
