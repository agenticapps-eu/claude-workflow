---
phase: 25
reviewers: [gemini, codex]
reviewed_at: "2026-05-31T18:30:00Z"
plans_reviewed: [25-01-PLAN.md, 25-02-PLAN.md, 25-03-PLAN.md, 25-04-PLAN.md, 25-05-PLAN.md]
self_cli_skipped: claude (CLAUDE_CODE_ENTRYPOINT=cli)
not_installed: [coderabbit, opencode]
---

# Cross-AI Plan Review — Phase 25

Plan-checker (same-LLM) passed iter-2 with 0 BLOCKERs / 0 WARNINGs. This review captures different-LLM perspectives per workflow commitment (`/gsd-review` precedes execution).

---

## Gemini Review

**Overall: LOW risk.** "Exceptionally well-structured and thorough plan."

### Strengths
- TDD discipline (Wave 0 RED before implementation)
- Deep research integration (Migration 0021 + canonical filename reframe)
- Robust test coverage (positive + negative migration fixtures + synthetic typecheck fixture)
- Architectural soundness (Guarded Shape A reuse, OQ-9 import-not-duplicate, ADRs for key decisions)
- Clear dependencies (wave-based structure + explicit depends_on chains)

### Concerns
- **MEDIUM:** Migration 0021 idempotency marker (queue-monitor.ts presence) creates partial-state risk if the script fails after copy but before version bump. Re-run would SKIP_ALREADY leaving project at correct files / wrong version.
- **LOW:** Test plan relies on grep assertions for some contracts (doc-comment presence, exports). Acceptable trade-off given project's established patterns.

### Suggestions
- Twofold idempotency check: `if [ -f queue-monitor.ts ] && [ version_is_1.20.0 ]; then SKIP; fi`. Or at minimum document the recovery path in 0021 docs.
- Plan 03 Task 3.2: add a verification that `@ts-expect-error` is not "unused" by temporarily fixing the line to confirm the firewall is active.

### Per-Plan Risk
| Plan | Risk |
|------|------|
| 25-01 | LOW |
| 25-02 | LOW |
| 25-03 | LOW |
| 25-04 | LOW |
| 25-05 | LOW |

**Overall: LOW**

---

## Codex Review

**Overall: HIGH risk.** "The TS stacks are not actually symmetric today. Migration 0021 as additive-only cannot close issue #56 for already-migrated consumers."

### Strengths (per plan)
- Strong TDD posture (Plan 01)
- Correct engine fix target sites + `resolve_anchor_files()` abstraction (Plan 02)
- Worker/openrouter D-03/D-05 edits are correct (Plan 03)
- Guarded Shape A design is sound (Plan 04)
- Documentation + version bumps are solid (Plan 05)

### Concerns (HIGH severity)

**H-1 (Plan 01):** `10-strict-env-typecheck` is weaker than it looks. Imports from template SOURCES, not a migrated consumer wrapper. Doesn't prove the supported migration path works for v1.19.0 projects.

**H-2 (Plan 01):** `10-strict-env-typecheck/tsconfig.json` depends on `@cloudflare/workers-types`, but the planned `npx -p typescript@5 tsc` does NOT install that package. Can fail for harness reasons unrelated to D-03/D-05/D-07.

**H-3 (Plan 03):** Plan treats all four `cron-monitor.ts` files as if they share `E extends Record<string, unknown>`. **They do not.** [VERIFIED against actual codebase by orchestrator before user surfacing]:
  - **worker / openrouter-monitor:** `<E extends Record<string, unknown>>(handler: ScheduledFn<E>, ...)`
  - **pages:** `withCronMonitor<R>(handler: () => Promise<R>, ...): (env: Record<string, unknown>) => Promise<R>` — `<R>` is return type, NOT env type
  - **supabase-edge:** `withCronMonitor(handler: (req: Request) => Promise<Response>, ...)` — NO generic; reads `Deno.env.get()` directly

**H-4 (Plan 03):** OQ-9's "export `buildMonitorConfig` + `isConfigured`" is NOT stack-neutral. In supabase-edge, `isConfigured()` has NO env parameter and reads `Deno.env.get('SENTRY_DSN')` directly [VERIFIED at supabase-edge/cron-monitor.ts:114].

**H-5 (Plan 04):** `queue-monitor.ts` re-importing helpers from `./cron-monitor` is brittle across stacks. Migration 0021 only adds `queue-monitor.ts`, so consumers receive `queue-monitor.ts` that imports `buildMonitorConfig`/`isConfigured` from a `cron-monitor.ts` that doesn't export them (because 0021 doesn't update cron-monitor.ts).

**H-6 (Plan 04):** `ts-supabase-edge/queue-monitor.ts` is conceptually mismatched. Supabase Edge is Deno/Supabase, but `withQueueMonitor` API is Cloudflare-specific (`MessageBatch`, `ExecutionContext`).

**H-7 (Plan 05):** **Migration 0021 only copying queue-monitor.ts is insufficient.** Existing v1.19.0 projects (callbot) also need the updated `cron-monitor.ts` for D-03 and D-05. **Otherwise findings 2 and 3 of issue #56 are NOT closed for already-migrated consumers.** This is the central structural flaw of the current D-02b design.

**H-8 (Plan 05):** SC5 doesn't prove `0021` yields a compilable consumer wrapper set; only template-level type shape.

### Concerns (MEDIUM)
- M-1 (Plan 01): `0021/common-setup.sh` seeds "v1.19.0 state" from live template files. Once Plan 03 edits cron-monitor.ts, the fixture is no longer a stable representation of pre-Phase-25 consumer state.
- M-2 (Plan 02): Sibling-co-anchor filter blocks bare `index.ts` but NOT directories containing both `index.ts` + `middleware.ts` from build outputs.
- M-3 (Plan 02): Plan updates `is_known_clean_wrapper()` but not `emit_refuse_artifacts()` — dirty index.ts roots get misleading/empty diff output.
- M-4 (Plan 02): "Partial-GREEN" state for fixtures 08/09 is awkward — suite intentionally fails for reasons unrelated to Plan 02.
- M-5 (Plan 03): Plan overstates byte-symmetry outside worker/openrouter.
- M-6 (Plan 04): Tests cover async handler failure but not synchronous throw after `handlerStarted = true`. Add explicit sync-throw test.
- M-7 (Plan 04): Plan relies too heavily on grep for import contract.
- M-8 (Plan 05): queue-monitor.ts presence as SOLE idempotency marker is lossy — truncated/manual/stale file still counts as "already applied".
- M-9 (Plan 05): 0021 has no dirty-state strategy.

### Suggestions
- **Split Plan 03 by stack** (worker+openrouter together, pages separately, supabase-edge separately).
- **Reconsider whether supabase-edge belongs in this phase at all.** If it stays, define what runtime contract it serves for queue handlers (Supabase has no Cloudflare Queue equivalent).
- **Redesign Migration 0021** — two viable options:
  - (a) 0021 updates BOTH `cron-monitor.ts` and `queue-monitor.ts` with clean/dirty detection policy (mirroring 0019's `canonicalize_awk` shape).
  - (b) Keep 0021 additive-only, but then the supported path for D-03/D-05 must be honestly documented as "manual re-run of 0019 after downgrade", NOT "0021 solves it".
- **Make SC5 a migrated-project fixture**, not just template-import fixture. Materialize a post-0019 consumer tree, run migration(s), then typecheck that tree.
- **Promote build-time enforcement over grep**: enforce OQ-9 import contract by compiling actual consumer wrappers, not regex.

### Per-Plan Risk
| Plan | Risk |
|------|------|
| 25-01 | MEDIUM |
| 25-02 | MEDIUM |
| 25-03 | HIGH |
| 25-04 | HIGH |
| 25-05 | HIGH |

**Overall: HIGH**

### Bottom Line (codex)
Plans 01-02 mostly sound. **Plans 03-05 need redesign around two facts the current plan set underestimates:**
1. The TS stacks are NOT actually symmetric today, especially `ts-supabase-edge`
2. `0021` as additive-only cannot close issue #56 for already-migrated consumers because it does not deliver the `cron-monitor.ts` fixes

---

## Consensus Summary

Gemini and codex sharply diverge — gemini sees LOW risk, codex sees HIGH. Verification against actual codebase confirms **codex's structural claims (H-3, H-4, H-7) are factually correct.** Gemini's review reads more like an evaluation of the plan documents in isolation; codex's review evaluates the plans against the real codebase.

### Agreed Strengths (mentioned by both)
- TDD discipline (Wave 0 RED before GREEN)
- ADR traceability
- Research integration

### Agreed Concerns (raised by both)
- **Migration 0021 idempotency / partial-state risk** (gemini MEDIUM, codex MEDIUM M-8/M-9 + HIGH H-7)
- **SC5 fixture is weaker than claimed** (gemini implies via grep brittleness; codex explicit H-1)

### Divergent Views — codex flags as HIGH, gemini missed
**These are the orchestrator's primary concern; they require user input before continuing:**

1. **The 3 TS stacks are not structurally symmetric (H-3, H-4, M-5).** D-03 (CronMonitorSchedule discriminated union) applies symmetrically; D-05 (generic narrowing) DOES NOT apply to cf-pages (no `<E>` generic) or supabase-edge (no generic, reads `Deno.env`). D-07 (withQueueMonitor) is Cloudflare-Queue-specific — doesn't fit supabase-edge at all.
2. **Migration 0021 as designed doesn't close findings 2+3 for already-migrated consumers (H-7).** callbot at v1.19.0 needs updated `cron-monitor.ts` to drop the LOCAL-PATCH cast (D-03) and to use strict-typed Env (D-05). 0021 ships only `queue-monitor.ts` — leaves cron-monitor.ts at pre-Phase-25 broken state.
3. **OQ-9 import contract is stack-fragile (H-4, H-5).** Cross-stack `export buildMonitorConfig + isConfigured` from cron-monitor.ts isn't viable for supabase-edge (functions don't exist in shape). The Wave 0 lock + plan-checker iter-2 PASS missed this because they didn't read the actual templates.

### Decisions That Need User Revision

Per codex's bottom line, three CONTEXT.md decisions need revision:

- **D-05 scope:** narrow from "all three TS templates" → "cf-worker + openrouter-monitor bundled subtree only". Pages and supabase-edge variants don't have the `<E>` generic to narrow.
- **D-07 scope:** narrow from "all three TS templates including supabase-edge for parity" → "cf-worker + cf-pages only". Supabase Edge has no Cloudflare Queue equivalent; symmetry-for-symmetry's-sake creates a non-functional file.
- **D-02b shape:** ship Migration 0021 as a re-rev with dirty-detection (OPTION A — copies updated cron-monitor.ts AND queue-monitor.ts; mirrors 0019's canonicalize_awk shape), OR document additive-only and honest manual-recovery for D-03/D-05 (OPTION B — current).

### Recommendation

Stop before `/gsd-execute-phase` and route to `/gsd-plan-phase 25 --reviews` AFTER user revises CONTEXT.md D-05, D-07, D-02b. The plan-checker's same-LLM verification missed these because it accepted the locked CONTEXT.md decisions as ground truth. A different-LLM review caught it — exactly the failure mode `/gsd-review` is designed to surface.

