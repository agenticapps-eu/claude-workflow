# Phase 25: Fix 0019 engine + withCronMonitor — Context

**Gathered:** 2026-05-31
**Status:** Ready for planning
**Source:** [Issue #56](https://github.com/agenticapps-eu/claude-workflow/issues/56) — four gaps surfaced migrating callbot v1.16.0 → v1.19.0

<domain>
## Phase Boundary

This phase closes the four discrete gaps documented in issue #56 inside the `claude-workflow` repo:

1. **0019 migration engine** accepts `index.ts`-anchored wrappers (legacy 0017 shape) for `ts-cloudflare-worker` and `ts-cloudflare-pages` stacks alongside the canonical `lib-observability.ts` anchor.
2. **`CronMonitorSchedule`** in `add-observability` TS templates becomes a real discriminated union matching Sentry's `MonitorSchedule` shape.
3. **`withCronMonitor`** generic constraint narrows from `<E extends Record<string, unknown>>` to `<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>`, accepting strict-typed `Env` interfaces without consumer-side casts or index-signature pollution.
4. **`withQueueMonitor`** ships as a new export with Guarded Shape A semantics (ADR-0029), symmetric to `withCronMonitor` but for Cloudflare Queue consumer handlers (`MessageBatch` first arg). Migration 0019 expanded to also copy `queue-monitor.{ts,go}` alongside `cron-monitor.{ts,go}` + `healthz-snippet.{ts,go}`.

**Out of scope (deferred):**
- callbot-side cleanup (separate callbot PR; consumer-side adoption is downstream).
- DEF-1 (TRACE_SAMPLE_RATE unwired), DEF-2 (REDACTED_KEYS missing authorization/bearer), DEF-3 (module-level mutable singletons), F-2 (package-lock.json policy), `.gitignore` extension to worker/pages/supabase-edge templates — all Phase 26 worker-template-hardening.
- Full retroactive bootstrap of ROADMAP.md (Phases 01-24) + STATE.md + PROJECT.md — own future phase.
- `FIX-0017-ENGINE.md` (untracked working-dir prompt for separate migration 0017 engine bugs surfaced by cparx) — distinct scope, own future phase.

</domain>

<decisions>
## Implementation Decisions

### 0019 Engine — anchor file detection

- **D-01:** Engine accepts `index.ts` as an alias anchor for `ts-cloudflare-worker` and `ts-cloudflare-pages` stacks, silently and without operator opt-in. Implementation: extend `find` candidate collection in `migrate-0019-sentry-crons-and-healthz.sh:224-226` to also include `-name index.ts`, and extend the classify branches at `:317-331` so cf-worker matches on `(lib-observability.ts OR index.ts) + middleware.ts` and cf-pages matches on `(lib-observability.ts OR index.ts) + _middleware.ts`. The `middleware.ts` / `_middleware.ts` co-anchor requirement guards against unintended `index.ts` matches in unrelated dirs.
- **D-02:** No follow-up migration 0021 needed. Migration 0019 is additive (creates `cron-monitor.{ts,go}` + `healthz-snippet.{ts,go}`) with `cron-monitor.ts` presence as idempotency marker. Projects skipped due to the anchor mismatch can re-run 0019 cleanly once the engine fix lands — files are absent, idempotency check passes, files get copied. `migrations/0019-sentry-crons-and-healthz.md` gets a docs amendment to document the expanded anchor set (note: `lib-observability.ts` OR `index.ts` accepted for cf-worker/cf-pages) plus a "Recovery" subsection telling consumers who hand-applied 0019 to re-run via `npx claude-workflow migrate 0019 --force`.

### Schedule type — discriminated union

- **D-03:** Replace `interface CronMonitorSchedule { type: "crontab" | "interval"; value: string }` with `type CronMonitorSchedule = { type: "crontab"; value: string } | { type: "interval"; value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" }`. Matches Sentry's `MonitorSchedule` discriminated union. Eliminates the consumer-side LOCAL-PATCH cast in callbot's `cron-monitor.ts:141-149`. Applies symmetrically to all three TS templates: `ts-cloudflare-worker/cron-monitor.ts`, `ts-cloudflare-pages/cron-monitor.ts`, `ts-supabase-edge/cron-monitor.ts`. Go template (`cron_monitor.go`) needs no change — already uses native `sentry.MonitorSchedule` interface.
- **D-04:** Type-shape change is functionally non-breaking. Consumers with the `interval` variant against the current template's `value: string` shape cannot compile against `Sentry.withMonitor`'s 3rd-arg type today — the population of working consumers using interval is empty. Consumers using `crontab` variant unchanged. Minor bump for `add-observability`, justified by the surface expansion (D-08).

### Generic narrowing — strict Env support

- **D-05:** Narrow `withCronMonitor<E extends Record<string, unknown>>` → `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>`. Inside the wrapper, the dynamic env-var lookup at `cron-monitor.ts:69-70` becomes `(env as unknown as Record<string, unknown>)[envKey]` — wrapper internals know env is loose-by-design; callers no longer need to lie. Apply symmetrically to all three TS templates and to the new `queue-monitor.ts` (D-09).
- **D-06:** Generic narrowing is functionally non-breaking in practice. Every `E` that satisfied the old constraint (`Record<string, unknown>` — has index signature) satisfies the new one (`{ SENTRY_DSN?: string; SERVICE_NAME?: string }` — these fields are optional and almost always present in observability-Env definitions). The only consumers that would break are those who actively redefined `SENTRY_DSN: number` or `SERVICE_NAME: boolean`, which is implausible. Minor bump (D-08).

### withQueueMonitor — new export

- **D-07:** New file `queue-monitor.ts` in each of `add-observability/templates/ts-cloudflare-worker/`, `add-observability/templates/ts-cloudflare-pages/`, and (for symmetry) `add-observability/templates/ts-supabase-edge/`. Signature: `withQueueMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }, Msg = unknown>(handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>, config?: CronMonitorConfig): typeof handler`. Same `CronMonitorConfig` shape — slug resolution + monitorConfig forwarding — reused.
- **D-08:** Guarded Shape A semantics (ADR-0029 / Phase 23 D-08): `handlerStarted` flag distinguishes pre-callback transport failure (fall back to unmonitored handler — queue consumer always runs) from post-callback errors (propagate to outer wrapper). Mirrors `withCronMonitor` line-for-line; only the handler signature differs.
- **D-09:** Slug resolution mirrors `withCronMonitor`'s D6 3-source policy: explicit `config.monitorSlug` > env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` (uppercased, hyphens → underscores) > auto-derive `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`. Auto-derive uses `MessageBatch.queue` (Cloudflare Workers Types field).
- **D-10:** Multi-queue policy mirrors `withCronMonitor`'s D11: handlers that dispatch by `batch.queue` MUST pass explicit `monitorSlug`. Reason: auto-derived per-queue slugs may not be provisioned in Sentry. Documented in the `queue-monitor.ts` doc comment and in `migrations/0019-sentry-crons-and-healthz.md`'s queue-monitor section.
- **D-11:** Migration 0019 expanded to copy `queue-monitor.{ts,go}` alongside existing files. Idempotency marker stays `cron-monitor.ts` presence (additive: re-runs add `queue-monitor.{ts,go}` if missing). Existing v1.19.0 consumers who already ran 0019 get `queue-monitor.{ts,go}` via re-run with `--force` once they upgrade claude-workflow. Migration markdown header gets a "Re-rev 2026-05-31 (Phase 25)" note documenting the expanded file set; whether to bump migration version to 0019.1 vs keep at 0019 with re-rev annotation is a **planner-level decision** — see Open Questions.
- **D-12:** Go template (`go-fly-http/queue_monitor.go`) — out of scope this phase. Fly HTTP workers don't have Cloudflare Queue equivalents; the Queue consumer signature is Cloudflare-specific. If/when a Fly equivalent surfaces, separate phase.

### Versioning

- **D-13:** `add-observability` bumps 0.8.0 → 0.9.0 (minor). Three template surface changes: schedule type fix, generic narrowing, new `queue-monitor.ts`. Symmetric to how Phase 23 was a 0.6.0 → 0.7.0 minor bump for the F2 + F5 combined surface. (Per memory `versioning-tracks-migrations.md`: pure engine bugfix gets no bump, but Phase 25 has template-surface changes too.)
- **D-14:** `claude-workflow` bumps 1.19.0 → 1.20.0 (minor). Migration 0019 is re-rev with engine fix (D-01) + new files copied (D-11). Migration content changes bump claude-workflow.

### Test surface

- **D-15:** Extend `migrations/test-fixtures/0019/` with a new fixture for the `index.ts`-anchored wrapper case (cf-worker AND cf-pages variants). Fixture asserts: discovery finds the wrapper, classify identifies the stack, apply copies `cron-monitor.ts` + `healthz-snippet.ts` + `queue-monitor.ts` correctly, idempotency check passes on re-run.
- **D-16:** Extend `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` (and pages/supabase-edge equivalents) with: (a) type-level test asserting `CronMonitorSchedule` interval variant requires `value: number + unit`; (b) generic-narrowing fixture using a strict-typed `Env` interface (no index signature) that previously failed; (c) regression assertion that `crontab` variant still compiles unchanged.
- **D-17:** New `queue-monitor.test.ts` in each of the three TS template dirs, structured identically to `cron-monitor.test.ts`. Mocks `@sentry/cloudflare`'s `withMonitor`; asserts D-08 happy path, D-09 slug resolution from all three sources, Guarded Shape A pre-callback vs post-callback distinction, D-10 multi-queue explicit-slug enforcement (compile-time? runtime warn? — planner decides).

### Claude's Discretion

- Specific file naming for the migration docs amendment ("Recovery" section heading, line position) — planner decides per docs convention.
- Exact `as unknown as Record<string, unknown>` placement inside `resolveSlug` (could be at the function boundary or just at the `env[envKey]` access site) — planner picks the smaller diff.
- Whether `queue-monitor.test.ts` mocks `MessageBatch` via `@cloudflare/workers-types` import or hand-rolls a minimal interface — planner picks per existing test conventions in this repo.
- Whether to bump migration filename to `0019.1-sentry-crons-and-healthz-with-queue.md` or keep at `0019-sentry-crons-and-healthz.md` with a re-rev annotation — planner decides per migration history conventions (see Open Questions).

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
- `migrations/0019-sentry-crons-and-healthz.md` — migration 0019 spec; document gets the D-02 docs amendment + D-11 queue-monitor addition
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` — engine; primary D-01 fix site (lines 188-191 anchor comments, 224-226 find candidates, 286-345 classify branches)
- `migrations/test-fixtures/0019/` — test-fixture directory; D-15 new fixture lands here

### add-observability templates (D-03, D-05, D-07-D-11 fix sites)
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` — primary template; D-03 (schedule type) + D-05 (generic narrowing) fixes
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` — D-16 test additions
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` — symmetric D-03 + D-05 fix
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts` — symmetric D-16 test
- `add-observability/templates/ts-supabase-edge/cron-monitor.ts` — symmetric D-03 + D-05 fix
- `add-observability/templates/ts-supabase-edge/cron-monitor.test.ts` — symmetric D-16 test
- `add-observability/templates/go-fly-http/cron_monitor.go` — D-03 N/A (Go uses native sentry.MonitorSchedule); confirm no changes needed
- NEW: `add-observability/templates/ts-cloudflare-worker/queue-monitor.ts` (D-07-D-10)
- NEW: `add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts` (D-17)
- NEW: `add-observability/templates/ts-cloudflare-pages/queue-monitor.ts` (D-07-D-10)
- NEW: `add-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts` (D-17)
- NEW: `add-observability/templates/ts-supabase-edge/queue-monitor.ts` (D-07-D-10) — supabase edge has no Queue trigger but include for cross-stack consistency, OR exclude (planner decides per template parity policy; see Open Questions)
- NEW: `add-observability/templates/ts-supabase-edge/queue-monitor.test.ts` — only if previous file ships

### Phase 22 + 23 prior decisions
- `.planning/phases/22-sentry-crons-healthz/CONTEXT.md` — D1 (separate wrapper), D5a (composition order), D6 (3-source slug resolution), D11 (multi-cron explicit-slug requirement), D12 (monitorConfig forwarding) — all carry forward to `withQueueMonitor`
- `.planning/phases/22-sentry-crons-healthz/PLAN.md` — original `withCronMonitor` design including R02 (fail-safe) and R04 (no-DSN no-op)
- `.planning/phases/23-observability-followups/CONTEXT.md` — F5 / D-08 / ADR-0029 (Guarded Shape A) — directly applies to `withQueueMonitor`
- `.planning/phases/23-observability-followups/PLAN.md` §F5 OQ-8 — five Sentry.withMonitor composition shapes; Shape A was chosen and is the pattern `withQueueMonitor` mirrors

### ADRs (if present — confirm during research)
- `docs/decisions/0029-*.md` — Guarded Shape A (likely exists; confirm path during research)
- New ADRs landing this phase: `docs/decisions/0031-0019-engine-index-ts-anchor-alias.md` (D-01 policy), `docs/decisions/0032-cron-monitor-generic-narrowing.md` (D-05 API stability), `docs/decisions/0033-with-queue-monitor.md` (D-07 new export)

### Sentry SDK
- `@sentry/cloudflare` re-export of `@sentry/core` — `withMonitor<T>(slug, callback, monitorConfig?): T` — Phase 23 Context7-verified, confirm version compatibility against the SDK pin used in Phase 24 (`add-observability/openrouter-integration.md` D-17 `^10.2.0` minimum applies to consumer apps; openrouter-monitor itself pinned `^8.0.0` carve-out)
- Sentry's `MonitorSchedule` type definition — verify discriminated union shape during research (Context7 lookup against `getsentry/sentry-javascript`)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CronMonitorConfig` interface (`cron-monitor.ts:25-35`) — reused verbatim by `withQueueMonitor` (D-07). No duplication needed.
- `resolveSlug` (`cron-monitor.ts:58-76`) — pattern reused for `resolveQueueSlug`; only the auto-derive line differs (cron uses `controller.cron`, queue uses `batch.queue`).
- `buildMonitorConfig` (`cron-monitor.ts:86-97`) — fully reusable; same `CronMonitorConfig` consumed.
- Phase 23 test harness (`cron-monitor.test.ts`) — pattern reused for `queue-monitor.test.ts`; mocks `@sentry/cloudflare`'s `withMonitor` the same way.
- Migration 0017 → 0019 engine pattern — both share `canonicalize_awk` content-hash + all-clean gate + per-root apply. Engine fix in D-01 follows the same shape; no new engine pattern.

### Established Patterns
- **Guarded Shape A** (ADR-0029) — `handlerStarted` flag pattern, mandated for any new Sentry-wrapped handler. `withQueueMonitor` MUST follow.
- **3-source slug resolution + D11 explicit-slug requirement** — established in Phase 22, mirrored by `withQueueMonitor`'s D-09 + D-10.
- **Anchor file co-requirement** — engine requires both anchor file AND middleware co-anchor to classify (line 318/331). D-01 preserves this guard.
- **Per-stack file symmetry** — when one stack gets a new file (cron-monitor.ts in Phase 22, queue-monitor.ts now), all relevant stacks get the symmetric file (cf-worker + cf-pages + supabase-edge; go-fly-http if applicable).
- **F5 behavioural-parity tests** (Phase 23 TD8) — mock `@sentry/cloudflare`'s `withMonitor`; assert (i) called once with `(slug, callback, monitorConfig)`; (ii) `captureCheckIn` NOT called directly from wrapper; (iii) when DSN unset, neither called; (iv) handler exception propagates. `queue-monitor.test.ts` follows this pattern.
- **Migration idempotency via marker-file presence** — 0019 uses `cron-monitor.ts` as marker; D-11 keeps this marker (adding `queue-monitor.ts` is additive, doesn't change idempotency contract).

### Integration Points
- `migrate-0019-sentry-crons-and-healthz.sh:224-226` (find candidates) + `:317-331` (classify) — D-01 fix site.
- `migrate-0019-sentry-crons-and-healthz.sh:343-345` (per-stack file list) — D-11 expansion site; add `queue-monitor.ts` (Go: `queue_monitor.go`) per stack.
- `add-observability/templates/{ts-cloudflare-worker,ts-cloudflare-pages,ts-supabase-edge}/cron-monitor.ts:20-23` — D-03 schedule type fix.
- `add-observability/templates/{three stacks}/cron-monitor.ts:115-153` — D-05 generic narrowing.
- `migrations/0019-sentry-crons-and-healthz.md` — D-02 docs amendment + D-11 queue-monitor section.
- `CHANGELOG.md` — minor-bump entry for 1.20.0 (claude-workflow) covering migration 0019 re-rev + add-observability 0.9.0 changes.
- `add-observability/templates/openrouter-monitor/` — NOT touched this phase (separate Phase 24 surface; openrouter-monitor pins Sentry `^8.0.0` deliberately and doesn't use the cron/queue wrappers).

</code_context>

<specifics>
## Specific Ideas

- **callbot is the acceptance fixture.** Issue #56 §"Acceptance check (when fixes ship)" lists four observable outcomes callbot must be able to achieve after this phase ships: (1) re-run 0019 cleanly via the engine, (2) drop the LOCAL-PATCH cast in `cron-monitor.ts`, (3) replace the local `withMonitor` helper in `apps/backend/src/index.ts` with upstream `withCronMonitor` + `withQueueMonitor`, (4) `tsc --noEmit` green without env-cast or index-signature escape hatches. The VERIFICATION step of Phase 25 should reference these four as the must-haves and validate via the callbot fixture or a synthetic strict-Env fixture in this repo.
- **Per Phase 23 reasoning, F5 behavioural-parity tests are the firewall against downstream regression.** When fxsa / callbot / future consumers pull the new minor, the `withMonitor` mock-assertion test catches any shape drift. Phase 25 inherits this firewall principle for `queue-monitor.test.ts`.
- **No Sentry SDK version pin change.** Phase 24 set `add-observability/openrouter-integration.md` D-17 `^10.2.0` minimum for consumer apps. Phase 25's `withCronMonitor` + `withQueueMonitor` changes work against this same pin — no SDK version shift required.

</specifics>

<deferred>
## Deferred Ideas

### Phase 26 carry-forward (was Phase 25.x in handoff)
- DEF-1: TRACE_SAMPLE_RATE unwired in worker template
- DEF-2: REDACTED_KEYS missing `authorization` / `bearer` in worker template
- DEF-3: module-level mutable singletons in worker template
- F-2: no tracked `package-lock.json` policy across templates (Option A committed lockfile + `npm ci` vs Option B lock-format-agnostic policy doc — D-question for Phase 26 discuss)
- Extending Phase 24's `add-observability/templates/openrouter-monitor/.gitignore` shape to `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`

### Future phases (not Phase 26)
- Full retroactive bootstrap of ROADMAP.md (Phases 01-24 enumerated) + STATE.md + PROJECT.md — own future phase. Today's stub ROADMAP.md has only Phase 25 + 26 placeholder.
- Migration 0017 engine bug fixes (cparx field report at `FIX-0017-ENGINE.md` working-dir prompt) — separate phase; different migration; different engine.
- `withQueueMonitor` for Go templates (`go-fly-http/queue_monitor.go`) — Fly HTTP workers don't have a Cloudflare-Queue equivalent today; revisit if a use case surfaces.
- GH Actions CI to run the 466-fixture test surface (still relevant per handoff priority 3).
- PROMPT C fxsa adoption + PROMPT D callbot adoption rollouts — downstream consumer work.

### Reviewed but not folded
No todos reviewed — todo cross-reference returned empty.

</deferred>

<open_questions>
## Open Questions (for planner)

These are decisions the planner should make during `/gsd-plan-phase 25`, not blockers requiring user input:

- **OQ-1:** Migration filename — keep at `0019-sentry-crons-and-healthz.md` with a "Re-rev 2026-05-31 (Phase 25)" annotation in the doc header? Or bump to `0019.1-...` per a migration-revision convention? Search prior migration history for re-rev precedent.
- **OQ-2:** Should `add-observability/templates/ts-supabase-edge/queue-monitor.ts` ship in Phase 25 for cross-stack consistency, or be excluded because Supabase Edge has no Queue trigger equivalent? Planner picks per template parity policy. Default: ship — symmetry beats deletion.
- **OQ-3:** Multi-queue explicit-slug enforcement (D-10) — compile-time (overload signatures), runtime warn (`console.warn`), or silent (rely on operator reading docs)? Phase 22 D11 chose silent + docs for multi-cron. Default to silent + docs here too for symmetry.
- **OQ-4:** ADR file numbering — confirm next available ADR number by listing `docs/decisions/*.md`. Phase 24 ended at ADR-0030. So Phase 25 ADRs would be 0031, 0032, 0033 (D-01, D-05, D-07).
- **OQ-5:** Whether to add a `--force` flag to the 0019 engine to support the D-02 recovery path, or whether the existing engine supports re-running an idempotent migration without a force flag. Likely already supported via the existing `cron-monitor.ts` presence check, but planner should verify.

</open_questions>

---

*Phase: 25-fix-0019-engine-and-cron-wrappers*
*Context gathered: 2026-05-31*
