# Phase 21 — Add Axiom as logs destination (Sentry stays errors-only)

**Branch**: `feat/axiom-logs-destination-v1.16.0`
**Spec target**: `agenticapps-workflow-core@v0.4.0` — §10.6 (destination independence) + §10.8 (project metadata). **No spec change.**
**Version bump**: `claude-workflow 1.15.0 → 1.16.0`; `add-observability` skill `0.4.0 → 0.5.0`; `implements_spec` unchanged (1.16.0→0.4.0, add-observability→0.3.2)
**Date opened**: 2026-05-26
**Hand-off source**: user-provided prompt (this session)
**Approved design spec**: `docs/superpowers/specs/2026-05-26-axiom-logs-destination-design.md` (brainstorming output — the research+design artifact for this phase)

## Background

The 5 stack templates (`ts-cloudflare-worker`, `ts-cloudflare-pages`,
`ts-supabase-edge`, `ts-react-vite`, `go-fly-http`) hardcode Sentry as the sole
observability destination. Spec §10.8's canonical project-metadata block already
exposes `destinations: { errors:, logs:, analytics: }`, and §10.6 already permits
multi-destination — but no template implements it. This phase makes future
`claude /add-observability init` wire **Sentry as the errors destination and Axiom
as the logs destination** via a role-based destination registry, and ships
migration 0017 so existing v0.4.0 projects opt-in. Sentry-only continues to work
for projects that skip the migration.

## Goals (must-haves)

| # | Goal | Evidence shape |
|---|------|----------------|
| G1 | Role-based destination registry + Sentry/Axiom adapters in all 5 stack wrappers | `destinations/{registry,sentry,axiom}.{ts,go}` present per stack; `registry.forRole("logs")`/`forRole("errors")` dispatch in wrapper `init`; `logEvent`→logs adapter, `captureError`→errors adapter |
| G2 | Wrapper public interface byte-identical (§10.1) | `init`/`Init`, `startSpan`, `logEvent`, `captureError` signatures unchanged vs 1.15.0; the 61 existing contract tests still pass unchanged |
| G3 | Axiom adapter emits logs, no-ops errors, fail-safe when unconfigured | 20 role-dispatch tests pass (5 stacks × 4 cases); `isConfigured()` false ⇒ no-op; `captureException` is a no-op on the Axiom adapter |
| G4 | ts-cloudflare-pages gains a full contract-test harness (D3) | `~15` baseline contract tests + 4 Axiom tests present and green; closes the pre-existing zero-coverage gap |
| G5 | Migration 0017 adopts the registry shape on existing v0.4.0 projects with §10.7 consent | `migrations/0017-add-axiom-logs-destination.md` + 6 fixtures; hand-modified wrappers refuse (exit non-zero + diff + guidance); CLAUDE.md `observability:` rewritten v0.3.0→v0.4.0 multi-destination via anchor-managed range |
| G6 | `init` gains role-map wiring; `meta.yaml` declares destinations | `--destinations errors=sentry,logs=axiom` flag in INIT.md; each `meta.yaml` has `destinations: { available, defaults, roles_supported }`; only role-referenced adapters copied at init |
| G7 | Version bump + CHANGELOG + green suites | `skill/SKILL.md` → `1.16.0`; `add-observability/SKILL.md` → `0.5.0`; CHANGELOG 1.16.0 entry; `migrations/run-tests.sh` PASS=prior+6 FAIL=0; 61+~35 contract tests green |

## Decisions / deltas from the hand-off (locked)

All carried into the approved spec. Summarised here for the planner/checker:

- **D1 — interface scope is FOUR entry points**, not three. `init`/`Init` is where
  the registry is built (load-bearing), plus `startSpan`/`logEvent`/`captureError`
  and the trace helpers + `Envelope`/`Span`/`TraceContext`/`InitEnv` types. The 61
  contract tests pin these; drift = refuse-to-merge (§10.1).
- **D2 — runtime role-map source = bake-at-init constant + `OBS_DESTINATIONS` env
  override.** CLAUDE.md is NOT readable at production runtime. The existing
  generator already carries a `DESTINATION` token in `meta.yaml` (currently
  comment-only); this makes it functional. CLAUDE.md's `observability:` block is the
  record of the decision, never the runtime source. Credentials stay pure env
  (`SENTRY_DSN`, `AXIOM_TOKEN`, `AXIOM_DATASET`).
- **D3 — ts-cloudflare-pages gains a full new test harness** (G4). It ships zero
  contract tests today.
- **D4 — 1.15.0 CHANGELOG backfill is the branch's first commit** (`bcbf539`, done).
- **D5 — no new TS flush export.** Go already exposes `Flush(timeout) bool`; the Go
  Axiom adapter wires into it. TS uses `ctx.waitUntil()` / `EdgeRuntime.waitUntil()`
  fire-and-forget — keeps the interface byte-identical.
- **D6 — adopted hand-off open-question recommendations:** US Axiom region default +
  `AXIOM_INGEST_URL` override; redact once in the wrapper before dispatch;
  anchor-managed CLAUDE.md range (migration 0014 idiom); `add-observability` →0.5.0.

## Canonical references

**Downstream agents MUST read these before planning or implementing.**

### Spec contract
- `~/Sourcecode/agenticapps/agenticapps-workflow-core/spec/10-observability.md` — §10.1 (wrapper interface), §10.5 (fire-and-forget + Flush), §10.6 (destination independence), §10.7 (consent rule), §10.8 (project metadata block, lines 174–183)

### Approved design
- `docs/superpowers/specs/2026-05-26-axiom-logs-destination-design.md` — full design (this phase's research artifact)

### Format precedents to mirror
- `migrations/0014-inject-spec-11-coding-discipline.md` — anchor-managed CLAUDE.md range idiom; migration frontmatter/preflight/idempotency shape
- `migrations/0016-fix-multi-ai-review-gate-resolution.md` — most recent migration shape
- `.planning/phases/20-spec-0.4.0-absorption/{CONTEXT,PLAN}.md` — local phase-doc convention (single PLAN.md, phase-grouped, per-phase verification gates)
- `add-observability/CONTRACT-VERIFICATION.md` — the 61-test contract baseline
- `add-observability/templates/ts-cloudflare-worker/{lib-observability.ts,meta.yaml,lib-observability.test.ts}` — canonical wrapper/meta/test reference

## Phase 0 discovery addendum (verified on disk 2026-05-26)

- **Public interface confirmed** (G2 anchor). TS exports: `init(env, ctx)`,
  `startSpan(name, attrs): Span`, `logEvent(envelope): void`,
  `captureError(err, envelope): void`, trace helpers
  (`parseTraceparent`/`newRootContext`/`formatTraceparent`/`runWithContext`/
  `getActiveContext`), types `Severity`/`SpanStatus`/`Envelope`/`Span`/
  `TraceContext`/`InitEnv`. Go: `Init()`, `StartSpan(ctx, name, attrs)`,
  `LogEvent(ctx, env)`, `CaptureError(ctx, err, env)`, `Flush(timeout) bool`, trace
  helpers. Template wrapper file is `lib-observability.ts` (materialises to
  `index.ts` per `target.wrapper_path`).
- **`meta.yaml spec_version: 0.2.1`** in the templates (the skill is 0.4.0; meta
  trails). A `DESTINATION` parameter already exists (`accepted: [sentry, axiom,
  otel, postgres]`) but is **comment-only** today — D2 makes it functional.
- **cf-pages has ZERO contract tests** (D3/G4). The real "61 tests" =
  cf-worker 15 / react-vite 22 / supabase-edge 12 / go-fly-http 12. There is **no
  unified template test runner**; the 4 existing suites run via materialize-and-test
  (vitest/deno/go), toolchain-dependent.
- **No `ROADMAP.md`** in `.planning/`. Phases are directories; `current-phase` is a
  symlink (→ phase 20). This phase follows the local single-`PLAN.md` convention,
  not the GSD roadmap-orchestration path.
- **Migration baseline green**: `bash migrations/run-tests.sh` ⇒ **PASS=152 FAIL=0**
  (preflight audit PASS=19 FAIL=0 SKIP=5), verified 2026-05-26 before any change.

## Non-goals (preserved from hand-off)

- No destinations beyond Sentry + Axiom (registry leaves room; Grafana/Honeycomb/
  OTLP defer to future PRs).
- No spec change (§10.6 + §10.8 already permit multi-destination).
- No `captureError` → Axiom dual-ship (errors role = Sentry only).
- No automatic Axiom resource creation (user creates dataset + token, pastes into
  secrets).
- No auto-batching (one event per POST in 1.16.0; batching defers to 1.17.0).
- No Axiom span emission (analytics role; defer to 1.17.0).
- No wrapper-interface change (the four entry points stay byte-identical).
- No downstream project adoption in this PR (cparx/fx-signal-agent/callbot pick up
  1.16.0 + migration 0017 in separate PRs).

## Artifacts this phase produces

- `add-observability/templates/*/destinations/{registry,sentry,axiom}.{ts,go}` (×5 stacks)
- Rewritten `add-observability/templates/*/lib-observability.{ts}` / `observability.go` (registry-dispatched internals; exports unchanged)
- cf-pages full test harness + 20 Axiom role-dispatch tests across 5 stacks
- Updated `add-observability/templates/*/{meta.yaml,env-additions.md,policy.md}`
- Updated `add-observability/init/INIT.md` (`--destinations` flag + "Destination role assignment" section)
- `migrations/0017-add-axiom-logs-destination.md` + `migrations/test-fixtures/0017/` (6 cases + `known-wrapper-hashes.json`) + `test_migration_0017()` in `run-tests.sh`
- Version bumps: `skill/SKILL.md` (1.16.0), `add-observability/SKILL.md` (0.5.0)
- `CHANGELOG.md` 1.16.0 entry
- PR `[AGE-XX]: feat: add Axiom as logs destination (claude-workflow 1.16.0)`
