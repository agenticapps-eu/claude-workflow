# Phase 29: SPLIT-02 — extract observability to `agenticapps-observability` - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning
**Source:** Synthesized from `SPLIT-02-agenticapps-observability.md` (full A–H plan doc) + `RESEARCH-cron-monitor-flush-fxsa.md` (cron-flush fix research) + ROADMAP Phase 29/30 boundary. No discuss-phase run — the source docs are richer than any discuss output would be.

<domain>
## Phase Boundary

Phase 29 is the **NEW-REPO side** of the observability split. It creates and populates
`agenticapps-eu/agenticapps-observability`, renames the skill, folds the deferred
observability fixes into a new migration in the obs repo, verifies the new repo green,
and tags `observability v0.11.0`.

**It does NOT touch claude-workflow's behavior.** claude-workflow stays fully working
through Phase 29 — `add-observability/` is COPIED (with history) into the new repo, not
deleted. The breaking cleanup (delete `add-observability/`, repoint the install migration,
alias deprecation window, `claude-workflow 2.0.0` ship, fix #58) is **Phase 30 (SPLIT-03)**.

### IN SCOPE (Phase 29)

- **Phase A — Bootstrap new repo.** `gh repo create agenticapps-eu/agenticapps-observability`
  (private initial, MIT default license), skeleton layout per the SPLIT-02 doc, `VERSION`
  `0.11.0`, `CHANGELOG.md` continuing the version line from `add-observability` 0.10.0,
  `implements-spec.md` (0.3.2), README skeleton, `install.sh` stub.
- **Phase A.3 — Submodule.** Add `agenticapps-shared` as a git submodule at
  `vendor/agenticapps-shared/`, pinned to `v1.0.0` (gitlink SHA `1f5d543`, the SPLIT-01
  release). Mirrors the SPLIT-01 consumption pattern.
- **Phase B — Extract WITH history.** `git filter-repo` against a claude-workflow scratch
  clone to bring the observability tree into the new repo with `git log --follow` lineage:
  `add-observability/` whole tree, the observability migration scripts + content + fixtures,
  and the observability ADRs. **Which migrations are "observability" is a planner audit task
  (see Gray Areas).**
- **Phase C — Skill rename (new-repo side only).** `SKILL.md` frontmatter
  `name: add-observability` → `name: observability`, `version: 0.10.0` → `0.11.0`; update
  internal references (init/INIT.md, scan/SCAN.md, README); scaffold the `add-observability`
  legacy alias (Option A dual-symlink) and the new repo's `install.sh`. (Managing the
  2-minor deprecation **window** and claude-workflow's references is Phase 30.)
- **Deferred-fix migration (the "first migration" the goal names).** A NEW migration in the
  obs migration line that **supersedes 0021** (do NOT mutate 0021 — it is Released/immutable),
  folding three deferred observability fixes:
  1. **cron-flush backport** — re-rev `cron-monitor.ts` (`withCronMonitor`) to the
     explicit-per-check-in-flush body. Canonical draft + rationale are in
     `RESEARCH-cron-monitor-flush-fxsa.md` (confirmed FX-SIGNALS-WORKERS-6 race; no upstream
     SDK fix as of 2026-06-02). Recognise the `FXSA-WORKERS-6` LOCAL-PATCH marker as a
     known-reconcilable divergence so fx-signal-agent accepts on marker removal.
  2. **#61 buildMonitorConfig / fixture fix** — replace the relaxed `MonitorConfig` stub in
     `migrations/test-fixtures/0021/04-.../types.d.ts` with the real `@sentry/cloudflare`
     shape; forward `monitorConfig` on every check-in (in_progress/ok/error).
  3. **queue-monitor.ts race audit** — audit `queue-monitor.ts` (cf-worker + cf-pages, shipped
     by 0021) for the identical buffered-flush race; apply the same explicit-flush treatment
     if its handler can run long.
  Plus a **new ADR** in the obs repo superseding ADR-0033's Guarded-Shape-A flush point, and
  rewriting the ~11 `withMonitor`-contract test cases + adding the immediate-flush regression
  test (per RESEARCH-cron Q3), while **preserving the narrowed strict-Env generic** (ADR-0032
  / SC5 — do NOT copy fxsa's `Record<string, unknown>` form).
- **Phase G — Verify the new repo green.** obs `migrations/run-tests.sh` runs 0019 (13
  fixtures) + 0021 (4 fixtures) + the new migration GREEN; all 5 template stacks pass; drift
  test passes (SKILL.md version == latest migration to_version, mechanism from shared);
  `/observability *` AND `/add-observability *` slash commands both resolve; `git log --follow`
  works on moved files.
- **Phase H (partial) — Ship the new repo.** Tag `agenticapps-observability v0.11.0`; push
  (USER-GATED — see Cross-Repo Constraints). The claude-workflow PR / `2.0.0` tag is Phase 30.
</domain>

<decisions>
## Implementation Decisions (LOCKED)

### Repo + naming
- New repo: `agenticapps-eu/agenticapps-observability`, private initially (flip to public after
  the 0.12.0 impl-agnostic refactor — deferred), MIT license default (user may override).
- Skill renamed `add-observability` → `observability` (the noun/product identity).
- `add-observability` stays as an alias for **two minor releases** (0.11.0, 0.12.0); warning
  in 0.13.0; removed in 0.14.0. Alias mechanism = **Option A (dual-symlink)** for 0.11.0+0.12.0.
- obs repo starts at **0.11.0**, continuing the version line from `add-observability` 0.10.0.
  0.11.0 = pure structural extraction + rename + deferred-fix migration. NO functional adapter
  refactor in 0.11.0.

### Submodule (mirrors SPLIT-01)
- Consume `agenticapps-shared` via git submodule at `vendor/agenticapps-shared/`, pinned by
  **gitlink SHA** to the `v1.0.0` release (`1f5d543`). obs `migrations/run-tests.sh` is a thin
  shim that sources the shared lib (same source-and-keep pattern claude-workflow uses).

### Deferred-fix migration
- A NEW migration that **supersedes 0021** (route (b) in RESEARCH-cron Q4). NOT a 0021 re-issue
  (0021 is immutable — mutating its baseline breaks the hash/idempotency contract for callbot,
  cparx). Same all-clean-gate + dirty-detection engine as 0021.
- The three deferred obs fixes ship together in this one migration (they touch the same templates).
- **fxsa's `CronMonitorConfigInput` function-form generalisation is SEPARABLE** — default per
  RESEARCH-cron: leave it out (fxsa retains a much smaller local delta); planner may fold it in
  if low-cost. Not required for the missed-checkin fix.

### History
- Phase 29 uses `git filter-repo` for **whole-file moves** (the observability tree), so
  `git log --follow` lineage IS preserved (unlike SPLIT-01's function-carve, which was
  provenance-by-note per D-28b). CHANGELOG records provenance to claude-workflow phases 21–26.

### Planning artifacts stay
- `.planning/phases/25-*` and `26-*` STAY in claude-workflow (historical record; moving them
  rewrites history and breaks PR #57/#60 links). Future obs phases get their own `.planning/`
  in the new repo.
</decisions>

<gray_areas>
## Gray Areas — resolve during planning (planner audit tasks)

1. **Migration-ownership audit (REQUIRED early task).** Apply the SPLIT-02 doc's boundary test
   — *"who owns the failure mode if this migration breaks?"* — to migrations 0011–0021 and
   produce a definitive move/copy/stay table. Known anchors: `add-observability/` install
   migration 0011 STAYS in claude-workflow (it bootstraps the skill INTO a project — Phase 30
   repoints it); 0019 + 0021 (scripts + content + fixtures) MOVE; obs ADRs 0029–0034 MOVE.
   **Unresolved in the source doc:** the SPLIT-02 doc lists `0017` under "stays in
   claude-workflow" (line 122) but `migrate-0017-axiom-destination.sh` scaffolds the Axiom
   destination = observability — the boundary test says it MOVES. Resolve explicitly. Also
   audit 0012/0013 (init/SKILL versioning — obs-specific per the doc).
2. **Disposition of the 4 known-failing `test_migration_0017` tests.** claude-workflow's
   baseline is `PASS=186 FAIL=4` where the 4 fails are `test_migration_0017` (FIX-0017 scope).
   If 0017 moves to the obs repo, those 4 failures move with it — the obs repo would start at
   `~13+4+...` with 4 known-failures until FIX-0017 lands. Decide: move 0017 + document the
   known-failures (mirroring claude-workflow today), or leave 0017 in claude-workflow for now
   and move it in a later obs migration. Either is defensible; planner picks and documents.
3. **Deferred-fix migration number + from/to versions.** Pick the obs migration number
   (continue the chain), `from_version` = current obs baseline, `to_version` = next.
</gray_areas>

<cross_repo_constraints>
## Cross-Repo Execution Constraints (memory: repo-split-wave-isolation, codex-exec-stdin-hang)

- **Sequential waves, no worktree isolation.** Phase 29 writes primarily to a SIBLING repo
  (`~/Sourcecode/agenticapps/agenticapps-observability`) and a scratch clone of claude-workflow.
  GSD worktree isolation does NOT help (the sibling repo is outside the worktree). Run waves
  sequentially.
- **User-gated sibling release.** Creating the GitHub repo, pushing it, and making the
  `agenticapps-shared` submodule resolvable are outward-facing, hard-to-reverse actions → the
  repo-create + push + tag tasks must be `autonomous: false` checkpoints. The new repo must
  exist and its submodule resolve BEFORE any verification that fetches `--recurse-submodules`.
- **Ordering:** A (bootstrap + submodule) → B (extract-with-history) → C (rename) +
  deferred-fix migration → G (verify) → H (tag/push, user-gated). A must complete (repo exists)
  before B can push into it.
- If any cross-AI review step shells `codex exec`, it must use `< /dev/null` to avoid the
  stdin-hang (memory: codex-exec-stdin-hash); the patched `review.md` already does this.
- **obs-repo feature-branch policy** (global CLAUDE.md "never commit directly to main"): plans 01–02
  bootstrap the fresh obs repo directly on `main` (no pre-existing branch to PR against — SPLIT-01
  precedent); plans 03–05 do their substantive development on the obs-repo feature branch
  `split-02-rename-and-0022`, and plan 05 opens a PR that is merged to `main` BEFORE the `v0.11.0` tag.
</cross_repo_constraints>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase plan + research (primary)
- `SPLIT-02-agenticapps-observability.md` — full A–H execution plan, exact `gh`/`git`
  commands, new-repo layout, skill-rename mechanics, failure-mode handling. **NOTE the scope
  correction in this CONTEXT: Phase E / 2.0.0 ship / claude-workflow deletion belong to Phase
  30, not 29; Phase D impl-agnostic refactor is deferred to its own phase in the new repo.**
- `RESEARCH-cron-monitor-flush-fxsa.md` — cron-flush fix: SDK-internals proof, the canonical
  `withCronMonitor` explicit-flush draft body, the 22-test impact, the FXSA-WORKERS-6 marker,
  and the obs-migration delivery recommendation. The `<draft>` body is copy-ready.

### ADRs (observability — moving to new repo)
- `docs/decisions/0029-*.md` … `0034-observability-init-singleton-invariant.md` — observability
  runtime ADRs. Verify each is observability-scoped during the migration-ownership audit.
- `docs/decisions/0035-shared-extraction-boundaries.md` — SHARED/WORKFLOW boundary (SPLIT-01;
  defines what `agenticapps-shared` owns).
- ADR-0032 (strict-Env generic narrowing / SC5), ADR-0033 (Guarded Shape A), ADR-0034 (init
  singleton invariant) — the cron-flush ADR supersedes ADR-0033's flush point.

### SPLIT-01 precedent (the proven pattern this phase repeats)
- `.planning/phases/28-split-01-agenticapps-shared/28-VERIFICATION.md` + `28-0{1,2,3}-SUMMARY.md`
- `migrations/run-tests.sh`, `install.sh`, `.gitmodules`, `vendor/agenticapps-shared/` —
  claude-workflow's working submodule-consumer reference implementation.

### Sources to extract (the move set — audit confirms exact list)
- `add-observability/` whole tree; `migrations/0019-*.md`, `0021-*.md`;
  `templates/.claude/scripts/migrate-0019-*.sh`, `migrate-0021-*.sh`;
  `migrations/test-fixtures/0019/` (13), `0021/` (4).
</canonical_refs>

<specifics>
## Specific Ideas

- New-repo layout is fully specified in the SPLIT-02 doc ("New repo layout (proposed)") — use
  it, but **the `destinations/_contract/`, `destinations/sentry/`, `destinations/axiom/`,
  `_examples/`, `docs/adapter-contract.md` items are Phase-D (deferred) scaffolding** — in
  Phase 29 these are at most empty `.gitkeep` skeleton dirs; no contract code, no adapter
  relocation. 0.11.0 keeps the existing `destinations/registry.ts` pattern verbatim.
- The cron-flush `withCronMonitor` draft (RESEARCH-cron, lines 123–166) is the authoritative
  body — copy it; do not redesign. Keep `isConfigured`/`resolveSlug`/`buildMonitorConfig` and
  the narrowed generic `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }` unchanged.
- The three floating root docs (`SPLIT-02-agenticapps-observability.md`,
  `RESEARCH-cron-monitor-flush-fxsa.md`, `FIX-0017-ENGINE.md`) are the untracked noise the
  handoff flagged. Phase 29 consumes the first two as planning inputs (now mirrored into this
  phase dir's CONTEXT/RESEARCH). Recommend committing or relocating them as part of planning.
</specifics>

<deferred>
## Deferred Ideas (explicitly OUT of Phase 29)

- **Phase 30 (SPLIT-03):** delete `add-observability/` from claude-workflow; repoint the install
  migration (0011) to the new repo + new skill name; manage the alias deprecation window on the
  claude-workflow side; ship `claude-workflow 2.0.0` (breaking-change rationale); fix #58
  (Stop-hook nag).
- **Phase D (own GSD phase IN the new obs repo, → obs 0.12.0):** implementation-agnostic
  redesign — promote the `Destination` interface to a published stable contract, relocate
  Sentry/Axiom code into `destinations/sentry/` + `destinations/axiom/`, move
  `buildSentryOptions` (DEF-1) into `destinations/sentry/buildOptions.ts`, refactor wrapper
  templates to consume the registry instead of importing SDKs, write `docs/adapter-contract.md`
  + `_examples/` skeletons, design the downstream `--migrate-to-destinations` story. The
  SPLIT-02 doc itself recommends running this as the obs repo's own Phase 1.
- **FIX-0017-ENGINE.md** (3 migration-0017 engine bugs + coverage gaps): NOT in the Phase 29
  goal. It travels WITH migration 0017 wherever the ownership audit lands it — if 0017 moves to
  the obs repo, FIX-0017 becomes an obs-repo follow-up phase. Documented + deferred, not
  implemented in Phase 29.
- **fxsa `CronMonitorConfigInput` function-form generalisation** — separable from the
  missed-checkin fix; default leave out (see Decisions).

---

*Phase: 29-split-02-agenticapps-observability*
*Context gathered: 2026-06-02 (synthesized from SPLIT-02 + RESEARCH-cron docs; scope corrected against ROADMAP Phase 29/30 boundary)*
