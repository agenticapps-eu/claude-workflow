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

Add a guard to 0029's Step 1, in **both** the Apply strip and the Rollback
strip, that validates **exactly the line set the strip deletes** — not a
convenient subset of it. When a provenance line is present, re-run the strip's
own state machine *in reverse* to emit precisely the lines it would delete
(mirroring `in_block` / `swallowed_own_h2` line-for-line, across **all**
provenance blocks), then, after normalising trailing whitespace and dropping
provenance lines and blanks, require the remainder to equal the canonical mirror
repeated once per provenance block:

- **Identical** → the strip removes nothing but provenance lines, blank
  separators, and canonical block bytes; strip-and-re-anchor is safe. Proceed.
- **Differs** → refuse (exit 3), print the diff, leave `CLAUDE.md`
  byte-identical for the operator to reconcile by hand.

The guard is **skipped when no provenance line is present** — the greenfield
inject path (state C) has no block to protect, and must not be turned into a
refusal.

An earlier revision of this fix copied 0030's `extract_block`, which validates
only the *first* block from its heading onward. Cross-AI review (codex) proved
that insufficient for 0029: 0030 only *edits* its first block, but 0029's strip
*reacts to every provenance line* and deletes from the provenance line (not the
heading). So `extract_block` left two live data-loss paths — content **before**
the heading, and a malformed **second** provenance region that makes the strip
run to end-of-file. Both are now reproduced as fixtures and closed by validating
the strip's exact deletion set. This is why the guard re-implements the strip in
reverse rather than reusing `extract_block`.

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

- Each guard re-runs the strip's state machine in reverse and so carries the
  same terminator alternation as the strip it gates — a fourth and fifth copy of
  the anchor rule. `run-tests.sh`'s `anchor-parity` guard is updated to require 5
  copies in the migration (was 3) and still requires all copies — migration and
  setup — to agree.

- Comparison is on non-blank content only, exactly like 0030 — no
  trailing-whitespace normalisation. A block that differs from the mirror in any
  non-blank byte (including trailing whitespace) refuses rather than being
  silently rewritten. A normalisation pass was tried and removed after cross-AI
  review (round 2): it could not repair a trailing-whitespace *heading* without
  diverging the guard's state machine from the strip's (which would break the
  "guard validates exactly what the strip deletes" invariant), and it risked
  rewriting away a Markdown hard break (two trailing spaces). Refusing on
  non-blank drift is the deliberate refuse-loudly trade the user chose.

- The presence and count checks use `grep -a` (text mode): a stray NUL byte
  anywhere in `CLAUDE.md` would otherwise make BSD grep classify the file
  "binary" and report no match, skipping the guard entirely while the awk-based
  strip still deletes the block — a silent data-loss bypass. `grep -a` keeps the
  guard firing (found in cross-AI review round 2).

- Fixtures mutation-prove the guard on **reachable** shapes (each asserts the
  real idempotency check reports not-applied, so the updater would run Apply —
  an isolated-guard fixture on an unreachable shape proves nothing about
  production): `12`/`13` (prose after the block, in-region), `14` (content
  before the heading), `15` (malformed second provenance region → run-to-EOF).
  Direct probes confirm a lawful interior host bullet is preserved and the two
  HIGH data-loss shapes now refuse with content intact.

- **Known limitations** (documented in the migration, narrow): refusal on
  trailing-whitespace-only drift (refuse-loudly, matches 0030); back-to-back
  duplicate provenance lines above one block refuse a heal the strip could
  perform (conservative refusal on a degenerate shape, never data loss); a NUL
  *within* a managed block line still reads as blank to BSD awk (pathological
  Markdown, shared with the strip); and the guard's predictable temp paths are
  hardened with `rm -f`-before-write against a pre-planted symlink, though a
  pre-existing directory at those names still fails `rm -f`, and the older
  strip/insert temps carry the same predictable-name pattern as 0030/0031
  (family-wide temp hardening is out of scope). The temp cases all require an
  attacker who can already write into the project directory before a
  user-initiated run.
