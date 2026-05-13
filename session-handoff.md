# Session Handoff — 2026-05-13 (phase 08)

## Accomplished

Shipped migration 0005 (workflow scaffolder 1.9.0 → 1.9.1) end-to-end via
the full GSD pipeline as **Phase 08**. Multi-AI plan review enforcement
gate: a PreToolUse hook (`templates/.claude/hooks/multi-ai-review-gate.sh`)
that blocks Edit/Write/MultiEdit during a phase if `*-PLAN.md` exists but
`*-REVIEWS.md` doesn't. Promotes `/gsd-review` from optional gsd-patch to
structurally enforced contract gate.

Also pushed and merged: PR #10 (0009, vendor CLAUDE.md), PR #13 (0008+0010,
Coverage Matrix + post-process GSD markers), PR #9 (settings.json bootstrap
fix). Carry-over drafts (0005/0006/0007 from old branch) were rebased onto
1.9.x in PR #12; 0005 then promoted into PR #14 (this phase's output).

Branch: `feat/phase-08-migration-0005-multi-ai-review` (pushed). 5 commits:

- `fd0990c` docs(phase-08) — CONTEXT + RESEARCH + PLAN + multi-AI REVIEWS
- `840d32d` test(RED) — 11 fixtures + harness
- `bf3a407` feat(GREEN) — MultiEdit closure + harness leak fix
- `7fbda90` feat(phase-08) — wire 1.9.1 + verification (T6b/T7/T-dogfood/T8)
- `6a8854b` fix(stage-2,cso) — address Stage 2 BLOCK + 5 FLAGs, CSO M1/L1

Harness: 13/13 PASS on test_migration_0005. Full suite: 79 PASS / 8 pre-
existing 0001 FAILs (carry-over from main).

## Decisions

- **Dogfood properly enforced.** The plan review for THIS phase was run
  via codex + gemini direct invocation, captured as `08-REVIEWS.md`.
  Codex returned REQUEST-CHANGES with 4 BLOCKs — all addressed by PLAN.md
  amendments **before** T1 execution. The gate fires on its own creation
  phase (T-dogfood: block→allow cycle verified for Edit + MultiEdit).
- **MultiEdit added to matcher** (codex B3). Was originally Edit|Write
  only with documented residual risk. Closing the gap promoted "structural
  enforcement" from aspirational to literal.
- **Path-prefix gating on bypass** (Stage 2 FLAG-A). Original basename-only
  bypass would have matched `docs/IMPLEMENTATION-PLAN.md`. Now requires
  `.planning/`-prefix AND GSD-canonical basename.
- **Idempotency guard on Step 2 jq** (Stage 2 BLOCK-1). Original
  unconditional `+=` would silently duplicate the hook entry on re-apply,
  breaking the migration framework contract. Now wrapped in `any()` check.
- **Fail-open on malformed JSON** (Stage 2 FLAG-B / CSO M1). `jq empty`
  guard with stderr warning + `exit 0`. Better than exit 5 with raw jq
  parse error spam.
- **FIFO-safe** (CSO L1). `[ -f "$REVIEWS" ]` guard prevents `wc -l` hang.
- **M2 + L2 deferred to 1.9.2** (curl integrity pin, Verify-step
  active-phase smoke test). Documented in REVIEW.md and PR #14 body.

## Files modified

- `templates/.claude/hooks/multi-ai-review-gate.sh` (rewritten — bypass
  tightening, malformed-JSON fail-open, FIFO-safe)
- `migrations/0005-multi-ai-plan-review-enforcement.md` (BLOCK-1 fix,
  Idempotency markers, sed-bak cleanup, whitespace trim, audit cmd fix)
- `migrations/run-tests.sh` (new test_migration_0005 stanza + HOSTILE_MARKER
  cleanup)
- `migrations/test-fixtures/0005/01-13/` (13 fixtures)
- `migrations/README.md` (index updated)
- `templates/config-hooks.json` (pre_execute_gates.multi_ai_plan_review)
- `docs/ENFORCEMENT-PLAN.md` (planning-gates row)
- `docs/decisions/0018-multi-ai-plan-review-enforcement.md` (version drift)
- `skill/SKILL.md` (1.9.0 → 1.9.1)
- `CHANGELOG.md` ([1.9.1] section)
- `.planning/phases/08-multi-ai-review-enforcement/` (CONTEXT, RESEARCH,
  PLAN, 08-REVIEWS, REVIEW, SECURITY, VERIFICATION, latency-bench,
  dogfood-evidence)

## Next session: start here

PR #14 is open, CLEAN/MERGEABLE, all reviews signed off. Recommended
pressure test before merge:

```bash
claude "/update-agenticapps-workflow --dry-run --migration 0005"  # inside ~/Sourcecode/factiv/cparx
```

The harness covers script behaviour in isolation; the migration runtime's
apply-step prose (Step 2 jq merge, Step 3 sed bump) is agent-driven and
only verified via dry-run in a real consumer.

After PR #14 merges, the carry-over PR #12 is reduced to just 0006 + 0007.
Each needs its own GSD phase (Phase 09 + Phase 10) following the same
discipline applied here.

## Open questions

- **Phase 09 (migration 0006 — LLM wiki builder)**. Already drafted in
  PR #12 with rebased 1.9.1 → 1.9.2 versions. Needs CONTEXT/RESEARCH/PLAN
  through GSD, plus the internal-reference inconsistencies (0006 references
  steps that 0005 doesn't actually contain) need to be either resolved by
  rewriting 0006's setup steps OR by adding the referenced steps to 0005
  via a 0005.1 patch.
- **CSO M2 follow-up (curl integrity).** Pin the hook-fetch URL to
  `/refs/tags/v1.9.1/...` and ship a SHA-256 alongside migration markdown.
  Verify with `shasum -a 256 -c` after download. Plan as 1.9.2 patch.
- **CSO L2 follow-up (Verify smoke test).** Wrap migration's Verify step's
  smoke test in `GSD_SKIP_REVIEWS=1` or run it from `/tmp` so it doesn't
  read the consumer's active-phase state. Same 1.9.2 patch.
- **FLAG-D stub-threshold revisit.** If real bad-faith 5-line REVIEWS.md
  stubs surface in audits, raise the floor to 20 lines or require reviewer-
  CLI section headers. Tracked but not actioned yet.
- **Pre-existing 0001 harness FAILs (8).** Still pre-dating this phase.
  Worth a small dedicated phase to investigate / fix.
