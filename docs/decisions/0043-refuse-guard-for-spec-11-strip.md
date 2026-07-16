# ADR-0043: Refuse-guard 0029's §11 strip against non-canonical region content

**Status**: Accepted  **Date**: 2026-07-16  **Linear**: —

## Context

Migration 0029 (ADR-0041) re-anchors the spec §11 canonical block above any
GitNexus region. Its Step 1 heal is a strip-and-re-insert: an awk pass deletes
everything from the block's provenance line to the next `## ` /
`<!-- gitnexus:start -->` terminator, then the canonical mirror is re-inserted
at the region-aware anchor. The Rollback pass shares the same strip awk.

§11 has **no end marker**. The managed region is bounded only on the lower side
by "the next terminator", so its true extent is provenance → the last non-blank
line before that terminator (region H..E). Anything a user places after the
block's closing paragraph but before the terminator falls inside H..E:

- operator prose written under the block, and
- a **lawful host-added anti-pattern bullet** — spec §11 explicitly permits a
  host to `MAY` add bullets to any of the four rules; they layer on top of the
  canonical bullets.

0029's strip deleted all of it, then re-inserted the mirror without it. The
`[ -s ]` non-empty guards downstream could not see the loss: the whole-file
output stays non-empty. Reproduced: a `CLAUDE.md` with prose (or a host bullet)
in that position loses it silently, with 0029 reporting success.

Migration 0030 (ADR-0042) hit the identical boundary in its own byte-resync and
solved it with a blank-line-strip-and-compare guard — but 0030 explicitly
recorded (rationale, "Prose between the block and its terminator") that it did
**not** alter 0029's on-disk contract. The defect stayed live in 0029, which is
the migration that actually runs the destructive strip on every 2.6.0 → 2.7.0
application across the fleet.

## Decision

Add 0030's guard to 0029's Step 1, in **both** the Apply strip and the Rollback
strip. When a provenance line is present, re-extract H..E with the same
buffered-blank-line `extract_block` awk 0030 uses, strip blank lines from it and
the canonical mirror, and diff the remainder:

- **Identical** (only blank-line placement differs) → the region holds exactly
  the canonical block; strip-and-re-anchor is safe (only canonical content
  moves). Proceed.
- **Differs** → refuse (exit 3), print the diff, leave `CLAUDE.md`
  byte-identical for the operator to reconcile by hand.

The guard is **skipped when no provenance line is present** — the greenfield
inject path (state C) has no block to protect, and must not be turned into a
refusal.

This is an **engine bugfix to an existing migration, fixed in place**: no new
migration, no version bump (0029's `to_version` is unchanged), matching the
0028 in-place-fix precedent (commit `85430f1`). Recorded as a `### Fixed` note
under the CHANGELOG `[Unreleased]` section.

## Alternatives Rejected

- **Preserve the prose: strip only the recognized canonical block and re-emit
  the trailing content after the re-anchored block.** Needs the strip to
  distinguish canonical bytes from user bytes, which requires the same
  mirror-comparison anyway, and carries a genuine ambiguity the refuse-guard
  does not: when the block moves above the region, does the prose move with it
  or stay behind? No non-arbitrary answer. 0030 rejected this same approach for
  the same reason.

- **Give §11 a real end marker**, closing the open lower boundary permanently.
  Changes the on-disk contract, needs its own migration to retrofit markers
  onto every existing file, touches the vendored mirror and the CI parity
  guard, and §11 is reproduced verbatim from the spec — inventing a marker is
  plausibly non-conformant (spec §11 Conformance). Wrong size for a bugfix;
  left as a possible future direction.

## Consequences

- A repo that both carries a lawful §11 customization **and** is mis-anchored
  (block below the GitNexus region) will now **refuse to re-anchor** rather than
  re-anchoring — a functional regression against 0029's purpose, traded for not
  destroying user content. This is the same trade 0030 made; 0030 verified all
  five fleet repos have nothing in that position. Refuse-and-reconcile is
  recoverable; destroy is not. The residual "analyze eats a non-re-anchored
  block" risk is mitigated (not eliminated) by migration 0031's
  `--skip-agents-md`.

- The guard's `extract_block` bounds the region with the same terminator
  alternation as the strip it gates, so it is now a fourth and fifth copy of the
  anchor rule. `run-tests.sh`'s `anchor-parity` guard is updated to require 5
  copies in the migration (was 3) and still requires all copies — migration and
  setup — to agree.

- Scope matches 0030's guard exactly, including its **first-block limitation**:
  a `CLAUDE.md` carrying two provenance blocks where only the second holds
  non-canonical content is not independently validated. The primary,
  fleet-relevant shape (a single block with trailing prose or a host bullet) is
  fully closed. Fixtures `12-prose-in-region-refused` (Apply) and
  `13-rollback-prose-refused` (Rollback) mutation-prove the guard; a direct
  probe confirms a lawful interior host bullet is preserved.
