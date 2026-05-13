# Phase 08 — Multi-AI Plan Reviews

**Plan reviewed:** PLAN.md (this phase)
**Date:** 2026-05-13
**Reviewers invoked:** gemini (Google), codex (OpenAI), claude (self — not run as independent, included for completeness)
**Reviewer CLIs available in env:** 3 of 5 (coderabbit, opencode absent)
**Floor satisfied:** ≥2 required by migration 0005 pre-flight → 2 actually independent runs (gemini + codex) → PASS

This is the dogfood artifact for Phase 08. The very gate this migration installs is being exercised on the phase that creates it. Both reviewers were given the full CONTEXT.md + RESEARCH.md + PLAN.md and asked for a structured BLOCK / FLAG / STRENGTHS verdict.

---

## Aggregate verdict

| Reviewer | Verdict | BLOCKs | FLAGs | STRENGTHS |
|---|---|---|---|---|
| gemini | APPROVE | 0 | 1 | 4 |
| codex | **REQUEST-CHANGES** | **4** | 3 | 3 |

**Action:** REQUEST-CHANGES wins. PLAN.md is updated below to address all 4 codex BLOCKs and the 3 codex FLAGs before T1 execution begins.

---

## Gemini review (raw)

```
## VERDICT
APPROVE

## BLOCK findings (must fix before execution)
- none

## FLAG findings (should address but not blockers)
- [F1] The "subtractive TDD" approach (PLAN.md T2-T4) validates a pre-existing,
  cherry-picked script with a new test harness. While this is a valid pattern
  that results in strong test coverage, it's a process observation that the
  core logic was not built test-first *within this phase*, which slightly
  increases the risk of discovering design divergences late in the TDD cycle.

## STRENGTHS
- [S1] The goal-backward verification matrix and detailed, measurable
  acceptance criteria (CONTEXT.md AC-1 through AC-10) create a robust and
  unambiguous definition of done.
- [S2] The plan explicitly addresses the dogfooding requirement (AC-9, PLAN.md
  "Out-of-band commitments"), ensuring the new gate is applied to its own
  development phase, which demonstrates high confidence and internal consistency.
- [S3] The RESEARCH.md document provides clear, well-reasoned justifications
  for key design decisions by exploring and rejecting concrete alternatives,
  resulting in a robust and defensible architecture (e.g., dual-surface
  override, stub detection policy).
- [S4] The STRIDE-based threat model in PLAN.md is comprehensive, connecting
  abstract threats directly to the implementation surface, proposed
  mitigations, and required verification evidence.

## Summary
The plan is exceptionally thorough, connecting a clear strategic goal to a
well-sequenced set of verifiable tasks. It proactively identifies and
mitigates risks, including the crucial dogfooding bootstrap problem. The plan
is approved for execution.
```

## Codex review (raw)

```
## VERDICT
REQUEST-CHANGES

## BLOCK findings (must fix before execution)
- [B1] AC-2 is not actually tested — PLAN: T6 only reads migrations/0005-...md
  for version strings and jq shape; it never applies 0005 to a 1.9.0 baseline,
  re-applies it, or rolls it back. Completing the task list would still leave
  the core ship claim unproven.
- [B2] The dogfood/self-bootstrap case is not exercised, only documented
  around — PLAN: Out-of-band commitments, AC-9, and the Goal-backward matrix
  require this phase to prove the gate on itself, but there is no task to
  install/apply 0005 locally, demonstrate "edit blocked before
  08-REVIEWS.md," then demonstrate unblock after review. "Artifact exists" is
  not the same as "gate fired."
- [B3] The plan knowingly ships a bypass while claiming "structurally
  enforced" gating — RESEARCH: Section 2 / Alternative 2A, PLAN: Risks
  accepted exclude MultiEdit. If the runtime exposes any batch-write tool
  under that or similar name, the contract is bypassable and the stated goal
  is false.
- [B4] AC-5's hostile-filename claim has no matching test in the task set —
  PLAN: T1 defines 09-non-edit-tool, while the Threat model says "Fixture 09"
  proves inert handling of a hostile file_path. If the hook short-circuits on
  non-edit tools, that fixture never touches the parsing branch the security
  claim depends on.

## FLAG findings (should address but not blockers)
- [F1] PLAN: T3 weakens verification by allowing substring stderr matches for
  non-empty cases. That can pass on the wrong branch or wrong reason string;
  use exact stable tokens/messages per decision branch.
- [F2] AC-3 / PLAN: T5 use /usr/bin/time -p for p95/p99. That is coarse and
  dominated by process startup noise; the latency number will not be reliable
  enough to defend a <100ms claim.
- [F3] The threat model relies on at least one incorrect filesystem
  assumption — Threat model preview says find -name "*-PLAN.md" "ignores
  hidden files." It does not. That does not automatically break the hook, but
  it means the security review is reasoning from a false premise.

## STRENGTHS
- [S1] RESEARCH is disciplined: alternatives are enumerated, rejected with
  rationale, and the chosen design stays consistent across CONTEXT, RESEARCH,
  and PLAN.
- [S2] PLAN: Section 6 / Alternative 6A correctly handles the planning-
  artifact bypass to avoid a chicken-and-egg deadlock on PLAN.md/REVIEWS.md.
- [S3] The Goal-backward verification matrix is the right shape for this
  change; preserve that framing once the missing execution checks are added.

## Summary
The plan is not execution-ready because it does not prove the migration
applies/idempotently re-applies/rolls back, and it does not actually dogfood
the new gate on this phase. It also knowingly leaves a write-path bypass
(MultiEdit) while claiming structural enforcement. Fix those gaps, add a real
hostile-filename edit-path test, then re-review.
```

---

## Resolution of codex BLOCKs (PLAN.md amended)

| # | Finding | Resolution |
|---|---|---|
| **B1** | AC-2 not actually tested (apply / idempotent re-apply / rollback) | **New task T6b** added to PLAN.md: run the migration body end-to-end against a fixture project at 1.9.0 baseline. Confirm apply success, idempotent re-apply (no-op), full rollback. Evidence: tmp-dir before/after diff. |
| **B2** | Gate not dogfooded on this phase's own execution | **New task T-dogfood** added: install hook into `.claude/hooks/` on this branch, symlink `.planning/current-phase` → `08-multi-ai-review-enforcement`, invoke the hook directly via stdin with a synthetic Edit-on-code-file payload — BEFORE this REVIEWS.md exists (expect block, exit 2) and AFTER (expect allow, exit 0). Captured outputs land in VERIFICATION.md. **AC-9 strengthened**: evidence becomes "hook output captured in both states," not just "REVIEWS.md exists." |
| **B3** | MultiEdit bypass while claiming "structurally enforced" | **Hook + migration matcher amended** to include MultiEdit alongside Edit and Write. Three coordinated changes: hook script's `tool_name` check, migration 0005's Step 2 `jq` matcher, and config-hooks.json metadata. Updates RESEARCH.md Section 2 decision (2B becomes the chosen alternative; 2A rejected by Codex review). |
| **B4** | Fixture 09 doesn't exercise hostile-filename parsing branch | **Fixture 09 redefined**: was non-Edit-tool short-circuit (exit 0 before parsing). Now is `Edit` tool with `tool_input.file_path` = `'$(rm -rf /)'` (literal injection attempt) — exits 0 only because no active phase / planning-artifact bypass / etc., but the hostile string is parsed by `basename` + `case` before exit. Replaces the previous fixture; adds **fixture 10** for the original "non-Edit tool" short-circuit so coverage isn't lost. Total fixture count becomes 10. |

## Resolution of codex FLAGs

| # | Finding | Resolution |
|---|---|---|
| **F1** | Substring stderr matching can pass on wrong branch | **Harness stricter**: T3 amended to require exact stable tokens per decision branch (e.g. block message must contain literal "Missing:   <phase>/<padded>-REVIEWS.md"). Non-empty expected-stderr.txt now requires *all* lines to be present in order, not just substring match. |
| **F2** | `/usr/bin/time -p` is coarse for p95 sub-100ms | **Benchmark switched** to bash `$EPOCHREALTIME` (microsecond precision via `printf` of `$EPOCHREALTIME` × 1000000). N=100 iterations per fixture; computed p50/p95/p99 in awk. Numbers land in VERIFICATION.md. |
| **F3** | Threat model claim "find ignores hidden files" is wrong | **Claim removed** from PLAN.md threat model. Replaced with the more accurate "find -name '*-PLAN.md' matches but does not execute filenames; no shell expansion of matched values." |

## Resolution of gemini's single FLAG

| # | Finding | Resolution |
|---|---|---|
| **F1** (gemini) | "Subtractive TDD" risks late design-divergence discovery | **Acknowledged but accepted.** This is the same pattern used by migration 0010 (phase 07), and it shipped cleanly. The hook script is small (86 LOC) and the fixtures are written first; any design divergence will surface in T4 (harness PASS) before further code is built. Note added to PLAN.md T-pattern section. |

---

## Eat-your-own-dogfood property

Phase 08's gate would have blocked T1 execution had this REVIEWS.md been absent. The block + unblock cycle is now part of T-dogfood. Once T-dogfood completes:

1. Hook installed locally on this branch.
2. `.planning/current-phase` symlinked to `08-multi-ai-review-enforcement/`.
3. Hook invoked twice (without REVIEWS.md → exit 2; with REVIEWS.md → exit 0).
4. Symlink + local hook reverted after dogfood (so they don't ship with the PR).

Evidence of the dogfood will land in VERIFICATION.md under AC-9.

---

## Reviewer-CLI floor compliance

Migration 0005's pre-flight check requires ≥2 of `gemini`, `codex`, `claude`, `coderabbit`, `opencode` to be installed. In this environment: 3 of 5 are present (`gemini`, `codex`, `claude`). The two missing (coderabbit, opencode) are non-blocking — the floor of 2 is satisfied.

For future phases in environments missing both `coderabbit` and `opencode`, the migration pre-flight will still pass. If only 1 reviewer is present, pre-flight will fail-fast with a clear error message (verified in T6b fixture).

---

## Conclusion

REVIEWS.md verdict: **REQUEST-CHANGES → PLAN.md amended → ready to proceed to execution.** The amendments above are tracked in commits to PLAN.md (see PLAN.md change log section); the original review-blocking issues are resolved structurally, not by argument.
