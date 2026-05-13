# Session Handoff — 2026-05-13 (phase 07)

## Accomplished

Shipped migration 0010 (workflow scaffolder 1.8.0 → 1.9.0) end-to-end:
post-processor hook that collapses inlined `<!-- GSD:{slug}-start
source:{label} -->...` blocks in CLAUDE.md into 3-line self-closing
references. Full GSD pipeline + three independent post-phase reviews
(Stage 1 spec, Stage 2 code-quality, CSO security) completed.

Branch: `feat/post-process-gsd-sections-0010` (local, not pushed).
Six commits off `feat/vendor-claude-md-sections-0009`:

- `f22f2af` test(RED) — fixtures + 7 harness assertions, no script
- `3bf6727` feat(GREEN) — initial bash post-processor, 7/7 PASS
- `8606387` feat(workflow) — migration 0010 + ADR 0022 + v1.9.0 bump
- `0ac39bd` fix(security) — CSO hardening (H1 basename, H2 PATH pin, M1 symlink, M2 5MiB DoS) +3 assertions
- `8f35efc` docs(phase-07) — Stage 1 REVIEW + VERIFICATION committed
- `d89f99f` fix(stage-2) — 6 BLOCKs (binary refuse, fence-aware, CRLF strip, atomic mv, slug allowlist, nested-marker reject) +6 regression assertions

Final harness: 16/16 PASS on test_migration_0010. Full suite: 66 PASS /
8 pre-existing 0001 FAILs (carry-over from before this phase).

End-to-end on real cparx CLAUDE.md (in tmp): 647L → 521L (0009 step) →
278L (0010 step). 0010 alone removes 243 lines (47% of post-0009 size).

## Decisions

- **Source identified upstream**: `gsd-tools generate-claude-md` at
  `~/.claude/get-shit-done/bin/lib/profile-output.cjs:911` (owned by
  pi-agentic-apps-workflow family, cross-repo). On-demand only — not
  auto-invoked. `--auto` flag preserves manual edits, which is what
  makes the post-processor stable across gsd-tools re-runs.
- **Downstream hook chosen over upstream patch** (ADR 0022). Cross-repo
  coordination too slow for cparx relief; post-processor delivers in
  hours; upstream PR queued as TODO.
- **Allowlist-based slug detection** (Stage-2 BLOCK-5 fix). Only the
  seven canonical slugs trigger normalization; custom slugs (e.g.,
  `<!-- GSD:wibble-start -->` for project-local tracking) are preserved
  with a stderr warning.
- **Atomic write via `mv`** (Stage-2 BLOCK-4 fix). Temp file lives in
  same dir as input → mv is a same-filesystem rename(2), POSIX-atomic.
  Two concurrent invocations now land on one final state, not corrupt.
- **AC-7 ≤200L target MISSED**: 278L actual on real cparx. 78L gap is
  non-GSD content (gstack skill table, anti-patterns, repo-structure
  diagram). Documented openly in VERIFICATION.md + CHANGELOG + ADR 0022
  with Phase 08+ follow-up path.
- **Three-stage review preserved.** Stage 1 (APPROVE-WITH-FLAGS, 0 BLOCKs)
  + Stage 2 (REQUEST-CHANGES with 6 BLOCKs, all addressed) + CSO
  (PASS-WITH-NOTES, 3 must-fix items, all addressed). Workflow skill
  Red Flag #8 prohibits collapsing — kept them as independent agents.

## Files modified

- `migrations/0010-post-process-gsd-sections.md` (new)
- `templates/.claude/hooks/normalize-claude-md.sh` (new, ~260 LOC)
- `templates/claude-settings.json` (Hook 6 entry added)
- `migrations/run-tests.sh` (test_migration_0010 stanza, 16 assertions)
- `migrations/test-fixtures/0010/` (5 fixtures + expected goldens)
- `migrations/README.md` (Migration index row)
- `docs/decisions/0022-post-process-gsd-section-markers.md` (new ADR)
- `skill/SKILL.md` (version 1.8.0 → 1.9.0)
- `CHANGELOG.md` (new [1.9.0] section)
- `.planning/phases/07-post-process-gsd-sections/` (CONTEXT, RESEARCH,
  PLAN, REVIEW with both Stage 1 + Stage 2, SECURITY, VERIFICATION)

## Next session: start here

Branch is local-only on `feat/post-process-gsd-sections-0010`, six
commits. All reviewers signed off after fixes; ready to ship:

```bash
git push -u origin feat/post-process-gsd-sections-0010
gh pr create --title "feat: post-process GSD section markers (migration 0010, v1.9.0)" \
  --body-file .planning/phases/07-post-process-gsd-sections/VERIFICATION.md
```

Recommended pressure test before opening the PR: apply 0010 to a real
consumer project end-to-end via `claude "/update-agenticapps-workflow
--dry-run --migration 0010"` inside `~/Sourcecode/factiv/cparx`. The
harness covers script behavior in isolation; the migration runtime's
apply-step prose (Step 2 jq insert, Step 3 user-confirmed diff
preview) is agent-driven and only verified via dry-run.

## Open questions

- **Per-phase commit history vs bundle.** Carry-over uncommitted
  changes from phases 0005/0006/0007 still in working tree (`??` in
  git status: ADRs 0018-0020, migrations 0005-0007, test-fixtures/0005/).
  Same situation as 0009's session-handoff noted. Decide whether to
  ship 0005-0007 as separate phases or fold into a single follow-up.
- **Upstream PR to pi-agentic-apps-workflow.** Add `--reference-mode`
  flag to `gsd-tools generate-claude-md` for native self-closing
  emission. TODO in ADR 0022. After upstream lands, 0010's
  post-processor becomes defense-in-depth.
- **Phase 08 scope.** Closing the 78L gap to ≤200L requires trimming
  non-GSD content: vendor the gstack `Available skills` enumeration
  the way 0009 vendored the Superpowers block, and collapse the repo-
  structure ASCII diagram to a 3-line `tree -L 2` reference. Worth
  bundling into 0011 / Phase 08?
- **Pre-existing 0001 harness FAILs (8 of them).** Pre-date this
  phase — caused by `git merge-base HEAD main` resolving to a
  post-0001-merge commit instead of v1.2.0 baseline. Tracked in
  session-handoff 06; still unfixed. Worth a small dedicated phase.
