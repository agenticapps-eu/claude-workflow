---
phase: 30
reviewers: [gemini, codex]
reviewed_at: 2026-06-03T09:03:27Z
plans_reviewed: [30-01-PLAN.md, 30-02-PLAN.md, 30-03-PLAN.md]
self_skipped: claude (running inside Claude Code — skipped for independence)
---

# Cross-AI Plan Review — Phase 30 (SPLIT-03)

## Gemini Review

## Phase 30 Plan Review: `SPLIT-03 — claude-workflow 2.0.0 follow-up`

### 1. Summary

This is an exemplary set of plans for a complex, high-risk refactoring phase. The three-wave structure (1. Delete, 2. Implement, 3. Document & Ship) is logical and effectively minimizes risk at each step. The planner has demonstrated a deep, nuanced understanding of the project's intricate migration engine, versioning policies, and test harness. The plans are grounded in thorough research, correctly identify and mitigate all major risks—especially around migration chain continuity and the critical drift-test invariant—and specify a safe, mature release process for a `v2.0.0` breaking change.

### 2. Strengths

*   **Migration Chain Integrity:** The plan's handling of the migration chain is flawless. The tombstone strategy, which preserves `from_version`/`to_version` continuity, is the correct way to handle the removal of released migrations.
*   **Drift-Test Safety:** The plan shows masterful awareness of the drift test. The sequencing is designed so the test remains `GREEN` between each wave: Wave 1 cleans up while the chain's `to_version` remains `1.20.0`, and Wave 2 atomically adds migration `0022` (`to_version: 2.0.0`) while bumping `skill/SKILL.md` to `2.0.0`. This prevents any broken-window states.
*   **Clarity and Specificity:** The plans are highly specific, often providing verbatim code, file content, and commands (e.g., the `phase-sentinel.sh` script, JSON blocks, tombstone frontmatter). This dramatically reduces ambiguity and risk for the implementing agent.
*   **Test-Driven Approach:** The explicit use of a TDD approach for the new migration (`30-02`) and constant validation against the test suite at every step ensures a high degree of quality and correctness. The detailed plan to remove obsolete test bodies and patch the dependent `test_migration_0011` shows exceptional thoroughness.
*   **Safe Release Process:** The use of a `checkpoint:human-verify` for the final `v2.0.0` release is the correct, mature procedure for an operation of this magnitude.

### 3. Concerns

*   **MEDIUM: Cross-Repository Dependencies.** The phase's success relies on the state of the `agenticapps-observability` repository (e.g., for verifying the install path and confirming the presence of extracted ADRs). While the plans include the correct safety checks (e.g., "STOP and do not delete" if an ADR isn't found), any unexpected change or availability issue in that external repo could derail execution. This is an inherent risk of the new split architecture, not a flaw in the plan, but it is the most significant external risk factor.
*   **LOW: Internal Inconsistency in Research Document.** The provided `RESEARCH.md` had a minor, self-corrected inconsistency regarding whether migration `0020` should be tombstoned or stay. The plan (`30-01-PLAN.md`) correctly resolves this ambiguity by following the authoritative `D-01` decision. This poses no risk to the current plan's execution but highlights a slight fragility in the underlying artifacts that a less diligent planner might have overlooked.

### 4. Suggestions

*   **Create a Consolidated Phase Verification Artifact:** The plans correctly specify creating a `SUMMARY.md` after each wave. It would be best practice to also create a top-level `.planning/phases/30-split-03-claude-workflow-2-0-0-follow-up/30-VERIFICATION.md` artifact. This file would consolidate the final test suite baseline (the new `PASS`/`FAIL` counts), the commit SHA of the `agenticapps-observability` repo that was validated against, and a final sign-off, providing a single, durable audit record for this critical breaking change.

### 5. Risk Assessment

*   **Overall Risk: LOW**
*   **Justification:** While the scope of change is large and technically complex, the planning is exceptionally thorough. The risks are well-understood, and the mitigations are robust. The phased approach, constant test validation, proactive handling of dependencies (`test_migration_0011` patch), and human-gated final release reduce the probability of failure to a very low level. The primary remaining risk is external dependency drift, which is a manageable operational risk rather than a planning failure. The plan is sound and ready for execution.

---

## Codex Review

# Phase-Wide Review

## Summary
The phase is well-researched and unusually explicit about sequencing, but it has one major architectural hole: it is safe for the happy path of `1.20.0 -> 2.0.0`, yet it does not convincingly preserve the project’s stated migration-chain replay guarantees for older downstreams. The plans treat tombstones as structurally sufficient, but the real failure point is earlier: immutable migration `0011` still depends on `add-observability/` living inside the claude-workflow install, and Wave 1 deletes that tree. If support for old-baseline replay still matters, this phase is not complete.

## Strengths
- Strong wave decomposition. Deletion, repoint/bump, and docs/release are separated cleanly.
- Good awareness of the drift invariant. The plans explicitly try to keep `latest migration to_version == skill/SKILL.md version`.
- Good handling of immutability for released migrations. `0022` as a new migration is the right shape.
- Good dual-delivery thinking for `#58`: template change plus migration for existing installs.
- Good adversarial handling of the `0020` contradiction instead of glossing over it.

## Concerns
- `HIGH:` Deleting `add-observability/` breaks immutable migration `0011` for any downstream still below `1.10.0`. `0022` does not help because those projects never reach it.
- `HIGH:` The tombstone design is too optimistic. A no-op tombstone that still advances version can let a downstream “progress” without the moved observability behavior ever being applied in the new repo.
- `HIGH:` The plans do not define the bootstrap/hand-off story for legacy downstreams moving from a single-axis pre-split world into the new two-install, two-axis world.
- `HIGH:` “Green between waves” is only true if Wave 1 is committed as a single wave-level unit. As written, Task 1 can delete files while `run-tests.sh` still references them.
- `HIGH:` There is a path inconsistency between `agenticapps-workflow` and `agentic-apps-workflow`. If that leaks into `0022`, the migration writes the wrong file.
- `MEDIUM:` Deleted tests are removed because they break after deletion, not because the plan proves equivalent coverage exists and is green in the obs repo.

## Suggestions
- Decide explicitly whether upgrades from `<1.20.0` remain supported. If yes, you need a compatibility mechanism for `0011`; if no, enforce that with a hard gate and document it.
- Change tombstones from pure informational no-ops to fail-closed redirects unless the equivalent obs skill/migration state is confirmed.
- Make Wave 1 a single commit by rule, or move the `run-tests.sh` cleanup into the same task as the deletions.
- Add one end-to-end replay test from an old baseline, not just `1.20.0`, to prove the split hand-off actually works.
- Normalize the installed-skill path once and assert it in plan text, tests, and migration steps.
- Add a parity checklist showing each deleted workflow-side test is now covered in the obs repo.

## Risk Assessment
**HIGH.** The plans are strong for the narrow `1.20.0 -> 2.0.0` case, but the phase claims more than that. The unresolved `0011` compatibility break and the version-advancing tombstones are release-level risks for a migration-driven scaffolder.

---

# 30-01-PLAN Review

## Summary
This is the sharpest plan operationally, but it is also where the main structural risk sits. The deletion inventory is good, the tombstone manifest is concrete, and the ADR verification step is disciplined. The problem is that it treats the migration chain as a file-sequencing problem when the real break is semantic: old downstreams still need `0011` and the moved functionality.

## Strengths
- Excellent deletion manifest with explicit paths.
- Good insistence on verbatim `from_version`/`to_version` in tombstones.
- Good ADR deletion guard, especially for `0030`.
- Good recognition that Wave 1 must not bump `skill/SKILL.md`.
- Good cleanup of dangling `run-tests.sh` bodies and dispatcher entries.

## Concerns
- `HIGH:` This plan deletes the very tree that immutable migration `0011` still requires at runtime. The test fix hides that break instead of solving it.
- `HIGH:` A tombstone that advances `from_version -> to_version` without confirming the obs-side equivalent is installed/applied can create false migration progress.
- `HIGH:` The plan only guarantees green “at end of wave.” If Task 1 is committed before Task 3, the suite can be red.
- `MEDIUM:` There is no subject-verification that the moved migration content, fixtures, and scripts are actually present in the obs repo before deletion, only ADR presence checks.
- `MEDIUM:` Removing eight tests is justified locally, but the plan does not prove where each responsibility now lives.

## Suggestions
- Add a hard requirement before deletion: verify obs repo contains each moved migration/fixture/script and note the destination path.
- Either preserve a minimal compatibility shim for `0011` or explicitly drop support for pre-`1.10.0` upgrades.
- Make tombstones block with an actionable message unless obs is installed, rather than silently advancing version.
- Require a single commit for all of 30-01, not one commit per task.
- Add a replay test from `1.9.3` or `1.10.0` to prove the chain still behaves intentionally.

## Risk Assessment
**HIGH.** The operational steps are clear, but this plan can ship a migration-chain break while still making the local suite greener by deleting failing tests.

---

# 30-02-PLAN Review

## Summary
This is the strongest of the three plans on intent. `0022` is the right place to put the repoint, version bump, and deterministic hook fix. The main issues are compatibility scope, weak idempotency checks, and an under-specified compatibility contract for the external obs skill.

## Strengths
- Correct decision to supersede via `0022` instead of mutating `0011`.
- Good atomicity rule for `0022` plus `skill/SKILL.md` bump.
- Good explicit no-auto-install stance with actionable abort instructions.
- Good split between template delivery and migration delivery for `phase-sentinel.sh`.
- Good addition of dedicated tests for both `0022` and the hook behavior.

## Concerns
- `HIGH:` The plan uses `agentic-apps-workflow` in `0022` paths while other materials use `agenticapps-workflow`. That is a likely runtime bug.
- `HIGH:` `requires.verify` only checks `name: observability`. It does not verify a minimum compatible obs version or the alias/contents needed for split compatibility.
- `HIGH:` The idempotency checks are too negative. “Old prompt text gone” is not the same as “correct command hook present.”
- `HIGH:` The plan validates `0022` mainly from `1.20.0`, but the phase’s real risk is older downstream replay and split hand-off.
- `MEDIUM:` “Restore from git” is a weak rollback story for downstream projects.
- `MEDIUM:` The migration updates `CLAUDE.md`, settings, and hook state, but not other existing project-local forward references that may still use `/add-observability`.

## Suggestions
- Tighten `requires.verify` to a compatibility floor, not just identity. Check obs version or a concrete sentinel proving split-ready behavior.
- Replace negative idempotency with positive assertions: exact command hook present, exact script contents or marker present, exact version line present.
- Add a fixture for “obs installed but too old” and make sure `0022` fails closed.
- Resolve the `agenticapps-workflow` vs `agentic-apps-workflow` path before implementation.
- Add one replay-path test that includes tombstones before `0022`, not just a direct `1.20.0` fixture.

## Risk Assessment
**MEDIUM-HIGH.** The core idea is right, but the compatibility contract is too weak for a breaking migration in a split ecosystem.

---

# 30-03-PLAN Review

## Summary
This plan is directionally right, but it is the least precise semantically. It treats several changes as string rewrites where they are actually behavior and installation-model changes. That is most dangerous in `install.sh`, which now needs to reflect “separate skill, separate install,” not just a renamed skill label.

## Strengths
- Correctly scopes rewrites to forward-looking, non-immutable files.
- Good call to put `UPGRADING.md` under `docs/`.
- Good explicit override of the nonexistent obs `docs/INSTALLATION.md`.
- Good human checkpoint for PR/tag/merge.

## Concerns
- `HIGH:` `install.sh` is under-specified. A lexical rename could leave the workflow installer pointing at a nonexistent internal observability path instead of reflecting the new two-install model.
- `MEDIUM:` README and setup docs are verified mostly by absence of `add-observability`, not by presence of correct separate-install instructions.
- `MEDIUM:` Existing project-local forward references outside the named files may survive if the grep scope is incomplete.
- `LOW:` Tag creation before human approval is acceptable locally, but it still creates avoidable cleanup if review finds release blockers.

## Suggestions
- Rewrite `install.sh` semantically, not textually: make it explicit that claude-workflow does not install observability.
- Add acceptance criteria that README and `setup/SKILL.md` explicitly describe the two independent installs.
- Add one grep-based inventory over the whole repo for forward-looking `add-observability` references, then whitelist immutable/historical exceptions.
- Make the release step assert the upgrade order in docs: install obs, then run `/update-agenticapps-workflow`.

## Risk Assessment
**MEDIUM.** The release mechanics are sensible, but the documentation/install surface can easily end up internally inconsistent if implemented as a rename pass.

---

# Bottom Line

The plans are good enough for a controlled `1.20.0 -> 2.0.0` upgrade if the team already assumes all downstreams are parked on the `1.21.0` baseline. They are not yet good enough for the stronger claim that old downstreams can still replay the full migration chain safely after the split.

If you fix only three things before execution, make them these:

- Preserve or explicitly de-support the `0011` path.
- Stop tombstones from silently advancing version without confirming obs-side readiness.
- Make Wave 1 commit-atomic, not just “green by the end.”

---

## Consensus Summary

Two independent reviewers (Gemini, Codex). Claude skipped for independence (self).
**Gemini: overall risk LOW — "sound and ready for execution."** **Codex: overall risk HIGH** —
but its top HIGHs split into (a) genuine, concrete defects the same-LLM plan-checker missed, and
(b) concerns rooted in a misread of the two-install / two-axis split model. Triage below.

### Agreed Strengths (both reviewers)
- Clean three-wave decomposition (delete → repoint/bump → docs/ship).
- Correct migration-immutability handling: `0022` as a NEW superseding migration, `0011` untouched.
- Strong drift-invariant awareness; verbatim `from_version`/`to_version` in tombstones.
- Good dual-delivery for #58 (template + migration); disciplined ADR-deletion guard incl. the 0020/0030 traps.
- Verbatim code/commands in tasks → low executor ambiguity.

### Agreed Concerns (cross-repo)
- Both flag the **cross-repo dependency** on `agenticapps-observability` (ADR/migration presence,
  install path). Gemini rates MEDIUM (mitigated by the plans' STOP-if-absent guards); Codex rates
  it part of the HIGH compatibility story.

### ACTIONABLE — confirmed real defects (verified against the files; fold into a `--reviews` replan)

1. **[BLOCKER] `install.sh` skill-pair must be DROPPED, not renamed (Codex 30-03 HIGH).**
   `install.sh:45` is the symlink pair `"add-observability add-observability"`. Phase 30 deletes the
   repo's `add-observability/` subdir, so this line symlinks a missing directory. 30-03 currently
   treats `install.sh` as a 4-ref string rewrite — a textual `add-observability`→`observability`
   rename produces a symlink to a `observability/` subdir that ALSO does not exist (obs moved out
   entirely). FIX: remove the `add-observability` pair from the `install.sh` skill list entirely;
   add an acceptance criterion asserting no skill-pair references a non-existent subdir
   (`! grep -qE '^\s*"add-observability ' install.sh` and the loop targets only existing dirs).

2. **[BLOCKER] Path hyphenation inconsistency in the 0022 version-bump target (Codex phase + 30-02 HIGH).**
   30-02 uses `.claude/skills/agentic-apps-workflow/SKILL.md` (hyphenated, matching `install.sh:42`
   skill-name `agentic-apps-workflow` AND `0011` applies_to). 30-01/30-03 use `agenticapps-workflow`
   (non-hyphenated). The 0022 `to_version: 2.0.0` verify greps an ambiguous path; if it targets the
   wrong form the bump silently no-ops. FIX: resolve the canonical project-local installed-skill
   path ONCE against `install.sh:42` + `0011` precedent (hyphenated `agentic-apps-workflow` is the
   version-bump file path), assert it identically in all three plans, and separate it from the
   distinct `~/.claude/skills/agenticapps-workflow` dev-clone path so the two are not conflated.

3. **[BLOCKER] Wave-1 red-commit boundary (Codex phase + 30-01 HIGH).**
   30-01 already couples each delete+tombstone into one commit, BUT the `run-tests.sh` test-body
   cleanup is a SEPARATE task (Task 3) committed after the deletions (Task 1). Between those commits
   the suite is RED (run-tests.sh still references deleted fixtures). "Green by end of wave" is not
   "green at every commit." FIX: make 30-01 commit-atomic — fold the `run-tests.sh` body removals
   into the SAME commit as the migration/fixture deletions they correspond to (or merge Task 1+Task 3).

### ACTIONABLE — lower-priority hardening (fold in if cheap)
4. **[MEDIUM] Positive idempotency assertions (Codex 30-02).** Replace negative checks ("old prompt
   text gone") with positive ones ("exact `phase-sentinel.sh` command hook present; `^version: 2.0.0$`
   present"). Strengthens 0022 + #58 verification.
5. **[MEDIUM] Obs subject-verification before deletion (Codex 30-01).** 30-01 verifies obs-repo ADR
   presence but not that each MOVED migration/fixture/script actually landed in obs. Add a presence
   check per moved artifact before `git rm` (cheap; the obs repo is local).
6. **[LOW] `requires.verify` compatibility floor (Codex 30-02).** Currently checks `name: observability`
   only. A min-obs-version sentinel would harden against "obs installed but too old." Low priority
   (0–1 consumers today), but a one-line grep is cheap.
7. **[LOW] Consolidated `30-VERIFICATION.md` audit artifact (Gemini).** GSD's execute/verify flow
   already produces this; no plan change needed — noted for awareness.

### DOCUMENT-and-dismiss — Codex HIGHs rooted in a misread of the split model (NO plan change)
- **"Deleting `add-observability/` breaks immutable `0011` for downstreams <1.10.0."** Verified false:
  `0011` does NOT source from the repo tree — its apply step invokes the INSTALLED skill via
  `claude /add-observability …` and its `verify` checks `~/.claude/skills/agenticapps-workflow/
  add-observability/scan/SCAN.md` (the SEPARATE install, satisfied by the obs repo's `add-observability`
  dual-symlink alias). `0011` also has HARD ABORTS if the skill is absent → fail-closed already. Under
  D-03 (two independent installs) this is the intended hand-off, double-gated by 0022's abort-if-absent.
- **"Version-advancing tombstones let downstream 'progress' without the obs behavior."** By design:
  the obs migration logic now lives on the obs repo's OWN axis, applied by its own update mechanism
  (D-03 forked axes). claude-workflow tombstones are deliberately pure version-advancers; making them
  "fail-closed redirects" (Codex's suggestion) would BREAK the clean axis separation. The fail-closed
  gate correctly lives at `0022` (abort if obs skill absent), not at each tombstone.
- **"Old-baseline (<1.20.0) full-chain replay unproven."** The milestone gated the split on the
  **Phase 27 v1.21.0 stable baseline (SPLIT-00 gate)** — all live downstreams are parked at 1.21.0.
  Recommendation: the replan should DOCUMENT the supported upgrade floor (1.21.0 → 2.0.0) explicitly
  in `docs/UPGRADING.md` and the 0022 pre-flight, rather than build a <1.20.0 replay test for a path
  no live consumer takes.

### Divergent Views
- **Overall risk: Gemini LOW vs Codex HIGH.** Reconciled: the LOW/HIGH gap is almost entirely the
  three confirmed defects above (install.sh symlink, path hyphenation, wave-1 atomicity) plus Codex's
  model-misread HIGHs. With defects 1–3 fixed and the misreads documented, residual risk is
  **MEDIUM** (cross-repo coupling is the irreducible remainder) — execution-ready after the replan.

### Recommended next step
`/gsd-plan-phase 30 --reviews` — fold in actionable items 1–6 (3 blockers + 3 hardening), document
the supported-floor + dismissals for items in the last two sections, then re-verify and re-run
`/gsd-review` per `gsd-review-non-skippable`.

---

## Re-Review (post-revision, codex focused pass) — 2026-06-03

After folding in the 3 blockers + 3 hardening items, codex re-reviewed the changed surfaces:

1. **install.sh skill-pair DROP** — CONFIRMED (removed from LINKS, not renamed; help echo + grep hint stripped; remaining source subdirs asserted to exist).
2. **Canonical hyphenated 0022 version-bump path** — CONFIRMED (targets `.claude/skills/agentic-apps-workflow/SKILL.md`, distinguished from the non-hyphenated dev-clone path; verify/acceptance greps target the hyphenated form).
3. **Wave-1 commit atomicity** — CONFIRMED (deletions + tombstones + run-tests.sh body removals in one atomic commit; SKILL.md held at 1.20.0 → drift green).

**New issues: none. Overall: READY.**

Both reviewers now align: Gemini LOW (ready), Codex READY after fixes. The same-LLM plan-checker independently re-verified the fixes against the live `install.sh` + `0011` files. Residual risk: MEDIUM (irreducible cross-repo coupling on `agenticapps-observability`). Plans are execution-ready.
