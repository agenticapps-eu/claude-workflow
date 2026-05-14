# Phase 11 — Chain-gap cleanup — RESEARCH

**Date:** 2026-05-14
**Author:** Donald (with Claude Opus 4.7)
**Source of truth for problem statement:** `session-handoff.md` (2026-05-14)

## Problem

The shipped migration chain on `main` contains a **gap** and a **collision**:

```
0001  1.2 → 1.3
0004  1.3 → 1.4
0002  1.4 → 1.5
[GAP — no migration claims from_version 1.5]
0008  1.7 → 1.8   ── collision (both 1.7 → 1.8)
0009  1.7 → 1.8   ──
0010  1.8 → 1.9
0005  1.9 → 1.9.1
0006  1.9.1 → 1.9.2
0007  1.9.2 → 1.9.3
```

A project still on `1.5.0` (e.g. `cparx`) cannot progress: the runner finds no
migration with `from_version: 1.5.0`. Confirmed via
`/update-agenticapps-workflow --dry-run --from 1.5.0` against `cparx`
during the 2026-05-13 end-of-day sweep.

## Alternatives considered

### Alternative A — Re-anchor 0008 + 0009 frontmatter (RECOMMENDED)

Change only the `from_version`/`to_version` keys on the two affected
migrations. No code-logic changes, no new files.

```
0008  1.5 → 1.6   (was 1.7 → 1.8)
0009  1.6 → 1.8   (was 1.7 → 1.8 — skip 1.7; to_version need not be from+0.1)
```

**Why it works:**
- **0008** ("Coverage Matrix Page") is a workflow-repo-only surface
  (dashboard route). Consumer-project state is unaffected by which
  `from_version` it claims, so re-anchoring is functionally harmless.
- **0009** ("Vendor CLAUDE.md sections") does identical work regardless of
  the incoming version. The 1.6 → 1.8 jump (skipping 1.7) is unusual but
  supported: the runner matches on `from_version` only.
- **0010** is unaffected (still `1.8 → 1.9`, still `requires: [0009]`).
- **0005/0006/0007** unaffected.

**Pros:** Two-line frontmatter rewrite per file. No new artifacts. No
behavioral change. Tiny diff, easy to review.

**Cons:** The chain has a non-monotonic minor-version jump (1.6 → 1.8,
skipping 1.7). Mildly violates "every migration bumps by 0.1" if one reads
that as a hard rule.

### Alternative B — Bridge migration `0011` (REJECTED)

Keep 0009 at `1.6 → 1.7`. Add a new `0011-bridge-1.7-1.8.md` migration that
does nothing but bumps the version. Re-anchor 0008 the same way.

```
0008  1.5 → 1.6
0009  1.6 → 1.7
0011  1.7 → 1.8   (no-op bridge)
0010  1.8 → 1.9
```

**Pros:** Strictly monotonic +0.1 increments through the whole chain.

**Cons:** Adds a no-op migration file purely for chain hygiene — more files,
more test fixtures, more code to maintain. A no-op migration is a code smell:
future readers will ask "why does this exist?" and the answer is "to dodge a
notation convention." The leaner Alternative A wins on every axis except
strict monotonicity.

**Rejection rationale:** the migration runner already supports `to_version`
jumps greater than +0.1 (it matches on `from_version`, not on minor-version
delta). The convention is informal. Codifying it via a no-op file is overkill.

## Decision

**Alternative A.** Two frontmatter edits, one README index update, one
CHANGELOG cleanup, run the test suite, verify against cparx dry-run.

## Scope guards (out-of-scope for this phase)

- **No changes to shipped migrations 0005/0006/0007/0010.** They have
  already shipped under their current `to_version` values; re-anchoring
  them would force consumer projects to re-run them on next update.
- **No new code in `migrations/run.sh` or runner logic.** This is a data fix.
- **No version bump to scaffolder.** The current head version `1.9.3` is
  unchanged. The fix is to the path *to* `1.9.3`, not its identity.

## Verification plan

1. `bash migrations/run-tests.sh` — full suite, all fixtures pass.
2. `/update-agenticapps-workflow --dry-run --from 1.5.0` inside cparx —
   chain walks `0001 → 0004 → 0002 → 0008 → 0009 → 0010 → 0005 → 0006 → 0007`
   without aborting on "no migration found for from_version".
3. `/update-agenticapps-workflow --dry-run --from 1.8.0` (a hypothetical
   newer-version project) — chain walks `0010 → 0005 → 0006 → 0007`,
   skipping the re-anchored 0008/0009 because their `to_version`s are below
   the starting point. (Sanity check that the re-anchor doesn't reintroduce
   already-applied migrations.)

## Related decisions

- See `session-handoff.md` 2026-05-14 (Next session — Phase 11).
- See ADR pending: a follow-up ADR is warranted to document
  "migrations need not be strictly +0.1 to_version" as a workflow norm.
