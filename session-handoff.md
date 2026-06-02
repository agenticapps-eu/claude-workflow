# Session Handoff — 2026-06-02 (SPLIT-01 PLANNED + REVIEWED + RE-CHECKED — next: /gsd-execute-phase 28)

## Accomplished

- **repo-split milestone opened.** v1.21.0 lightweight-closed (NO heavy /gsd-complete-milestone
  ceremony — `v1.21.0` tag already exists, project uses stub-ROADMAP model, no REQUIREMENTS.md /
  milestones-archive). ROADMAP + STATE transitioned; Phases 28 (SPLIT-01), 29 (SPLIT-02),
  30 (SPLIT-03) registered.
- **Two decisions LOCKED (user):** D-28a sharing mechanism = **git submodule** at
  `vendor/agenticapps-shared/`; D-28b history = **provenance-by-note** (carve into clean new
  lib files + CHANGELOG/commit-SHA provenance; the original "git log --follow" acceptance
  criterion is amended). Memory written: `split-sharing-mechanism.md`.
- **SPLIT-01 Phase A DONE (bootstrap, outside plan cycle):** repo `agenticapps-eu/agenticapps-shared`
  created **private**, skeleton committed `d136c96`, tag `v1.0.0-pre.0` pushed. `git-filter-repo`
  installed (turns out NOT needed for SPLIT-01).
- **SPLIT-01 fully planned through the GSD cycle:** 28-CONTEXT.md (authored directly — all decisions
  already held) → 28-RESEARCH.md (gsd-phase-researcher, HIGH confidence) → 3 PLANs (gsd-planner) →
  **gsd-plan-checker = VERIFICATION PASSED** (all 11 dims, 8 SCs + D-28a..f covered, 2 info notes only).
- **Two corrections from research (applied to ROADMAP + CONTEXT):** (1) real baseline is
  **PASS=186 FAIL=4**, not "190+ green" — the 4 are pre-existing test_migration_0017 / FIX-0017
  scope, do NOT touch. (2) **NO git filter-repo** step in SPLIT-01 — all `migrate-*.sh` are
  obs-specific (→ SPLIT-02), so every carved artifact is provenance-by-note.

## Decisions

- **Skipped the heavy milestone-completion ceremony** — it conflicts with the existing v1.21.0 tag
  and this project's lightweight planning model. Did a lightweight close instead.
- **Authored 28-CONTEXT.md directly instead of interactive /gsd-discuss-phase** — all design
  decisions were already locked (SPLIT docs + ADR-0035 + D-28a/b). No redundant interview.
- **ADR-0035 governs the carve:** extraction target is `migrations/run-tests.sh` (9 SHARED /
  20 WORKFLOW annotations), NOT `bin/gsd-tools.cjs` (not in-repo). Drift test = MECHANISM shared,
  POLICY stays (D-28d).

## Files modified (this session)

- `.planning/ROADMAP.md` — v1.21.0 ✅, repo-split milestone + Phases 28-30, 186/4 corrections (committed `034e685` on `plan/28-split-01`).
- `.planning/STATE.md` — milestone=repo-split, planning-complete status, next-gate=/gsd-review (committed `docs(28)`).
- `.planning/phases/28-split-01-agenticapps-shared/` — 28-CONTEXT.md, 28-RESEARCH.md, 28-0{1,2,3}-PLAN.md (committed).
- NEW repo `~/Sourcecode/agenticapps/agenticapps-shared` — skeleton `d136c96`, tag `v1.0.0-pre.0` (pushed to GitHub, private).
- Memory: `split-sharing-mechanism.md` + MEMORY.md index line.

## Reviews incorporated (this session)

`/gsd-review 28` ran: **gemini LOW, codex HIGH** — codex caught 4 structural blind-spots the
same-LLM plan-checker (which PASSED) missed. All 7 action items (A1–A7 in `28-REVIEWS.md`) were
incorporated via `/gsd-plan-phase 28 --reviews` and **re-verified PASS**. Key change: **A1
(user-locked)** — `setup_fixture` demoted to a claude-workflow wrapper; only `extract_to` is shared
(amends ADR-0035, SHARED 9→8). Also A2 (tag gated on real extract_to/preflight tests), A3
(install.sh existing-clone fix), A4 (pin by gitlink SHA not tag), A5 (set -u), A6 (real GSD diff),
A7 (PR body). Plans committed through `d1e67ba`.

**Side fix (cross-repo):** the codex stdin-hang that bit `/gsd-review` 3× was a missing `< /dev/null`
in `~/.claude/get-shit-done/workflows/review.md` (global, used by every repo). Patched all three
prompt-arg CLIs there (`< /dev/null` + `timeout`). Survives `/gsd-update` via GSD's
`gsd-local-patches` hash-backup → run `/gsd-reapply-patches` after any update. See memory
`codex-exec-stdin-hang`.

## Next session: start here

**On branch `plan/28-split-01`. Run `/gsd-execute-phase 28`.** Plans are fully review-hardened +
re-checked. **Execution spans TWO repos:** Wave 1 (28-01,28-02, autonomous) acts on
`~/Sourcecode/agenticapps/agenticapps-shared` — carve lib (`helpers.sh`, `fixture-runner.sh` =
**extract_to ONLY**, `preflight.sh`, `drift-test.sh`), broadened standalone suite, amend ADR-0035,
record the release commit SHA, **tag v1.0.0** (must precede Wave 2). Wave 2 (28-03,
**autonomous:false**) acts on claude-workflow feature branch `split-01-agenticapps-shared` — add
submodule **pinned by gitlink SHA == 28-02's recorded SHA**, refactor `run-tests.sh` source-and-keep
(rebuild `setup_fixture` as a wrapper over shared `extract_to`), install.sh existing-clone fix, GSD
before/after diff, PR — then the human-verify checkpoint (fresh-clone `--recurse-submodules` test +
`/gsd-review` on the diff). **HARD GATE: suite must stay PASS=186 FAIL=4 exactly** — do not "fix"
the 0017 failures.

## Open questions

- **agenticapps-shared go-public + LICENSE** — deferred to after SPLIT-01 verifies clean (repo is
  private now; license intentionally not baked in at creation — org-policy call).
- **claude-workflow version bump** — deferred to SPLIT-02 ship time (likely 2.0.0-rc.X).
- **Branch hygiene** — plans live on `plan/28-split-01`; execution Wave 2 uses
  `split-01-agenticapps-shared`. They converge in the phase PR; decide whether to consolidate.
- **SPLIT-02 fold-ins** (Phase 29): cron-flush backport (`RESEARCH-cron-monitor-flush-fxsa.md`),
  #61 buildMonitorConfig/fixture fix, queue-monitor.ts race audit; obs-specific migrate-0019/0021
  + fixtures move here.
