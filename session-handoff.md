# Session Handoff — 2026-05-15 (Phase 14 shipped v1.10.0; Phase 15 planned, awaiting review)

## Accomplished

**Phase 14 (v1.10.0) — shipped + merged.** PR #25 merged as `e587741`. Local `main` synced.
- spec §10.9 observability enforcement at scaffolder 1.10.0; skill `add-observability` 0.2.1 → 0.3.0 (`implements_spec: 0.3.0`)
- §10.9.1 + §10.9.2 (MUSTs) fully implemented; §10.9.3 (SHOULD) ships as opt-in example at `add-observability/enforcement/observability.yml.example`, NOT auto-installed
- Migration 0011 (1.9.3 → 1.10.0) ships **local-first** after post-review Option-4 pivot (no Claude-in-CI dependency)
- Multi-AI plan review BLOCK → APPROVE; CodeRabbit post-merge surfaced 15 findings → 10 fixed in commit `900b282`, 2 false positives explained on PR thread, 3 cosmetic MD040 deferred
- 6/6 migration-0011 fixtures green; 61 v0.2.1 contract tests regression-guarded by zero template diff

**Phase 15 (v1.11.0) — planning landed, execution not yet started.** Branch `feat/init-and-slash-discovery-v1.11.0`, commit `6d8cce7`. Closes issues #22 (slash-discovery) + #26 (init/INIT.md missing) — both block the documented v1.9.3 → v1.10.0 upgrade path. Commented on #26 acknowledging v1.10.0 shipped over the gap.

## Decisions

- **Pivot to local-first (Option 4) post-review.** Phase 14 originally shipped a CI workflow; user picked local-only ("we don't need claude in CI now"). The CI workflow preserved as `enforcement/observability.yml.example` (opt-in for self-hosted runners or v1.11.0+ Node-port adopters). Spec §10.9.3 is SHOULD; "example-only" conformance level is defensible. Rationale codified in CHANGELOG and CONTRACT-VERIFICATION.
- **Slash-discovery fix = option C** (promote scaffolder layout; user-confirmed in Phase 15 RESEARCH). `~/.claude/skills/add-observability` becomes a symlink to `~/.claude/skills/agenticapps-workflow/add-observability/` (the scaffolder's nested copy). Closes both upstream discovery and per-project install gaps in one move. Fallback to option A (symlink at install only) if option C's surface area is materially larger than estimated.
- **Phase 14 lesson codified**: multi-AI review missed that `SKILL.md` routes to non-existent `init/INIT.md`. New structural check Q8 in `/gsd-review` prompt going forward: every manifest- or routing-table-referenced path MUST resolve on disk.
- **v1.11.0 unblocks v1.10.0 adoption.** Until Phase 15 lands, no fresh v1.9.3 project can reach v1.10.0 (migration 0011 requires init, init is missing). fx-signal-agent already has observability scaffolded so it may upgrade — confirm before promising. The Node-scanner-port follow-up I'd ranked top-priority post-Phase-14 is **downgraded** since we don't need claude-in-CI under Option 4.

## Files modified

### Phase 14 — already merged in `e587741` (main)
Full ledger in pre-merge handoff at `e587741`'s session-handoff.md. Plus `900b282` (CodeRabbit fixes) covering 10 files.

### Phase 15 — branch `feat/init-and-slash-discovery-v1.11.0` (commit `6d8cce7`)
- `.planning/phases/15-init-and-slash-discovery/CONTEXT.md` (133 lines) — gaps, why we shipped over them, §10.7 obligations, per-stack init data already in `meta.yaml`, 8 open questions for RESEARCH
- `.planning/phases/15-init-and-slash-discovery/RESEARCH.md` (164 lines) — 8 design decisions D1-D8 with options + recommendations
- `.planning/phases/15-init-and-slash-discovery/PLAN.md` (445 lines) — 17 tasks across 7 phases; wave dependency graph; risk register

## Next session: start here

**First action**: spawn multi-AI review against `.planning/phases/15-init-and-slash-discovery/PLAN.md` per the Phase 14 pattern — codex + gemini + Claude self-review. Use the existing `.review-prompt.md` template as the starting prompt; **add Q8 (the new structural existence check)**. Capture into `15-REVIEWS.md`. Revise PLAN.md if BLOCK or REQUEST-CHANGES surfaces, then start T1 (scaffolder layout refactor — the symlink that closes #22).

Concretely:
```bash
git checkout feat/init-and-slash-discovery-v1.11.0
# Draft the review prompt with the new Q8 structural check; reuse phase 14's prompt as starting point
# Run codex + gemini in parallel against PLAN.md
# Consolidate into 15-REVIEWS.md
# Start T1
```

If you'd rather skip the review gate and start T1 directly (since the PLAN is heavily derived from RESEARCH which surfaced the alternatives), that's the user's call. Phase 14 demonstrated codex catches things; recommend running it.

## Open questions

- **fx-signal-agent v1.10.0 adoption** — issue's blocked on Phase 15 if init is required. Verify whether fx-signal-agent ran init at v0.2.x somehow (maybe Donald scaffolded the wrapper manually). If yes, migration 0011 should apply now even without Phase 15. Worth a quick check before promising the v1.11.0 timeline.
- **PR split with issue-26 author** — DonaldVl offered in #26 to PR INIT.md contributions. Decide split before T5-T9 starts: I land slash-discovery refactor + migration 0012 + INIT.md skeleton; author contributes one or more per-stack procedure sections + fixtures.
- **Carried from prior sessions** (still open):
  - Phase 17 — fix 8 pre-existing `test_migration_0001` failures (`git merge-base` resolution).
  - Phase 18 — fix `test_migration_0007` fixture `03-no-gitnexus` fnm-PATH leak on this dev machine.
  - Phase 19 — `--strict-preflight` flag for the Phase 13 audit.
  - Helper-script license consent for `index-family-repos.sh --all`.
  - Canonical install command for `/gsd-review` skill.
  - CHANGELOG hygiene: stamp `[1.9.3]` as released.
  - coderabbit + opencode CLI install docs (carried; multi-AI reviewer floor met without them).
