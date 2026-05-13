# Session Handoff — 2026-05-13 (phase 07)

## Accomplished

Built migration 0010 (workflow scaffolder 1.8.0 → 1.9.0) that
post-processes inlined `<!-- GSD:{slug}-start source:{label} -->...`
section markers in CLAUDE.md into a 3-line self-closing reference form
via a vendored POSIX bash hook script. Companion to migration 0009.

Branch: `feat/post-process-gsd-sections-0010` (off main+0009). Three commits:
- `40bd?` test(RED): phase 07 fixtures + harness (5 scenarios, 7 assertions)
- `3bf6727` feat(GREEN): post-process GSD section markers (~220 LOC bash)
- `8606387` feat(workflow): migration 0010 + ADR 0022 + v1.9.0

Full GSD pipeline executed: source identification (Step 1a, blocker),
brainstorming (RESEARCH.md, 4 alternatives evaluated), discuss-phase
(CONTEXT.md with 6 decisions resolved), plan (PLAN.md with 15 tasks +
threat model + goal-backward check), execute (TDD RED → GREEN), end-to-end
verification against real cparx (647L → 521L → 278L), three independent
post-phase reviews (Stage 1 spec compliance, Stage 2 code quality, CSO
security) — running in background as of session end.

Test harness: 7/7 PASS for migration 0010 fixtures. 0009 unchanged.
Full harness: 57 PASS + 8 pre-existing 0001 FAILs (not introduced here).

## Decisions

- **Source identified as upstream `gsd-tools generate-claude-md`** at
  `~/.claude/get-shit-done/bin/lib/profile-output.cjs:911`. Owned by
  pi-agentic-apps-workflow (cross-repo from claude-workflow). Trigger is
  on-demand only — not auto-invoked anywhere. The script has a `--auto`
  flag at line 981 that preserves manually-edited sections via
  `detectManualEdit()` — our post-processor's output IS a manual edit
  from gsd-tools' perspective, so `--auto` keeps it stable.
- **Source label ≠ file path.** `source:PROJECT.md` is a display label;
  the actual file is `.planning/PROJECT.md`. Post-processor's
  `resolve_source_path` mirrors gsd-tools' internal mapping for 8 labels.
- **Downstream hook chosen over upstream patch.** ADR 0022 documents:
  cross-repo coordination too slow for cparx relief; post-processor
  delivers within hours; upstream PR queued as follow-up. After upstream
  lands, post-processor becomes defense-in-depth no-op.
- **Workflow GSD block REMOVED entirely** (not kept as ref) when
  `.claude/claude-md/workflow.md` exists. The 0009 vendored file is more
  comprehensive than the inlined GSD workflow paragraph; keeping both is
  redundant. Documented in ADR 0022 "Bad / risks".
- **AC-7 ≤200L target MISSED** (actual 278L, miss by 78L). Documented
  openly in VERIFICATION.md + CHANGELOG + ADR 0022. The gap is non-GSD
  content (gstack skill table, anti-patterns, repo-structure ASCII
  diagram). Closing requires Phase 08+. Net 0010-only reduction is 243
  lines (47% of post-0009 size).
- **Three-stage review architecture preserved.** Spawned three
  independent background agents (Stage 1 / Stage 2 / CSO) rather than
  collapsing — the workflow skill's Red Flag #8 prohibits collapsing.

## Files modified

Phase-07 commits on `feat/post-process-gsd-sections-0010`:
- `migrations/0010-post-process-gsd-sections.md` (new)
- `templates/.claude/hooks/normalize-claude-md.sh` (new, executable)
- `templates/claude-settings.json` (Hook 6 added to PostToolUse)
- `migrations/run-tests.sh` (test_migration_0010 stanza, 7 assertions)
- `migrations/README.md` (Migration index row for 0010)
- `migrations/test-fixtures/0010/` (5 fixtures + README, expected goldens)
- `docs/decisions/0022-post-process-gsd-section-markers.md` (new ADR)
- `skill/SKILL.md` (version 1.8.0 → 1.9.0)
- `CHANGELOG.md` (new [1.9.0] section)
- `.planning/phases/07-post-process-gsd-sections/{CONTEXT,RESEARCH,PLAN,VERIFICATION}.md`

REVIEW.md and SECURITY.md are written by the three background review
agents — check `.planning/phases/07-post-process-gsd-sections/` for the
latest before opening the PR.

## Next session: start here

Branch is local-only on `feat/post-process-gsd-sections-0010`, three
commits (`40bd?`, `3bf6727`, `8606387`).

Three review agents were dispatched in background:
- `pr-review-toolkit:code-reviewer` (Stage 1 — spec compliance)
- `pr-review-toolkit:silent-failure-hunter` (Stage 2 — code quality)
- `gsd-security-auditor` (CSO — security audit)

When you resume, check:
```bash
ls .planning/phases/07-post-process-gsd-sections/
# Expect: CONTEXT.md PLAN.md REVIEW.md SECURITY.md RESEARCH.md VERIFICATION.md
cat .planning/phases/07-post-process-gsd-sections/REVIEW.md
cat .planning/phases/07-post-process-gsd-sections/SECURITY.md
```

Address any BLOCK-severity findings before opening the PR. APPROVE-WITH-FLAGS
verdicts can ship with the flags captured as follow-up issues.

To ship after reviews land:
```bash
git push -u origin feat/post-process-gsd-sections-0010
gh pr create --title "feat: post-process GSD section markers (migration 0010, v1.9.0)" \
  --body-file .planning/phases/07-post-process-gsd-sections/VERIFICATION.md
```

## Open questions

- **AC-7 partial.** ≤200L target missed by 78L on real cparx (278L
  actual). Acceptable to ship 0010 alone, or block until Phase 08
  trims non-GSD content? Recommendation: ship — the win is real
  (243-line reduction), the gap is openly documented, and Phase 08
  scope (gstack-skill-table reference, repo-structure diagram
  collapse) is clear.
- **Upstream PR to pi-agentic-apps-workflow.** Add `--reference-mode`
  to `gsd-tools generate-claude-md` so it natively emits the
  self-closing form. Captured as a TODO in ADR 0022. When?
- **Pre-existing 0005-0008 carryover.** Branch was cut off
  `feat/vendor-claude-md-sections-0009`, which itself carried
  uncommitted work from phases 0005/0006/0007 (`?? migrations/0005-*`,
  `?? docs/decisions/0018-0020`, etc.). Those files DID NOT get
  staged in this phase's commits — verified via `git status --short`.
  They remain untracked. Session-handoff for 0009 noted them as
  bundled in 0009's commit `ca90ff8`; that bundling is now phase-09
  baseline. Decide separately whether to ship 0005-0007 as separate
  phases or fold into a single follow-up.
- **The `workflow` GSD block removal is a behavior change.** Documented
  in ADR 0022 "Bad / risks". Users who relied on the shorter GSD
  workflow paragraph as their canonical workflow note (rather than
  0009's more comprehensive vendored file) lose it. Mitigation already
  in the apply prose.
