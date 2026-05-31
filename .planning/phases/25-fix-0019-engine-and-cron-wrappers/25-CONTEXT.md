# Phase 25: Fix 0019 engine + withCronMonitor — Context

**Gathered:** 2026-05-31
**Revised:** 2026-05-31 (post-research; D-01 reframed, D-02 split into D-02a/b, D-09 expanded, OQ-1..7 resolved or punted to plan-phase)
**Status:** Ready for planning
**Source:** [Issue #56](https://github.com/agenticapps-eu/claude-workflow/issues/56) — four gaps surfaced migrating callbot v1.16.0 → v1.19.0

<domain>
## Phase Boundary

This phase closes the four discrete gaps documented in issue #56 inside the `claude-workflow` repo plus two post-research scope additions:

1. **0019 migration engine** accepts `index.ts`-anchored wrappers as the **canonical materialised filename** (per `meta.yaml:target.wrapper_path` — researcher revised the D-01 framing; see D-01) for `ts-cloudflare-worker` and `ts-cloudflare-pages` stacks; `lib-observability.ts` continues to work as a legacy/fixture filename.
2. **`CronMonitorSchedule`** in `add-observability` TS templates becomes a real discriminated union matching Sentry's `MonitorSchedule` shape ([VERIFIED] in installed `@sentry/core@8.55.2` types).
3. **`withCronMonitor`** generic constraint narrows from `<E extends Record<string, unknown>>` to `<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>`, accepting strict-typed `Env` interfaces without consumer-side casts or index-signature pollution.
4. **`withQueueMonitor`** ships as a new export with Guarded Shape A semantics (ADR-0029), symmetric to `withCronMonitor` but for Cloudflare Queue consumer handlers (`MessageBatch` first arg, [VERIFIED] against installed `@cloudflare/workers-types`). Migration 0019 expanded to copy `queue-monitor.{ts,go}` alongside `cron-monitor.{ts,go}` + `healthz-snippet.{ts,go}` on **fresh applies** (pre-1.18.0 projects).
5. **NEW Migration 0021** (`from_version: 1.19.0` → `to_version: 1.20.0`, additive: copies only `queue-monitor.{ts,go}`) for **already-migrated projects**. The migration runner uses exact `from_version` matching per `migrations/README.md:60-99` — re-revving 0019 alone cannot retrigger on v1.18.0+ projects. Researcher's Pitfall 2 finding; user-locked.
6. **NEW openrouter-monitor bundled subtree gets D-03/D-05 fixes.** Phase 24's bundled `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` is a snapshot of the cf-worker template; applying the fixes symmetrically prevents future Phase 24 scaffold consumers from shipping the broken type. Byte-symmetric one-line scope addition (researcher's Pitfall 3 / new OQ-6 finding; user-locked).

**Out of scope (deferred):**
- callbot-side cleanup (separate callbot PR; consumer-side adoption is downstream).
- DEF-1 (TRACE_SAMPLE_RATE unwired), DEF-2 (REDACTED_KEYS missing authorization/bearer), DEF-3 (module-level mutable singletons), F-2 (package-lock.json policy), `.gitignore` extension to worker/pages/supabase-edge templates — all Phase 26 worker-template-hardening.
- Full retroactive bootstrap of ROADMAP.md (Phases 01-24) + STATE.md + PROJECT.md — own future phase.
- `FIX-0017-ENGINE.md` (untracked working-dir prompt for separate migration 0017 engine bugs surfaced by cparx) — distinct scope, own future phase.
- `maxRuntime` seconds-vs-minutes pre-existing template quirk (researcher's Sentry Type Verification note 3) — Phase 26 candidate.

</domain>

<decisions>
## Implementation Decisions

### 0019 Engine — anchor file detection

- **D-01 [REVISED post-research]:** `index.ts` is the **canonical materialised filename** for cf-worker + cf-pages wrappers per `meta.yaml:target.wrapper_path` across all three TS stacks. `lib-observability.ts` is the **template source filename** (test fixtures hand-seed it, which is why the bug shipped green). The engine treats `index.ts` as a first-class anchor (not an alias of the legacy fixture name); `lib-observability.ts` continues to work for fixture compatibility. Implementation: extend `find` candidate collection in `migrate-0019-sentry-crons-and-healthz.sh:224-226` to include `-name index.ts`, add classify branches at `:317-331` so cf-worker matches `(index.ts OR lib-observability.ts) + middleware.ts` and cf-pages matches `(index.ts OR lib-observability.ts) + _middleware.ts`, and add a `resolve_anchor_files()` helper that picks the actually-present anchor at fingerprint time. The `middleware.ts` / `_middleware.ts` co-anchor requirement guards against unintended `index.ts` matches in unrelated dirs (e.g., `dist/`, `node_modules/`). Pre-classify filter recommended over fail-closed `SKIP_UNSUPPORTED` to avoid operator-facing noise.
- **D-02a [REVISED post-research]:** Migration **0019 in-place edits** — engine fix (D-01) + docs amendment in `migrations/0019-sentry-crons-and-healthz.md`. Applies to pre-1.18.0 projects only (`from_version: 1.17.0` exact-match per `migrations/README.md:60-99`). Affected projects that previously failed 0019 due to the anchor mismatch can now re-run cleanly via the standard migration runner — no `--force` flag (it does not exist; researcher verified). The 0019.md gains a "Recovery" subsection documenting the manual path for already-migrated projects (`rm <wrapper>/cron-monitor.{ts,go} <wrapper>/healthz-snippet.{ts,go}`, downgrade `skill/SKILL.md version: 1.17.0`, re-run engine — but this is *informational only*; D-02b is the supported path).
- **D-02b [NEW post-research]:** Ship migration **0021** (`from_version: 1.19.0` → `to_version: 1.20.0`) for already-migrated projects. Additive: copies only `queue-monitor.{ts,go}` if absent. Idempotency marker: `queue-monitor.ts` presence. callbot and any v1.19.0 project picks up the queue wrapper via 0021. Replaces CONTEXT.md's original (broken) D-02 premise that engine fix alone suffices — the migration runner's exact `from_version` matching means re-revving 0019 cannot retrigger on v1.18.0+ projects. Per researcher's "option (d)" recommendation (Pitfall 2).

### Schedule type — discriminated union

- **D-03:** Replace `interface CronMonitorSchedule { type: "crontab" | "interval"; value: string }` with `type CronMonitorSchedule = { type: "crontab"; value: string } | { type: "interval"; value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" }`. Matches Sentry's `MonitorSchedule` discriminated union. Eliminates the consumer-side LOCAL-PATCH cast in callbot's `cron-monitor.ts:141-149`. Applies symmetrically to all three TS templates: `ts-cloudflare-worker/cron-monitor.ts`, `ts-cloudflare-pages/cron-monitor.ts`, `ts-supabase-edge/cron-monitor.ts`, **and** the bundled `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` per D-21. Go template (`cron_monitor.go`) needs no change — already uses native `sentry.MonitorSchedule` interface.
- **D-04:** Type-shape change is functionally non-breaking. Consumers with the `interval` variant against the current template's `value: string` shape cannot compile against `Sentry.withMonitor`'s 3rd-arg type today — the population of working consumers using interval is empty. Consumers using `crontab` variant unchanged. Minor bump for `add-observability`, justified by the surface expansion (D-08).

### Generic narrowing — strict Env support

- **D-05:** Narrow `withCronMonitor<E extends Record<string, unknown>>` → `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>`. Inside the wrapper, the dynamic env-var lookup at `cron-monitor.ts:69-70` becomes `(env as unknown as Record<string, unknown>)[envKey]` — wrapper internals know env is loose-by-design; callers no longer need to lie. Apply symmetrically to all three TS templates, the new `queue-monitor.ts` (D-09), **and** the bundled `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` per D-21.
- **D-06:** Generic narrowing is functionally non-breaking in practice. Every `E` that satisfied the old constraint (`Record<string, unknown>` — has index signature) satisfies the new one (`{ SENTRY_DSN?: string; SERVICE_NAME?: string }` — these fields are optional and almost always present in observability-Env definitions). The only consumers that would break are those who actively redefined `SENTRY_DSN: number` or `SERVICE_NAME: boolean`, which is implausible. Minor bump (D-08).

### withQueueMonitor — new export

- **D-07:** New file `queue-monitor.ts` in each of `add-observability/templates/ts-cloudflare-worker/`, `add-observability/templates/ts-cloudflare-pages/`, and (for symmetry) `add-observability/templates/ts-supabase-edge/`. Signature: `withQueueMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }, Msg = unknown>(handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>, config?: CronMonitorConfig): typeof handler`. Same `CronMonitorConfig` shape — slug resolution + monitorConfig forwarding — reused.
- **D-08:** Guarded Shape A semantics (ADR-0029 / Phase 23 D-08): `handlerStarted` flag distinguishes pre-callback transport failure (fall back to unmonitored handler — queue consumer always runs) from post-callback errors (propagate to outer wrapper). Mirrors `withCronMonitor` line-for-line; only the handler signature differs.
- **D-09:** Slug resolution mirrors `withCronMonitor`'s D6 3-source policy: explicit `config.monitorSlug` > env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` (uppercased, hyphens → underscores) > auto-derive `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`. Auto-derive uses `MessageBatch.queue` (Cloudflare Workers Types field, [VERIFIED] at `node_modules/@cloudflare/workers-types/index.d.ts:2382`). **Default `handlerName` is `"queue"`** (vs cron's `"scheduled"`); env-key naming `SENTRY_CRON_MONITOR_SLUG_QUEUE`. Reuses the shared `SENTRY_CRON_MONITOR_SLUG_*` prefix — Sentry server-side doesn't distinguish cron vs queue at the monitor_slug field, and operators get one naming convention.
- **D-10 [RESOLVED post-research, OQ-3]:** Multi-queue policy: **silent + docs** (mirrors Phase 22 D11). Handlers that dispatch by `batch.queue` MUST pass explicit `monitorSlug`, documented in the `queue-monitor.ts` doc comment and in `migrations/0019-sentry-crons-and-healthz.md`'s queue-monitor section. No compile-time overload signatures, no runtime warn — same enforcement shape as cron-monitor's D11.
- **D-11 [REVISED post-research]:** Migration 0019 expanded to copy `queue-monitor.{ts,go}` alongside existing files **for fresh applies (pre-1.18.0 projects)**. Idempotency marker stays `cron-monitor.ts` presence (additive: when re-applied on a project that originally received `cron-monitor.{ts,go}` only, the engine's apply step adds `queue-monitor.{ts,go}` if missing — but **only for projects that have not yet bumped past 1.18.0**, because the runner contract gates by `from_version`; see D-02b for already-migrated projects). Migration markdown header gets a "Re-rev 2026-05-31 (Phase 25)" note documenting the expanded file set; filename remains `0019-sentry-crons-and-healthz.md` (no `0019.1` rename — no precedent in this repo per researcher's OQ-1 finding).
- **D-12:** Go template (`go-fly-http/queue_monitor.go`) — out of scope this phase. Fly HTTP workers don't have Cloudflare Queue equivalents; the Queue consumer signature is Cloudflare-specific. If/when a Fly equivalent surfaces, separate phase.

### Versioning

- **D-13:** `add-observability` bumps 0.8.0 → 0.9.0 (minor). Three template surface changes: schedule type fix, generic narrowing, new `queue-monitor.ts`. Symmetric to how Phase 23 was a 0.6.0 → 0.7.0 minor bump for the F2 + F5 combined surface. (Per memory `versioning-tracks-migrations.md`: pure engine bugfix gets no bump, but Phase 25 has template-surface changes too.)
- **D-14 [REVISED post-research]:** `claude-workflow` bumps 1.19.0 → 1.20.0 (minor). Migration 0019 is re-rev with engine fix (D-01) + new files copied (D-11), AND new migration 0021 (D-02b) lands. Two migration deltas justify the minor bump (versus engine-only patch).

### Test surface

- **D-15 [REVISED post-research]:** Extend `migrations/test-fixtures/0019/` with three new fixtures: (a) `08-index-ts-anchored-worker/` for D-01 cf-worker case; (b) `09-index-ts-anchored-pages/` for D-01 cf-pages case; (c) `11-stray-index-ts-no-co-anchor/` negative fixture proving engine SKIP_UNSUPPORTED behaviour when an `index.ts` exists without `middleware.ts` co-anchor (mitigates researcher's Pitfall 1 regression). Each fixture asserts: discovery finds (or correctly skips) the wrapper, classify identifies (or correctly fails to identify) the stack, apply copies `cron-monitor.ts` + `healthz-snippet.ts` + `queue-monitor.ts` correctly on success cases, idempotency check passes on re-run.
- **D-16 [REVISED post-research]:** Extend `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` (and pages/supabase-edge equivalents) with: (a) type-level test asserting `CronMonitorSchedule` interval variant requires `value: number + unit` — use vitest's `expectTypeOf` AND an explicit `const _check: Sentry.MonitorConfig['schedule'] = ourSchedule` pattern as the firewall against the harness's `skipLibCheck: true` blind spot (researcher's Pitfall 4); (b) generic-narrowing fixture using a strict-typed `Env` interface (no index signature) that previously failed; (c) regression assertion that `crontab` variant still compiles unchanged.
- **D-17:** New `queue-monitor.test.ts` in each of the three TS template dirs, structured identically to `cron-monitor.test.ts`. Mocks `@sentry/cloudflare`'s `withMonitor`; asserts D-08 happy path, D-09 slug resolution from all three sources, Guarded Shape A pre-callback vs post-callback distinction. Multi-queue explicit-slug enforcement (D-10) verified by doc-comment presence assertion (silent + docs policy locked).
- **D-18 [NEW post-research, OQ-7]:** SC5 acceptance via **synthetic strict-Env typecheck fixture** at `migrations/test-fixtures/0019/10-strict-env-typecheck/` (or equivalent placement under add-observability templates per planner discretion). Asserts: a callbot-shape strict `Env` interface (named fields, no `[k: string]`) compiles against `withCronMonitor` + `withQueueMonitor` without consumer-side casts or `[key: string]: unknown` escape hatches. Mirrors the four items in issue #56's "Acceptance check" subsection. Real callbot adoption (using upstream wrappers, deleting local helper) is a separate downstream PR.

### Post-research scope expansion (Phase Boundary item 6)

- **D-21 [NEW post-research, OQ-6]:** Apply D-03 + D-05 fixes symmetrically to the bundled openrouter-monitor copy at `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts`. Same diffs as `ts-cloudflare-worker/cron-monitor.ts`; verification step: `diff add-observability/templates/ts-cloudflare-worker/cron-monitor.ts add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` returns empty post-execute. openrouter-monitor's pinned `@sentry/cloudflare ^8.0.0` (Phase 24 carve-out) is unaffected — `MonitorSchedule` discriminated union shape is identical between SDK 8.x and 10.x ([VERIFIED] in installed 8.55.2 types). Does **not** include adding `queue-monitor.ts` to openrouter-monitor (no Queue trigger in monitor scaffold scope — would be a Phase 26 candidate if a use case surfaces).

### Claude's Discretion (after research)

- Specific file naming for the migration 0019.md docs amendment ("Recovery" section heading, line position) and migration 0021.md structure — planner decides per docs convention (refer to 0019.md as the structural model; 0021.md is shorter — additive single-file migration).
- Exact `as unknown as Record<string, unknown>` placement inside `resolveSlug` (function boundary vs `env[envKey]` access site) — planner picks smaller diff. Researcher recommends access-site placement (1-line change).
- Whether `queue-monitor.test.ts` mocks `MessageBatch` via `@cloudflare/workers-types` import or hand-rolls a minimal interface — planner picks per existing test conventions (cron-monitor.test.ts:32 uses `{...} as ScheduledController` pattern; suggest mirroring with `as MessageBatch<unknown>`).
- Whether `queue-monitor.ts` imports `CronMonitorConfig` + `buildMonitorConfig` from `./cron-monitor` (option a — recommended, both files always co-copy via 0019/0021) vs duplicates inline (option b — larger diff, no inter-file dependency).
- ts-supabase-edge `queue-monitor.ts` — researcher confirmed OQ-2 default (ship for parity); planner follows the supabase-edge `_setWithMonitorForTest` Deno seam pattern from `ts-supabase-edge/cron-monitor.ts`.

### Folded Todos

No matching todos surfaced.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Issue + field report
- `https://github.com/agenticapps-eu/claude-workflow/issues/56` — primary source of the four findings (read in full)
- `https://github.com/agenticapps-eu/callbot/pull/45` — callbot's hand-applied 0019 migration commits (`adbbe5b`, `f42caaa`); the "acceptance check" in issue #56 §"Acceptance check" lists the 4 things callbot should be able to drop after this phase ships

### Migration + engine
- `migrations/README.md` §"Frontmatter fields" + §"Picking versions" — the runner contract (`from_version` exact-match; researcher Pitfall 2 source)
- `migrations/0019-sentry-crons-and-healthz.md` — migration 0019 spec; gets D-02a docs amendment + D-11 queue-monitor section
- **NEW:** `migrations/0021-with-queue-monitor.md` (filename TBD by planner — recommend `0021-add-queue-monitor.md`) — `from_version: 1.19.0` → `to_version: 1.20.0`; additive single-file copy per D-02b
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` — engine; primary D-01 fix sites (`:188-191` anchor comments, `:219-229` find candidates, `:286-345` classify branches, `:340-348` fingerprint files, `:686-728` apply Files Copied for D-11)
- **NEW:** `templates/.claude/scripts/migrate-0021-add-queue-monitor.sh` — engine for 0021; thinner than 0019 (single-file copy, no canonicaliser needed for additive-only migration; planner picks whether to mirror 0019's full shape for consistency vs minimal)
- `migrations/test-fixtures/0019/` — test-fixture directory; D-15 new fixtures land here (08, 09, 11)
- **NEW:** `migrations/test-fixtures/0021/` — fixtures for 0021 (e.g., `01-fresh-1.19.0-apply/`)

### add-observability templates (D-03, D-05, D-07-D-11, D-21 fix sites)
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` — primary template; D-03 (schedule type) + D-05 (generic narrowing) fixes
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` — D-16 test additions
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` — symmetric D-03 + D-05 fix
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts` — symmetric D-16 test
- `add-observability/templates/ts-supabase-edge/cron-monitor.ts` — symmetric D-03 + D-05 fix
- `add-observability/templates/ts-supabase-edge/cron-monitor.test.ts` — symmetric D-16 test
- `add-observability/templates/go-fly-http/cron_monitor.go` — D-03 N/A (Go uses native sentry.MonitorSchedule); no changes
- **NEW per D-21:** `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` — bundled subtree; same D-03 + D-05 diffs as cf-worker
- NEW: `add-observability/templates/ts-cloudflare-worker/queue-monitor.ts` (D-07–D-10)
- NEW: `add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts` (D-17)
- NEW: `add-observability/templates/ts-cloudflare-pages/queue-monitor.ts` (D-07–D-10)
- NEW: `add-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts` (D-17)
- NEW: `add-observability/templates/ts-supabase-edge/queue-monitor.ts` (D-07–D-10) — ship for cross-stack parity (researcher OQ-2 default confirmed)
- NEW: `add-observability/templates/ts-supabase-edge/queue-monitor.test.ts` (D-17)

### Phase 22 + 23 prior decisions
- `.planning/phases/22-sentry-crons-healthz/CONTEXT.md` — D1 (separate wrapper), D5a (composition order), D6 (3-source slug resolution), D11 (multi-cron explicit-slug requirement), D12 (monitorConfig forwarding) — all carry forward to `withQueueMonitor`
- `.planning/phases/22-sentry-crons-healthz/PLAN.md` — original `withCronMonitor` design including R02 (fail-safe) and R04 (no-DSN no-op)
- `.planning/phases/23-observability-followups/CONTEXT.md` — F5 / D-08 / ADR-0029 (Guarded Shape A) — directly applies to `withQueueMonitor`
- `.planning/phases/23-observability-followups/PLAN.md` §F5 OQ-8 — five Sentry.withMonitor composition shapes; Shape A was chosen and is the pattern `withQueueMonitor` mirrors

### ADRs (numbering confirmed via `ls docs/decisions/` — researcher OQ-4 verified)
- `docs/decisions/0028-*.md` — Sentry Crons + healthz convention (Phase 22)
- `docs/decisions/0029-*.md` — Guarded Shape A composition (Phase 23 ADR-0029)
- `docs/decisions/0030-*.md` — OpenRouter integration SDK-first (Phase 24)
- **NEW:** `docs/decisions/0031-0019-engine-index-ts-anchor.md` — D-01 policy + canonical filename reframe
- **NEW:** `docs/decisions/0032-cron-monitor-generic-narrowing.md` — D-05 API stability
- **NEW:** `docs/decisions/0033-with-queue-monitor.md` — D-07 new export + Migration 0021 rationale

### Sentry SDK ([VERIFIED] in installed 8.55.2)
- `node_modules/@sentry/core/build/types/types-hoist/checkin.d.ts:2-12` — `MonitorSchedule` discriminated union shape, source of D-03
- `node_modules/@sentry/core/build/types/exports.d.ts:95` — `withMonitor<T>(slug, callback, monitorConfig?)` signature, source of Phase 23 D-08
- `@sentry/cloudflare` re-export of `@sentry/core` — template harness pins `^8.0.0`; consumer `^10.2.0` floor per Phase 24 D-17 applies only to consumer apps using AI Monitoring (template surface unaffected)

### Cloudflare Workers Types ([VERIFIED] in installed `@cloudflare/workers-types`)
- `index.d.ts:2379-2386` — `MessageBatch<Body>` shape (`messages`, `queue`, `metadata`, `retryAll`, `ackAll`)
- `index.d.ts:510-516, :14282` — canonical Queue handler signature `(batch, env, ctx) => void | Promise<void>` (`QueueHandler<Env, Message, Props>`)

### Repo-level instructions
- `CLAUDE.md` (project root) — GitNexus impact analysis MUST run on `withCronMonitor`, `resolveSlug`, `buildMonitorConfig` symbols before edits; `gitnexus_detect_changes()` MUST run before commits
- `migrations/README.md:60-99` — runner contract authoritative reference
- `versioning-tracks-migrations.md` memory — engine bugfixes alone don't bump claude-workflow; Phase 25 bumps because migration content changed (new 0021 file + 0019 expansion)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CronMonitorConfig` interface (`cron-monitor.ts:25-35`) — reused verbatim by `withQueueMonitor` (D-07). Researcher recommends importing from `./cron-monitor` (option a) since both files always co-copy via 0019/0021.
- `resolveSlug` (`cron-monitor.ts:58-76`) — pattern reused for `resolveQueueSlug`; only the auto-derive line differs (cron uses `controller.cron`, queue uses `batch.queue`).
- `buildMonitorConfig` (`cron-monitor.ts:86-97`) — fully reusable; same `CronMonitorConfig` consumed; `MonitorConfig.schedule` is required in Sentry's type but the helper returns it conditionally (researcher notes runtime tolerance; out-of-scope tightening).
- Phase 23 test harness (`cron-monitor.test.ts`) — pattern reused for `queue-monitor.test.ts`; mocks `@sentry/cloudflare`'s `withMonitor` the same way (`vi.mock` + `vi.fn`).
- Migration 0017 → 0019 engine pattern — both share `canonicalize_awk` content-hash + all-clean gate + per-root apply. **Engine fix in D-01 does NOT touch the canonicaliser** (researcher anti-pattern note; per `migrations/0019-…md:260` "Any future refinement should land in 0017 FIRST"). Only discovery (find) and classification (classify_stack + stack_fingerprint_files) change.
- Existing fixture pattern (`migrations/test-fixtures/0019/{01,02,03}/setup.sh + verify.sh + expected-exit`) — new fixtures 08, 09, 11 mirror this shape.

### Established Patterns
- **Guarded Shape A** (ADR-0029) — `handlerStarted` flag pattern, mandated for any new Sentry-wrapped handler. `withQueueMonitor` MUST follow.
- **3-source slug resolution + D11 explicit-slug requirement** — established in Phase 22, mirrored by `withQueueMonitor`'s D-09 + D-10. Same `SENTRY_CRON_MONITOR_SLUG_*` env-key prefix for both.
- **Anchor file co-requirement** — engine requires both anchor file AND middleware co-anchor to classify (line 318/331). D-01 preserves this guard.
- **Per-stack file symmetry** — when one stack gets a new file (cron-monitor.ts in Phase 22, queue-monitor.ts now), all relevant stacks get the symmetric file (cf-worker + cf-pages + supabase-edge; go-fly-http if applicable).
- **F5 behavioural-parity tests** (Phase 23 TD8) — mock `@sentry/cloudflare`'s `withMonitor`; assert (i) called once with `(slug, callback, monitorConfig)`; (ii) `captureCheckIn` NOT called directly from wrapper; (iii) when DSN unset, neither called; (iv) handler exception propagates. `queue-monitor.test.ts` follows this pattern.
- **Migration idempotency via marker-file presence** — 0019 uses `cron-monitor.ts` as marker; 0021 uses `queue-monitor.ts` as marker (D-02b).

### Integration Points
- `migrate-0019-sentry-crons-and-healthz.sh:219-229` (find candidates) + `:317-331` (classify) + `:340-348` (stack_fingerprint_files) — D-01 fix sites; add `resolve_anchor_files()` helper per researcher's recommendation
- `migrate-0019-sentry-crons-and-healthz.sh:686-728` (apply_root Files Copied) — D-11 expansion site; add `queue-monitor.ts` per TS stack
- `migrate-0019-sentry-crons-and-healthz.sh:566-591` (`emit_refuse_artifacts_for`) — also emit would-be `queue-monitor.ts` for TS stacks per D-11
- **NEW:** `templates/.claude/scripts/migrate-0021-add-queue-monitor.sh` — new engine for 0021; can be thinner (additive-only, single file)
- `add-observability/templates/{ts-cloudflare-worker,ts-cloudflare-pages,ts-supabase-edge}/cron-monitor.ts:20-23` — D-03 schedule type fix
- `add-observability/templates/{three stacks}/cron-monitor.ts:115-153` — D-05 generic narrowing
- `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` — D-21 bundled subtree symmetric fix
- `migrations/0019-sentry-crons-and-healthz.md` — D-02a docs amendment + D-11 queue-monitor section
- **NEW:** `migrations/0021-add-queue-monitor.md` — D-02b new migration spec
- `CHANGELOG.md` — minor-bump entry for 1.20.0 (claude-workflow) covering 0019 re-rev + 0021 + add-observability 0.9.0 changes
- `meta.yaml` files (cf-worker, cf-pages, supabase-edge) — confirm `target.wrapper_path: index.ts` baseline; **DO NOT edit** (researcher anti-pattern: filename is canonical; SOURCE/TARGET symmetry is intentional)

</code_context>

<specifics>
## Specific Ideas

- **callbot is the acceptance fixture (proxy).** Issue #56 §"Acceptance check (when fixes ship)" lists four observable outcomes callbot must be able to achieve after this phase ships: (1) re-run 0019 cleanly via the engine, (2) drop the LOCAL-PATCH cast in `cron-monitor.ts`, (3) replace the local `withMonitor` helper in `apps/backend/src/index.ts` with upstream `withCronMonitor` + `withQueueMonitor`, (4) `tsc --noEmit` green without env-cast or index-signature escape hatches. The VERIFICATION step of Phase 25 references these four as the must-haves and validates via the **synthetic strict-Env fixture per D-18** (not the real callbot working tree — that's a separate downstream PR).
- **Per Phase 23 reasoning, F5 behavioural-parity tests are the firewall against downstream regression.** When fxsa / callbot / future consumers pull the new minor, the `withMonitor` mock-assertion test catches any shape drift. Phase 25 inherits this firewall principle for `queue-monitor.test.ts`.
- **skipLibCheck test harness blind spot — D-16 explicit firewall.** The template test harness's `tsconfig.json` writes `skipLibCheck: true`, meaning Sentry-type compatibility (the WHOLE POINT of D-03) is never asserted at typecheck time. D-16 must use BOTH vitest's `expectTypeOf` AND an explicit `const _: Sentry.MonitorConfig['schedule'] = ourSchedule` pattern in the test file — that's the firewall (researcher Pitfall 4).
- **No Sentry SDK version pin change.** Phase 24 set `add-observability/openrouter-integration.md` D-17 `^10.2.0` minimum for consumer apps. Phase 25's `withCronMonitor` + `withQueueMonitor` changes work against this same pin — no SDK version shift required ([VERIFIED] `MonitorSchedule` shape identical between 8.x and 10.x installed types).
- **`index.ts` over-match pitfall — sibling-anchor filter required.** Naively adding `-name index.ts` to the engine's find without filtering matches every `index.ts` in `dist/`, `build/`, generated code. Researcher recommends filtering by sibling `middleware.ts` / `_middleware.ts` co-anchor (same logic as classify branches). Validate via D-15 negative fixture (11-stray-index-ts-no-co-anchor).

</specifics>

<deferred>
## Deferred Ideas

### Phase 26 carry-forward (was Phase 25.x in handoff)
- DEF-1: TRACE_SAMPLE_RATE unwired in worker template
- DEF-2: REDACTED_KEYS missing `authorization` / `bearer` in worker template
- DEF-3: module-level mutable singletons in worker template
- F-2: no tracked `package-lock.json` policy across templates (Option A committed lockfile + `npm ci` vs Option B lock-format-agnostic policy doc — D-question for Phase 26 discuss)
- Extending Phase 24's `add-observability/templates/openrouter-monitor/.gitignore` shape to `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`

### NEW post-research deferrals
- **`maxRuntime` unit mismatch** (`cron-monitor.ts:84` comment: "Wrapper-API unit is SECONDS"; Sentry doc says minutes) — pre-existing quirk; researcher recommends not fixing in Phase 25. Phase 26 candidate.
- **`buildMonitorConfig` return-type tightening** — Sentry's `MonitorConfig.schedule` is required, but the helper makes it optional. Runtime tolerates (researcher A1). Out of scope; only matters if Sentry changes their stance.
- **Real callbot adoption PR** (using upstream wrappers instead of local helper) — separate consumer-side work post-1.20.0.

### Future phases (not Phase 26)
- Full retroactive bootstrap of ROADMAP.md (Phases 01-24 enumerated) + STATE.md + PROJECT.md — own future phase. Today's stub ROADMAP.md has only Phase 25 + 26 placeholder.
- Migration 0017 engine bug fixes (cparx field report at `FIX-0017-ENGINE.md` working-dir prompt) — separate phase; different migration; different engine.
- `withQueueMonitor` for Go templates (`go-fly-http/queue_monitor.go`) — Fly HTTP workers don't have a Cloudflare-Queue equivalent today; revisit if a use case surfaces.
- GH Actions CI to run the now-~486-fixture test surface (handoff priority 3).
- PROMPT C fxsa adoption + PROMPT D callbot adoption rollouts — downstream consumer work.

### Reviewed but not folded
No todos reviewed — todo cross-reference returned empty.

</deferred>

<open_questions>
## Open Questions (resolved/punted to planner)

### Resolved post-research

- **OQ-1 (filename):** Keep `0019-sentry-crons-and-healthz.md` — no `0019.1` precedent in repo per researcher. New file: `0021-add-queue-monitor.md` (or planner-picked equivalent).
- **OQ-2 (supabase-edge queue-monitor):** Ship for parity — researcher confirms default; symmetric with cron-monitor pattern (Deno seam at `_setWithMonitorForTest`).
- **OQ-3 (multi-queue enforcement):** Silent + docs (D-10) — mirrors Phase 22 D11.
- **OQ-4 (ADR numbering):** 0031 (D-01), 0032 (D-05), 0033 (D-07) — confirmed by directory listing.
- **OQ-5 (--force flag):** Does not exist; not adding. Manual recovery documented in 0019 "Recovery" subsection per D-02a (informational); D-02b is the supported re-application path for v1.19.0 projects.
- **OQ-6 (openrouter-monitor bundled subtree):** Include in scope per D-21 (user-locked).
- **OQ-7 (SC5 verification):** Synthetic strict-Env fixture per D-18 (user-locked).

### Still planner-level (not blockers)

- **OQ-8:** Migration 0021 engine shape — mirror 0019's full `canonicalize_awk` + all-clean-gate pattern (consistent codebase) vs minimal additive-only single-file copy (smaller diff, less surface). Researcher recommends thinner — additive-only doesn't need the canonicaliser since there's nothing to canonicalise (no existing queue-monitor.ts to compare against).
- **OQ-9:** Whether `queue-monitor.ts` imports from `./cron-monitor` (option a — recommended) vs duplicates `CronMonitorConfig` + `buildMonitorConfig` inline (option b — no inter-file dependency).
- **OQ-10:** ts-supabase-edge `queue-monitor.ts` Deno specifier choice (`npm:@sentry/deno@^8.0.0` per cron-monitor pattern, or `import * as Sentry from "@sentry/cloudflare"` per cf-worker pattern). Cron uses Deno specifier; queue should mirror.
- **OQ-11:** Migration 0021 docs structure — full standalone spec (mirroring 0019.md sections) vs cross-reference to 0019.md + delta-only docs. Planner picks per docs hygiene preference.

</open_questions>

---

*Phase: 25-fix-0019-engine-and-cron-wrappers*
*Context gathered: 2026-05-31*
*Revised post-research: 2026-05-31*
