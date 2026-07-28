# ADR-0046: The vendored workflow reference is a companion, not a second copy

**Status**: Accepted  **Date**: 2026-07-28  **Linear**: —

Resolves the open question recorded in
[ADR-0045](0045-revendor-openspec-instruction-payload.md).
Implemented by migration `0034` (3.1.0 → 3.2.0).

## Context

`0033` retargeted `.claude/claude-md/workflow.md` off the retired GSD engine and
onto the OpenSpec lifecycle. What it shipped was ~190 lines restating the
trigger skill's commitment ritual, lifecycle table, gate-to-skill map,
rationalization table and red flags. Correct — and duplicated.

Three things made the duplication indefensible rather than merely untidy:

1. **The duplication is what caused the defect `0033` fixed.** The §04 red-flag
   divergence sat undetected for five migrations precisely because the second
   copy could drift silently. `skill/SKILL.md` disclosed it in `## Spec deltas`
   and nobody re-read that file.
2. **The guard `0033` added is a pin holding one block in sync — and only one.**
   `test_workflow_md_red_flags_match_canonical` was the right response to a
   divergence and the wrong response to its cause. A check that exists to keep
   two copies identical is an argument for having one copy. Worse, it covers the
   §04 red-flag block *only*: the lifecycle table, the gate-to-skill map and the
   rationalization table were duplicated in both files and pinned in neither, so
   they could drift exactly as §04 did with nothing to notice.
3. **A downstream repo had already solved it.** `agents-task-viewer` replaced
   its vendored copy, by hand, with a 67-line companion that orients and then
   defers, under an explicit rule: it *"never duplicates the SKILL's lifecycle
   or gate rules (§11: one source, no drift)"*. When the `0033` rollout swept
   the fleet it **overwrote that file** with the 190-line duplicate. The sweep
   destroying the better structure is what surfaced the question.

## Decision

**Adopt the downstream shape upstream.** The vendored file becomes a companion:
it states the three disciplines, the six lifecycle stages, what the §18 gate
enforces and where the gstack tooling fits — then defers. The commitment ritual
template, the rationalization table and the red flags live in the SKILL and are
not restated. The file opens with the contract that makes this checkable:

```
> **Authoritative source:** the enforcement skill
> [`.claude/skills/agentic-apps-workflow/SKILL.md`](../skills/agentic-apps-workflow/SKILL.md).
> This file is a short companion — it orients, then defers. It never duplicates
> the SKILL's lifecycle rules, gate map, rationalization table, or red flags
> (spec §11: one source, no drift).
```

**The file is not deleted.** `CLAUDE.md` is always in the context window; a
skill loads only when its trigger fires. A short always-on orientation document
earns its place — the 190-line restatement did not. Deleting it outright would
also change `normalize-claude-md.sh` behaviour (it keys off the file's existence
to collapse a `<!-- GSD: -->` marker block — live in `cparx` and
`agents-task-viewer` today) and break `0000`/`0009`'s post-checks. That remains
available as a separate change; nothing here forecloses it.

**The sync pin is inverted, not deleted.** With one copy there is nothing to
pin, but silently dropping the check would let a revert reintroduce the
duplicate unnoticed. `test_workflow_md_defers_to_the_skill` now asserts that the
SKILL still carries the canonical §04 block *and the rationalization table*, and
that the template and snapshot carry **neither** — plus the sentinel that
`0000`, `0009` and `0034` all anchor on. Same assert-the-absence treatment
`check-snapshot-parity.sh` §10 gave GitNexus.

## Alternatives Rejected

- **Keep the full duplicate and rely on the pin.** Rejected: the pin only covers
  the red-flag block. The lifecycle table, gate map and rationalization table
  were never pinned and could drift exactly as §04 did.
- **Delete the file, repoint `CLAUDE.md` at the skill.** The cleanest
  single-source answer, and still on the table — but it must ship with the
  `normalize-claude-md.sh` change and the `0000`/`0009` post-check changes in
  one migration. That is a bigger, hook-touching change than this one, and the
  always-in-context value of a short orientation doc is real.
- **Sweep `0033` to the fleet and revisit later.** This is what was in progress
  when the question arose. It propagates *correctness* while *entrenching* the
  duplication, and costs two rounds of downstream churn instead of one.

## Consequences

- **One source for every rule the workflow enforces.** The companion can go
  stale about *orientation*; it can no longer disagree with the SKILL about a
  *rule*, because it states none.
- **Two released migrations gained shape tolerance.** `0000`'s post-check and
  `0009`'s Step 2 idempotency check anchored on the
  `Superpowers Integration Hooks (MANDATORY` heading, which the companion does
  not have. Both now accept that heading **or** the Authoritative-source
  sentinel. Both alternatives are kept, not swapped: a chain replaying from an
  old install passes through the pre-3.2.0 shape on the way here.
- **`0033`'s post-checks were pinned to their own payload, and are now
  version- and shape-tolerant.** Two of them broke the moment `0034` landed:
  one asserted the red-flag block was byte-identical (it is now absent), the
  other asserted `version: 3.1.0` literally (Step 3 copies whatever the
  scaffolder ships, so the literal turns false on every later bump). Both were
  rewritten to assert the *guarantee* rather than the *payload of the day* —
  "no red-flag block that differs from canonical", and "the trigger skill is the
  scaffolder's copy, at 3.1.0 or later". This is a recurring trap in a migration
  chain whose fixtures replay against the live scaffolder, and worth naming:
  **a post-check that pins the current payload expires; one that states the
  invariant does not.**
- **`agents-task-viewer` is the origin of this shape, not a straggler.** Its
  local companion predates the upstream one and differs in wording. Either
  answer on `0034`'s divergence prompt is defensible there.
- **`agenticapps-dashboard` keeps no `workflow.md` at all.** `0034` Step 1
  no-ops there and does not re-litigate that choice.
