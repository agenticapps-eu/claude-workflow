# Design — Add Axiom as logs destination (claude-workflow 1.16.0)

**Status:** Approved (brainstorming) — 2026-05-26
**Author:** Claude (pairing with Donald)
**Supersedes:** `~/Documents/Claude/Projects/agentic-workflow/dual-destination-templates-prompt.md` (stale: assumed v1.12.0→v1.13.0 + dual-shipping)
**Spec target:** `agenticapps-workflow-core` §10.6 (destination independence) + §10.8 (project metadata) — **no spec change**, stays 0.4.0
**GSD phase:** 21 (`.planning/phases/21-axiom-logs-destination/`)

## Problem

The 5 stack templates (`ts-cloudflare-worker`, `ts-cloudflare-pages`,
`ts-supabase-edge`, `ts-react-vite`, `go-fly-http`) hardcode Sentry as the sole
observability destination. Spec §10.8's canonical project-metadata block already
exposes a `destinations: { errors:, logs:, analytics: }` shape, and §10.6 already
permits multi-destination — but no template implements it. This is implementation
catching up to a contract the spec already exposes.

Goal: future `claude /add-observability init` invocations wire **Sentry as the
errors destination and Axiom as the logs destination**, satisfying §10.8's literal
`errors: sentry / logs: axiom` separation. Existing v0.4.0 projects (cparx,
fx-signal-agent, callbot) opt-in via migration 0017; Sentry-only continues to
work for projects that skip the migration.

## Architecture: role-based destination registry

Each stack's wrapper gains a `destinations/` sub-directory:

```
<wrapper-dir>/                     # path varies per stack — meta.yaml target.wrapper_path
├── index.{ts,go}                  # public interface — exports UNCHANGED
├── middleware.{ts,go}             # unchanged
├── policy.md                      # gains "Destination roles" section
├── destinations/
│   ├── registry.{ts,go}           # role→adapter map; built once at init()
│   ├── sentry.{ts,go}             # adapter (lifted from current inlined Sentry code)
│   └── axiom.{ts,go}              # adapter (new)
└── README.md
```

### Destination interface

```ts
export interface Destination {
  name: string;                                       // "sentry" | "axiom"
  supportedRoles: ReadonlyArray<"errors" | "logs" | "analytics">;
  isConfigured(env: EnvLike): boolean;                // required env vars present?
  init(env: EnvLike, ctx?: ExecutionContext): void;   // idempotent
  emit(envelope: Envelope): void;                     // logEvent path; fire-and-forget per §10.5
  captureException(err: unknown, envelope: Envelope): void;  // captureError path
  flush?(timeoutMs: number): Promise<boolean>;        // §10.5 — short-lived processes
}
```

Registry:

```ts
export function buildRegistry(config: DestinationsConfig, env: EnvLike, ctx?: ExecutionContext): Registry;
interface Registry {
  forRole(role: "errors" | "logs" | "analytics"): Destination | null;
  all(): Destination[];   // Flush() calls every active adapter
}
```

### Role dispatch — NOT dual-ship

Each role maps to exactly one destination:

- `logEvent(envelope)` → `registry.forRole("logs").emit()`. Default `logs: axiom`.
- `captureError(err, envelope)` → `registry.forRole("errors").captureException()`.
  Default `errors: sentry`. Sentry's own breadcrumb trail captures the lead-up; we
  do **not** manually duplicate `logEvent` into Sentry breadcrumbs.
- `startSpan(name)` → destination(s) declaring span support. Sentry native. Axiom
  span-as-event is **out of scope** (defer to 1.17.0).
- `errors: none` ⇒ `captureError` no-ops; `logs: none` ⇒ `logEvent` no-ops — same
  fail-safe as today's v0.3.2 wrapper when `SENTRY_DSN` is unset.

## Decisions / deltas from the hand-off

### D1 — public interface scope is FOUR entry points

The byte-identical surface is `init`/`Init`, `startSpan`, `logEvent`,
`captureError` (+ trace helpers `parseTraceparent`/`newRootContext`/
`formatTraceparent`/`runWithContext`/`getActiveContext` and types
`Envelope`/`Span`/`TraceContext`/`InitEnv`). `init` is where the registry is
built, so it is load-bearing even though its signature must not move. The 61
existing contract tests pin these and are the regression guard. Any signature
drift is a refuse-to-merge condition (§10.1).

### D2 — runtime role-map source: bake-at-init + env override

CLAUDE.md is a dev-time artifact, NOT readable at production runtime. The role map
resolves as:

1. A constant baked into the generated `registry` at `init`-time via token
   substitution — the existing generator already carries a `DESTINATION` param in
   meta.yaml (currently comment-only); this makes it functional.
2. Overridable at startup by an `OBS_DESTINATIONS` env var (e.g.
   `errors=sentry,logs=axiom`) for ops flexibility.

CLAUDE.md's `observability:` block is the **record** of the decision, never the
runtime source. Adapter **credentials** stay pure env (`SENTRY_DSN`,
`AXIOM_TOKEN`, `AXIOM_DATASET`).

### D3 — ts-cloudflare-pages gains a full new test harness

cf-pages ships zero contract tests today (the other 4 stacks have one each — the
real "61 tests" total: cf-worker 15 / react-vite 22 / supabase-edge 12 /
go-fly-http 12). This PR authors a full cf-pages contract harness (~15 baseline
tests mirroring cf-worker) PLUS its 4 Axiom tests — closing a pre-existing
coverage gap.

### D4 — 1.15.0 CHANGELOG backfill is the branch's first commit

The 1.15.0 entry (migration 0016 / ADR 0025) was never written. It lands as the
first commit on `feat/axiom-logs-destination-v1.16.0`, ahead of 1.16.0 work.
(Already committed: `bcbf539`.)

### D5 — no new TS flush export

Go already exposes `Flush(timeout) bool`; the Axiom Go adapter's `flush()` wires
into it directly. TS Workers/Edge use `ctx.waitUntil()` / `EdgeRuntime.waitUntil()`
fire-and-forget, so no new top-level TS flush export — keeps the interface
byte-identical.

### D6 — adopted hand-off recommendations

- Axiom region: US default (`api.axiom.co`) + `AXIOM_INGEST_URL` override for
  EU/self-hosted.
- Redaction: redact once in the wrapper before dispatch (smaller PII surface).
- CLAUDE.md rewrite: anchor-managed range, same `<!-- spec-source -->` idiom as
  migration 0014.
- `add-observability/SKILL.md`: bump 0.4.0 → 0.5.0 (new declarative surface).

## Per-stack realization

| Stack | env source | fire-and-forget | flush |
|---|---|---|---|
| ts-cloudflare-worker | Worker `env` arg | `ctx.waitUntil()` | n/a (waitUntil) |
| ts-cloudflare-pages | Worker `env` arg | `ctx.waitUntil()` | n/a (waitUntil) |
| ts-supabase-edge | `Deno.env.get` | `EdgeRuntime.waitUntil()` | n/a |
| ts-react-vite | `import.meta.env.VITE_*` | sendBeacon on unload | n/a |
| go-fly-http | `os.Getenv` | goroutine | existing `Flush(timeout)` |

**Axiom adapter:** `supportedRoles: ["logs", "analytics"]` (no `errors` — Sentry's
error-grouping UI is the value prop; not duplicating). `isConfigured()` ⇒
`!!AXIOM_TOKEN && !!AXIOM_DATASET`. `emit()` ⇒ one `POST <ingest>` (`Authorization:
Bearer <token>`, body `[envelope]`). `captureException()` no-ops. Ingest URL
default `https://api.axiom.co/v1/datasets/<dataset>/ingest`, `AXIOM_INGEST_URL`
override.

**Sentry adapter:** lifted from current wrapper. `supportedRoles: ["errors",
"logs"]`. `isConfigured()` ⇒ `!!SENTRY_DSN`.

**ts-react-vite browser caveat:** browser CANNOT ship an ingest-write token (CORS +
exfil). Default adapter = console-only in browser unless `VITE_AXIOM_PROXY_URL`
set, which POSTs to a same-origin `/api/log` proxy. Documented in env-additions +
policy.md.

## Migration 0017

`from_version: 1.15.0 → to_version: 1.16.0`. Mirrors migration 0014 shape.

1. **Pre-flight** — workflow 1.12.0–1.15.x AND ≥1 materialised wrapper from
   add-observability 0.3.x/0.4.x.
2. **Idempotency** — skip module-roots where `destinations/registry.{ts,go}`
   already exists.
3. **Hand-modified detection** — content-hash each wrapper `index.{ts,go}` vs
   `migrations/test-fixtures/0017/known-wrapper-hashes.json` (generated in this
   PR). No match ⇒ show diff, **refuse**, emit manual-splice guidance, exit
   non-zero (§10.7 consent rule).
4. **Apply (safe path)** — copy `destinations/{registry,sentry,axiom}` adapters,
   rewrite `index.{ts,go}` inlined-Sentry → registry-dispatched, merge Axiom env
   rows, rewrite CLAUDE.md `observability:` block to v0.4.0 multi-destination shape
   (anchor-managed), smoke-verify (`tsc --noEmit` / `go build ./...`).
5. **Rollback** — `rm -rf destinations/` + git-restore wrapper + git-restore
   CLAUDE.md. Caveat: rollback may lose Axiom env vars added between apply and
   rollback.
6. **Post-checks** — adapters exist, wrapper imports registry, CLAUDE.md has
   v0.4.0 block, scan clean.
7. **Skip cases** — unsupported stack; no wrapper (pre-init); hand-modified
   (refuse).

CLAUDE.md target block:

```yaml
observability:
  spec_version: 0.4.0
  destinations:
    errors: sentry
    logs: axiom
    analytics: none
  policy: <stack-path>/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
```

## meta.yaml + init changes

Each `meta.yaml` gains:

```yaml
destinations:
  available: ["sentry", "axiom"]
  defaults: { errors: sentry, logs: axiom, analytics: none }
  roles_supported:
    sentry: ["errors", "logs"]
    axiom: ["logs", "analytics"]
```

`init` (in `add-observability/init/INIT.md`) gains a `--destinations
errors=sentry,logs=axiom` flag (falls back to template defaults), copies only the
adapters referenced by the role map, writes the role map into CLAUDE.md (consent
gate 3), and writes env stubs for active destinations only. New INIT.md
sub-section "Destination role assignment" between "Detect stacks" and "Resolve
targets".

## Testing

- 5 stacks × 4 Axiom role-dispatch cases = **20 tests** (`fakeFetch` for TS,
  `httptest.Server` for Go): `errors=sentry,logs=axiom` / `logs=none` /
  `errors=none,logs=axiom` / both `none`.
- cf-pages full harness: **~15 baseline backfill** (its 4 Axiom tests are part of
  the 20 above, not additional) (D3). New-test total ≈ **35** + migration fixtures.
- Migration 0017: 6 fixtures (`01-fresh-apply-cparx-shape`,
  `02-fresh-apply-fxsa-shape`, `03-already-applied`, `04-hand-modified-refuse`,
  `05-multi-stack-partial`, `06-no-claudemd`) + `test_migration_0017()` in
  `run-tests.sh`.
- Baseline pre-change (verified 2026-05-26): migration suite **PASS=152 FAIL=0**
  (preflight audit PASS=19 FAIL=0 SKIP=5); 61 template contract tests green.
  Recorded in CONTEXT.md.

## Version bumps

- `skill/SKILL.md`: 1.15.0 → **1.16.0** (`implements_spec` stays 0.4.0).
- `add-observability/SKILL.md`: 0.4.0 → **0.5.0** (`implements_spec` stays 0.3.2).

## Non-goals

- No destinations beyond Sentry + Axiom (registry pattern leaves room).
- No spec change (§10.6 + §10.8 already permit multi-destination).
- No `captureError` → Axiom dual-ship.
- No automatic Axiom resource creation (user creates dataset + token, pastes into
  secrets).
- No auto-batching (one event per POST in 1.16.0; batching defers to 1.17.0).
- No wrapper-interface change (the four entry points stay byte-identical).

## Hard constraints

1. Wrapper interface byte-identical (§10.1) — refuse-to-merge on drift.
2. `captureError` does NOT go to Axiom.
3. Adapters compile cleanly when their env vars are unset (`isConfigured()` ⇒
   false ⇒ no-op).
4. Hand-modified wrappers abort migration safely (refuse + diff + guidance).
5. Browser stack ships NO ingest-token-from-browser default.

## Downstream pickup (separate PRs, not this one)

cparx (2 module-roots), fx-signal-agent (7), callbot (2 — admin-ui needs the proxy
pattern) each run `/update-agenticapps-workflow` → 1.16.0 → migration 0017, then
create Axiom dataset + paste credentials. Does not block 1.16.0 shipping.
