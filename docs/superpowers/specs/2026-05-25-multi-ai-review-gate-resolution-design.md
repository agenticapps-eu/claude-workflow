# Design: Fix the dead multi-AI plan-review gate (phase resolution)

**Date:** 2026-05-25
**Author:** Donald Vlahovic (with Claude)
**Status:** Approved — ready for implementation plan
**Related:** ADR 0018 (multi-AI plan review enforcement), migration 0005, workflow-core spec 0.4.0

## Problem

The multi-AI plan-review gate (`multi-ai-review-gate.sh`, installed by migration
0005 per ADR 0018) is **installed and wired in the product repos but never
fires**. Every code-touching `Edit`/`Write`/`MultiEdit` is silently allowed.

Evidence (2026-05-25 audit of `factiv/`):

| Repo | Gate file | Wired in settings.json | Phases with `*-REVIEWS.md` |
|---|---|---|---|
| cparx | present | yes | 01–04.8 only; **04.9, 04.10, 04.11, 04.12, 04.13, 05** and gaps 03.5/03.6/04.6/04.7 missing |
| fx-signal-agent | present | yes | **zero** (01, 02, 03, 04, 04.1, 04.2, 05, 05.1, 06 all missing) |
| callbot | present | yes | **zero** (02, 03, 03.1, 03.2, 03.3, 04, 04.1 all missing) |

This is the exact drift pattern ADR 0018 was written to prevent — and the
enforcement gate it created has been a no-op since it shipped.

## Root cause — a convention collision

The gate resolves the active phase with:

```bash
CURRENT_PHASE=$(readlink .planning/current-phase 2>/dev/null || true)
if [ -z "$CURRENT_PHASE" ] || [ ! -d "$CURRENT_PHASE" ]; then
  exit 0   # "No active phase pointer — allow"
fi
```

It assumes `.planning/current-phase` is a **symlink → phase directory**. But the
*design-shotgun* gate and the *database-sentinel* gate treat
`.planning/current-phase/` as a **directory** that holds approval sentinel files
(`design-shotgun-passed`, `migrations-approved`). In all three product repos
`current-phase` is therefore a regular directory (or, in cparx, absent).
`readlink` on a regular directory returns empty → the gate hits its allow-path →
`exit 0` on every edit.

GSD's canonical record of the active phase is `.planning/STATE.md`
(`## Current Phase`, also surfaced by `gsd-tools.cjs state json` as
`current_phase`), **not** the `current-phase/` directory. The symlink assumption
was never valid for these repos.

## Decision — hybrid phase resolver, grandfather guard

Replace the single `readlink` with an ordered resolver. Each layer is simple;
the chain **fails open** (allows the edit) if nothing resolves, preserving the
sub-100ms / never-crash contract from ADR 0018.

```
Resolve active phase dir:
  1. readlink .planning/current-phase            # legacy symlink (back-compat)
  2. gsd-tools.cjs state json -> .current_phase  # -> phases/<padded>-*
  3. parse STATE.md '## Current Phase'           # -> phases/<padded>-*
  4. newest *-PLAN.md by mtime -> its phase dir
  5. none resolved -> exit 0 (fail-open)
```

**Block condition** (the trust boundary, plus a grandfather guard):

> Block (`exit 2`) the edit **iff** the resolved phase dir has a `*-PLAN.md`
> **AND** has no `*-REVIEWS.md` **AND** has no `*-SUMMARY.md`.

The `!*-SUMMARY.md` guard is the key addition. It means a phase that was already
**executed** without a review is *grandfathered* (allowed) — only a phase that
has been **planned but not yet executed and not reviewed** blocks. Without it, a
working gate would instantly block all code edits in fx-signal-agent and callbot
(every phase there is unreviewed), which ADR 0018 explicitly forbids: "The hook
does not block new code in a project that already shipped phases without reviews;
it only blocks NEW phases that planned without reviewing."

Preserved unchanged from the current hook:
- planning-artifact bypass (`PLAN.md`, `ROADMAP.md`, `REQUIREMENTS.md`,
  `*-CONTEXT.md`, `*-RESEARCH.md`, `*-REVIEWS.md`) — avoids deadlock
- emergency overrides: `GSD_SKIP_REVIEWS=1` and
  `touch .planning/current-phase/multi-ai-review-skipped`
- fail-open on malformed JSON; regular-file checks on `REVIEWS.md`
- matcher `Edit|Write|MultiEdit`

### Filename conventions confirmed against real repos

- plans: `NN-NN-PLAN.md` (matches `*-PLAN.md`)
- reviews: `NN-REVIEWS.md` (matches `*-REVIEWS.md`)
- summaries: `NN-NN-SUMMARY.md` (matches `*-SUMMARY.md`)

All three guard globs match the real artifacts.

## Components / deliverables

1. **Spec (cross-host source of truth)** — update
   `agenticapps-workflow-core/spec/02-hook-taxonomy.md` to specify the
   phase-resolution algorithm for Hook 5 (so all hosts implement it
   identically), and bump the spec version. Add a conformance note that
   **codex-workflow** and **pi-agentic-apps-workflow** must adopt the same
   resolver — tracked as follow-ups, not part of this change.
2. **ADR** — `claude-workflow/docs/decisions/0025-fix-multi-ai-review-gate-resolution.md`
   documenting the collision and the fix (per ADR 0018's own "close the loophole"
   instruction).
3. **Hook** — `claude-workflow/templates/.claude/hooks/multi-ai-review-gate.sh`
   with the hybrid resolver + grandfather guard.
4. **Migration** — `claude-workflow/migrations/0016-fix-multi-ai-review-gate-resolution.md`
   that idempotently re-installs the corrected hook into downstream repos and
   bumps skill version **1.14.0 → 1.15.0** (minor: enforcement behavior changes).
5. **Tests** — extend `claude-workflow/migrations/test-fixtures/` (and/or a hook
   unit test) covering:
   - dir-style `current-phase` + planned/unreviewed/**unexecuted** → **BLOCK**
   - planned/unreviewed + **SUMMARY present** → **ALLOW** (grandfathered)
   - legacy symlink `current-phase -> phases/...` still resolves and blocks
   - GSD-state resolution path (STATE.md `current_phase`)
   - no resolvable phase → allow; malformed JSON → fail-open
   - planning-artifact edit → bypass
6. **Propagation** — apply migration 0016 to cparx, fx-signal-agent, callbot via
   `/update-agenticapps-workflow`; verify the gate now fires (inject a synthetic
   `Edit` event, assert `exit 2` when the active phase is planned/unreviewed/
   unexecuted, `exit 0` otherwise).

## Out of scope (explicit follow-ups)

- **Backfilling historical missing reviews** (cparx 04.9→05, all of
  fx-signal-agent and callbot). The fix is go-forward only. Retro reviews can be
  run separately with `/gsd-review --phase N --all` per phase, on demand.
- **codex-workflow and pi-agentic-apps-workflow** parity — noted in the
  workflow-core spec as conformance follow-ups; not implemented here.
- **claude-workflow dogfooding the gate on itself** — separate decision; the
  user explicitly does not need it in the workflow repo right now.

## Risks

- **STATE.md / gsd-tools reliability.** `gsd-tools state json` returned
  `status: unknown` (no `current_phase`) in callbot. The resolver therefore does
  not depend on any single signal — it falls through to STATE.md parse, then
  newest-`PLAN.md`, then fail-open. No layer can crash the chain.
- **mtime fragility** (layer 4) across `git checkout`/clone. Acceptable because
  it is the last resort before fail-open, and layers 1–3 cover the normal case.
- **Grandfather guard false-allow.** A genuinely active phase that already has a
  `SUMMARY.md` (re-execution / follow-up work) won't block. Acceptable: such a
  phase already executed once; the review gate's purpose is pre-execution.
