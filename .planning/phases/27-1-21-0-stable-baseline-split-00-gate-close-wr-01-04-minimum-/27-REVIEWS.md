---
phase: 27
reviewers: [gemini, codex]
reviewed_at: 2026-06-02T09:44:09Z
plans_reviewed: [27-01-PLAN.md, 27-02-PLAN.md, 27-03-PLAN.md, 27-04-PLAN.md, 27-05-PLAN.md, 27-06-PLAN.md]
self_skipped: claude (running inside Claude Code CLI — skipped for independence)
---

# Cross-AI Plan Review — Phase 27

Two independent external CLIs reviewed the full 6-plan set for the 1.21.0 stable baseline.
Gemini rated overall risk **LOW**; Codex rated it **MEDIUM** (release-semantics ambiguity, not
implementation risk). Both converge strongly on the WR-01 firewall brittleness, the WR-03 "TDD
theater" critique, and the A2 dual-version model needing tighter framing.

## Gemini Review

### 1. Summary

The phase plan set for `claude-workflow` 1.21.0 is a well-structured and disciplined approach to achieving a stable baseline before a major repository split. The plans demonstrate a keen awareness of project-specific constraints, such as the `versioning-tracks-migrations` rule and the "cooling-off" invariant. The work is logically divided into parallelizable streams of test-harness fixes, documentation updates, and targeted refactoring, all while meticulously managing risk and avoiding scope creep. The overall strategy of using a tag-only release to decouple this stabilization work from the migration-driven versioning scheme is a pragmatic, if complex, solution to a difficult self-imposed constraint.

### 2. Strengths

* **Risk-Averse:** The plans consistently prioritize stability. The "cooling-off" invariant is respected, and changes are carefully contained (e.g., test-only, docs-only, comment-only annotations).
* **Clear Rationale:** Each plan, particularly the more complex ones like 27-01 and 27-05, provides a clear root-cause analysis and explains the "why" behind the "what," demonstrating deep context.
* **Pragmatic Invariants:** The handling of the imperfect byte-symmetry in plan 27-05 is a standout example of pragmatic engineering. Instead of aiming for an unreachable ideal state, it establishes a sound, achievable invariant ("substituted diff UNCHANGED") that safely contains the change.
* **Disciplined Execution:** The plans call for specific disciplines like TDD (27-02), explicit firewalling (27-01), use of mandated tooling (GitNexus in 27-05), and manual human checkpoints for critical release steps (27-06).
* **Strong Alignment:** The six plans map directly and completely to the nine success criteria, ensuring that if the plans are executed as written, the phase goals will be met.

### 3. Concerns

* **(HIGH) Brittle Acceptance Criteria:** The acceptance criterion in **27-01-PLAN.md** for the WR-01 firewall (`grep -n '|| echo "0"' ... returns EXACTLY 128,130,558,559`) is extremely brittle. It depends on exact line numbers, which are subject to change from unrelated edits, turning a safety check into a potential source of future friction and false negatives.
* **(MEDIUM) Versioning Scheme Complexity:** The A2 tag-only versioning decision, while respecting the project's internal rules, creates a significant divergence between the user-facing version (`1.21.0` in `CHANGELOG` and git tag) and a key developer-facing artifact (`SKILL.md` at `1.20.0`). While the plan mitigates this with a `CHANGELOG` note, it introduces cognitive overhead and could easily confuse new contributors or downstream consumers who don't read the note carefully. This is a deliberate trade-off, but its long-term cost should be acknowledged.
* **(LOW) TDD Ceremony:** The TDD approach in **27-02-PLAN.md**, while demonstrating good discipline, is more of a validation ritual than true test-driven development since the implementation already exists and is known to be correct. The value is primarily in verifying the test's own logic, which is minor but not zero. It risks being seen as "TDD theater" without adding substantial value over simply writing the correct test from the start.

### 4. Suggestions

* **Improve WR-01 Acceptance:** Replace the line-number-based check in **27-01-PLAN.md**. A more robust check would be to verify the *content* of the lines. For example, confirm that the count of `grep -oE .* || echo "0"` is exactly 4, and the count of `grep -c .* || echo "0"` is 0 after the change. This is immune to line number shifts.
* **Formalize Versioning Policy:** The versioning complexity is a direct result of the `versioning-tracks-migrations` rule. Consider adding a `VERSIONING.md` file or a dedicated section in `PROJECT.md` or `README.md` that explicitly defines this tag-only release strategy. This would provide a canonical, permanent reference for the behavior described in the `CHANGELOG` note, making it easier for future developers to understand the policy.
* **Clarify Byte-Symmetry Goal:** The snapshot approach in **27-05-PLAN.md** is excellent. To prevent future confusion, the plan should recommend adding a comment to the `check-byte-symmetry.sh` script or a related document explaining *why* a snapshot-and-compare approach is necessary (i.e., due to token templates and historical prose drift) for this specific pair.

### 5. Risk Assessment

**LOW**

The overall risk for this phase is low. The work is composed primarily of test fixes, documentation, and a single, well-contained refactoring. The planning demonstrates a high degree of foresight, identifying potential pitfalls (brittle shell logic, imperfect symmetry, versioning conflicts) and defining specific, robust mitigation strategies for them. The emphasis on maintaining the "cooling-off" invariant and the explicit firewalling of changes provide strong guardrails. The most significant risk is not technical but communicative: the potential for confusion arising from the tag-only versioning scheme, which is adequately mitigated by the planned documentation.

---

## Codex Review

### Summary

The Phase 27 plan set is technically well-scoped and mostly disciplined: the code changes are small, the repo references are real, and the split-prep work is intentionally kept comment-only. The weak point is not implementation detail but release semantics. The plans map cleanly to all 9 success criteria, but criteria 8 and 9 are only partially "proved" by doc edits: under A2, `v1.21.0` becomes a release tag while the installed workflow still self-identifies as `1.20.0` in `skill/SKILL.md:3`. That can work, but only if you add a hard verification path for downstream pinning and make the dual-version model explicit everywhere it matters.

### Strengths

- The plans are grounded in the actual tree. WR-01, WR-02, WR-04, and the SPLIT-00 mismatch all correspond to real current repo state (`run-template-tests.sh:633`, `ts-supabase-edge/index.test.ts:231`, `openrouter-monitor/src/index.ts:46`, `SPLIT-00-PREREQUISITES.md:52`).
- A2 is internally consistent with the drift invariant: highest migration is still `1.20.0`, and `CHANGELOG.md:7` already documents the migration-locked version rule.
- WR-04 is correctly isolated to the entry file, not the byte-symmetry pair. That is the right surgical boundary.
- 27-03 is appropriately minimal. It avoids the trap of turning PROJECT/STATE/ROADMAP cleanup into a fake historical reconstruction.
- 27-04 correctly retargets split-prep from the nonexistent `bin/gsd-tools.cjs` premise to `migrations/run-tests.sh:2149`.
- The wave structure is mostly sane: independent low-risk work in Wave 1, release-note/tagging last.

### Concerns

- **HIGH**: A2 creates a release that cannot self-describe after installation. A downstream pinned to tag `v1.21.0` will still contain `version: 1.20.0` in its installed workflow skill. Changing SPLIT-00 prose to "pin by tag" is necessary but not sufficient if any audit, installer, or human later asks "what version is installed?" and reads only SKILL.md.
- **HIGH**: Success criteria 8 and 9 are governance criteria, not just file-edit criteria. The plans prove that docs mention pin-by-tag and that the changelog mentions `1.21.0`; they do not yet prove that downstream upgrade workflows can reliably record or verify the source tag/commit.
- **MEDIUM**: The dual-truth model is easy to misread: `CHANGELOG.md:7` will say `1.21.0`, while `skill/SKILL.md:3` stays `1.20.0`. Without explicit terminology like "release baseline tag" vs "migration-coupled skill version," future maintainers will treat this as inconsistency, not policy.
- **MEDIUM**: WR-01's firewall acceptance is brittle because it asserts exact line numbers (`128,130,558,559`). That is true today in `run-template-tests.sh:128`, but line-number assertions are fragile and can fail for harmless comment churn.
- **MEDIUM**: WR-03's RED step is TDD theater. Writing a knowingly false `.not.toBe(0.1)` assertion does not discover behavior; it only demonstrates that vitest can fail on command. Since the helper already exists and likely already passes, this weakens the credibility of the RED/GREEN history.
- **LOW**: WR-03's grep-based acceptance can false-positive because `buildSentryOptions` already appears in comments elsewhere. The exact file set should be asserted, not just a broad recursive grep.
- **MEDIUM**: WR-04's snapshot-before/after check proves "no new drift introduced," not "symmetry is healthy." That is acceptable for scope control, but the plan is normalizing a known drift instead of resolving it. Freezing a known-drifted pair is a conscious debt, not a clean invariant.
- **MEDIUM**: 27-05's GitNexus instruction targets `withSentry`, which is an imported library API, not the repo-owned symbol being changed. That impact analysis is likely noisy or meaningless. The real impacted symbol is the openrouter entry/exported handler or the `buildSentryOptions` call site.
- **MEDIUM**: 27-04 classifies the drift test as `# SHARED`. The mechanism may be shared, but the specific policy "SKILL.md version must equal latest migration to_version" is repo-policy, not obviously repo-agnostic infrastructure. The ADR needs to separate shared harness mechanics from repo-specific versioning policy.
- **LOW**: 27-06 appears ready to promote `[Unreleased]` into `[1.21.0]`, but it does not explicitly preserve an empty `[Unreleased]` section afterward. That will make the next release cycle messier than necessary.

### Suggestions

- Add an explicit downstream evidence rule to SPLIT-00: each downstream must record both source tag and commit SHA of the installed workflow in a durable place such as its phase doc, state file, or PR body. Do not use installed SKILL.md as proof of "1.21.0".
- Standardize terminology across PROJECT/STATE/ROADMAP/CHANGELOG: `release tag` or `baseline tag` for `v1.21.0`; `migration version` or `skill version` for `1.20.0`.
- Replace WR-01's line-number firewall with content-based assertions: exact count of `|| echo "0"` occurrences plus exact match of the four preserved expressions.
- Recast 27-02 as "coverage addition" rather than strict TDD. If you want to prove test sensitivity, use a temporary mutation of the implementation locally, not a deliberately false assertion committed as RED evidence.
- Tighten WR-03 verification to exact test names and exact target files. Broad greps are too weak here.
- Treat `.byte-symmetry.snapshot` as ephemeral verification output, not a repo artifact to keep around, unless you explicitly want it versioned.
- In ADR-0035, split "shared framework mechanism" from "workflow-specific policy." The drift-test runner can be shared; the exact version-coupling rule may stay policy-owned by the consumer repo.
- Change the GitNexus impact target in 27-05 to the openrouter entry/exported handler or the `buildSentryOptions` consumer path, not `withSentry`.
- In 27-06, keep an empty `[Unreleased]` header after cutting `[1.21.0]`, and state plainly that SPLIT-00 remains blocked until the actual `v1.21.0` tag exists on main.

### Risk Assessment

**Overall risk: MEDIUM**

The implementation risk is low: the concrete code/test edits are small and well-bounded. The real risk is release/process ambiguity. If you tighten the proof story around A2 — especially how downstreams verify "we are on the 1.21.0 baseline" when installed SKILL.md still says `1.20.0` — this becomes a solid baseline phase. If you do not, you are likely to ship a technically stable repo with a semantically confusing release contract.

---

## Consensus Summary

Both reviewers agree the **implementation** risk is low — small, well-bounded, grounded-in-the-real-tree edits with strong scope discipline and accurate retargeting (B1) of the split-prep premise. The divergence is on **release/process semantics**: Gemini treats the A2 dual-version model as adequately mitigated by a CHANGELOG note (LOW); Codex treats the "installed SKILL.md says 1.20.0 while the release is 1.21.0" gap as a HIGH governance risk that doc prose alone does not close (MEDIUM overall).

### Agreed Strengths (raised by both)

- Plans map cleanly and completely to all 9 success criteria.
- WR-04 is correctly isolated to the entry file, leaving the byte-symmetry pair untouched (right surgical boundary).
- 27-03 PROJECT.md/STATE/ROADMAP refresh is appropriately minimal — no fake historical reconstruction.
- Strong risk-aversion: cooling-off invariant respected, changes contained to test/docs/comment-only.
- A2 is internally consistent with the drift-test invariant (highest migration still 1.20.0).

### Agreed Concerns (raised by both — highest priority)

1. **WR-01 firewall is brittle (Gemini HIGH / Codex MEDIUM).** The acceptance criterion asserts exact line numbers `128,130,558,559`. Both recommend replacing it with **content-based** assertions: exactly 4 occurrences of `|| echo "0"` AND the four preserved `grep -oE … || echo "0"` expressions matched by content; zero `grep -c … || echo "0"` remaining. → Action: update 27-01 acceptance criteria.
2. **A2 dual-version model needs explicit, standardized framing (Gemini MEDIUM / Codex HIGH).** Both want clear terminology distinguishing the **release/baseline tag** `v1.21.0` from the **migration-coupled skill version** `1.20.0`, applied consistently across CHANGELOG/PROJECT/STATE/ROADMAP. Gemini suggests a canonical `VERSIONING.md` or PROJECT.md section; Codex additionally wants a hard downstream-evidence rule (record source tag + commit SHA, never rely on installed SKILL.md as proof of 1.21.0). → Action: strengthen 27-03 (PROJECT.md versioning section) + 27-04 (SPLIT-00 downstream evidence rule) + 27-06 (terminology in CHANGELOG note).
3. **WR-03 "TDD theater" (Gemini LOW / Codex MEDIUM).** The deliberately-false `.not.toBe(0.1)` RED is a ritual, not behavior discovery, since the helper already exists and passes. Codex recommends recasting 27-02 as a "coverage addition" and, if test sensitivity must be proven, using a temporary local mutation of the implementation rather than committing a knowingly-false assertion as RED evidence. → Action: consider relabeling 27-02 type from `tdd` to coverage-add, or keep TDD framing but document the limitation.

### Codex-only Concerns (worth investigating)

- **WR-03 grep acceptance can false-positive** — `buildSentryOptions` already appears in comments; assert the exact 3 target files + exact test names, not a broad recursive grep. (LOW)
- **WR-04 GitNexus target is wrong** — `withSentry` is an imported library API, not the repo-owned symbol. Impact analysis on it is noisy/meaningless; retarget to the openrouter exported handler / `buildSentryOptions` call site. (MEDIUM) — **concrete, actionable, cheap fix to 27-05.**
- **ADR-0035 should separate mechanism from policy** — the drift-test *runner* is shared infrastructure, but the rule "SKILL.md version == latest migration to_version" is repo-specific policy. Annotate/ADR accordingly so SPLIT-01 doesn't extract the policy as if it were generic. (MEDIUM)
- **27-06 should preserve an empty `[Unreleased]` header** after cutting `[1.21.0]`, and state SPLIT-00 stays blocked until the tag actually exists on main. (LOW)
- **`.byte-symmetry.snapshot`** should be treated as ephemeral verification output, not a committed repo artifact (unless deliberately versioned). (LOW) — note 27-05 lists it under `files_modified`.

### Divergent Views

- **Overall risk:** Gemini **LOW** vs Codex **MEDIUM**. The delta is entirely the A2 release-semantics story — Gemini considers the CHANGELOG note sufficient; Codex wants an enforceable downstream-verification path before calling SC-8/SC-9 truly met. Given downstreams (cparx, callbot, fx-signal-agent) gate on this baseline, Codex's stricter bar is the safer one to adopt.

### Recommended pre-execution edits (synthesis)

| # | Plan | Change | Source | Effort |
|---|------|--------|--------|--------|
| 1 | 27-01 | Replace line-number firewall with content-based assertion (count + expression match) | both | low |
| 2 | 27-05 | Retarget GitNexus impact from `withSentry` to the openrouter exported handler / `buildSentryOptions` call site | codex | low |
| 3 | 27-03 / 27-06 | Standardize "baseline tag v1.21.0" vs "skill version 1.20.0" terminology; add a versioning-policy section to PROJECT.md | both | low |
| 4 | 27-04 | Add downstream-evidence rule to SPLIT-00 (record tag + SHA, not SKILL.md); in ADR-0035 separate shared mechanism from repo-specific version policy | codex | low |
| 5 | 27-02 | Relabel as coverage-add OR document the RED-is-ritual limitation; tighten WR-03 acceptance to exact files/test names | both | low |
| 6 | 27-06 | Preserve empty `[Unreleased]` after cutting `[1.21.0]` | codex | trivial |
| 7 | 27-05 | Confirm whether `.byte-symmetry.snapshot` should be committed or gitignored | codex | trivial |

---

## Resolution — all 7 applied (2026-06-02, pre-execution)

User accepted all 7 recommended edits. Applied directly to the unexecuted plans (phase at 0/6):

1. **27-01** — Firewall acceptance/verify rewritten content-based: exactly 4 `|| echo "0"` lines (all `grep -oE`), zero `grep -c … || echo "0"`, 633-634 use `|| true`. Line-number assertions removed everywhere (incl. frontmatter truth + `<verification>`). Immune to line shifts.
2. **27-05** — GitNexus impact target changed `withSentry` → `buildSentryOptions` (repo-owned symbol; `withSentry` is an imported library API). Updated read_first, `<manual>` detect-changes scope, and `<done>`.
3. **27-03 / 27-06** — Added a `## Versioning policy` section to PROJECT.md defining standardized terms **release/baseline tag `v1.21.0`** vs **migration-coupled skill version `1.20.0`**; renumbered sections; added acceptance grep for the terms; instructed STATE/ROADMAP (27-03 Task 2) and the CHANGELOG note (27-06) to reuse the terminology.
4. **27-04** — SPLIT-00 gains a downstream-evidence rule (record source tag + commit SHA; installed SKILL.md explicitly NOT proof of 1.21.0). ADR-0035 + run-tests.sh annotations now separate SHARED *mechanism* (drift-test runner) from repo-specific *policy* (the version-coupling rule). Added matching acceptance criteria.
5. **27-02** — Recast from strict TDD to **coverage-add**: `type: tdd`→`execute`, both tasks de-TDD'd. The deliberately-false `.not.toBe(0.1)` RED is removed; test sensitivity is now proven via a temporary, uncommitted local impl mutation (reverted). Acceptance tightened to the 3 exact files + named tests (no broad recursive grep) + asserts no committed false assertion. VALIDATION.md Wave-0 + sign-off + the WR-03 row updated to match; ROADMAP plan-list line updated.
6. **27-06** — Task 1 now preserves an empty `## [Unreleased]` header after cutting `[1.21.0]`, and notes SPLIT-00 stays blocked until the `v1.21.0` tag exists on `main`. Added acceptance grep.
7. **27-05** — `.byte-symmetry.snapshot` declared ephemeral: gitignore it (added `add-observability/templates/.gitignore` to `files_modified`), never commit; acceptance asserts `git status --porcelain` is clean for it.

Also corrected the WR-04 row in VALIDATION.md from "`diff -q` symmetry empty" to "snapshot-before/after UNCHANGED" (the pair is token-substituted with known drift — raw diff is non-empty by design).
