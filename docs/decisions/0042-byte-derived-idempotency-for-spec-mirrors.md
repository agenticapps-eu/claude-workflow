# ADR-0042: Byte-derived idempotency for vendored spec mirrors

**Status**: Accepted  **Date**: 2026-07-15  **Linear**: —

## Context

Migration 0014 vendors `agenticapps-workflow-core`'s spec §11 canonical block
as `templates/spec-mirrors/11-coding-discipline-0.4.0.md` and injects it into
consumer `CLAUDE.md` files under a provenance comment
(`spec-source: agenticapps-workflow-core@0.4.0 §11`). `913360e` (#42,
2026-05-21) shipped that mirror byte-identical to core's spec §11 as it read
at that moment (core `5ea7ea9`, 2026-05-20). `cparx` (`e6e44e7b`) and
`fx-signal-agent` (`d38a97c`) both ran 0014 that same day and faithfully
received those bytes.

Four days later, core `10f2c96` (#12, 2026-05-25 20:50) added a blank line
after each of §11's four "Anti-patterns this rule prevents:" labels — a
prettier "blank lines around lists" fix — **without bumping `spec_version`**:
it was `0.4.0` both immediately before and immediately after that commit.
`34ee72e` (#44, 2026-05-25 20:51) mirrored the same edit into this repo's
vendored copy, four insertions, one file, no migration.

That stranded the two consumers that had already run 0014: their `CLAUDE.md`
still carried the pre-`10f2c96` bytes, but nothing said so. `callbot` needed
no repair — not because it ran 0014 after the fix, but because it ran 0014
twenty minutes *before* `34ee72e` (`4fa4dac`, 20:31) and received the same
stale bytes as the other two, then self-healed four minutes later when its
own `format:check` ran prettier over `CLAUDE.md` (`1149187`, 20:35) and
independently landed on the same bytes core would ship. A later squash merge
(`d2e92db`, 2026-05-26) concatenates `4fa4dac` and `1149187` under one date,
which is why reading that commit alone produces a false account of the
sequence.

`cparx` and `fx-signal-agent` are stale for exactly one reason: nothing runs
prettier over their root `CLAUDE.md`. `cparx` has no prettier config reaching
its repo root at all; `fx-signal-agent` has a `.prettierrc` but no `format`
script in `package.json` that would ever invoke it. Prettier never stripped
anything from anyone — it *added* the same four lines everywhere it ran
(core's spec, callbot's `CLAUDE.md`, this repo's mirror), and the two repos
that stayed stale are simply the two it never touched. A formatter running
over canonical prose in one location silently forked it from copies in
locations where the formatter never runs — the migration that repairs this
(0030) exists because idempotency was checked against provenance, which
could not see the fork.

## Decision

**Idempotency for vendored spec-mirror payloads is derived from the block's
bytes, never from the provenance version stamp.** This is a structural
necessity, not a style preference: core revised §11's canonical prose without
bumping `spec_version`, so `@0.4.0` remained — and remains — a genuinely
correct stamp over bytes that no longer match the spec it names. A
version-keyed check cannot distinguish "already synced" from "stale" in this
state even in principle; both read `@0.4.0`. Migration 0030 therefore extracts
the block as it currently sits in a project's `CLAUDE.md` and diffs it against
the vendored mirror, byte for byte, ignoring the provenance line entirely for
the purpose of the check.

This also closes an escape hatch that could never have fired. 0014's design
notes prescribe that a future spec revision vendor a new
`11-coding-discipline-0.5.0.md` alongside a migration that swaps both the
provenance line and the block bytes. Core never shipped `0.5.0` — it revised
`0.4.0` in place — so that convention had no revision boundary to trigger on.

**Any edit to a vendored mirror must ship a re-sync migration.** `34ee72e`
edited `templates/spec-mirrors/11-coding-discipline-0.4.0.md` alone and
stranded every project that had already consumed the old bytes. A mirror is
consumed by copy, not by reference, so an edit to it is a fleet-wide change
the moment any consumer exists — never a local one.

`test_mirror_matches_core_spec_11` (`migrations/run-tests.sh`) enforces the
second half of this by binding the mirror itself to a live extraction of
core's spec §11 on every run, with `ci.yml` checking core out at `ref: main`
— deliberately unpinned. Had this guard existed on 2026-05-25, core's
`10f2c96` would have turned this repo's CI red that same day; that is
precisely the notification that was missing for seven weeks. A pinned SHA
would have hidden the same drift and only relocated the hole to "who
remembers to bump the pin." The guard is mutation-proven against the real
historical bytes: installing `git show 913360e:templates/spec-mirrors/11-coding-discipline-0.4.0.md`
over the current mirror turns it red.

## Alternatives Rejected

- **Bump `spec_version` retroactively for `10f2c96` (e.g. to `0.4.1`).**
  Would make provenance-based idempotency work again, but requires editing
  core's history after the fact and inventing a version core never actually
  shipped. Rejected in favor of matching what upstream did, not what it
  should have done.
- **Pin `ci.yml`'s core checkout to a fixed SHA.** Makes the guard
  deterministic, but a pinned SHA can never observe upstream drift — it would
  have stayed green through `10f2c96` and hidden the exact defect this ADR
  records. The guard's entire value is in tracking `main`.
- **Trust the provenance version and rely on manual review to catch upstream
  edits made without a version bump.** This is what shipped in `913360e`
  through `34ee72e`, and it took seven weeks to surface the drift.

## Consequences

- Migration 0030 (v2.7.0 → 2.8.0) re-syncs `cparx` and `fx-signal-agent`;
  `callbot` short-circuits on the idempotency check because its block is
  already byte-identical to the canonical mirror.
- `test_mirror_matches_core_spec_11` runs on every `migrations/run-tests.sh`
  invocation where a sibling `agenticapps-workflow-core` clone is present
  (`CORE_SPEC_DIR`), and is a hard CI failure (`CORE_SPEC_REQUIRED=1`) rather
  than a skip. Any future in-place revision to core's §11 prose — with or
  without a `spec_version` bump — now fails this repo's CI the same day
  instead of silently forking.
- The rule generalizes to any future vendored spec-mirror payload: an edit to
  a mirror file always ships alongside a migration, and any drift check
  written against it should compare bytes, not the provenance stamp.
