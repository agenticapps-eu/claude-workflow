# claude-workflow

claude-workflow is the **AgenticApps Claude Workflow** — a spec-first, migration-driven
workflow scaffolder for AgenticApps projects. It ships a GSD planning discipline
(discuss → research → plan → execute → verify) together with a migration chain that
keeps every downstream project on a known, reproducible baseline. When a project runs
`/update-agenticapps-workflow`, the migration engine applies every outstanding migration
in sequence, transforming template stacks, tests, and configuration files in-place so
the project can stay current without manual rewrites.

## Core value

- **Spec-first via GSD:** Every feature, fix, or change is planned through the
  GSD workflow (discuss → research → plan → execute → verify) before a single line
  of code is written. Phase planning artifacts live in `.planning/phases/`.
- **Migration-driven versioning:** Downstream projects pin to a baseline release tag
  and advance by running the migration chain. The `skill/SKILL.md` version is
  migration-coupled — it tracks the `to_version` of the latest migration, not the
  latest git tag.

## Who uses it

AgenticApps repositories adopt claude-workflow to get scaffolded observability stacks,
a consistent GSD planning structure, and a migration chain that keeps templates in sync.
Known downstream consumers (as of the 1.21.0 baseline):

- **factiv/cparx** — upgrade target for 1.21.0 baseline
- **factiv/callbot** — upgrade target for 1.21.0 baseline
- **factiv/fx-signal-agent** — upgrade target for 1.21.0 baseline

## Key constraints

### (a) Migration-driven versioning

Per the user rule `versioning-tracks-migrations`:

- The `skill/SKILL.md` `version:` field advances **only** when a migration's
  `to_version` advances.
- Engine fixes, test fixes, or harness changes applied to an existing migration get
  **no** version bump.
- If a release ships **no migration** (e.g., a tag-only baseline), the skill version
  **does not move**.
- Downstream projects verify their baseline via the **git tag + commit SHA**, not by
  reading the installed `SKILL.md` version.

### (b) Spec-first via GSD

All scope changes go through the full GSD lifecycle. No ad-hoc edits to migrations,
templates, or engine code outside a planned phase.

## Versioning policy

claude-workflow uses a two-axis version model:

| Axis | Example | Meaning |
|---|---|---|
| **release / baseline tag** | `v1.21.0` | Git tag + CHANGELOG release marker; what downstreams pin to. |
| **skill version** | `1.20.0` (in `skill/SKILL.md`) | Migration-coupled; advances only when a migration's `to_version` advances. |

A **release/baseline tag MAY lead the skill version.** When a release ships no new
migration (a tag-only release), the skill version stays at the previous migration's
`to_version`. This is deliberate policy, not an inconsistency.

Downstreams verify "we are on the 1.21.0 baseline" by the **tag + commit SHA**, never
by reading the installed `SKILL.md` version. Under the A2 (tag-only) release strategy
used for 1.21.0, the installed `SKILL.md version: 1.20.0` is **not** acceptable
evidence of the 1.21.0 baseline (it would incorrectly indicate 1.20.0 to an auditor).

## Current milestone

**v1.20.x worker-template hardening** — Phases 25-26 shipped `claude-workflow 1.20.0`
(PR #55, `8a838e8`) and then `0.10.0` / `1.20.0` polish (PR #60, `46bb394`).

**Phase 27 (complete, 2026-06-02 — verified 9/9):** Shipped the `v1.21.0` stable baseline as a
**tag-only release** (release/baseline tag `v1.21.0`; skill version stays `1.20.0` — no new
migration, per A2). Closed PR #60's deferred WR-01..04, established this PROJECT.md, refreshed
STATE/ROADMAP drift, and laid split-prep groundwork (ADR-0035 boundary audit). The
`git tag v1.21.0` is a manual release action created at ship time once this work merges to
`main`. Goal: a cooled-off, stable baseline the factiv downstreams upgrade to before the
three-repo split begins. See `SPLIT-00-PREREQUISITES.md`.

## The 3-repo split

claude-workflow is splitting into three repos to let each layer ship independently:

| Repo | Role |
|---|---|
| `claude-workflow` (slimmed) | GSD commands, planning skills, non-observability migrations |
| `agenticapps-shared` (new) | Migration runner, drift test, shared helpers |
| `agenticapps-observability` (new) | Observability scaffolder (Sentry+Axiom, pluggable) |

Split plans:
- `SPLIT-00-PREREQUISITES.md` — gating conditions (this phase satisfies the workflow side)
- `SPLIT-01-agenticapps-shared.md` — shared infrastructure extraction (starts after 1.21.0 ships + cools)
- `SPLIT-02-agenticapps-observability.md` — observability extraction (starts after SPLIT-01 lands)

No code moves in Phase 27. The split is annotation + planning only until the 7-day
cooling-off period completes.

## History

Phases 01-26 history lives in `.planning/phases/` (per-phase directories with
CONTEXT, PLAN, and SUMMARY artifacts) and the git log (`git log --oneline`).
This file does not reconstruct it. Phase 24 (`875c90c`) was the last shipped phase
before formal ROADMAP tracking began.
