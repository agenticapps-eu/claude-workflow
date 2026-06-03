# Phase 30: SPLIT-03 — claude-workflow 2.0.0 follow-up - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 30 is the **claude-workflow side** of the observability split. Phase 29 *copied*
the observability tree (with history) into `agenticapps-eu/agenticapps-observability`
(live at **v0.11.1**) without touching claude-workflow's behavior. Phase 30 performs the
breaking cleanup that makes claude-workflow a clean scaffolder which no longer ships
observability, wires the downstream upgrade path, and ships **claude-workflow 2.0.0** as a
deliberate breaking change.

### IN SCOPE

- **Delete the moved observability tree** from claude-workflow: the whole `add-observability/`
  directory, and the migrations that moved to the obs repo in Phase 29 — `0012, 0013, 0017,
  0018, 0019, 0020, 0021` (their `.md`, their `test_migration_00NN` bodies in `run-tests.sh`,
  their `test-fixtures/00NN/`), the `migrate-0019-*.sh` / `migrate-0021-*.sh` scripts under
  `templates/.claude/scripts/`, and obs ADRs `0029–0034`.
- **Tombstone the removed migration slots** (D-01) so claude-workflow's migration sequence
  stays contiguous and a half-migrated downstream project gets an actionable pointer, not a
  hard gap.
- **Repoint the observability install** via a NEW superseding migration (D-02) — `0011` stays
  immutable/historical; the new migration repoints `requires`/verify to the renamed
  `observability` skill and aborts with an actionable "install agenticapps-observability first"
  message if it is absent (no auto-install — see D-03).
- **Downstream consumption = two fully independent installs** (D-03): consuming projects install
  claude-workflow and agenticapps-observability separately. No submodule, no setup chaining.
- **Ship claude-workflow 2.0.0** (D-04): the repoint/cleanup migration carries `to_version: 2.0.0`,
  bumping `skill/SKILL.md` to 2.0.0 and resolving the existing 1.20.0/1.21.0 skew; git tag `v2.0.0`.
- **Reference cleanup** (D-05): rewrite `add-observability` → `observability` only in NON-immutable
  files (README, CLAUDE.md template, setup/update skills, docs). Immutable shipped migrations keep
  their old-name references — the obs repo's dual-symlink alias resolves them.
- **Downstream upgrade story** (D-06): `docs/UPGRADING.md` (1.21.0 → 2.0.0: "you now also install
  agenticapps-observability separately").
- **Fix #58** (D-07): replace the Haiku prompt-type Stop hook (Hook 3, Phase Sentinel) with the
  deterministic `phase-sentinel.sh` per the issue's proposed fix; delivered as a template change
  (new projects) AND via the 2.0.0 migration (existing projects on `/update`).

### OUT OF SCOPE (deferred / other repos)

- The implementation-agnostic adapter refactor (Destination contract, Sentry/Axiom adapters) —
  that is obs repo **0.12.0**, planned in the obs repo's own `.planning/`.
- FIX-0017 (4 XFAIL 0017 fixtures) — an obs-repo follow-up; travels with migration 0017 in obs.
- Making `agenticapps-shared` / `agenticapps-observability` public — deferred until obs gains
  external consumers.
</domain>

<decisions>
## Implementation Decisions (LOCKED)

### Migration-chain disposition
- **D-01: Tombstone/redirect stubs.** Each removed migration number (`0012, 0013, 0017, 0018,
  0019, 0020, 0021`) is replaced by a minimal no-op `.md` tombstone recording "moved to
  agenticapps-observability" + the equivalent obs migration reference. The chain stays
  contiguous; a project replaying the chain gets an actionable pointer instead of a missing-number
  failure. **Researcher must verify** the migration engine treats a no-op tombstone as
  satisfied (drift test + ordering) and define the canonical tombstone frontmatter shape.

### Install repoint vs. immutability
- **D-02: New superseding migration.** Ship a NEW claude-workflow migration that supersedes
  `0011`'s install step — repoints `requires: skill` and the verify grep from `add-observability`
  to `observability`, updates the project's `observability:` CLAUDE.md metadata cross-reference as
  needed. `0011` is NOT mutated (immutability contract — same rule that forced 0021→0022 in
  Phase 29). This is the migration that also carries the 2.0.0 bump (D-04) and the #58 fix (D-07).

### Downstream consumption model
- **D-03: Two fully independent installs.** Consuming projects install claude-workflow and
  agenticapps-observability separately. NO git submodule (obs is a per-project skill installed into
  `~/.claude/skills`, not a sourced lib), NO setup-agenticapps-workflow → setup-observability
  chaining. The repoint migration (D-02) therefore does NOT bootstrap the skill — it verifies the
  `observability` skill is present and emits an actionable install pointer if absent.

### 2.0.0 ship mechanics
- **D-04: Repoint migration with `to_version: 2.0.0`.** The superseding migration (D-02) sets
  `to_version: 2.0.0`. `skill/SKILL.md` → `2.0.0`, git tag `v2.0.0`, consumer axis advances — the
  existing 1.20.0 (SKILL.md) / v1.21.0 (tag) skew is resolved. The PR is conventional-commits
  breaking: `v2.0.0 chore!: extract observability to agenticapps-observability (SPLIT-03)`.
- **Migration number:** next free integer in claude-workflow's OWN chain. After tombstones fill
  0012–0021, the new migration is **`0022`**. Distinct from obs's `0022` because the two axes are
  now FORKED (D-03 independent installs → separate installed-version fields). claude-workflow goes
  to its own `2.x` axis; obs keeps its `1.x` consumer axis. Planner confirms the exact number.

### Reference cleanup scope
- **D-05: Non-immutable files only.** Rewrite `add-observability` → `observability` in README,
  CLAUDE.md template, setup-agenticapps-workflow / update-agenticapps-workflow skills, and docs.
  Do NOT touch the text of immutable shipped migrations (would break their content hash); the obs
  repo's `add-observability` dual-symlink alias (0.11.0+0.12.0) resolves their old-name references.

### Upgrade story
- **D-06: `docs/UPGRADING.md`.** Document the 1.21.0 → 2.0.0 transition: observability is now a
  separate repo you install independently. Reference the obs repo's own `docs/INSTALLATION.md`
  (written in Phase 29 / obs side).

### #58 — Stop-hook nag
- **D-07: Deterministic shell hook.** Replace the Haiku prompt-type Stop hook (Hook 3, Phase
  Sentinel) in `templates/claude-settings.json` with `templates/.claude/hooks/phase-sentinel.sh`
  per the issue's proposed fix (allow stop unless `.planning/current-phase/checklist.md` exists AND
  has unchecked `- [ ]` items). Delivered as a template change (new projects) AND folded into the
  2.0.0 migration (existing projects get it on `/update`). Self-contained — fix shape already
  specified in #58.

### Claude's Discretion
- Exact tombstone frontmatter shape and whether tombstones carry `from_version`/`to_version`
  passthrough — researcher/planner decides within D-01's intent.
- Whether the #58 hook migration step is part of the 0022 migration or a separately-numbered
  step within it — planner decides; D-07 only fixes the delivery (template + migration).
- Whether `docs/UPGRADING.md` lives at repo root or under `docs/` — planner picks per existing
  docs layout.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 29/30 boundary + locked carry-forward
- `.planning/phases/29-split-02-agenticapps-observability/29-CONTEXT.md` — the authoritative
  Phase 29/30 boundary, the migration-ownership / test-coverage carry-forward matrix (which
  migrations MOVED vs STAY), the TWO version axes (consumer `1.x` vs obs product `0.x`), and the
  immutability rationale. **The move set Phase 30 deletes is this file's "MOVE" column.**
- `.planning/phases/29-split-02-agenticapps-observability/29-VERIFICATION.md` — Phase 29 ship
  evidence (what obs v0.11.0 verified; 186/4 claude-workflow guard).
- `SPLIT-02-agenticapps-observability.md` §"Phase E — Claude-workflow cleanup", §"Phase F —
  Downstream upgrade story", §"Phase G — Verification", §"Phase H — Ship" — the original A–H plan;
  Phase 30 IS Phases E–H of this doc. (Note: the obs-side adapter refactor in §"Phase D" is
  OUT OF SCOPE — obs 0.12.0.)

### Migration engine + the file being superseded
- `migrations/0011-observability-enforcement.md` — the install migration to supersede (D-02).
  Read its `requires:`/`verify:` block (the `add-observability` path grep) and pre-flight aborts.
- `migrations/README.md` — migration engine semantics: immutability of released migrations, the
  drift test (latest migration `to_version` == skill version), `from_version`/`to_version`
  contract, idempotent-reapply guarantee. Defines what a tombstone must not break.
- `migrations/run-tests.sh` — the harness whose `test_migration_00NN` bodies for the moved
  migrations must be removed; the drift test lives here.

### Versioning policy
- `.planning/PROJECT.md` §"Migration-driven versioning" — the rule that SKILL.md version advances
  only with a migration `to_version`; release/baseline tag vs skill version distinction.
- Memory `versioning-tracks-migrations` — engine bugfixes to an existing migration get no bump;
  reinforces why D-02 is a NEW migration, not a 0011 edit.

### #58
- GitHub issue: `https://github.com/agenticapps-eu/claude-workflow/issues/58` — root cause +
  proposed deterministic `phase-sentinel.sh` (the fix shape for D-07).
- `templates/claude-settings.json` — current Hook 3 (Phase Sentinel) prompt-type Stop hook to
  replace.

### Sibling repo (obs side — read for the install contract + alias mechanism)
- `~/Sourcecode/agenticapps/agenticapps-observability/install.sh` — the dual-symlink installer
  the repoint migration's verify must align with (skill name `observability` + `add-observability`
  alias).
- `~/Sourcecode/agenticapps/agenticapps-observability/SKILL.md` — confirms renamed skill identity
  (`name: observability`, `version: 0.11.x`).
- `~/Sourcecode/agenticapps/agenticapps-observability/docs/INSTALLATION.md` (if present) — the
  consuming-project install story UPGRADING.md should cross-reference.

### Cross-repo execution constraints (memories)
- Memory `repo-split-wave-isolation` — Phase 30 touches claude-workflow primarily, but verifying
  the install path reads the sibling obs repo; worktree isolation does not span repos; run
  sequentially.
- Memory `codex-exec-stdin-hang` — `/gsd-review` (D-02 plan must be peer-reviewed) needs
  `< /dev/null` on codex/gemini exec; patched in `~/.claude/get-shit-done/workflows/review.md`.
- Memory `local-scaffolder-clone` — `~/.claude/skills/agenticapps-workflow` is a claude-workflow
  clone; after the 2.0.0 release, `git pull main` there to pick up the deletion/rename.
- Memory `gsd-review-non-skippable` — run `/gsd-review` after plan-checker PASS.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets / precedents
- **0021→0022 supersede pattern (Phase 29).** Phase 29 created a NEW migration to supersede an
  immutable one rather than mutate it. D-02 follows the same shape. See obs repo's `0022` migration.
- **Tag-only baseline precedent (Phase 27, v1.21.0).** Showed a release can ship without a
  migration `to_version` bump; D-04 deliberately does the opposite (migration-driven 2.0.0) to
  resolve the skew that precedent created.
- **Dual-symlink alias (Phase 29 obs `install.sh`).** The alias mechanism already exists on the
  obs side; Phase 30 relies on it for D-05 (old-name references in immutable migrations still
  resolve), so claude-workflow ships NO alias of its own.

### Established patterns / constraints
- **Released migrations are immutable** (content-hash / idempotent-reapply contract for
  callbot, cparx). Forces D-02 (new migration) and D-05 (don't edit immutable migration text).
- **Drift test** asserts latest migration `to_version` == `skill/SKILL.md` version. Deleting the
  highest migrations (0017–0021) drops the "latest" to a tombstone or to 0016; the new 0022
  migration (`to_version: 2.0.0`) re-establishes the drift invariant. **Researcher must confirm
  the drift test reads tombstones correctly.**
- **Sequential migration replay.** The engine applies migrations in number order; tombstones
  (D-01) preserve order so a project pinned to an old baseline doesn't trip a gap.

### Integration points
- `migrations/run-tests.sh` (remove moved `test_migration_*` bodies; keep drift test green).
- `templates/claude-settings.json` + `templates/.claude/hooks/` (#58 hook swap).
- `skill/SKILL.md` (version → 2.0.0).
- README / CLAUDE.md template / setup + update skills (D-05 reference cleanup).
</code_context>

<specifics>
## Specific Ideas

- PR title (conventional-commits breaking): `v2.0.0 chore!: extract observability to
  agenticapps-observability (SPLIT-03)`. PR body links SPLIT-00/01/02/03 + the obs repo + UPGRADING.md.
- The two version axes are now FORKED, not shared: claude-workflow → `2.x` (its skill version),
  obs → `1.x` consumer axis (its own `MIGRATIONS_VERSION`). This is the structural consequence of
  D-03 (two independent installs) and is what makes the `0022`-number reuse across repos safe.
</specifics>

<deferred>
## Deferred Ideas

- **Obs 0.12.0 implementation-agnostic refactor** (Destination contract + Sentry/Axiom adapters) —
  belongs in the obs repo's own planning, not claude-workflow Phase 30.
- **FIX-0017** (4 XFAIL 0017 fixtures) — obs-repo follow-up phase.
- **Make shared/obs repos public** — deferred until external consumers exist.
- **Untracked root docs** (`SPLIT-02-...md`, `RESEARCH-cron-monitor-flush-fxsa.md`,
  `FIX-0017-ENGINE.md`) — decide commit/gitignore/archive during Phase 30 cleanup (content is
  mirrored into phase dirs; these are working drafts).
</deferred>

---

*Phase: 30-split-03-claude-workflow-2-0-0-follow-up*
*Context gathered: 2026-06-03*
