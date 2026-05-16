# Phase 15 — PLAN — Ship `init/INIT.md` + slash discovery (option A symlink) — v1.11.0

**Phase goal**: a fresh project can run `/setup-agenticapps-workflow` → `/add-observability init` → `/update-agenticapps-workflow` and land at v1.11.0 with §10.7 obligations (1) wrapper scaffolded and (2) middleware wired actually satisfied. Closes #26 (init missing) and #22 (slash-discovery) together.

**Versions**:
- Scaffolder `skill/SKILL.md`: 1.10.0 → 1.11.0.
- Skill `add-observability/SKILL.md`: 0.3.0 → 0.3.1 (patch; `implements_spec` stays 0.3.0).

**RESEARCH decisions encoded**: D1 = **A** at scaffolder-install layer (top-level symlink registered by `install.sh`; true option C — fully out of the nested scaffolder layout — is deferred to v1.12.0+ because the symlink approach delivers the same user-visible behaviour without a layout refactor; see PLAN v2 revision after 15-REVIEWS BLOCK), D2 = hybrid consent over `scaffold` / `entry-file` / `CLAUDE.md` (RESEARCH-mandated; replaces v1's `intent` / `scaffold` / `entry-file` set), D3 = walk-all + `--stack` override, D4 = per-stack `policy.md` materialisation but `policy:` field in CLAUDE.md is **scalar** for v0.3.1 (multi-stack array breaks migration 0011's POLICY_PATH parser at line 63 — defer unification to spec amendment), D5 = strict first-run, D6 = anchor-comment markers, D7 = chain hint, D8 = both migration 0012 + scaffolder setup-time.

---

## Task breakdown (atomic — one commit per task)

### Phase 1 — Scaffolder install + migration discovery wire-up (option A at scaffolder layer)

> **D1 label change (PLAN v2):** RESEARCH D1's option C ("move `add-observability/` out of the nested scaffolder layout into a sibling skill") is **deferred to v1.12.0+**. This PLAN ships **option A executed at the scaffolder-install layer**: `install.sh` registers a top-level symlink to the nested skill directory. Functionally equivalent for slash-discovery; smaller refactor; honest about what the code does. True option C remains the right long-term shape but is out of scope here.

#### T1 — Register `add-observability` as a top-level discoverable skill via `install.sh`

**Touches**: `install.sh` (existing scaffolder install entry point), `README.md` (scaffolder root, install instructions), `setup/SKILL.md` (post-clone instructions).

**Root cause (re-verified from 15-REVIEWS Q2 #2)**: `install.sh:22-28` defines a `LINKS=( "skill agentic-apps-workflow" … )` array and symlinks each pair from `$SCAFFOLDER/<subdir>` into `~/.claude/skills/<name>`. There is NO row for `add-observability`. Fresh installs that run `./install.sh` end up with `~/.claude/skills/agenticapps-workflow/` only — the nested `add-observability/` is not slash-discoverable. README and setup/SKILL.md changes alone are insufficient because `install.sh` is the actual register.

**Fix**: add ONE row to `install.sh`'s `LINKS` array:

```bash
LINKS=(
  "skill agentic-apps-workflow"
  "setup setup-agenticapps-workflow"
  "update update-agenticapps-workflow"
  "add-observability add-observability"      # NEW — closes #22 fresh-install side
)
```

`install.sh` already handles all the discovery-related plumbing for this new row:
- Lines 46-53 skip silently if the source subdir is missing (forward-compat).
- Lines 55-59 fail loud if the source has no `SKILL.md`.
- Lines 61-70 detect an existing symlink and either skip (correct target) or replace (wrong target).
- Lines 71-76 **refuse to clobber** an existing non-symlink directory at the target path — exits 1 with a clear "Inspect it; if safe to replace, run: rm -rf '$link' && rerun this script." message. This is install.sh's built-in protection for the "user previously installed something else at this path" case (15-REVIEWS Q2 #3); no new pre-flight needed in T1.

**Files touched**:
- `install.sh` — add the `"add-observability add-observability"` row to `LINKS` (lines 22-28).
- `README.md` (scaffolder root) — update install instructions to mention slash-discovery now works for `/add-observability` after running `./install.sh`. Add the slash command to the post-install summary echoed by the script (lines 92-95).
- `setup/SKILL.md` — update any documented install layout to note that `add-observability` is now slash-discoverable post-install.

**Idempotency / verification**:
- `install.sh` is itself idempotent (lines 61-70). Re-running with the new row reports "✓ already linked: add-observability → …" once the symlink exists.
- Smoke: `./install.sh && test -L ~/.claude/skills/add-observability && readlink ~/.claude/skills/add-observability | grep -q 'agenticapps/claude-workflow/add-observability'`.

**Commit**: `feat(setup): register add-observability as top-level discoverable skill (install.sh LINKS row, closes #22 fresh-install side)`

---

#### T2 — Backport slash-discovery fix to migration 0002 + add migration 0012

**Touches**: `migrations/0002-observability-spec-0.2.1.md`, `migrations/0012-slash-discovery.md` (create — note: filename matches title; no longer claims to ship INIT.md), `migrations/README.md` (chain table).

**0002 changes**: Step 1 already does the per-project install. Add a new sub-step that adds the global symlink if not already present:

```bash
# Idempotent: only create if symlink missing OR pointing elsewhere
if [ ! -L "$HOME/.claude/skills/add-observability" ]; then
  ln -sfn "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
          "$HOME/.claude/skills/add-observability"
fi
```

The per-project copy under `.claude/skills/add-observability/` remains as a project-level audit marker but is no longer the discovery path.

**Portability lint**: do NOT use `readlink -f` anywhere in 0002, 0012, or `run-tests.sh` — BSD `readlink` (macOS default) does not support `-f`. Use one-level `readlink` (which both BSD and GNU support) or `python -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' <path>` for canonical resolution.

**0012 (new migration)**: Backport the slash-discovery fix for projects already at v1.10.0 (i.e., they ran 0002 before this PR landed). **Discovery wire-up only — INIT.md ships via the scaffolder skill repo at v1.11.0, NOT via this migration** (15-REVIEWS Q3 #3).

```yaml
id: 0012
slug: slash-discovery
title: Slash-command discovery wire-up (closes #22)
from_version: 1.10.0
to_version: 1.11.0
applies_to:
  # NOTE: this migration's applies_to references a path OUTSIDE the project
  # tree (`~/.claude/skills/...`). This is novel for the migrations framework
  # (existing migrations reference project-relative paths only). The verify
  # step uses `test -L` (POSIX) so cross-platform support is fine; the
  # cross-tree path is documented here so a future maintainer doesn't take
  # it as a precedent for arbitrary host-system mutation.
  - ~/.claude/skills/add-observability (symlink — creates if missing)
  - .claude/skills/agentic-apps-workflow/SKILL.md (version bump)
requires:
  - skill: agentic-apps-workflow
    install: "(scaffolder install)"
    verify: "test -d ~/.claude/skills/agenticapps-workflow/add-observability"
```

Manifest body opens with this comment block:

> **Scope note (for future maintainers):** INIT.md is delivered via the scaffolder skill repo at v1.11.0 (T4 ships it as part of the `add-observability` skill itself). This migration's role is **discovery wire-up only** — it ensures projects already on v1.10.0 can invoke `/add-observability init` after the scaffolder updates. Issue #26 is closed by the scaffolder skill bump (T12), not by this migration.

Steps:
- **Step 1 — Install global symlink**: `ln -sfn ~/.claude/skills/agenticapps-workflow/add-observability ~/.claude/skills/add-observability`. Idempotency: `readlink` (no `-f`) returns the expected target.
- **Step 2 — Verify slash-discoverability**: `test -f ~/.claude/skills/add-observability/SKILL.md && grep -q '^name: add-observability' ~/.claude/skills/add-observability/SKILL.md` — confirms Claude Code's discovery will find it.
- **Step 3 — Bump scaffolder version**: `sed -i.bak 's/^version: 1.10.0$/version: 1.11.0/'`.

Update `migrations/README.md` chain table to add the 0012 row with a one-line title pointing at #22 only.

**Idempotency / verification**:
- Re-running 0012 reports "skipped (already applied)" on all three steps.
- New fixture coverage under `migrations/test-fixtures/0012/` (create).

**Commit**: `feat(migrations): 0002 + 0012 — slash-discovery wire-up (closes #22)`

---

#### T3 — Test fixtures for migration 0012

**Touches**: `migrations/test-fixtures/0012/` (create) + `migrations/run-tests.sh` `test_migration_0012()` stanza (new).

5 fixtures (state-comparison pattern matching 0011):

| # | Scenario | Expected |
|---|---|---|
| 01-fresh-apply | v1.10.0 project, no `~/.claude/skills/add-observability` symlink | Steps 1-3 apply; symlink present; version 1.11.0 |
| 02-idempotent-reapply | After fixture 01, re-run | All 3 step idempotency checks return 0 |
| 03-symlink-already-exists | `~/.claude/skills/add-observability` already symlinked correctly | Step 1 idempotent; rest proceeds |
| 04-symlink-wrong-target | `~/.claude/skills/add-observability` exists pointing elsewhere | **Step 1 hard-aborts with exit 1** and message `Manual intervention: existing symlink at ~/.claude/skills/add-observability points to $OTHER. Remove or move it before re-running 0012.` **NO version bump on this path** (15-REVIEWS Q3 #2 — majority resolution; Phase 14's "applied with warning" pattern does not apply because 0012 has no scaffolder-owned content to overwrite — there is nothing valid to install if the symlink is wrong) |
| 05-rollback | After fixture 01, run rollback procedure | Symlink removed; version reverted |

**Commit**: `test(migrations): 0012 fixtures (5 scenarios)`

---

### Phase 2 — Author `init/INIT.md` skeleton

#### T4 — `add-observability/init/INIT.md` skeleton with 9 phases

**Touches**: `add-observability/init/INIT.md` (create).

Skeleton structure (each phase fleshed out per-stack in subsequent tasks T5-T9):

```
# `init` subcommand procedure

## Inputs
- Project root (CWD)
- --stack <id> (optional, default: walk all detected stacks)
- --force (optional, v0.4.0+; rejected at v0.3.1)

## Outputs
- Wrapper module(s) materialised at meta.yaml `target.wrapper_path`
- Middleware materialised (where applicable per stack)
- policy.md materialised per-stack
- Entry file(s) rewritten with observability wrap + anchor comments
- `observability:` metadata block written to CLAUDE.md

## Procedure

### Phase 1 — Detect stacks
(Identical to scan/SCAN.md Phase 1; reuse the same detection rules.)

### Phase 2 — Resolve targets
For each detected stack: read meta.yaml, resolve target.* paths against
the module root (NOT project root, per spec §10.7.1), resolve parameters
per derive_from rules.

### Phase 3 — Show full plan (NOT a consent gate; informational)
Print a summary so the user knows what is about to be proposed across
the 3 consent gates that follow:
- Stacks detected: <list>
- New files to be materialised (Phase 4 — gate 1): <list>
- Entry files to be rewritten (Phase 5 — gate 2): <list>
- CLAUDE.md observability block (Phase 6 — gate 3): present | absent
No prompt here; this is "what to expect". Each subsequent phase has
its own y/n.

### Phase 4 — Materialise wrapper + middleware + policy (consent gate 1 of 3 — scaffold)
For each stack: copy template files to target paths, performing token
substitution. Anchor wrapper insertions with
`// agenticapps:observability:start` / `:end` (Go variant `//`; TS `//`;
Python `#`).
Consent: "Apply these N new files? [y/n]"
Decline ⇒ exit cleanly with summary "No files changed."

### Phase 5 — Rewrite entry file (consent gate 2 of 3 — entry-file)
For each stack with `entry_file_candidates`, scan the project for the
first matching candidate. Show unified diff for each.
Consent: "Rewrite these N entry files? [y/n]"
**Decline path**: print rollback procedure (`rm -rf` the wrapper dirs
written in Phase 4) AND exit cleanly. Do NOT proceed to Phase 6 —
writing a `observability:` block when entry-files are not wired is
false-conformance per §10.7 obligation (2). Migration 0011's pre-flight
will block any future upgrade from this state, so the user must either
roll back or re-run init with all gates accepted.

### Phase 6 — Write `observability:` metadata to CLAUDE.md (consent gate 3 of 3 — CLAUDE.md)
Per spec §10.8. Show the diff of the `observability:` block to be added
to CLAUDE.md.
Consent: "Add this block to CLAUDE.md? [y/n]"
**Decline path**: print warning "Wrapper and entry-file are wired, but
no `observability:` block is in CLAUDE.md. Migration 0011's pre-flight
will fail until you add the block manually OR re-run init and accept
gate 3." Do NOT auto-roll-back Phases 4-5 on this decline (the wrapper
+ entry rewrite are valid even without the metadata block; only the
upgrade path is blocked).
Anchor with `<!-- agenticapps:observability:start -->` / `:end`.
**Schema constraint**: `policy:` MUST be a scalar string path for v0.3.1
(see T11). Multi-stack projects ship the primary stack's policy path
only; per-stack policy unification awaits spec amendment.

### Phase 7 — Smoke verification
For each materialised stack: run a language-native syntax check
(`tsc --noEmit` / `go build` / `deno check`). If failures, report but
do not auto-fix — user reviews and applies.

### Phase 8 — Print summary + chain hint
Summary: "Init complete. <N> stacks scaffolded: <list>." Chain hint:
"If you previously ran `add-observability scan`, the report is stale;
re-run scan."

### Phase 9 — Verification before exit
Confirm wrapper files exist, parameters substituted (no
unfilled `{{...}}` tokens), entry file's anchor comments parse, CLAUDE.md
metadata block present.

## Important rules
- Never run if wrapper directory already exists (v0.3.1 strict).
- Anchor comments are load-bearing — never edit by hand outside the
  anchored block; that's an init-rewrite-only zone.
- Parameter substitution uses `{{NAME}}` tokens; missing values default
  per meta.yaml or error if no default.

## Verification before exiting
- All target.* files exist with no unfilled tokens.
- Entry file's anchor block parses.
- CLAUDE.md observability block validates against §10.8 schema.
```

**Idempotency / verification**:
- `grep -E '### Phase [1-9]' add-observability/init/INIT.md` returns 9 matches.

**Commit**: `feat(add-observability): init/INIT.md skeleton (9 phases)`

---

### Phase 3 — Per-stack init procedure sections

T5-T9 each flesh out ONE stack's Phase 5 (entry-file rewrite) — the shape that meta.yaml only sketches. Each task is one stack: rewrite shape pre/post, anchor placement, parameter substitution details, edge cases. Each stack also gets a test fixture pair.

#### T5 — `ts-cloudflare-worker` init procedure + fixture
**Touches**: INIT.md "Phase 5 — `ts-cloudflare-worker`" subsection; `migrations/test-fixtures/init-ts-cloudflare-worker/{before,expected-after}/` (create).

**Rewrite shape — fetch AND scheduled handlers** (queue handler is commented-out in `templates/ts-cloudflare-worker/middleware.ts:130-138`; out of scope for v0.3.1 — see CONTEXT.md "Out of scope" extension below). The template exports both `withObservability` (fetch) and `withObservabilityScheduled` (scheduled — `templates/ts-cloudflare-worker/middleware.ts:70-99`).

| Entry shape | Wrapped shape |
|---|---|
| `export default { fetch: handler }` | `export default { fetch: withObservability(handler) }` |
| `export default { fetch: f, scheduled: s }` | `export default { fetch: withObservability(f), scheduled: withObservabilityScheduled(s) }` |
| `export default { scheduled: handler }` (scheduled-only) | `export default { scheduled: withObservabilityScheduled(handler) }` |

- Wrappers come from `import { withObservability, withObservabilityScheduled } from "./lib/observability"` (added by Phase 4).
- Anchor comments around the import block AND around the modified default-export object.
- Edge: handler defined inline vs imported (procedure handles both via diff-preview).
- Edge: class-based exports (`export default class extends WorkerEntrypoint { ... }`) and the queue handler — both **explicitly out of scope** for v0.3.1; init falls back to "manual instrumentation required — see env-additions.md" message for these shapes.
- Fixture: minimal Worker project with `wrangler.toml` + `src/index.ts` exporting `{ fetch, scheduled }`; init scaffolds; expected-after shows the wrapper + middleware + rewritten entry + policy.md + CLAUDE.md block.

**Commit**: `feat(add-observability): init for ts-cloudflare-worker + fixture`

---

#### T6 — `ts-cloudflare-pages` init procedure + fixture
**Touches**: INIT.md subsection; `migrations/test-fixtures/init-ts-cloudflare-pages/{before,expected-after}/` (create).

**Rewrite shape — `_middleware.ts` IS the mount point** (Pages auto-loads it; no per-route wrapping needed). The shipped template at `templates/ts-cloudflare-pages/_middleware.ts` carries the comment block: *"Cloudflare Pages auto-loads `functions/_middleware.ts` … and runs it before any matching `onRequest*` handler. … Use as: this file IS the middleware mount. Pages's runtime wires it automatically; no explicit `withObservability(...)` call needed in route handlers."*

Concrete init actions for this stack (Phase 4 — materialise; Phase 5 — entry-rewrite is a **no-op for route files**):
- **Phase 4** materialises:
  - `functions/_lib/observability/index.ts` (wrapper — same shape as Worker's lib-observability.ts after token substitution; per `templates/ts-cloudflare-pages/meta.yaml` `target.wrapper_path`)
  - `functions/_middleware.ts` (mount file — copied verbatim from template)
  - `functions/_lib/observability/policy.md`
- **Phase 5** for Pages: scan `functions/_middleware.ts` candidates. If one already exists, do not overwrite — print "Existing _middleware.ts at functions/_middleware.ts; this stack uses the mount-point pattern. Manual merge required: combine your middleware with the scaffolded shape from templates/ts-cloudflare-pages/_middleware.ts." If none exists, the file from Phase 4 is the entry. **Route files (`onRequest*` exports) are NOT touched.**
- Edge: per-folder `_middleware.ts` (Pages allows nested middleware). Out of scope for v0.3.1 — init materialises only `functions/_middleware.ts` at the root; users wire nested middleware manually.
- Fixture: minimal Pages project with `functions/api/[[path]].ts` having multiple `onRequest*` exports + NO existing `_middleware.ts`. Init scaffolds; expected-after shows `_middleware.ts` materialised at `functions/_middleware.ts`, the route file **untouched**, wrapper + policy.md present, CLAUDE.md block written.

**Commit**: `feat(add-observability): init for ts-cloudflare-pages + fixture (mount-point pattern)`

---

#### T7 — `ts-supabase-edge` init procedure + fixture
**Touches**: INIT.md subsection; `migrations/test-fixtures/init-ts-supabase-edge/{before,expected-after}/` (create).

**Rewrite shape — handle BOTH `Deno.serve` signatures**. Per `templates/ts-supabase-edge/middleware.ts:4` header, `withObservability` is exported from `middleware.ts`, NOT `index.ts`.

| Entry shape | Wrapped shape |
|---|---|
| `Deno.serve(handler)` | `Deno.serve(withObservability(handler))` |
| `Deno.serve({ port: 8000 }, handler)` | `Deno.serve({ port: 8000 }, withObservability(handler))` |
| `Deno.serve({ port, hostname }, handler)` | same — wrap the function-position arg regardless of options shape |

- Import: `import { withObservability } from "../_shared/observability/middleware.ts"` (note: `middleware.ts`, not `index.ts` — the latter is the wrapper itself, not the middleware export).
- Detection: parse the `Deno.serve(...)` call; if first arg is an object literal, wrap second arg; else wrap first arg. Anchor comments around the import line and around the call.
- Edge: `Deno.serve(handler, options)` (handler-first, options-second — legacy Deno signature). Out of scope for v0.3.1; init falls back to manual-instrumentation message.
- Fixture: `supabase/functions/myfunc/index.ts` with `Deno.serve(handler)`; expected-after shows the wrapper at `supabase/functions/_shared/observability/index.ts`, middleware at `supabase/functions/_shared/observability/middleware.ts`, rewritten `index.ts` with `withObservability` wrap + anchored import, policy.md, CLAUDE.md block.

**Commit**: `feat(add-observability): init for ts-supabase-edge + fixture (1-arg + 2-arg Deno.serve)`

---

#### T8 — `ts-react-vite` init procedure + fixture
**Touches**: INIT.md subsection; `migrations/test-fixtures/init-ts-react-vite/{before,expected-after}/` (create).

**Canonical shape — `init()` + `ObservabilityErrorBoundary`** (NOT a fabricated `ObservabilityProvider`). The shipped template is documented at `templates/ts-react-vite/env-additions.md:55-73` with the exact expected post-init shape:

```tsx
import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { init, ObservabilityErrorBoundary } from "./lib/observability"   // ← anchored import block (Phase 4-materialised wrapper)
import App from "./App"
import "./index.css"

init()   // ← MUST be called BEFORE createRoot().render() — installs the
         //   global fetch interceptor (lib-observability.ts:131 —
         //   `window.fetch = instrumentedFetch(originalFetch)`).
         //   Without this call, §10.7 obligation (2) "wire trace
         //   propagation middleware" is NOT satisfied for browser stacks.

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ObservabilityErrorBoundary>
      <App />
    </ObservabilityErrorBoundary>
  </StrictMode>,
)
```

- Wrapper at `src/lib/observability/{index.ts, ErrorBoundary.tsx}` (Phase 4 materialise).
- Phase 5 entry-rewrite produces TWO anchored regions in `src/main.tsx`:
  1. One around the added import (`import { init, ObservabilityErrorBoundary } …`).
  2. One around `init()` + the `<ObservabilityErrorBoundary>` JSX wrap. The `init()` call sits between imports and `createRoot` (StrictMode-aware: if `StrictMode` is present, both `init()` and the `ObservabilityErrorBoundary` go INSIDE `StrictMode` per the canonical shape above).
- Edge: project uses `ReactDOM` namespace import (`import ReactDOM from "react-dom/client"; ReactDOM.createRoot(...)`) instead of named — procedure handles both, anchoring the wrap around the `.render(...)` call regardless of the receiver expression.
- Edge: project already has its own ErrorBoundary — procedure inserts `ObservabilityErrorBoundary` OUTSIDE the existing one (closer to the root) so it captures errors the inner boundary doesn't.
- Fixture: `src/main.tsx` with `createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>)`; expected-after shows the wrapper materialised at `src/lib/observability/{index.ts, ErrorBoundary.tsx}`, `main.tsx` rewritten with anchored `init()` + `<ObservabilityErrorBoundary>` wrap, policy.md, CLAUDE.md block.

**Commit**: `feat(add-observability): init for ts-react-vite + fixture (init() + ObservabilityErrorBoundary)`

---

#### T9 — `go-fly-http` init procedure + fixtures (one per router pattern)
**Touches**: INIT.md subsection; `migrations/test-fixtures/init-go-fly-http-{stdmux,chi,gorilla}/{before,expected-after}/` (create — 3 fixtures, one per detected router pattern).

**Router detection — explicit rule** (replaces v1's vague "Init detects pattern"):

Scan the project's Go source files for the following import lines in lexical order; first match wins:

| Order | Import substring | Detected pattern | Wrap shape |
|---|---|---|---|
| 1 | `"github.com/go-chi/chi/v5"` or `"github.com/go-chi/chi"` | **chi** | `r := chi.NewRouter(); r.Use(observability.Middleware)` |
| 2 | `"github.com/gorilla/mux"` | **gorilla/mux** | `r := mux.NewRouter(); r.Use(observability.Middleware)` |
| 3 | (none of the above) — falls back to | **std net/http** | wrap at server boot: `srv := &http.Server{ Addr: ":8080", Handler: observability.Middleware(mux) }` |

Per `templates/go-fly-http/middleware.go:33-48` header: `Middleware(next http.Handler) http.Handler` is compatible with net/http, chi, echo, gorilla/mux, and any router that accepts `http.Handler` middleware.

**Phase 5 rewrites for each pattern**:
- **chi**: locate `chi.NewRouter()` call; insert `r.Use(observability.Middleware)` immediately after, anchored. Plus `observability.Init()` in `main()` before router setup.
- **gorilla/mux**: locate `mux.NewRouter()` call; insert `r.Use(observability.Middleware)` immediately after, anchored. Plus `observability.Init()`.
- **std net/http**: locate `http.ListenAndServe(addr, mux)` OR `http.Server{Handler: mux}`. Rewrite to wrap the handler with `observability.Middleware(mux)`. Insert `observability.Init()` at top of `main()`.

Import additions: `import "<MODULE_PATH>/internal/observability"` (path resolved per `templates/go-fly-http/meta.yaml` `parameters.MODULE_PATH.derive_from`).

- Edge: `chi` import path that's been aliased (`chiv5 "github.com/go-chi/chi/v5"`) — procedure handles named imports by tracking the alias.
- Edge: echo / fiber / gin — out of scope for v0.3.1. Init falls back to manual-instrumentation message: "Detected unsupported router. See env-additions.md for manual wiring."
- 3 fixtures (one per pattern): `cmd/api/main.go` with std net/http; with chi; with gorilla/mux. Each `expected-after/` shows the wrap shape per the table above.

**Commit**: `feat(add-observability): init for go-fly-http + 3 fixtures (chi/gorilla/stdmux)`

---

### Phase 4 — Default policy.md templates + observability metadata block

#### T10 — Per-stack `policy.md` template files
**Touches**: `add-observability/templates/<stack>/policy.md.template` (create for each of 5 stacks).

Each template has 3 sections:
- `## Trivial errors` pre-populated per language (Go: `pgx.ErrNoRows`, `sql.ErrNoRows`, `context.Canceled`, `context.DeadlineExceeded`; TS: HTTP 4xx-returning errors, validation errors).
- `## Redacted attributes` defaults to `password|token|api_key|card_number|cvv`.
- `## Project event names` empty placeholder section with a `<!-- add domain events here -->` comment.

**Commit**: `feat(add-observability): per-stack policy.md templates`

---

#### T11 — `observability:` metadata block writer per spec §10.8

**Touches**: INIT.md Phase 6 + `add-observability/init/metadata-template.md` (create — the YAML block schema).

The block (single canonical shape — `policy:` is **scalar** per spec §10.8 line 157 AND migration 0011's POLICY_PATH parser at line 63: `awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}'`):

```yaml
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: <primary-stack-wrapper-dir>/policy.md   # scalar string path; required by 0011 pre-flight parser
  enforcement:
    baseline: .observability/baseline.json
    # ci: <host-specific-ci-workflow-path>          # OPTIONAL per spec §10.8 line 160; omitted by default (Option-4 ships no auto-installed CI workflow)
    pre_commit: optional
```

**Multi-stack handling (v0.3.1 — narrow contract)**: when init detects multiple stacks, `policy:` ships the **primary stack's path only** (primary = first stack in detection order, which is the first detector to match in `add-observability/scan/detectors.md`). The init procedure prints an explicit notice:

> Multi-stack project detected. The `observability:` block's `policy:` field is **scalar** for v0.3.1 per spec §10.8. Primary stack `<id>`'s policy path is recorded; other stacks' policy.md files are materialised but not referenced from CLAUDE.md. Per-stack policy unification awaits a spec amendment.

This avoids breaking 0011's pre-flight (15-REVIEWS Q1 #6) and keeps v0.3.1 spec-conformant. Multi-stack policy unification is captured in PLAN "Out of scope" + filed as a follow-up against agenticapps-workflow-core spec.

**Commit**: `feat(add-observability): observability metadata block writer (§10.8, scalar policy)`

---

### Phase 5 — Skill SKILL.md + version bumps

#### T12 — Bump skill `0.3.0 → 0.3.1` and document init in the description
**Touches**: `add-observability/SKILL.md`.

- Frontmatter: `version: 0.3.1`.
- Description: expand the `init` subcommand row to reference the now-shipped procedure and the 9-phase flow.
- Routing table verification check: add a structural note that `./init/INIT.md` MUST exist on disk (closes #26).

**Commit**: `chore(version): add-observability 0.3.0 → 0.3.1 (init shipped)`

---

#### T13 — Bump scaffolder `1.10.0 → 1.11.0` + CHANGELOG entry
**Touches**: `skill/SKILL.md`, `CHANGELOG.md`.

CHANGELOG `[1.11.0] — Unreleased` section above `[1.10.0]`:
- `add-observability/init/INIT.md` shipped — closes #26 + §10.7 obligations (1) and (2).
- Slash-discovery via global symlink (closes #22).
- Migration 0012 (1.10.0 → 1.11.0).
- 5-stack init fixtures.
- Updates CHANGELOG `[1.10.0]` to mark the init-blocker as resolved (cross-reference to v1.11.0).

**Commit**: `docs(changelog): record v1.11.0 — init shipped + slash discovery`

---

### Phase 6 — Multi-AI review (pre-execution gate) — **COMPLETED PLAN v1 → v2**

**Status (PLAN v2)**: multi-AI review of PLAN.md v1 completed 2026-05-15; verdict **BLOCK** by codex (REQUEST-CHANGES by gemini + Claude). 20-item revision list in `15-REVIEWS.md` has been applied to produce this PLAN v2. Re-run Q8 mechanical script as smoke check before T1 (item 20 below).

**Pattern** (carry-forward for future phases): invoke `codex exec` + `gemini` for independent review of PLAN.md, plus a Claude self-review. Raw reviewer outputs gitignored; consolidated `<NN>-REVIEWS.md` is the canonical record. **New structural check (Q8)**: every manifest- or routing-table-referenced path MUST resolve OR be explicitly annotated `(create)` / `(new)` in PLAN.md. Codified from Phase 14's miss + Phase 15's stricter reading.

**Q8 mechanical script** (canonical form — fixed regex):

```bash
grep -oiE '\./[a-zA-Z/_-]+\.md' add-observability/SKILL.md | sort -u | while read rel; do
  abs="add-observability/${rel#./}"
  [ -f "$abs" ] && echo "  OK $rel" || echo "  MISSING $rel"
done
```

> **Q8 regex bugfix lesson (PLAN v2)**: the v1 version used `[a-z/-]+\.md` which is lowercase-only and missed `./init/INIT.md`. The corrected case-insensitive form `[a-zA-Z/_-]+\.md` (with `-i` flag for safety) is what produced the canonical MISSING result. Codify this regex in the `gsd-review` skill's reviewer-prompt template so future phases inherit the fix.

Re-run Q8 against PLAN v2 before T1 starts (item 20 of the revision list). Expected: single MISSING `./init/INIT.md` (still — T4 deliverable) + zero un-annotated PLAN Touches paths.

---

### Phase 7 — Verification + close

#### T14 — End-to-end smoke test
**Touches**: produces `.planning/phases/15-init-and-slash-discovery/smoke/output.txt` (create) and `.planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` (create — captures the steps so they're re-runnable).

Cut a fresh empty Node project (sandboxed via `mktemp -d`):
0. **Pre-step (NEW for PLAN v2 — Q7 row "install.sh LINKS row honored by fresh install")**: In a clean `$HOME/.claude/skills/` (test in isolation: `HOME=$(mktemp -d) ./install.sh`), run `./install.sh` and assert `$HOME/.claude/skills/add-observability` is a symlink to the scaffolder's `add-observability/` directory. This closes #22 fresh-install path verification.
1. Apply scaffolder install (Phase 1 / T1 changes — already done in step 0).
2. Run `claude /add-observability init` against a minimal Worker fixture.
3. Run `claude /add-observability scan` — confirms post-init scan shows zero high-confidence gaps (the wrapper is just-shipped, no instrumentation gaps yet).
4. Run migration 0011 (`/update-agenticapps-workflow`).
5. Assert project is at v1.10.0 with valid baseline.json (the v1.10.0 path now works end-to-end since init is shipped).
6. Run migration 0012.
7. Assert project at v1.11.0.

If any step fails, that's a stop-the-line bug. Capture full output.

**Commit**: `test(smoke): end-to-end v1.9.3 → v1.10.0 → v1.11.0 via init + 0011 + 0012`

---

#### T15 — VERIFICATION.md
**Touches**: `.planning/phases/15-init-and-slash-discovery/VERIFICATION.md` (create).

1:1 must-have → evidence ledger. Each row maps to a §10.7 / §10.8 MUST or a regression guard:

| Must-have | Evidence |
|---|---|
| §10.7 obligation (1) wrapper scaffold | For each of 5 stacks: fixture `expected-after/` contains the wrapper at `meta.yaml target.wrapper_path`. |
| §10.7 obligation (2) middleware wired — Worker/Pages/Supabase/Go | For each: fixture asserts middleware present at `target.middleware_path` AND entry-file rewritten with the canonical wrap shape (per T5-T9 procedure tables). |
| §10.7 obligation (2) trace propagation wired — Vite (browser stack) | T8 fixture asserts (a) `init()` call appears in `main.tsx` before `createRoot(...).render(...)`; (b) `src/lib/observability/index.ts` is present; (c) `lib-observability.ts` exports `init` AND `window.fetch` interceptor activation (structural grep: `grep -nE 'window\.fetch\s*=' src/lib/observability/index.ts`). |
| §10.7 obligation (4) apply with consent — decline path | Synthetic INIT.md run with each consent gate declined in turn; assert post-state for each: gate-1 decline ⇒ no files; gate-2 decline ⇒ files written but no entry-rewrite + rollback hint printed; gate-3 decline ⇒ files + entry written, NO CLAUDE.md block + warning printed (T4 Phase 4/5/6 contract). |
| §10.8 metadata block byte-shape | `awk` or `jq` extraction of the post-init CLAUDE.md observability block; assert: `spec_version: 0.3.0` present, `destinations:` is a list, `policy:` is a **scalar string** (not array), `enforcement.baseline:` present. |
| §10.8 `policy:` is scalar AND parseable by 0011 | Run `awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}' <fixture-CLAUDE.md>` and assert non-empty single-token output. |
| Anchor comments idempotent re-detection | Re-run init in each T5-T9 fixture's `expected-after/` state; assert "already initialised" message + no file changes. (Done inline in each T5-T9 fixture as a second run-pass on the same fixture — no second-fixture-pair-per-stack overhead.) |
| Slash discovery — symlink present after migration 0012 fixture 01 | T3 fixture 01-fresh-apply asserts `test -L ~/.claude/skills/add-observability && readlink ~/.claude/skills/add-observability` matches the expected target. |
| Slash discovery — fresh-install path | T14 smoke step 1 runs `./install.sh` in a clean `~/.claude/skills/` and asserts `~/.claude/skills/add-observability` is a symlink to the scaffolder `add-observability/` directory. |
| Migration 0012 — 5/5 fixtures green | `bash migrations/run-tests.sh 0012` exits 0 with all 5 fixtures listed. |
| Migration 0011 POLICY_PATH parser regression | `bash migrations/run-tests.sh 0011` post-T1-T13 — all 6 fixtures still green. **This is the explicit guard against T11's scalar-policy decision breaking 0011's pre-flight.** |
| All other earlier migration fixtures green | `bash migrations/run-tests.sh` (full suite) exits 0. |
| 61 v0.2.1 contract tests still green | `bash run-tests.sh` (skill contract tests) — regression-guarded by zero template diff. |
| D7 chain hint — stale `.scan-report.md` warning | Fixture variant: one of T5-T9's `before/` state includes a pre-existing `.scan-report.md`; assert init's Phase 8 stdout contains `re-run scan` chain-hint line. (Pick one stack's fixture — no need to repeat across all 5.) |
| Smoke test — end-to-end v1.9.3 → v1.10.0 → v1.11.0 | T14 output captured at `.planning/phases/15-init-and-slash-discovery/smoke/output.txt`; all 7 steps exit 0. |

**Commit**: `docs(verification): phase 15 evidence ledger`

---

#### T16 — `/review` + `/cso` post-phase

`/review` against the branch diff. `/cso` focused on:
- The default `REDACTED_KEYS` list — is it sufficient for sensitive data?
- The anchor-comment pattern — can attacker-contributed code inject anchor comments to bypass detection?
- Symlink-based discovery — symlink-following CVEs are a real pattern; should we check for symlink-target tampering?

**Commits**: `docs(review): phase 15 — REVIEW.md` + `docs(security): phase 15 — SECURITY.md`.

---

#### T17 — Session handoff + PR

Open PR `feat: ship init procedure + slash discovery (v1.11.0)` against main. Reference #22, #26, #24 in the description.

---

## Wave dependency graph

```
T1 (layout refactor) ─┐
T2 (migrations 0002 + 0012) ─┤  Phase 1 — slash discovery
T3 (0012 fixtures)            ─┘
                              ▼
T4 (INIT.md skeleton) ── must be done before any of T5-T9
                              ▼
T5 (ts-cloudflare-worker) ─┐
T6 (ts-cloudflare-pages)   ─┤  Phase 3 — per-stack init (can be parallelized but
T7 (ts-supabase-edge)      ─┤  sequential per the migration-fixture lesson —
T8 (ts-react-vite)         ─┤  one stack's fixture-stub bug shouldn't block 4
T9 (go-fly-http)           ─┘  others)
                              ▼
T10 (policy.md templates) ─┐
T11 (metadata writer)     ─┤  Phase 4 — supporting artefacts
                          ▼
T12 (skill version bump) ─┐
T13 (scaffolder + CHANGELOG) ─┤  Phase 5 — versions
                              ▼
   ━━━ Multi-AI review gate (Phase 6) ━━━ [REQUIRED before T1 if strict; 
                                          recommended NOW since structure is
                                          settled and reviewers can spot the 
                                          per-stack wrap shapes before code]
                              ▼
T14 (smoke) ─┐
T15 (VERIFICATION) ─┤  Phase 7 — verify + close
T16 (review + cso) ─┤
T17 (handoff + PR)
```

Concrete execution order: T1, T2, T3, T4, multi-AI review, T5-T9 (parallel-ish), T10, T11, T12, T13, T14, T15, T16, T17.

---

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Symlink fix breaks existing fresh installs of the scaffolder | Low | T1 backwards-compatible: existing installs without the symlink work as today (degraded — no slash-discovery); migration 0012 forward-fixes |
| Per-stack entry-file rewrite is wrong for one stack | Med | T5-T9 each ship a fixture exercising the rewrite shape; if a fixture fails, that stack's procedure is wrong |
| Anchor-comment pattern subverted by code formatters | Med | `// agenticapps:observability:start` is a comment; gofmt/prettier preserve it. T5-T9 fixtures include a post-rewrite formatter run (`prettier --write` for TS, `gofmt -w` for Go) and re-assert the anchors survive. Specifically verify against Prettier's `--prose-wrap=always` which can re-wrap comment text. |
| Multi-stack monorepo CLAUDE.md write order non-deterministic | Med | Lexicographic sort on stack_id; same as baseline.json sort in Phase 14 |
| Smoke test in T14 fails on a fixture project that doesn't exist | High at start, Low after T5-T9 | Smoke uses one of T5-T9's fixtures as its starting state. |
| Multi-AI review surfaces a different INIT.md shape | Med | Same pattern as Phase 14: incorporate into PLAN v2 before T1 starts. **Status: this PLAN v2 has incorporated the Phase-15 multi-AI review's 20-item revision list.** |
| Symlink-target tampering CVE class | Low | T16 `/cso` review covers this. The symlink target is inside the scaffolder repo's git-managed tree; attacker would need filesystem write access to alter it. |
| **install.sh LINKS array not updated → fresh installs undiscoverable** (15-REVIEWS Q2 #2) | **High** if T1 missed this; **closed in PLAN v2** | T1 adds `"add-observability add-observability"` row to install.sh; T14 smoke step 1 explicitly verifies the symlink post-`./install.sh`. |
| `~/.claude/skills/add-observability` exists as real directory (manual install or prior cp-copy) → install.sh refuses to clobber (lines 71-75) | Low-Med | install.sh's existing exit-1 message tells the user how to resolve (`rm -rf ... && rerun`). 0012 inherits the same protection via `[ -L ]` / `[ -e ]` check. T3 fixture 04 covers the symlink-wrong-target variant. |
| **Consent gate-2 (entry-rewrite) decline → wrapper materialised but no entry wiring** | High (cautious users) | T4 Phase 5 contract: on decline, print rollback hint (`rm -rf` the wrapper dirs) AND skip Phase 6 (no false-conformance CLAUDE.md write). Verified by T15 consent-decline fixture row. |
| **Consent gate-3 (CLAUDE.md block) decline → migration 0011 pre-flight will fail on next upgrade** | Med (users who hand-curate CLAUDE.md) | T4 Phase 6 prints explicit warning + recovery (manual block addition or re-run init). Documented in `add-observability/SKILL.md` description. |
| `policy:` array would break migration 0011 POLICY_PATH parser at line 63 | **Closed in PLAN v2** | T11 ships scalar `policy:` for v0.3.1 — primary stack's path only; multi-stack unification deferred to spec amendment. T15 explicit row runs `bash migrations/run-tests.sh 0011` post-T1-T13 as regression guard. |
| BSD vs GNU `readlink -f` portability in run-tests.sh + migrations | Low | T2 portability lint: no `readlink -f` in 0002, 0012, or run-tests.sh. Use one-level `readlink` (POSIX) or `python -c 'os.path.realpath(...)'`. |
| 6th stack (python-fastapi, etc.) addition friction post-v0.3.1 | Low (future) | INIT.md "Important rules" documents the extension procedure: copy a per-stack section, add to T5-T9 fixture pattern, add to scan/detectors.md. Pattern is structural copy-paste. |
| `applies_to:` cross-tree path (`~/.claude/skills/...`) novel for migrations framework | Med | 0012 manifest comment documents the cross-tree exception so future maintainers don't take it as precedent for arbitrary host-system mutation. Framework's `test -L` verify works POSIX cross-platform. |

---

## Out of scope (deferred to v1.12.0+)

- **`init --force` re-init** — D5 decision; defer to a future version.
- **Pre-commit hook template** (§10.9.4 MAY) — same deferral as Phase 14.
- **Standalone Node scanner port** — downgraded after Option 4 pivot.
- **fx-signal-agent retroactive adoption** — separate consumption work; should follow phase 15 to validate the v1.9.3 → v1.11.0 path.
- **Python / Rust / Java stacks** — new templates are their own phases.
- **`init` interactive multi-stack pickers** (D3 "C" option) — current PLAN ships walk-all + `--stack <id>` override.
