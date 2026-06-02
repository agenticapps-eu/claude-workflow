# Session Handoff — 2026-06-02

## Accomplished
- Executed **Phase 28 (SPLIT-01)** end-to-end across two repos — `/gsd-execute-phase 28`.
- **Wave 1 / 28-01:** carved SHARED migration harness into `agenticapps-shared/migrations/lib/{helpers,fixture-runner,preflight,drift-test}.sh` (A1: only `extract_to` shared, `setup_fixture` stays WORKFLOW; A5: `${STRICT_PREFLIGHT:-0}` set-u safe; D-28d drift mechanism/policy split). ADR-0035 amended (9→8 SHARED). 3 commits in agenticapps-shared.
- **Wave 1 / 28-02:** standalone suite (12/0) proving extract_to real-ref + preflight strict/non-strict + set-u; CHANGELOG provenance; tagged **v1.0.0** @ `1f5d543` (canonical pin SHA, A4).
- Pushed `agenticapps-shared` main + v1.0.0 to GitHub (user-authorized release).
- **Wave 2 / 28-03 (checkpoint plan):** claude-workflow consumes the submodule at `vendor/agenticapps-shared` (gitlink == `1f5d543`); run-tests.sh source-and-keep refactor; setup_fixture wrapper (A1); install.sh A3. **Hard gate held: PASS=186 FAIL=4.** Opened PR #65.
- **Review:** gstack `/review` + codex cross-model on the diff. 3 edge-case findings → all hardened in `096f35f` (fail-closed lib check, install.sh non-git guard, symlink-safe path). Re-verified 186/4.
- **Fresh-clone verification** (SC-2) passed: clean `--recurse-submodules` clone runs 186/4 at pinned SHA.
- **Merged PR #65** (squash `aa1d60f`) to main; deleted feature branch.
- **Close-out:** gsd-verifier PASS 9/9 → `28-VERIFICATION.md`; ROADMAP/STATE phase 28 complete. Opened **PR #66** (bookkeeping).

## Decisions
- Wave 1 run sequentially on main tree (no worktree) — 28-02 depends on 28-01's lib AND both write the un-isolated `agenticapps-shared` repo. Worktree isolation would not have helped.
- Submodule pinned by **gitlink SHA** (A4); tag v1.0.0 is provenance only.
- Applied all 3 codex review findings before merge (user chose "apply all 3").
- Close-out docs go via PR #66, not direct-to-main (global rule).

## Files modified
- `migrations/run-tests.sh` — sources shared lib + setup_fixture wrapper + policy wrappers + hardening.
- `install.sh` — submodule sync+update (A3) + non-git guard.
- `.gitmodules`, `vendor/agenticapps-shared` (gitlink), `CHANGELOG.md`, `docs/decisions/0035-*.md`.
- `agenticapps-shared` repo: `migrations/lib/*.sh`, `tests/run-tests.sh`, `_example` fixtures, CHANGELOG/README/VERSION, tag v1.0.0.
- `.planning/`: 28-0{1,2,3}-SUMMARY, 28-VERIFICATION, ROADMAP, STATE.

## Next session: start here
**Merge PR #66** (close-out bookkeeping) to finalize phase 28 records on main. Then Phase 28 is fully closed. Next roadmap item is **Phase 29 (SPLIT-02)** — extract observability to `agenticapps-observability` (skill rename `add-observability`→`observability`, starts 0.11.0, folds deferred obs fixes incl. `RESEARCH-cron-monitor-flush-fxsa.md`). Begin with `/gsd-plan-phase 29` (CONTEXT lives in `SPLIT-02-agenticapps-observability.md`).

## Open questions
- Optional: `/gsd-secure-phase 28` — low value (bash harness + submodule, no auth/storage/API/LLM surface); skipped by judgment.
- `agenticapps-shared` is still **private**; go-public + LICENSE deferred until SPLIT-01 verified clean (now is — revisit before SPLIT-02 consumers).
- Pre-existing untracked root noise (`FIX-0017-ENGINE.md`, `RESEARCH-cron-monitor-flush-fxsa.md`, `SPLIT-02-agenticapps-observability.md`) — decide commit/gitignore/relocate during SPLIT-02 planning.
