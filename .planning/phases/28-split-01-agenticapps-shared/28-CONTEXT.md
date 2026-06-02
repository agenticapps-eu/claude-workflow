# Phase 28: SPLIT-01 — extract shared infrastructure to `agenticapps-shared` - Context

> Authored directly 2026-06-02 (not via interactive /gsd-discuss-phase): all design
> decisions were already locked this session via SPLIT-00/01/02 docs, ADR-0035, and two
> user decisions (D-28a, D-28b). This CONTEXT.md captures those as the planner's input.

<domain>
## Phase Boundary

**In scope:** Carve the SHARED migration infrastructure out of `claude-workflow`'s
single `migrations/run-tests.sh` into the new repo `agenticapps-eu/agenticapps-shared`,
and wire `claude-workflow` to consume it as a git submodule. Shared = the generic
runner/harness/helpers + the drift-test RUNNER mechanism. After this phase, the migration
suite baseline `PASS=186 FAIL=4` is preserved EXACTLY with the shared lib sourced from the
submodule. **(Research correction: baseline is 186/4, NOT "190+ all green." The 4 failures
are pre-existing `test_migration_0017` / FIX-0017 scope — out of this phase. Do not "fix"
them here; do not regress them.) Research also found NO whole-file move qualifies for
filter-repo in SPLIT-01 (all `migrate-*.sh` are obs-specific → SPLIT-02), so EVERY carved
artifact is provenance-by-note (D-28b) and there is NO git-history-surgery step in this phase.**

**Out of scope (explicit):**
- `add-observability/` (whole dir) — moves in Phase 29 (SPLIT-02).
- Observability-specific test bodies/fixtures: `test_meta_destinations_consistency`,
  `_roles_from_adapter`/`_roles_from_meta`, `test_sigterm_mid_apply_preserves_state`,
  `migrate-0019-*`, `migrate-0021-*`, fixtures `0019/` `0021/` — stay (move to obs in SPLIT-02).
- GSD discipline (`gsd-*` skills, agents) and the `agentic-apps-workflow` SKILL.md — stay.
- `bin/gsd-tools.cjs` — DOES NOT EXIST in this repo (it's the GSD framework at
  `~/.claude/get-shit-done/bin/`). SPLIT-01's Phase C framing around it is SUPERSEDED by ADR-0035.
- Version bump of claude-workflow — decided at SPLIT-02 ship time (likely 2.0.0-rc.X).

**Phase A already done (outside the plan cycle):** repo `agenticapps-eu/agenticapps-shared`
created PRIVATE, skeleton committed `d136c96`, tag `v1.0.0-pre.0`. `git-filter-repo` installed.
</domain>

<decisions>
## Implementation Decisions

### D-28a — Sharing mechanism = git submodule (LOCKED, user)
Both consumers (`claude-workflow` now, `agenticapps-observability` in SPLIT-02) vendor the
shared repo as a git submodule at `vendor/agenticapps-shared/`, SHA/tag-pinned. Zero runtime
dependency (no npm registry). Rejected: npm (overweight for bash + tiny CLI), vendored copy
(reintroduces the drift the split exists to kill). CI/install must fetch `--recurse-submodules`.

### D-28b — History preservation = provenance-by-note (LOCKED, user)
`run-tests.sh` is ONE 2579-line file with SHARED+WORKFLOW functions intermingled. `git
filter-repo` is whole-file granularity → it CANNOT carve out only the SHARED functions.
Therefore the SHARED helpers are **refactored** out of `run-tests.sh` into clean NEW
`migrations/lib/*.sh` files in `agenticapps-shared`. `git log --follow` lineage is NOT
preserved for carved code. Provenance is recorded instead via:
- `agenticapps-shared` CHANGELOG "Migration provenance" section
- commit messages referencing the originating claude-workflow commit SHA(s)
The original SPLIT-01 acceptance criterion "every moved file's full log via `git log
--follow`" is AMENDED: it applies only to any WHOLE-FILE moves (e.g. framework-generic
`migrate-*.sh` scripts, generic fixtures) — not to the carved lib functions.

### D-28c — SHARED/WORKFLOW boundary = ADR-0035 annotations (canonical)
The `# SHARED` / `# WORKFLOW` annotations IN `migrations/run-tests.sh` are the canonical
line-level boundary map (9 SHARED / 20 WORKFLOW). ADR-0035's tables are narrative; if they
conflict with the file, the file wins. SHARED set to carve:
`_runtests_do_cleanup`, `extract_to`, `setup_fixture`, `run_check`, `assert_check`,
`test_preflight_verify_paths`, the drift-test RUNNER mechanism, the dispatcher shape.

### D-28d — Drift test: MECHANISM shared, POLICY stays (ADR-0035 §MECHANISM vs POLICY)
The generic grep+awk runner (reads a SKILL.md `version`, finds latest migration `to_version`,
compares) is SHARED. The specific rule "SKILL.md version == latest migration to_version"
(the `versioning-tracks-migrations` invariant) is claude-workflow POLICY and STAYS. The shared
runner takes the SKILL.md path + migrations dir as inputs; the consumer owns "PASS is required".

### D-28e — claude-workflow run-tests.sh becomes a consumer
After extraction, `claude-workflow:migrations/run-tests.sh` SOURCES the shared lib from
`vendor/agenticapps-shared/migrations/lib/*.sh`, KEEPS all WORKFLOW per-migration
`test_migration_00NN` bodies + the drift POLICY, and stays the entry point developers run.
(Decision point for the planner: thin-shim wrapper vs. source-and-keep — recommend source-and-keep
so per-migration bodies stay co-located with the migrations they test.)

### D-28f — Formal rigor (LOCKED, user)
This phase runs the full GSD plan cycle: gsd-planner → gsd-plan-checker → /gsd-review
(codex cross-AI). Justified by high blast radius (history rewriting + run-tests.sh refactor +
new public-org repo + submodule wiring that the whole test suite depends on).

### Claude's Discretion
- Exact lib file decomposition (`helpers.sh` / `fixture-runner.sh` / `drift-test.sh` / `dispatcher.sh`)
- Whether any whole-file moves (framework-generic `migrate-*.sh`, `_example` fixture) go via
  filter-repo (history-preserved) vs. fresh copy with provenance note — prefer filter-repo
  where a file moves WHOLE and is genuinely generic.
- Submodule pin: tag `v1.0.0` (cut at ship) vs. commit SHA — recommend tag.
</decisions>

<canonical_refs>
## Canonical References

- `SPLIT-01-agenticapps-shared.md` — execution plan (Phase A done; Phase C gsd-tools framing SUPERSEDED)
- `SPLIT-00-PREREQUISITES.md` — gate (GREEN by waiver), end-state repo map, open questions
- `SPLIT-02-agenticapps-observability.md` — downstream consumer; depends on this phase's submodule
- `docs/decisions/0035-shared-extraction-boundaries.md` — SHARED/WORKFLOW boundary + MECHANISM/POLICY
- `migrations/run-tests.sh` — the annotated source file (2579 lines; canonical boundary map)
- `RESEARCH-cron-monitor-flush-fxsa.md` — obs fix folded in SPLIT-02 (NOT this phase)
- New repo: `https://github.com/agenticapps-eu/agenticapps-shared` (private, skeleton `d136c96`)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `agenticapps-shared` skeleton already on `main`: `migrations/lib/` `migrations/test-fixtures/_example/`
  `templates/` `bin/` `tests/` (all `.gitkeep`), VERSION=1.0.0, CHANGELOG (with Migration provenance
  stub), README (submodule consumption documented).

### Established Patterns
- Migration discipline: `migrations/NNNN-slug.md` content files + `to_version` frontmatter;
  fixtures `test-fixtures/NNNN/MM-name/{setup.sh, verify.sh, expected-exit}`.
- `run-tests.sh` dispatcher: `if [ -z "$FILTER" ]` runs all; otherwise filtered subset.

### Integration Points
- `install.sh` — must init submodule on fresh clone.
- Any CI workflow — must clone `--recurse-submodules` (verify presence of CI first).
- Drift test consumes `skill/SKILL.md` (stays in claude-workflow at version 1.20.0 under A2).
- `migrations/run-tests.sh` is invoked by developers + likely by GSD hooks — path must keep working.
</code_context>

<specifics>
## Specific Ideas
- Suggested lib decomposition in agenticapps-shared:
  `migrations/lib/helpers.sh` (logging, `run_check`, `assert_check`, cleanup trap),
  `migrations/lib/fixture-runner.sh` (`setup_fixture`, `extract_to`),
  `migrations/lib/preflight.sh` (`test_preflight_verify_paths`),
  `migrations/lib/drift-test.sh` (the runner mechanism, policy-agnostic).
- `agenticapps-shared/tests/run-tests.sh` exercises the shared lib in isolation (so the shared
  repo has its own green suite independent of claude-workflow).
</specifics>

<deferred>
## Deferred Ideas
- `agenticapps-shared` go-public flip + LICENSE choice — defer to after SPLIT-01 verifies clean
  (repo is private now; license is an org-policy call, intentionally not baked in at creation).
- `add-observability`→`observability` rename, obs fix backports, #58 — Phases 29/30.
- Whether agenticapps-shared needs its OWN drift test — ADR-0035 says probably not (ships infra,
  not a skill); revisit if a SKILL.md ever lands there.
</deferred>
