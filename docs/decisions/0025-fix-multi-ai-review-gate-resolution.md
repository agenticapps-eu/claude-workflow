# ADR 0025 — Fix multi-AI review gate phase resolution

**Status:** Accepted
**Date:** 2026-05-25
**Supersedes:** —
**Superseded by:** —
**Related:** ADR 0018, migration 0005, migration 0016

## Context

ADR 0018 created the multi-AI plan-review gate (`multi-ai-review-gate.sh`,
migration 0005) to block code edits when a phase is planned but not reviewed.
A 2026-05-25 audit found the gate installed and wired in cparx, fx-signal-agent,
and callbot — yet firing in none of them. cparx produced no REVIEWS.md after
phase 04.8; fx-signal-agent and callbot produced none ever.

Root cause: the gate resolves the active phase with
`readlink .planning/current-phase`, assuming a symlink to the phase dir. But the
design-shotgun and database-sentinel gates use `.planning/current-phase/` as a
DIRECTORY of approval sentinels. `readlink` on a directory returns empty, so the
gate hit its allow-path and exited 0 on every edit. A convention collision,
silent since migration 0005.

## Decision

Replace the symlink-only resolver with a fail-open chain: (1) legacy symlink,
(2) `STATE.md` `## Current Phase` (cheap awk parse, tried before node),
(3) GSD `state json` `current_phase` (node fallback), (4) newest `*-PLAN.md` by
mtime, (5) allow. Add a grandfather guard to the block condition: block only when
the resolved phase has `*-PLAN.md` AND no `*-REVIEWS.md` AND no `*-SUMMARY.md`.
The `!SUMMARY` guard prevents bricking repos that already shipped phases without
reviews (enforcement is go-forward).

## Alternatives Rejected

- **GSD-state only:** cleanest, but `gsd-tools state json` returned
  `status: unknown` (no `current_phase`) in callbot — unreliable as sole signal.
- **Newest-PLAN heuristic only:** mtime is fragile across `git checkout`/clone;
  kept as the last resort before fail-open, not the primary.
- **Block all unreviewed phases:** would brick fx-signal-agent/callbot; ADR 0018
  forbids blocking already-shipped phases.

## Consequences

- The gate fires on directory-style `current-phase` repos (the real-world case).
- Already-executed unreviewed phases are grandfathered; only new planned-but-
  unexecuted phases block. Historical backfill stays optional.
- Distributed via migration 0016 (workflow 1.14.0 → 1.15.0); idempotent.
- codex-workflow and pi-agentic-apps-workflow need the same resolver — tracked
  as conformance follow-ups in workflow-core spec 02-hook-taxonomy.md.
