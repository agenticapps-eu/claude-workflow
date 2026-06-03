# Phase 30: SPLIT-03 — claude-workflow 2.0.0 follow-up - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 30-split-03-claude-workflow-2-0-0-follow-up
**Areas discussed:** Migration-chain disposition, Install repoint vs. immutability, Downstream consumption model, 2.0.0 ship + #58 delivery

---

## Migration-chain disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Tombstone/redirect stubs | No-op .md at each removed number recording "moved to agenticapps-observability" + obs equivalent; preserves chain contiguity | ✓ |
| Hard delete | Remove files entirely; claude-workflow + obs become fully independent chains; engine must tolerate numbering gaps | |
| Keep .md, gut skill only | Leave migration docs, delete only the add-observability/ skill they install | |

**User's choice:** Tombstone/redirect stubs (D-01)
**Notes:** Researcher must verify the engine treats a no-op tombstone as satisfied and define the canonical tombstone frontmatter.

---

## Install repoint vs. immutability

| Option | Description | Selected |
|--------|-------------|----------|
| New superseding migration | New migration supersedes 0011's install step; 0011 stays immutable; mirrors Phase 29's 0021→0022 | ✓ |
| Mutate 0011 in place | Edit released 0011's requires/verify; simplest but breaks the content-hash immutability contract | |
| Setup-skill only, no migration | Handle install in setup-agenticapps-workflow; existing projects on /update don't get repointed | |

**User's choice:** New superseding migration (D-02)
**Notes:** This migration also carries the 2.0.0 bump (D-04) and the #58 fix (D-07).

---

## Downstream consumption model

| Option | Description | Selected |
|--------|-------------|----------|
| Chain to setup-observability + UPGRADING.md | setup-agenticapps-workflow optionally invokes obs installer | |
| Vendor obs as a git submodule | Pin obs like agenticapps-shared (SPLIT-01 pattern); awkward for a per-project skill | |
| Two fully independent installs | Install claude-workflow and obs separately, no chaining; maximally decoupled | ✓ |

**User's choice:** Two fully independent installs (D-03)
**Notes:** Structural consequence — the two repos' migration axes FORK (claude-workflow 2.x, obs 1.x consumer axis), which makes the 0022-number reuse across repos safe. The repoint migration verifies the skill is present rather than installing it.

---

## 2.0.0 ship + #58 delivery

| Option | Description | Selected |
|--------|-------------|----------|
| Repoint migration with to_version: 2.0.0 | The superseding migration sets to_version 2.0.0; SKILL.md → 2.0.0; resolves 1.20.0/1.21.0 skew | ✓ |
| Tag-only v2.0.0 baseline | Pure git tag; SKILL.md stays at last migration to_version (skew persists) | |
| Dedicated bump-only 2.0.0 migration | Separate migration just for the version bump | |

**User's choice:** Repoint migration with to_version: 2.0.0 (D-04)
**Notes:** Secondary sub-decisions taken as stated defaults (not contested): #58 delivered as template change + folded into the 2.0.0 migration (D-07); reference cleanup touches non-immutable files only, alias resolves the rest (D-05).

## Claude's Discretion

- Exact tombstone frontmatter shape (D-01).
- Whether the #58 hook step is part of 0022 or a sub-step (D-07).
- `docs/UPGRADING.md` location (D-06).

## Deferred Ideas

- Obs 0.12.0 implementation-agnostic refactor (obs repo planning).
- FIX-0017 XFAIL fixtures (obs follow-up).
- Make shared/obs repos public.
- Untracked root working-draft docs — decide commit/gitignore/archive during Phase 30.
