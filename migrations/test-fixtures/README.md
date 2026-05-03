# Migration test fixtures

Fixture-based test harness for migrations. The runner is `migrations/run-tests.sh`.

## Approach

Migrations are markdown files describing patches an agent applies. We can't
execute the agent inside `bash`, but we **can** verify the most important
contract — idempotency — by checking each step's idempotency check against
two known reference states:

| State | Meaning | Source |
|---|---|---|
| **before** | Project state immediately before the migration applies | `git show <commit>:templates/...` for the commit that represents `from_version` |
| **after** | Project state immediately after the migration applies | `git show <commit>:templates/...` for the commit that represents `to_version` |

For each step:

- The idempotency check MUST return **non-zero** on the **before** state
  (translation: "the patch is not yet applied — please apply").
- The idempotency check MUST return **zero** on the **after** state
  (translation: "the patch is already applied — skip").

If either property fails, the migration's idempotency contract is broken
and re-running it will either re-apply (corrupting state) or skip-on-first-run
(producing no change).

This catches the most common migration defect — bad anchor strings in
idempotency checks — without requiring an agent runtime.

## What this does NOT test

- The **apply** step itself. An agent executes the apply block based on
  prose interpretation; bash can't simulate that. End-to-end validation
  requires running the migration through `/update-agenticapps-workflow`
  against a real fixture project.
- The **rollback** step. Same reason.
- Migration `0000-baseline.md` — its steps require interactive
  `AskUserQuestion` responses (project name, client, etc.) which can't be
  faked non-interactively. 0000 is validated by running
  `/setup-agenticapps-workflow` against a real fresh project.

## Reference commits

| Version | Commit | Notes |
|---|---|---|
| 1.2.0 | `main` (the commit before any migration applied — at the time of writing, `7dafa63`) | The baseline state. Extracted as the "before" fixture. |
| 1.3.0 | `HEAD` of feat/wire-go-impeccable-database-sentinel after Phase 3 (`c275a04`) | The state migration 0001 should produce. Extracted as the "after" fixture. |

`run-tests.sh` resolves these dynamically (the 1.2.0 baseline is
`git merge-base HEAD main` — the most recent ancestor that pre-dates this
branch) so the harness keeps working after the branch lands and the commits
are renamed by squash-merge.

## Layout

This directory holds:

- `README.md` (this file)

That's it. There are no checked-in `before/` and `after/` subtrees — the
runner extracts them from git on demand. This avoids duplicating ~15KB of
template content that would otherwise need to stay in sync with the live
templates.

## Adding a fixture for a new migration

When you ship migration `NNNN-slug.md` with `from_version: X.Y.Z` and
`to_version: A.B.C`, add a stanza to `run-tests.sh` that:

1. Resolves the commit that represents `X.Y.Z` (typically the merge-base
   from main, or a tagged commit).
2. Resolves the commit that represents `A.B.C` (typically the head commit
   of the branch that ships the migration).
3. Loops every step in the migration, running the idempotency check
   against both reference states.

See the existing 0001 stanza in `run-tests.sh` for the template.
