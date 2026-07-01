# ADR-0036 — Fresh installs use a snapshot, not migration replay

**Status:** Accepted
**Supersedes (for the setup path):** the "setup and update share one code
path through the migration files" stance (originally ADR for the v1.2.0
migration-framework refactor).

## Context

`setup-agenticapps-workflow` applied every migration from `0000-baseline`
forward to reach the current shape — the same runtime as `update`. With 20+
migrations in the chain, a brand-new project re-executes the entire history to
arrive at a state that is fully known ahead of time, and every historical
migration must remain replayable against an empty repo forever. There is no
prior state to migrate on a fresh project, so the replay is pure overhead and a
standing fragility surface.

## Decision

Split the two flows by mechanism:

- **Fresh install (`setup`) → snapshot.** Ship `setup/snapshot/`, the
  materialized end-state of every project artifact. Setup copies it,
  substitutes placeholders, stamps the version. No migration executes.
- **Existing install (`update`) → migrations.** Unchanged. Apply only pending
  migrations (`from_version >` the installed version).

The installed-version record stays where it was: the `version:` frontmatter of
the project's `.claude/skills/agentic-apps-workflow/SKILL.md`.

## How the snapshot stays correct

The snapshot can drift from the chain (a migration is added but `snapshot/`
isn't regenerated). Two mechanisms prevent shipping drift:

- **`bin/build-snapshot.sh`** materializes `snapshot/` by replaying
  `0000`→latest into a throwaway fixture on a host with the scaffolder + GSD +
  gstack installed. This is the only step that must run on a real machine — it
  is inherent: you cannot materialize a 20+ migration end-state without
  executing the migrations.
- **`migrations/check-snapshot-parity.sh`** (CI, every PR) replays the chain
  and diffs the result against `snapshot/`. A mismatch fails the build.

## Consequences

- Fresh setup is one reviewable diff instead of 20+ commits.
- Adding a migration gains a second obligation: regenerate `snapshot/`. The
  drift guard enforces it.
- The migration chain remains the source of truth for upgrades and stays fully
  replayable; `0000-baseline` is retained as the parity anchor.
- This is consistent with the parallel decision in `opencode-workflow`
  (ADR-0007) and `codex-workflow`, keeping the three host forks aligned on
  install semantics. See `agenticapps-workflow-core` if/when this is promoted
  into the shared spec (it currently diverges from core ADR-0013).
