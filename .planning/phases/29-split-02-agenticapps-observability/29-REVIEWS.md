---
phase: 29
reviewers: [gemini, codex]
reviewed_at: 2026-06-02
plans_reviewed: [29-01-PLAN.md, 29-02-PLAN.md, 29-03-PLAN.md, 29-04-PLAN.md, 29-05-PLAN.md]
self_skipped: claude (running inside Claude Code — skipped for independence)
---

# Cross-AI Plan Review — Phase 29 (SPLIT-02)

## Gemini Review

### Summary
Exceptionally thorough, well-structured five-plan set for a complex repository split. Safely
navigates extraction into a new repo with git history, submodule integration, and a critical
correctness fix. Phased approach, human-gated checkpoints for irreversible actions, and
adherence to project patterns (TDD, feature-branch workflow) are exemplary.

### Strengths
- Safety-first: scratch clone for `git filter-repo`, explicit GUARD plan (29-05), install.sh
  clobber-guards, user-gated checkpoints for all outward-facing actions.
- Foresight: anticipates the temporary drift-test failure in 29-03 (resolved in 29-04), the
  SKILL.md path difference for the runner, the FXSA-WORKERS-6 marker reconciliation.
- Adherence to conventions: reuses source-and-keep runner, install.sh structure, feature-branch/PR policy.
- Clarity: exact commands, file contents, acceptance criteria; explicit migration-ownership audit.
- Strong scope containment: Phase 30 cleanup + Phase D refactor clearly deferred.

### Concerns
- **LOW — filter-repo merge complexity (29-02 T3):** conflicts beyond CHANGELOG.md (.gitignore, README.md) could add complexity to the unrelated-histories merge.
- **LOW — internal path references (Pitfall 6, 29-03 T3):** manual find-and-replace of `ENGINE=` paths; a missed reference → non-obvious test failure.
- **LOW — test cleanup (29-03 T2):** install.sh verification creates symlinks in `~/.claude/skills` with no cleanup step.

### Suggestions
- Add acceptance criterion `! grep -r "templates/.claude/scripts" migrations/*.md` to catch missed path refs.
- Add a cleanup step to remove `~/.claude/skills` symlinks created during install verification.

### Risk Assessment: **LOW**
Riskiest ops (filter-repo, unrelated-histories merge) handled with scratch clones + proven
strategies; TDD ensures cron-flush correctness; the GUARD check protects the source repo.

---

## Codex Review

### Summary
Well-structured operationally: clear wave sequencing, gated outward actions, explicit
scratch-clone discipline, unusually well-defended Phase 29/30 boundary. **The weak point is
semantic consistency** — a few decisions that simplify execution would break the migration
model or the release gate as defined: the `0022 to_version: 0.11.0` choice, the treatment of
the known-failing `0017` tests, and the narrowed verification set after moving more migrations
than the new repo actually tests.

### Strengths
- Coherent five-wave breakdown matching the repo-split shape.
- Repo create/push/PR-merge/tag correctly treated as `autonomous: false` hard-to-reverse checkpoints.
- filter-repo in the right boundary: fresh scratch clone, never the live tree.
- Strong scope containment (Phase 30 + Phase D deferred).
- Submodule pinning by exact gitlink SHA, not tag-name trust.
- cron-flush grounded in a concrete contract (canonical body, narrowed generic, immediate-flush regression test).
- Avoids mutating released `0021`; introduces `0022` as the corrective migration.
- Feature-branch policy applied to substantive obs work in Plans 03–05.

### Concerns
- **HIGH — `29-04` `0022 to_version: 0.11.0` conflicts with the migration contract.** In
  `migrations/README.md`, `to_version` is the installed *project* version written by the update
  flow. Moved migrations use the consumer-project axis (`1.10.0`…`1.20.0`). A `1.20.0 → 0.11.0`
  migration satisfies the obs drift check but **downgrades/corrupts the consumer version axis**.
- **HIGH — release gate internally inconsistent around `0017`.** Plans 03 and 05 say the harness
  exits non-zero on `FAIL>0`, while Phase 29 also accepts `0017` at `PASS=7 FAIL=4`. "Full suite
  green" and "4 known failures travel" cannot both be true unless expected-failures are encoded.
- **HIGH — ownership move broader than verification move.** The harness has dedicated tests for
  `0012`, `0013`, `0018`, but Plan 03 only carries forward `0017`, `0019`, `0021`. Moving those
  migrations without their tests is a coverage regression.
- **MEDIUM — wrong `0021` filename hardcoded.** Repo has `migrations/0021-with-cron-and-queue-updates.md`,
  not `0021-cron-monitor-shape-and-queues.md`. Plan 02 notices it as a preflight, but Plans 03–04
  still reference the wrong name directly.
- **MEDIUM — queue-monitor changes not paired with test updates.** Repo has `queue-monitor.test.ts`
  in both CF stacks, but Plan 04 only rewrites/runs `cron-monitor.test.ts`.
- **MEDIUM — filter-repo merge strategy under-specified** for conflicts beyond CHANGELOG.md
  (README.md, .gitignore, directory-level).
- **MEDIUM — install verification mutates the operator's real `~/.claude/skills`** (last-writer-wins
  for add-observability before Phase 30 removes the old source).
- **MEDIUM — #61 fixture-fix story split-brained:** objective says "replace stub in `0021/04`",
  implementation moves it into `0022` fixtures to preserve 0021 immutability. Latter is right;
  say it cleanly.
- **LOW — RESEARCH still mentions `git push --force` as safe for the first filtered push** while
  the plans correctly forbid `--force`. Dangerous inconsistency given "never force" is core.
- **LOW — filter-repo `--path-rename` syntax leans on an unverified assumption** (mitigated by
  making help/manifest validation step 1, but don't present the command block as near-final).

### Suggestions
- Separate the two version axes: keep migration `from_version`/`to_version` on the
  consumer-project axis; change the **obs drift policy** instead (obs-specific drift wrapper or a
  separate repo-version marker) rather than overloading `0022.to_version`.
- Resolve `0017` known-failure policy: either keep `0017` out of the Phase 29 ship gate, OR
  convert the 4 cases to explicit expected-failure/skip semantics so "green" = "no unexpected failures".
- If `0012`/`0013`/`0018` move, move their harness bodies + fixtures too; else revise the ownership table.
- Normalize the `0021` filename once in Plan 02; propagate the canonical name through 03–05.
- Add explicit queue-monitor test work to Plan 04 (update + run `queue-monitor.test.ts` in both CF stacks).
- Make the merge policy explicit for every overlapping root file, OR create the repo without
  bootstrap content that will collide (extract first, add skeleton-only files after).
- Run install verification against a temporary HOME or restore prior symlinks after the check.
- State that the #61 type-shape fix lands only in `0022` artifacts/tests, not by mutating `0021`.
- Tighten Plan 05 ship criteria to distinguish: (1) zero unexpected failures, (2) documented
  expected failures, (3) release-blocking failures.

### Risk Assessment: **HIGH**
Execution choreography is good, but three release-grade risks remain: mixed version axes in
migration metadata, a "green" gate that knowingly contains 4 failing tests, and dropped coverage
for moved-but-untested migrations. Fixable planning issues — correct before implementation starts.

---

## Consensus Summary

### Agreed Strengths (2/2 reviewers)
- Scratch-clone discipline for `git filter-repo`; live tree never touched.
- Outward-facing actions gated as `autonomous: false` checkpoints; no `--force`.
- Strong Phase 29/30 scope containment; submodule pinned by exact gitlink SHA.
- cron-flush grounded in a concrete contract; `0021` left immutable, `0022` is the corrective migration.

### Agreed Concerns (2/2 reviewers)
- **filter-repo merge-conflict policy beyond CHANGELOG.md is under-specified** (gemini LOW / codex MEDIUM).
- **install.sh verification mutates `~/.claude/skills` with no cleanup/isolation** (gemini LOW / codex MEDIUM).
- **Internal path/filename references are fragile** — gemini: `ENGINE=` path refs (Pitfall 6); codex: wrong `0021` filename in plans 03–04.

### Divergent Views (the signal)
Gemini rated overall risk **LOW**; codex rated it **HIGH**. The divergence is itself diagnostic:
codex (different model family from the planner+checker) surfaced **three HIGH semantic/release-gate
issues the same-LLM checker accepted** — the `0022 to_version` version-axis collision, the
self-contradictory "green" gate vs. 4 known-failing `0017` tests, and the ownership-vs-test-coverage
mismatch for `0012`/`0013`/`0018`. These are the highest-priority items to resolve before execution.
Mirrors SPLIT-01, where codex caught 4 structural blind-spots the checker missed.

### Recommended action
Replan via `/gsd-plan-phase 29 --reviews` to incorporate the three HIGH findings + the
filename/queue-test/merge-policy/install-isolation MEDIUMs.
