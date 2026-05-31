# Phase 25: Fix 0019 engine + withCronMonitor — Context

**Gathered:** 2026-05-31
**Revised:** 2026-05-31 (three rounds:
  (a) post-research — D-01 reframed, D-02 split into D-02a/b, D-09 expanded, OQ-1..7 resolved;
  (b) post-plan-checker iter-1 — OQ-9 contract tightening across Plans 03/04;
  (c) post-codex-review — D-05 scope narrowed to cf-worker only, D-07 scope narrowed to cf-worker + cf-pages, D-02b reshaped to migration 0021 with dirty detection)
**Status:** Ready for re-planning (`/gsd-plan-phase 25 --reviews`)
**Source:** [Issue #56](https://github.com/agenticapps-eu/claude-workflow/issues/56) — four gaps surfaced migrating callbot v1.16.0 → v1.19.0

<domain>
## Phase Boundary

This phase closes the four discrete gaps documented in issue #56 inside the `claude-workflow` repo plus two post-research scope additions:

1. **0019 migration engine** accepts `index.ts`-anchored wrappers as the **canonical materialised filename** (per `meta.yaml:target.wrapper_path` — researcher revised the D-01 framing; see D-01) for `ts-cloudflare-worker` and `ts-cloudflare-pages` stacks; `lib-observability.ts` continues to work as a legacy/fixture filename.
2. **`CronMonitorSchedule`** in `add-observability` TS templates becomes a real discriminated union matching Sentry's `MonitorSchedule` shape ([VERIFIED] in installed `@sentry/core@8.55.2` types). Applies to all three TS stacks + openrouter-monitor bundled (the type interface is independent of the wrapper's generic shape).
3. **`withCronMonitor`** generic constraint narrows from `<E extends Record<string, unknown>>` to `<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>` **on cf-worker only** (codex review: cf-pages uses `<R>` return-type generic and supabase-edge has no generics — D-05 is structurally inapplicable there).
4. **`withQueueMonitor`** ships as a new export with Guarded Shape A semantics (ADR-0029), in **cf-worker + cf-pages only** (codex review: supabase-edge is Deno-runtime; `MessageBatch` + `ExecutionContext` are Workers-runtime types — no Cloudflare-Queue equivalent on Supabase Edge).
5. **NEW Migration 0021** (`from_version: 1.19.0` → `to_version: 1.20.0`) for **already-migrated projects**. **Re-rev shape with dirty detection** (codex H-7 verified — additive-only would not deliver D-03/D-05 fixes to callbot at 1.19.0). 0021 copies updated `cron-monitor.ts` (D-03 + D-05) AND new `queue-monitor.ts`; mirrors 0019's `canonicalize_awk` content-hash + all-clean-gate + per-root apply pattern. Refuses on hand-modified `cron-monitor.ts` and emits `.observability-0021.patch` (callbot's LOCAL-PATCH at `cron-monitor.ts:141-149` WILL trigger refuse; honest: callbot drops the LOCAL-PATCH first, then re-applies).
6. **NEW openrouter-monitor bundled subtree gets D-03/D-05 fixes.** Phase 24's bundled `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` is a snapshot of the cf-worker template; applying the fixes symmetrically prevents future Phase 24 scaffold consumers from shipping the broken type.

**Out of scope (deferred):**
- callbot-side cleanup (separate callbot PR; consumer-side adoption is downstream).
- DEF-1 (TRACE_SAMPLE_RATE unwired), DEF-2 (REDACTED_KEYS missing authorization/bearer), DEF-3 (module-level mutable singletons), F-2 (package-lock.json policy), `.gitignore` extension to worker/pages/supabase-edge templates — all Phase 26 worker-template-hardening.
- Full retroactive bootstrap of ROADMAP.md (Phases 01-24) + STATE.md + PROJECT.md — own future phase.
- `FIX-0017-ENGINE.md` (untracked working-dir prompt for separate migration 0017 engine bugs surfaced by cparx) — distinct scope, own future phase.
- `maxRuntime` seconds-vs-minutes pre-existing template quirk (researcher's Sentry Type Verification note 3) — Phase 26 candidate.
- **NEW (codex review):** ts-supabase-edge/queue-monitor.ts — Deno/Supabase stack has no Cloudflare-Queue equivalent; revisit if a Deno-Queue-equivalent surfaces.
- **NEW (codex review):** ts-cloudflare-pages D-05 generic narrowing — pages signature is `<R>(handler: () => Promise<R>, ...): (env: Record<string, unknown>) => Promise<R>`, no `<E>` generic to narrow. If callbot or similar needs strict-Env on cf-pages, that's a separate Phase 26+ refactor.
- **NEW (codex review):** ts-supabase-edge D-05 generic narrowing — supabase-edge reads `Deno.env.get()` directly with no Env parameter. If a Deno-shaped strict-env idiom emerges, separate phase.

</domain>

<decisions>
## Implementation Decisions

### 0019 Engine — anchor file detection

- **D-01 [REVISED post-research]:** `index.ts` is the **canonical materialised filename** for cf-worker + cf-pages wrappers per `meta.yaml:target.wrapper_path` across all three TS stacks. `lib-observability.ts` is the **template source filename** (test fixtures hand-seed it, which is why the bug shipped green). The engine treats `index.ts` as a first-class anchor (not an alias of the legacy fixture name); `lib-observability.ts` continues to work for fixture compatibility. Implementation: extend `find` candidate collection in `migrate-0019-sentry-crons-and-healthz.sh:224-226` to include `-name index.ts`, add classify branches at `:317-331` so cf-worker matches `(index.ts OR lib-observability.ts) + middleware.ts` and cf-pages matches `(index.ts OR lib-observability.ts) + _middleware.ts`, and add a `resolve_anchor_files()` helper that picks the actually-present anchor at fingerprint time. The `middleware.ts` / `_middleware.ts` co-anchor requirement guards against unintended `index.ts` matches in unrelated dirs (e.g., `dist/`, `node_modules/`). Pre-classify filter recommended over fail-closed `SKIP_UNSUPPORTED` to avoid operator-facing noise. **Codex M-2 follow-up:** filter must also discard dirs whose path matches `dist/` / `build/` / `out/` patterns even with both `index.ts` + `middleware.ts` present (build outputs are typed compiled output that happens to share filenames).
- **D-02a [REVISED post-research]:** Migration **0019 in-place edits** — engine fix (D-01) + 0019 expanded copy list (D-11 — adds `queue-monitor.{ts,go}`) + docs amendment in `migrations/0019-sentry-crons-and-healthz.md`. Applies to pre-1.18.0 projects only (`from_version: 1.17.0` exact-match per `migrations/README.md:60-99`). Affected projects that previously failed 0019 due to the anchor mismatch can now re-run cleanly via the standard migration runner — no `--force` flag (it does not exist; researcher verified). 0019.md gains a "Recovery" subsection explicitly referencing D-02b as the supported path for v1.19.0 projects.
- **D-02b [REVISED post-codex-review]:** Ship migration **0021** (`from_version: 1.19.0` → `to_version: 1.20.0`) as a **re-rev with dirty detection** for already-migrated projects. Engine mirrors 0019's `canonicalize_awk` content-hash + all-clean-gate + per-root apply pattern. Files copied: updated `cron-monitor.ts` (D-03 + D-05 fixes for cf-worker; D-03-only for cf-pages — supabase-edge skipped since D-05 doesn't apply there) AND new `queue-monitor.ts` (cf-worker + cf-pages). Idempotency check: BOTH (a) `queue-monitor.ts` presence AND (b) cron-monitor.ts content-hash matches v1.20.0 baseline. Refuses on hand-modified `cron-monitor.ts` (callbot's LOCAL-PATCH triggers refuse) and emits `.observability-0021.patch` listing the diff. Honest: callbot drops the LOCAL-PATCH first → re-runs 0021 cleanly. Closes findings 2 + 3 + 4 of issue #56 for already-migrated consumers. (Original additive-only 0021 design — codex H-7: didn't deliver cron-monitor.ts fixes to v1.19.0 projects; rejected by user post-codex-review.) Per researcher's Pitfall 2 option (a) shape; user-locked 2026-05-31.

### Schedule type — discriminated union

- **D-03:** Replace `interface CronMonitorSchedule { type: "crontab" | "interval"; value: string }` with `type CronMonitorSchedule = { type: "crontab"; value: string } | { type: "interval"; value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" }`. Matches Sentry's `MonitorSchedule` discriminated union. Eliminates the consumer-side LOCAL-PATCH cast in callbot's `cron-monitor.ts:141-149`. **Applies symmetrically to all three TS templates** (`ts-cloudflare-worker/cron-monitor.ts:20-23`, `ts-cloudflare-pages/cron-monitor.ts:27-30`, `ts-supabase-edge/cron-monitor.ts:35-38`) **and** the bundled `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` per D-21. The schedule type interface is decoupled from the wrapper's env-generic shape; symmetry verified post-codex-review. Go template (`cron_monitor.go`) needs no change — already uses native `sentry.MonitorSchedule` interface.
- **D-04:** Type-shape change is functionally non-breaking. Consumers with the `interval` variant against the current template's `value: string` shape cannot compile against `Sentry.withMonitor`'s 3rd-arg type today — the population of working consumers using interval is empty. Consumers using `crontab` variant unchanged. Minor bump for `add-observability` (D-13).

### Generic narrowing — strict Env support

- **D-05 [REVISED post-codex-review, 2026-05-31]:** Narrow `withCronMonitor<E extends Record<string, unknown>>` → `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>` for **cf-worker only**. Inside the wrapper, the dynamic env-var lookup at `cron-monitor.ts:69-70` becomes `(env as unknown as Record<string, unknown>)[envKey]`. Apply symmetrically to: `ts-cloudflare-worker/cron-monitor.ts` + `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` (bundled cf-worker snapshot per D-21). **DROPPED from scope (codex H-3 verified):** `ts-cloudflare-pages/cron-monitor.ts` has `withCronMonitor<R>(handler: () => Promise<R>, ...): (env: Record<string, unknown>) => Promise<R>` — `<R>` is the return type, not env type; D-05 is structurally inapplicable. `ts-supabase-edge/cron-monitor.ts` has no generics and reads `Deno.env.get()` directly (line 114 `isConfigured(): boolean`); D-05 is structurally inapplicable.
- **D-06 [REVISED post-codex-review]:** Generic narrowing remains functionally non-breaking — every cf-worker `E` that satisfied the old constraint satisfies the new one. cf-pages and supabase-edge unaffected (no signature change there). Minor bump for `add-observability` (D-13).

### Helper export contract (OQ-9 — REVISED post-codex-review)

- **D-19 [REVISED]:** Helper export contract for queue-monitor.ts re-import. Applies to cf-worker + cf-pages (where queue-monitor.ts ships per D-07). `cron-monitor.ts` exports `buildMonitorConfig` and `isConfigured` (adds `export` keyword to existing module-private functions). `queue-monitor.ts` re-imports via `import { type CronMonitorConfig, buildMonitorConfig, isConfigured } from "./cron-monitor"`. Both files always co-copy via 0019 (fresh applies) and 0021 (already-migrated). **Does NOT apply to supabase-edge** — D-07 dropped that variant; supabase-edge `isConfigured()` has no env parameter and is Deno-runtime-specific.

### withQueueMonitor — new export

- **D-07 [REVISED post-codex-review]:** New file `queue-monitor.ts` in `add-observability/templates/ts-cloudflare-worker/` and `add-observability/templates/ts-cloudflare-pages/` only. **DROPPED supabase-edge from scope (codex H-6 verified):** Supabase Edge runs on Deno and has no Cloudflare Queue equivalent — `MessageBatch` / `ExecutionContext` are Workers-runtime types. Shipping `ts-supabase-edge/queue-monitor.ts` "for symmetry" creates a non-functional file in a Deno-runtime template. Signature for cf-worker + cf-pages: `withQueueMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }, Msg = unknown>(handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>, config?: CronMonitorConfig): typeof handler`. Same `CronMonitorConfig` shape — slug resolution + monitorConfig forwarding — reused. cf-pages Queue handlers exist (Pages Functions supports Queue consumers); same signature as cf-worker.
- **D-08:** Guarded Shape A semantics (ADR-0029 / Phase 23 D-08): `handlerStarted` flag distinguishes pre-callback transport failure (fall back to unmonitored handler — queue consumer always runs) from post-callback errors (propagate to outer wrapper). Mirrors `withCronMonitor` line-for-line; only the handler signature differs. **Codex M-6 addition:** test surface (D-17) must include an **explicit synchronous-throw test** — handler sets `handlerStarted = true` and throws synchronously; wrapper must re-throw (post-callback path), not fall back to unmonitored. Existing tests cover async rejection; sync throw is the under-tested corner.
- **D-09:** Slug resolution mirrors `withCronMonitor`'s D6 3-source policy: explicit `config.monitorSlug` > env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` (uppercased, hyphens → underscores) > auto-derive `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`. Auto-derive uses `MessageBatch.queue` (Cloudflare Workers Types field, [VERIFIED] at `node_modules/@cloudflare/workers-types/index.d.ts:2382`). **Default `handlerName` is `"queue"`** (vs cron's `"scheduled"`); env-key naming `SENTRY_CRON_MONITOR_SLUG_QUEUE`. Reuses the shared `SENTRY_CRON_MONITOR_SLUG_*` prefix — Sentry server-side doesn't distinguish cron vs queue at the monitor_slug field, and operators get one naming convention.
- **D-10 [RESOLVED post-research, OQ-3]:** Multi-queue policy: **silent + docs** (mirrors Phase 22 D11). Handlers that dispatch by `batch.queue` MUST pass explicit `monitorSlug`, documented in the `queue-monitor.ts` doc comment and in `migrations/0019-sentry-crons-and-healthz.md`'s queue-monitor section. No compile-time overload signatures, no runtime warn — same enforcement shape as cron-monitor's D11.
- **D-11 [REVISED post-codex-review]:** Migration 0019 expanded to copy `queue-monitor.ts` alongside existing files **for fresh applies (pre-1.18.0 projects)**, in cf-worker + cf-pages only (per D-07 scope revision). Idempotency marker stays `cron-monitor.ts` presence. v1.19.0+ projects ride 0021 per D-02b — NOT 0019. Migration markdown header gets a "Re-rev 2026-05-31 (Phase 25)" note documenting the expanded file set; filename remains `0019-sentry-crons-and-healthz.md`.
- **D-12:** Go template (`go-fly-http/queue_monitor.go`) — out of scope this phase. Fly HTTP workers don't have Cloudflare Queue equivalents.

### Versioning

- **D-13:** `add-observability` bumps 0.8.0 → 0.9.0 (minor). Template surface changes (now narrower than originally planned): D-03 schedule type fix across 4 sites, D-05 generic narrowing on cf-worker + openrouter only, new `queue-monitor.ts` on cf-worker + cf-pages, D-19 export-helper contract on cf-worker + cf-pages. Symmetric to Phase 23's 0.6.0 → 0.7.0 minor bump.
- **D-14 [REVISED post-codex-review]:** `claude-workflow` bumps 1.19.0 → 1.20.0 (minor). 0019 re-rev + new 0021 re-rev (with dirty detection per D-02b). Two migration deltas; minor is honest (codex confirmed against repo's "patch for clarifications, minor for additive, major for breaking" guidance).

### Test surface

- **D-15 [REVISED post-codex-review]:** Extend `migrations/test-fixtures/0019/` with: (a) `08-index-ts-anchored-worker/` for D-01 cf-worker; (b) `09-index-ts-anchored-pages/` for D-01 cf-pages; (c) `11-stray-index-ts-no-co-anchor/` negative fixture (SKIP_UNSUPPORTED on bare index.ts); (d) `12-dist-shaped-anchor-pair/` negative fixture (codex M-2 — dist/build/out path detection even with both anchors present). Plus `migrations/test-fixtures/0021/` with: (e) `01-fresh-1.19.0-apply/` happy-path re-rev test; (f) `02-callbot-shape-dirty-refuse/` REFUSE with LOCAL-PATCH simulation; (g) `03-already-1.20.0-skip/` idempotency check. Each fixture asserts: discovery + classify + apply + idempotency per fixture's expected outcome. **Codex M-1 addition:** 0021 fixtures use **frozen literal files** under the fixture dir, NOT `cp` from mutable template sources (otherwise Plan 03's cron-monitor.ts edit breaks the "v1.19.0 baseline" fixture).
- **D-16 [REVISED post-codex-review]:** Extend `cron-monitor.test.ts` per stack with: (a) **D-03 type-level test asserting `CronMonitorSchedule` interval variant requires `value: number + unit`** — applies to all three stacks (worker, pages, supabase-edge). Use vitest's `expectTypeOf` AND an explicit `const _check: Sentry.MonitorConfig['schedule'] = ourSchedule` pattern as the firewall against the harness's `skipLibCheck: true` blind spot (researcher's Pitfall 4). (b) **D-05 generic-narrowing fixture using a strict-typed `Env` interface** — applies to **cf-worker only** (pages and supabase-edge unaffected by D-05). (c) Regression assertion that `crontab` variant still compiles unchanged — all stacks.
- **D-17 [REVISED post-codex-review]:** New `queue-monitor.test.ts` in **cf-worker + cf-pages only**. Structured identically to `cron-monitor.test.ts`. Mocks `@sentry/cloudflare`'s `withMonitor`; asserts D-08 happy path, D-09 slug resolution from all three sources, Guarded Shape A pre-callback vs post-callback distinction. **Codex M-6 explicit sync-throw test** for D-08 (handler sets handlerStarted=true and throws synchronously; wrapper re-throws). Multi-queue explicit-slug enforcement (D-10) verified by doc-comment presence assertion using tightened regex `/multi-queue.*MUST.*monitorSlug|MUST set monitorSlug explicitly|MUST pass explicit.*monitorSlug/i` (no organic `batch.queue` match). ts-supabase-edge variant DROPPED with D-07.
- **D-18 [REVISED post-codex-review]:** SC5 acceptance via **migrated-wrapper typecheck fixture**, NOT template-import fixture (codex H-1: template-import doesn't prove the supported migration path works). Fixture location: `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/`. Procedure: (a) seed a post-0019 v1.19.0 consumer wrapper tree (frozen literal files — same convention as D-15 M-1 fix); (b) run migration 0021 against it; (c) typecheck the resulting wrapper tree with `tsc --noEmit` using a callbot-shape strict `Env` interface (named fields, no `[k: string]`); (d) verify `withCronMonitor<CallbotEnv>` AND `withQueueMonitor<CallbotEnv>` both compile without consumer-side casts. **Codex H-2 fix:** fixture includes a local `types.d.ts` with minimal `ScheduledController` + `ExecutionContext` + `MessageBatch` ambient declarations rather than depending on `@cloudflare/workers-types` from the harness's package install.

### Post-research scope expansion (Phase Boundary item 6)

- **D-21 [NEW post-research, OQ-6]:** Apply D-03 + D-05 fixes symmetrically to the bundled openrouter-monitor copy at `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts`. Same diffs as `ts-cloudflare-worker/cron-monitor.ts`; verification step: `diff add-observability/templates/ts-cloudflare-worker/cron-monitor.ts add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` returns empty post-execute. openrouter-monitor's pinned `@sentry/cloudflare ^8.0.0` (Phase 24 carve-out) is unaffected. Does **not** include adding `queue-monitor.ts` to openrouter-monitor (no Queue trigger in monitor scaffold scope).

### Claude's Discretion (after research + codex review)

- Migration 0021.md docs structure — full standalone spec mirroring 0019.md (recommended given re-rev shape) vs cross-reference (less appropriate for a non-additive migration). Planner picks per docs convention.
- Exact placement of `as unknown as Record<string, unknown>` cast inside `resolveSlug` in cf-worker cron-monitor.ts — function boundary vs `env[envKey]` access site. Researcher recommends access-site (1-line change).
- Whether `queue-monitor.test.ts` mocks `MessageBatch` via `@cloudflare/workers-types` import or hand-rolls a minimal interface — planner picks per existing test conventions (cron-monitor.test.ts:32 uses `{...} as ScheduledController` pattern; suggest mirroring with `as MessageBatch<unknown>`).
- 0021 engine — mirror 0019's full canonicaliser shape (recommended given re-rev semantics) or thinner variant. Re-rev shape mandates the canonicaliser since dirty detection is required.

### Folded Todos

No matching todos surfaced.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Issue + field report
- `https://github.com/agenticapps-eu/claude-workflow/issues/56` — primary source of the four findings
- `https://github.com/agenticapps-eu/callbot/pull/45` — callbot's hand-applied 0019 migration commits (`adbbe5b`, `f42caaa`); the "acceptance check" in #56 §"Acceptance check" defines callbot's success criteria

### Migration + engine
- `migrations/README.md` §"Frontmatter fields" + §"Picking versions" — the runner contract (`from_version` exact-match)
- `migrations/0019-sentry-crons-and-healthz.md` — gets D-02a docs amendment + D-11 expansion (cf-worker + cf-pages queue-monitor.ts on fresh applies)
- **NEW:** `migrations/0021-add-queue-monitor.md` (or `0021-with-cron-and-queue-updates.md` — planner picks per docs convention) — `from_version: 1.19.0` → `to_version: 1.20.0`, **re-rev shape with dirty detection** per D-02b
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` — engine; D-01 fix sites
- **NEW:** `templates/.claude/scripts/migrate-0021-*.sh` — new engine; mirrors 0019's canonicalize_awk + all-clean-gate + per-root apply (re-rev shape per D-02b)
- `migrations/test-fixtures/0019/` — fixtures 08, 09, 11, 12 (codex M-2 dist-path negative case)
- **NEW:** `migrations/test-fixtures/0021/` — fixtures 01 (fresh-apply), 02 (callbot dirty refuse), 03 (idempotency), 04 (D-18 migrated-wrapper SC5)

### add-observability templates (revised fix sites per D-05 + D-07 narrowing)
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` — **D-03 + D-05 + D-19 export contract** fixes
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` — **D-16 (a)(b)(c)** tests
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` — **D-03 + D-19 export contract only** (no D-05 — pages signature is `<R>` return-type generic)
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts` — **D-16 (a)(c) only** (no (b) generic-narrowing test — N/A here)
- `add-observability/templates/ts-supabase-edge/cron-monitor.ts` — **D-03 only** (no D-05 — no generic; no D-19 export contract — D-07 dropped)
- `add-observability/templates/ts-supabase-edge/cron-monitor.test.ts` — **D-16 (a)(c) only**
- `add-observability/templates/go-fly-http/cron_monitor.go` — N/A (Go uses native sentry.MonitorSchedule)
- **NEW per D-21:** `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` — bundled cf-worker snapshot; same diffs as cf-worker (D-03 + D-05 + D-19)
- NEW: `add-observability/templates/ts-cloudflare-worker/queue-monitor.ts` (D-07 + D-08 + D-09 + D-10)
- NEW: `add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts` (D-17 with sync-throw)
- NEW: `add-observability/templates/ts-cloudflare-pages/queue-monitor.ts` (D-07 + D-08 + D-09 + D-10)
- NEW: `add-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts` (D-17 with sync-throw)
- **DROPPED per D-07 revision:** `add-observability/templates/ts-supabase-edge/queue-monitor.ts` + tests — Supabase Edge has no Cloudflare Queue equivalent

### Phase 22 + 23 prior decisions
- `.planning/phases/22-sentry-crons-healthz/CONTEXT.md` — D1/D5a/D6/D11/D12 — all carry forward to `withQueueMonitor`
- `.planning/phases/23-observability-followups/CONTEXT.md` — F5 / D-08 / ADR-0029 (Guarded Shape A)

### ADRs
- `docs/decisions/0028-*.md` through `0030-*.md` — existing
- **NEW:** `docs/decisions/0031-0019-engine-index-ts-anchor.md` (D-01)
- **NEW:** `docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md` (D-05 — title reflects narrowed scope post-codex review)
- **NEW:** `docs/decisions/0033-with-queue-monitor.md` (D-07 + D-02b migration 0021 rationale + dirty-detection design)

### Sentry SDK ([VERIFIED] in installed 8.55.2) + Cloudflare Workers Types ([VERIFIED])
- `node_modules/@sentry/core/build/types/types-hoist/checkin.d.ts:2-12` — `MonitorSchedule` discriminated union
- `node_modules/@sentry/core/build/types/exports.d.ts:95` — `withMonitor<T>(slug, callback, monitorConfig?)`
- `node_modules/@cloudflare/workers-types/index.d.ts:2379-2386` — `MessageBatch<Body>` shape
- `node_modules/@cloudflare/workers-types/index.d.ts:510-516, :14282` — Queue handler signature

### Repo-level instructions
- `CLAUDE.md` (project root) — GitNexus impact analysis required for symbol edits
- `migrations/README.md:60-99` — runner contract
- `versioning-tracks-migrations.md` memory — D-14 rationale

</canonical_refs>

<code_context>
## Existing Code Insights

### Verified template signatures (post-codex-review evidence)

| Stack | `withCronMonitor` signature | `isConfigured` signature | D-03 applies? | D-05 applies? | D-07 applies? |
|-------|----------------------------|--------------------------|---------------|---------------|---------------|
| **cf-worker** | `<E extends Record<string, unknown>>(handler: ScheduledFn<E>, ...)` | `(env: Record<string, unknown>)` | YES | YES | YES |
| **cf-pages** | `<R>(handler: () => Promise<R>, ...): (env: Record<string, unknown>) => Promise<R>` (`<R>` is return type) | `(env: Record<string, unknown>)` (not generic) | YES | NO | YES |
| **supabase-edge** | `(handler: (req: Request) => Promise<Response>, ...)` (no generics, reads `Deno.env`) | `()` (NO env param; reads `Deno.env.get()`) | YES | NO | NO |
| **openrouter-monitor bundled** | cf-worker snapshot | cf-worker snapshot | YES | YES | NO |

### Reusable Assets
- `CronMonitorConfig` interface (`cron-monitor.ts:25-35` cf-worker; similar shapes per stack) — reused by `withQueueMonitor` (D-07). D-19 export contract: cf-worker + cf-pages export it; supabase-edge does NOT export (D-07 dropped).
- `resolveSlug` (cf-worker `cron-monitor.ts:58-76`) — pattern reused for `resolveQueueSlug`; only the auto-derive line differs.
- `buildMonitorConfig` (cf-worker `cron-monitor.ts:86-97`) — fully reusable; D-19 makes it exported on cf-worker + cf-pages.
- Phase 23 test harness (`cron-monitor.test.ts`) — pattern reused for `queue-monitor.test.ts`.
- Migration 0017 → 0019 engine pattern — `canonicalize_awk` content-hash + all-clean gate + per-root apply. **Migration 0021 mirrors this shape** (D-02b re-rev requires dirty detection).

### Established Patterns
- **Guarded Shape A** (ADR-0029) — `handlerStarted` flag pattern, mandated for any new Sentry-wrapped handler.
- **3-source slug resolution + D11/D-10 explicit-slug requirement** — established in Phase 22, mirrored by `withQueueMonitor`.
- **Anchor file co-requirement** — engine requires both anchor file AND middleware co-anchor to classify (D-01 preserves).
- **Per-stack file symmetry** — narrowed by codex review: cf-worker + openrouter for D-05; cf-worker + cf-pages for D-07.
- **F5 behavioural-parity tests** — mock `@sentry/cloudflare`'s `withMonitor`; assert behaviour shape.
- **Migration idempotency via marker-file presence** — 0019 uses `cron-monitor.ts`; 0021 uses **BOTH** `queue-monitor.ts` presence AND `cron-monitor.ts` content-hash matches v1.20.0 baseline (re-rev shape).

### Integration Points (revised per codex review)
- `migrate-0019-sentry-crons-and-healthz.sh:219-229` (find candidates) + `:317-331` (classify) + `:340-348` (stack_fingerprint_files) — D-01 fix sites
- `migrate-0019-sentry-crons-and-healthz.sh:566-591` (`emit_refuse_artifacts_for`) — also emit would-be `queue-monitor.ts` (codex M-3: refuse path must also use `resolve_anchor_files()` not the old `stack_fingerprint_files()`)
- `migrate-0019-sentry-crons-and-healthz.sh:686-728` (apply_root Files Copied) — D-11 expansion: copy `queue-monitor.ts` for cf-worker + cf-pages
- **NEW:** `templates/.claude/scripts/migrate-0021-*.sh` — new engine; mirrors 0019's canonicaliser + all-clean-gate; copies updated cron-monitor.ts (cf-worker + cf-pages) AND queue-monitor.ts (cf-worker + cf-pages)
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:20-23` (D-03), `:115` (D-05 generic), `:86, :47` (D-19 export keywords) — fix sites
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts:27-30` (D-03), `:86, :49` (D-19 export keywords) — fix sites (no D-05)
- `add-observability/templates/ts-supabase-edge/cron-monitor.ts:35-38` (D-03 only)
- `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` — D-21 (D-03 + D-05 + D-19)
- `migrations/0019-sentry-crons-and-healthz.md` — D-02a docs amendment + D-11 queue-monitor section
- **NEW:** `migrations/0021-*.md` — D-02b new migration spec (re-rev shape)
- `CHANGELOG.md` — 1.20.0 entry covering 0019 re-rev + 0021 + add-observability 0.9.0

</code_context>

<specifics>
## Specific Ideas

- **callbot is the acceptance fixture (proxy via D-18).** Issue #56 §"Acceptance check" lists four observable outcomes. The synthetic strict-Env typecheck fixture (D-18, REVISED to migrated-wrapper shape per codex H-1) proves them: (1) re-run 0021 cleanly via the engine (after dropping LOCAL-PATCH — which is exactly what callbot will do post-Phase-25); (2) updated cron-monitor.ts has D-03 fix (no LOCAL-PATCH cast needed); (3) `withQueueMonitor` exists; (4) strict-typed Env compiles via D-05 narrowing.
- **callbot's LOCAL-PATCH triggers 0021 REFUSE — by design (codex H-7 honest path).** callbot dropping the LOCAL-PATCH is part of the supported upgrade path: drop patch → re-run 0021 → engine accepts → updated cron-monitor.ts ships with D-03 fix → patch becomes unnecessary. This is the honest user story; documented in 0021.md "Recovery" section.
- **F5 behavioural-parity tests are the firewall against downstream regression** (Phase 23 reasoning preserved).
- **skipLibCheck test harness blind spot — D-16 explicit firewall.** D-16(a) tests use BOTH `expectTypeOf` AND `const _: Sentry.MonitorConfig['schedule'] = ourSchedule`.
- **No Sentry SDK version pin change.** `@sentry/cloudflare ^8.0.0` template pin; consumer `^10.2.0` floor per Phase 24 unaffected.
- **`index.ts` over-match pitfall** — sibling-anchor filter required; codex M-2 adds dist/build/out path negative filter as well (fixture 12).

</specifics>

<deferred>
## Deferred Ideas

### Phase 26 carry-forward
- DEF-1, DEF-2, DEF-3 (worker-template hardening)
- F-2 lockfile policy
- `.gitignore` extension to other templates

### NEW post-codex-review deferrals
- **cf-pages D-05 equivalent** — if a use case for strict-Env on cf-pages surfaces, separate phase to refactor pages signature from `<R>(handler: () => Promise<R>, ...): (env: ...) => Promise<R>` to a generic-env shape.
- **supabase-edge D-05 equivalent** — if a Deno-shaped strict-env idiom emerges (e.g., a `DenoEnvShim` interface), separate phase.
- **ts-supabase-edge queue-monitor.ts** — if a Deno-Queue-equivalent surfaces (e.g., Supabase RPC queues), separate phase.

### Other deferred
- `maxRuntime` seconds-vs-minutes quirk — Phase 26
- `buildMonitorConfig` return-type tightening — only if Sentry changes their stance
- Real callbot adoption PR — post-1.20.0 consumer-side work
- Full retroactive bootstrap of ROADMAP.md / STATE.md / PROJECT.md
- Migration 0017 engine fixes (cparx)
- `withQueueMonitor` for Go (Fly HTTP — no Queue equivalent)
- GH Actions CI

</deferred>

<open_questions>
## Open Questions

### Resolved post-research
- OQ-1 (filename): Keep `0019-…md`; new `0021-…md` per planner
- OQ-2 (supabase-edge queue-monitor): **OVERTURNED post-codex-review** — DROPPED (was "ship for parity"; codex H-6: no Cloudflare-Queue equivalent on Deno/Supabase). See D-07.
- OQ-3 (multi-queue): silent + docs (D-10)
- OQ-4 (ADR numbering): 0031, 0032, 0033
- OQ-5 (--force flag): doesn't exist; not adding
- OQ-6 (openrouter-monitor): included per D-21
- OQ-7 (SC5 verification): **REVISED post-codex-review** — migrated-wrapper fixture per D-18 (was "template-import only"; codex H-1 verified)

### Resolved post-codex-review (NEW)
- **OQ-12 (D-05 scope):** cf-worker + openrouter-monitor only. cf-pages + supabase-edge structurally inapplicable.
- **OQ-13 (D-07 scope):** cf-worker + cf-pages only. supabase-edge structurally inapplicable.
- **OQ-14 (D-02b shape):** Re-rev with dirty detection (mirroring 0019 canonicalize_awk). Additive-only design rejected — wouldn't close findings 2+3 for v1.19.0 consumers.

### Still planner-level
- **OQ-8:** Migration 0021 engine shape — **resolved as re-rev** by OQ-14 / D-02b. Mirror 0019's canonicalize_awk + all-clean-gate. Was: "thinner additive-only".
- **OQ-9:** queue-monitor.ts re-imports helpers from `./cron-monitor` per D-19 (recommended; planner-locked iter-1). Single import line; no inline duplication.
- ~~OQ-10 (supabase-edge queue-monitor Deno specifier)~~ — N/A: supabase-edge queue-monitor.ts dropped (D-07 revision).
- **OQ-11:** Migration 0021 docs structure — full standalone spec mirroring 0019.md (recommended given re-rev shape; cross-reference inadequate for non-additive migration).

</open_questions>

---

*Phase: 25-fix-0019-engine-and-cron-wrappers*
*Context gathered: 2026-05-31*
*Revised post-research: 2026-05-31*
*Revised post-codex-review: 2026-05-31*
