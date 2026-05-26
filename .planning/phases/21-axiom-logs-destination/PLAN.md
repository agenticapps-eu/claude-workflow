# Phase 21 — Execution Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement task-by-task. This plan follows the
> local convention (single PLAN.md, phase-grouped P0–P6, per-phase verification
> gates) established by phase 20 — not the GSD multi-file roadmap path (this repo
> has no ROADMAP.md). Steps that build behavior are TDD: failing test first.

**Goal:** Wire Sentry-as-errors / Axiom-as-logs across all 5 stack templates via a
role-based destination registry, with migration 0017 for existing v0.4.0 projects.

**Architecture:** Each wrapper factors its inlined Sentry code into a
`destinations/` sub-dir (registry + sentry + axiom adapters). The wrapper's `init`
builds a role→adapter registry once; `logEvent`/`captureError` dispatch by role. No
dual-ship. Public interface byte-identical (§10.1).

**Tech stack:** TypeScript (Cloudflare Workers/Pages, Deno Edge, Vite browser), Go;
vitest / deno test / go test; bash migration harness.

> **Discipline reminder.** Interface byte-identity (§10.1) is a refuse-to-merge
> gate — the 61 existing contract tests MUST stay green unchanged. `captureError`
> never reaches Axiom. Adapters compile/no-op cleanly when their env vars are
> unset. Hand-modified wrappers abort migration (refuse + diff + guidance, never
> overwrite) per §10.7. Redact once in the wrapper before dispatch.

## Conventions

- Single 1.16.0 PR; phases (P1–P6) are commit-grouping units, not separate PRs.
- Atomic commits per discrete change. Adapters land TDD: `test(...): … (RED)` then
  `feat(...): … (GREEN)`.
- Migration test fixtures land in the same commit as the migration they test
  (precedent: migrations 0014/0015).
- **GitNexus discipline (CLAUDE.md):** before editing any wrapper symbol, run
  `gitnexus_impact({target, direction:"upstream"})` and report blast radius; run
  `gitnexus_detect_changes()` before each commit. Warn on HIGH/CRITICAL.
- Verification-gate evidence captured in the terminal commit message of each phase.

---

## P0 — Bootstrap (DONE)

- [x] Branch `feat/axiom-logs-destination-v1.16.0` cut off `main`.
- [x] 1.15.0 CHANGELOG backfill committed first (`bcbf539`) — divergence D4.
- [x] Design spec committed (`bc36d09`).
- [x] Baseline green: `migrations/run-tests.sh` PASS=152 FAIL=0; 61 contract tests
  documented green (`add-observability/CONTRACT-VERIFICATION.md`).

**P0 gate:** met. Recorded in CONTEXT.md Phase 0 discovery addendum.

---

## P1 — Destination registry + adapter interface (the contract)

### P1.1 — Define the `Destination` interface + `Registry` (TS reference: cf-worker)

**Files:**
- Create: `add-observability/templates/ts-cloudflare-worker/destinations/registry.ts`

**read_first:** `ts-cloudflare-worker/lib-observability.ts` (current `init`,
`Envelope`, `Span`, `InitEnv`, `ExecutionContext` usage).

**Action — exact interface (copy verbatim into the file):**
```ts
export type Role = "errors" | "logs" | "analytics";
export interface Destination {
  name: "sentry" | "axiom";
  supportedRoles: ReadonlyArray<Role>;
  isConfigured(env: InitEnv): boolean;
  init(env: InitEnv, ctx?: ExecutionContext): void;
  emit(envelope: Envelope): void;
  captureException(err: unknown, envelope: Envelope): void;
  flush?(timeoutMs: number): Promise<boolean>;
}
export interface DestinationsConfig { errors: DestName; logs: DestName; analytics: DestName; }
export type DestName = "sentry" | "axiom" | "none";
export interface Registry { forRole(role: Role): Destination | null; all(): Destination[]; }
export function buildRegistry(config: DestinationsConfig, env: InitEnv, ctx?: ExecutionContext): Registry;
```
`buildRegistry` constructs each named adapter once, calls `init()` on those that
`isConfigured()`, maps each role to its named adapter (skipping `"none"`), and
returns a `Registry` whose `forRole` returns the adapter only when configured.

**D2 role-map source:** `DestinationsConfig` resolves from (1) a baked constant
`DESTINATIONS_CONFIG` substituted at init-time by the generator (default
`{errors:"sentry",logs:"axiom",analytics:"none"}`), overridable by (2) an
`OBS_DESTINATIONS` env var parsed as `errors=sentry,logs=axiom`.

- [ ] **Step 1:** Write failing registry tests (RED) — see P2 test matrix; the
  registry test asserts `forRole("logs").name === "axiom"` under default config and
  `forRole("errors")` is `null` when `errors:"none"`.
- [ ] **Step 2:** Run `npx vitest run registry` → FAIL (no `buildRegistry`).
- [ ] **Step 3:** Implement `registry.ts` minimal.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(obs/cf-worker): destination registry + role map (GREEN)`.

### P1.2 — Wire the registry into `init`/`logEvent`/`captureError` (cf-worker)

**Files:** Modify `ts-cloudflare-worker/lib-observability.ts`.

**read_first:** the same file (current `init` body lines ~99–135, `logEvent` ~241,
`captureError` ~248). Run `gitnexus_impact` on each before editing.

**Action:** in `init`, after existing setup, set
`module-level registry = buildRegistry(resolveConfig(env), env, ctx)`. Rewrite
`logEvent(envelope)` body to `registry?.forRole("logs")?.emit(envelope)`. Rewrite
`captureError(err, envelope)` body to
`registry?.forRole("errors")?.captureException(err, envelope)`. **Signatures
unchanged.** Redaction stays in the wrapper, applied to `envelope` BEFORE dispatch
(D6). `startSpan` unchanged (Sentry-native; Axiom span deferred).

- [ ] **Step 1:** Confirm the 15 existing cf-worker contract tests still pass
  BEFORE refactor (baseline).
- [ ] **Step 2:** Refactor internals (no signature change).
- [ ] **Step 3:** `npx vitest run` → the 15 contract tests still PASS unchanged (G2).
- [ ] **Step 4:** `gitnexus_detect_changes()` confirms only expected symbols moved.
- [ ] **Step 5:** Commit `refactor(obs/cf-worker): dispatch logEvent/captureError via registry`.

**P1 gate:**
- `grep -n "buildRegistry" ts-cloudflare-worker/lib-observability.ts` present.
- The 15 cf-worker contract tests pass unchanged (diff of test file = empty).
- `tsc --noEmit` clean for the cf-worker template.

---

## P2 — Sentry + Axiom adapters per stack (+ cf-pages harness, D3)

Apply the P1 pattern to all 5 stacks. Per stack: extract Sentry into `sentry.{ts,go}`,
add `axiom.{ts,go}`, add `destinations/registry.{ts,go}`, wire `init`. Per-stack
runtime adaptations are spelled out below — do not guess.

### P2.1 — Sentry adapter (per stack, lift-and-shift)

`sentry.{ts,go}`: `supportedRoles: ["errors","logs"]`; `isConfigured` ⇒
`!!env.SENTRY_DSN`; `init` = existing per-stack Sentry init (`withSentry` for
cf-worker/pages, `Sentry.init` for deno/react, Go init for go-fly-http);
`emit`/`captureException` = the wrapper's existing Sentry calls, moved verbatim.

### P2.2 — Axiom adapter (per stack, new)

`axiom.{ts,go}`: `supportedRoles: ["logs","analytics"]` (NO `errors`); `isConfigured`
⇒ `!!env.AXIOM_TOKEN && !!env.AXIOM_DATASET`; `init` caches token + dataset + ingest
URL (`https://api.axiom.co/v1/datasets/<dataset>/ingest`, `AXIOM_INGEST_URL`
override); `emit(envelope)` ⇒ one `POST <ingest>` with `Authorization: Bearer
<token>`, body `[envelope]`; `captureException` ⇒ **no-op**; `flush` per stack.

| Stack | env source | fire-and-forget | flush impl |
|---|---|---|---|
| ts-cloudflare-worker | Worker `env` arg | `ctx.waitUntil(fetch(...))` | n/a |
| ts-cloudflare-pages | Worker `env` arg | `ctx.waitUntil(fetch(...))` | n/a |
| ts-supabase-edge | `Deno.env.get(...)` | `EdgeRuntime.waitUntil(...)` (guarded) | n/a |
| ts-react-vite | `import.meta.env.VITE_*` | `navigator.sendBeacon` on unload; else `fetch` | n/a |
| go-fly-http | `os.Getenv(...)` | goroutine | drain into existing `Flush(timeout)` (D5) |

**ts-react-vite browser caveat (HARD constraint):** the browser adapter MUST NOT
ship an ingest-write token. Default = console-only in prod unless
`VITE_AXIOM_PROXY_URL` is set, in which case `emit` POSTs to that same-origin proxy.
Documented in P3 env-additions + policy.md.

### P2.3 — cf-pages full contract harness (D3 / G4)

**Files:** Create `add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts`.

**read_first:** `ts-cloudflare-worker/lib-observability.test.ts` (the 15-test
reference) and cf-pages' `lib-observability.ts`.

**Action:** author ~15 baseline contract tests mirroring cf-worker (trace
round-trip, redaction scrubs default keys, emit-without-Sentry no-throw,
captureError-nil no-op, logEvent-without-init no-throw, startSpan child context,
span-end idempotent) adapted to the cf-pages wrapper, PLUS the 4 Axiom role-dispatch
cases (P2.4). This closes cf-pages' zero-coverage gap.

### P2.4 — Axiom role-dispatch tests (4 per stack × 5 = 20; G3)

Use `fakeFetch` (TS, matching existing fixture style) / `httptest.Server` (Go).

| Case | Config | Expect |
|---|---|---|
| 1 | `errors=sentry, logs=axiom` | `logEvent` POSTs to Axiom ingest; `captureError` calls Sentry; Axiom gets no error |
| 2 | `errors=sentry, logs=none` | `logEvent` no-ops (no POST); `captureError` calls Sentry |
| 3 | `errors=none, logs=axiom` | `logEvent` POSTs to Axiom; `captureError` no-ops cleanly |
| 4 | `errors=none, logs=none` | both no-op; no POST, no Sentry call |

**TDD per adapter:** tests written first (RED — adapter/registry absent), then
adapter implemented (GREEN). Commit pairs per stack:
`test(obs/<stack>): axiom role-dispatch (RED)` → `feat(obs/<stack>): sentry+axiom adapters (GREEN)`.

**P2 gate:**
- All 5 stacks have `destinations/{registry,sentry,axiom}.{ts,go}`.
- `npx vitest run` (cf-worker, cf-pages, react-vite), `deno test` (supabase-edge),
  `go test ./...` (go-fly-http) all green.
- New-test total ≈ 35 (20 Axiom + ~15 cf-pages baseline). 61 prior contract tests
  unchanged where stacks were only extended.
- `tsc --noEmit` / `go build ./...` clean per stack.
- `grep -L "errors" axiom.{ts,go}` confirms Axiom adapter has no errors role.

---

## P3 — env-additions + policy.md per stack

### P3.1 — env-additions.md (per stack)

**Action:** add an Axiom section beside the existing Sentry section per stack, with
the exact var table:

| Var | Where | Required | Example |
|---|---|---|---|
| `AXIOM_TOKEN` | wrangler secret / fly secrets / .env | required if logs=axiom | `xaat-...` (ingest-scoped) |
| `AXIOM_DATASET` | wrangler.toml / fly.toml / .env | required if logs=axiom | `myapp-prod` |
| `AXIOM_INGEST_URL` | only if non-default region/self-hosted | optional | `https://api.eu.axiom.co/v1/datasets/<ds>/ingest` |
| `OBS_DESTINATIONS` | runtime env | optional | `errors=sentry,logs=axiom` (overrides baked default) |

Document: both Sentry+Axiom env absent ⇒ console-only fallback (§10.5 fail-safe
preserved). For `ts-react-vite`, additionally document `VITE_AXIOM_PROXY_URL` and a
short Hono/Express `/api/log` proxy example.

### P3.2 — policy.md "Destination roles" section (per stack)

**Action:** add a section stating: errors→sentry, logs→axiom, analytics→none by
default; redaction runs once in the wrapper before dispatch (D6); per-role
no-op-when-unconfigured semantics.

**P3 gate:**
- `grep -l "AXIOM_TOKEN" add-observability/templates/*/env-additions.md` = 5 files.
- `grep -l "Destination roles" add-observability/templates/*/policy.md*` = 5 files.
- react-vite env-additions contains `VITE_AXIOM_PROXY_URL` and a proxy example.

---

## P4 — meta.yaml + init wiring

### P4.1 — meta.yaml destinations block (per stack)

**Action:** add to each `meta.yaml`:
```yaml
destinations:
  available: ["sentry", "axiom"]
  defaults: { errors: sentry, logs: axiom, analytics: none }
  roles_supported:
    sentry: ["errors", "logs"]
    axiom: ["logs", "analytics"]
```
Bump each `meta.yaml` `spec_version` note only if other meta fields require it —
otherwise leave (declarative-only addition).

### P4.2 — INIT.md `--destinations` flag + role assignment

**Files:** Modify `add-observability/init/INIT.md`.

**read_first:** `add-observability/init/INIT.md` (Phase "Detect stacks" → "Resolve
targets" → "Phase 5 consent gates").

**Action:** add a "Destination role assignment" sub-section between "Detect stacks"
and "Resolve targets". Accept `--destinations errors=sentry,logs=axiom` (parse to
role map) or fall back to `meta.yaml` defaults. Copy ONLY adapters referenced by the
role map into `<wrapper-dir>/destinations/` (e.g. `errors=none,logs=axiom` ⇒ only
`axiom.{ts,go}`). Write the resolved role map into the baked `DESTINATIONS_CONFIG`
constant AND into CLAUDE.md's `observability:` block (consent gate 3). Write env
stubs for active destinations only.

**P4 gate:**
- `grep -l "roles_supported" add-observability/templates/*/meta.yaml` = 5.
- `grep -n "Destination role assignment" add-observability/init/INIT.md` present.
- `grep -n "\-\-destinations" add-observability/init/INIT.md` present.

---

## P5 — Migration 0017 for existing v0.4.0 projects (G5)

### P5.1 — Author migration 0017

**File:** `migrations/0017-add-axiom-logs-destination.md`. Mirror 0014 shape.

- **Frontmatter:** `id: 0017`, `slug: add-axiom-logs-destination`,
  `title: "Add Axiom as logs destination (spec §10.8 multi-destination materialisation)"`,
  `from_version: 1.15.0`, `to_version: 1.16.0`,
  `applies_to: [add-observability wrapper dirs]`,
  `optional_for: [projects without a materialised wrapper]`.
- **Pre-flight:** workflow 1.12.0–1.15.x AND ≥1 materialised wrapper from
  add-observability 0.3.x/0.4.x. Idempotency: `grep -RIn 'destinations/registry'
  <wrapper-paths>` — skip module-roots already migrated.
- **Step 1 — hand-modified detection (§10.7):** content-hash each wrapper
  `index.{ts,go}` vs `migrations/test-fixtures/0017/known-wrapper-hashes.json`. No
  match ⇒ print the would-be diff, **refuse**, emit manual-splice guidance, exit
  non-zero.
- **Step 2 — apply (safe path):** copy `destinations/{registry,sentry,axiom}` from
  the matching template stack; rewrite `index.{ts,go}` inlined-Sentry →
  registry-dispatched (target = v1.16.0 template); merge Axiom env rows into
  `.env.example`/`env-additions`; rewrite CLAUDE.md `observability:` block v0.3.0→
  v0.4.0 multi-destination via anchor-managed range; smoke `tsc --noEmit` /
  `go build ./...`.
- **Step 3 — version bump:** `skill/SKILL.md` 1.15.0 → 1.16.0 (idempotency:
  `grep -q '^version: 1.16.0$'`).
- **Rollback:** `rm -rf <wrapper-dir>/destinations/` + git-restore wrapper +
  git-restore CLAUDE.md. Caveat: may lose Axiom env vars added between apply and
  rollback — re-paste from secrets manager.
- **Post-checks:** adapters present; wrapper imports registry; CLAUDE.md has v0.4.0
  block; scan clean.

CLAUDE.md target block (anchor-managed):
```yaml
observability:
  spec_version: 0.4.0
  destinations: { errors: sentry, logs: axiom, analytics: none }
  policy: <stack-path>/observability/policy.md
  enforcement: { baseline: .observability/baseline.json }
```

### P5.2 — Generate known-wrapper-hashes.json

**Action:** hash the scaffolded v0.3.x and v0.4.x `index.{ts,go}` shapes per stack;
write to `migrations/test-fixtures/0017/known-wrapper-hashes.json`. These are the
"un-modified" reference hashes the refuse-path checks against.

### P5.3 — Migration 0017 fixtures + harness

**Files:** `migrations/test-fixtures/0017/` + `test_migration_0017()` in
`migrations/run-tests.sh`.

| Case | Setup | Verify | Exit |
|---|---|---|---|
| `01-fresh-apply-cparx-shape` | Go backend + React frontend, un-modified wrappers | adapters + registry added to both roots; CLAUDE.md v0.4.0 block | 0 |
| `02-fresh-apply-fxsa-shape` | 6 cf-worker roots + 1 react-vite, un-modified | all 7 roots migrated | 0 |
| `03-already-applied` | registry already present | zero changes (idempotent) | 0 |
| `04-hand-modified-refuse` | wrapper with extra logic (hash mismatch) | refuse, diff printed, no files written | non-zero |
| `05-multi-stack-partial` | one clean root + one hand-modified | clean root migrated, modified listed + refused | non-zero |
| `06-no-claudemd` | no CLAUDE.md | stub `observability:` block written to new CLAUDE.md | 0 |

**TDD:** fixtures (setup.sh/verify.sh/expected-exit) written FIRST (RED — harness
FAILs, migration absent), then migration authored (GREEN). Commits:
`test(migration-0017): 6 fixtures (RED)` → `feat(migration-0017): axiom logs destination (GREEN)`.

**P5 gate:**
- `bash migrations/run-tests.sh` PASS = prior(152) + 6, FAIL=0.
- Case 04 + 05 exit non-zero and write no wrapper files (verify via git status in
  the sandbox).
- `migrations/test-fixtures/0017/known-wrapper-hashes.json` exists and is valid JSON.

---

## P6 — CHANGELOG + version bumps + PR (G7)

### P6.1 — Version bumps

**Action:**
- `skill/SKILL.md`: `version: 1.15.0 → 1.16.0` (migration 0017 Step 3 does this;
  P6.1 verifies on disk). `implements_spec` stays `0.4.0`.
- `add-observability/SKILL.md`: `version: 0.4.0 → 0.5.0`. `implements_spec` stays
  `0.3.2`.

### P6.2 — CHANGELOG 1.16.0 entry

**Action:** prepend `## [1.16.0] — 2026-05-26` above 1.15.0. Cover: registry +
adapters across 5 stacks; cf-pages harness backfill (D3); 20 role-dispatch tests;
meta.yaml destinations block; INIT `--destinations` flag; migration 0017 (consent /
refuse semantics); CLAUDE.md v0.3.0→v0.4.0 block migration. Note Axiom span +
batching + dual-ship deferred to 1.17.0.

### P6.3 — PR

**Action:** `superpowers:finishing-a-development-branch` composes the PR
`[AGE-XX]: feat: add Axiom as logs destination (claude-workflow 1.16.0)`. Body
carries the cross-phase verification output.

**P6 gate:**
- `grep '^version:' skill/SKILL.md` ⇒ `1.16.0`; `add-observability/SKILL.md` ⇒ `0.5.0`.
- `grep -n '## \[1.16.0\]' CHANGELOG.md` present.

---

## Cross-phase verification (run before opening PR for review)

```bash
# Migration suite green (+6 for 0017)
bash migrations/run-tests.sh            # expect PASS=158 FAIL=0

# Interface byte-identity (G2): existing contract test files unchanged
git diff --stat main -- add-observability/templates/*/lib-observability.test.ts \
                         add-observability/templates/*/index.test.ts \
                         add-observability/templates/go-fly-http/observability_test.go
# expect: only ADDITIONS (new Axiom describe blocks), no edits to existing assertions

# Adapters present in all 5 stacks
for s in ts-cloudflare-worker ts-cloudflare-pages ts-supabase-edge ts-react-vite go-fly-http; do
  ls add-observability/templates/$s/destinations/ 2>/dev/null
done   # expect registry + sentry + axiom per stack

# Axiom has no errors role
grep -rL '"errors"' add-observability/templates/*/destinations/axiom.* | wc -l   # expect 5

# Type/build clean
# (per stack) npx vitest run ; deno test ; go build ./... && go test ./...

# Versions
grep '^version:' skill/SKILL.md                     # 1.16.0
grep '^version:' add-observability/SKILL.md         # 0.5.0
grep -n '## \[1.16.0\]' CHANGELOG.md                # present
```

Capture all of the above in the final PR description's "Verification" section.

---

## Post-phase gates (per agentic-apps-workflow skill)

- `/review` (stage 1: spec compliance) + `superpowers:requesting-code-review`
  (stage 2: code quality) → REVIEW.md with both stages.
- `/cso` — phase handles secret tokens (`AXIOM_TOKEN`) + an HTTP egress endpoint +
  browser token-exfil surface → SECURITY.md.
- `/gsd-review` (multi-AI plan review, ADR 0018) on THIS plan BEFORE execution →
  21-REVIEWS.md.
