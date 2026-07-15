# ADR-0041: Region-aware §11 block placement

**Status**: Accepted  **Date**: 2026-07-15  **Linear**: —

## Context

Migration 0014 anchors the spec §11 canonical block immediately before the
first `## ` heading in `CLAUDE.md`. That placement is deliberate — it
guarantees the block is followed by a `## ` line, which bounds the managed
section for 0014's replace and rollback logic.

It assumes the first `## ` belongs to project content. In a `CLAUDE.md` that
leads with the GitNexus block that heading is `## Always Do`, inside
`<!-- gitnexus:start -->…<!-- gitnexus:end -->`. The block is injected into the
region and the next `gitnexus analyze` — which regenerates everything between
the markers — destroys it silently. Recovery is closed: 0014's `to_version` is
`1.14.0`, so `update/SKILL.md`'s pending predicate (`installed >= from_version
&& installed < to_version`) makes it permanently not-pending for any 2.x repo,
and its pre-flight (`grep -qE '^version: 1\.(12\.0|14\.0)$'`) refuses the
`--migration 0014` force path on anything else.

A separate instance of the same confusion: `agenticapps-dashboard` was
snapshot-installed at 2.3.0, before the setup flow gained its §11 step (#84,
2.5.0), while 0014 was already past — so it carries no §11 block at all while
stamping `implements_spec: 0.9.0`.

## Decision

Anchor the block before the first line that is **either** a `## ` heading
**or** a line that is *exactly* `<!-- gitnexus:start -->` — whichever comes
first; EOF if neither. Ship it as migration 0029 (`from_version: 2.6.0`,
`to_version: 2.7.0`), which reaches installed repos and repairs the dashboard.
0014 stays immutable.

Both marker regexes are anchored (`^<!-- gitnexus:start -->$`,
`^<!-- gitnexus:end -->$`), not substring-matched. An unanchored
`/<!-- gitnexus:start -->/` also fires on prose that merely *mentions* the
marker — this repo's own `CLAUDE.md` line 2 does exactly that, inside the
guard comment that opens the §11 block itself. An unanchored regex would have
selected that line as the insertion point and injected the block *inside the
HTML comment*, silently commenting the whole thing out on the very file this
repo's own #88 fix repaired. Verified empirically against the file, not
reasoned about in the abstract.

The rule was originally scoped as "a one-alternation delta, so 0014's
structural invariant survives: the block is always followed by a `## ` line."
That claim is false. Once the anchor can be a marker line, a healed
region-led file has the block followed by `<!-- gitnexus:start -->`, not a
`## ` line. Every consumer that bounds the managed section — the strip pass
in Step 1's Apply and Step 1's Rollback — therefore had to carry the same
alternation as the anchor itself, or it would over-consume: running the
old, `## `-only Rollback logic against a healed region-led file eats the
start marker and the region's real content, leaving an orphaned
`<!-- gitnexus:end -->` with no matching start. The anchor rule and the
terminator rule are one decision, not two, and ship together. The invariant
that actually holds after 0029: the block is always followed by a `## ` line,
an anchored `<!-- gitnexus:start -->` marker, or EOF.

Pre-flight guards the canonical block with `test -s` (rejects a zero-byte
mirror — e.g. an interrupted `git pull` in the scaffolder clone) plus a tail
sentinel (`grep -q '^### 4\. Goal-Driven Execution$'`). `test -f` alone is not
enough: it passes on a zero-byte file, the insert pass's `while ((getline ...
< block_file))` loop then reads nothing and still exits 0 with non-empty
output (the rest of the file plus an orphaned provenance line), and `mv`
commits that data loss while the migration reports success. Idempotency is
provenance-based, so after that false "success" the run is recorded as
already applied and never retries — the loss is silent and permanent absent
this guard.

Mirror the identical rule into `setup/SKILL.md` step e2, locked by a new
`anchor-parity` guard in `migrations/run-tests.sh` (spec §08: setup end-state
≡ full replay), modelled on #87's predicate-parity guard for 0028's
`.prettierignore` check.

Ten fixtures cover it (`migrations/test-fixtures/0029/01`–`10`): the anchor
rule on a region-led file, moving a block already inside a region, a
byte-identical no-op on a healthy file, a missing-`CLAUDE.md` skip, the
hand-pasted-heading refusal, an EOF fallback with no heading and no region, a
prose-mention-of-the-marker case that must NOT be treated as a region,
Rollback on a healed region-led file, a two-provenance file healing to one,
and a corrupt/truncated spec-mirror refusal. The last four (07–10) were each
added after a review caught a bug that a then-green suite did not bind — they
are coverage gaps the suite closed, not padding.

## Alternatives Rejected

- **Anchor before `gitnexus:start` whenever a region exists.** The obvious
  reading of "put it above the region", and wrong. cparx's region starts at
  L306, so §11 would land ~300 lines down the file, violating §12's placement
  advisory. The region is only the anchor when it comes *first*.
- **Always anchor immediately after the H1.** Moves the block in all five
  healthy repos for no benefit, and breaks 0014's followed-by-`## `
  invariant in the same way the naive marker anchor does.
- **Edit 0014 in place.** It is immutable, already applied in five repos, and
  permanently not-pending under `update/SKILL.md`'s pending predicate —
  editing it would change nothing anywhere it has already run.
- **Vendor the anchor as a shared script both paths call.** Eliminates drift
  structurally rather than detecting it, but adds a payload file to every
  scaffolded project and pulls in 0014's `requires:`/install machinery. Larger
  blast radius than the defect warrants; the `anchor-parity` guard is the
  cheaper control.

## Consequences

- Validated against all six real repo shapes: the rule re-derives the block's
  current *position* exactly in the five healthy repos, and on the dashboard
  selects L5, above the region at L82, restoring a block the repo never had.
  The dashboard exercises the missing-block defect, not the region-led
  placement defect — its first `## ` already sits above its region, so
  0014's naive anchor would have placed the block identically; the
  region-led anchor has no live instance and is bound by fixtures 01/02. The
  actual zero-churn guarantee for the five healthy repos is the idempotency
  check short-circuiting Apply entirely (all five already read
  "already applied"), not byte-identical round-tripping through strip +
  re-insert — three of the five have lost the blank line after each
  `Anti-patterns this rule prevents:` heading to prettier normalization, so a
  strip+re-insert round-trip on them is not byte-identical.
- Five repos (agenticapps-roadmap, fbc-platform, cparx, fx-signal-agent,
  callbot) take a version stamp only. `agenticapps-dashboard` gains its
  missing block and becomes conformant with the spec 0.9.0 it already claims;
  it sits at 2.5.0, so `/update` chains 0028 (2.5.0 → 2.6.0) then 0029
  (2.6.0 → 2.7.0).
- `codex-workflow` and `opencode-workflow` carry the same naive anchor in
  their own §11 injectors and inherit the defect wherever their `AGENTS.md`
  is region-led. Both are currently latent (§11 sits above the region in
  each). Propagation follows ADR-0037 and is tracked separately — not fixed
  by this migration.
