# Migration 0029 — region-aware §11 placement

**Date:** 2026-07-15
**Status:** Approved (brainstorming → design approved 2026-07-15)
**Scope:** `migrations/0029-*`, `setup/SKILL.md` step e2, `migrations/run-tests.sh`, CHANGELOG, ADR-0041

## Problem

Two defects, one root cause: the §11 injection machinery treats "the first `## `
heading in `CLAUDE.md`" as a safe boundary for project content. It is not, when a
GitNexus-managed region leads the file.

### Defect 1 — 0014 can inject §11 inside a GitNexus-managed region (latent)

Migration 0014 inserts the canonical §11 block immediately before the first `## `
heading (`migrations/0014-inject-spec-11-coding-discipline.md:186-206`). That
placement was deliberate: it guarantees the block is followed by a `## ` line,
which is what 0014's replace and rollback logic depends on to bound the managed
section.

In a `CLAUDE.md` that leads with the GitNexus block, the first `## ` is
`## Always Do` — inside `<!-- gitnexus:start -->…<!-- gitnexus:end -->`. The
block is injected into the region, and the next `gitnexus analyze` — which
regenerates everything between the markers — destroys it silently.

Reproduced end-to-end: the block landed at lines 10–95 of a region spanning
5–96, and a modelled region regeneration removed it with no diagnostic.

The recovery path is closed. After the loss, 0014's own idempotency check
correctly reports "needs apply", but nothing re-runs it:

- `update/SKILL.md:77-79` marks a migration pending iff
  `installed >= from_version && installed < to_version`. 0014's `to_version` is
  `1.14.0`, so for any repo at 2.x it is permanently not-pending.
- The `--migration 0014` escape hatch also fails: 0014's pre-flight demands
  `^version: 1\.(12\.0|14\.0)$` and aborts on anything else.

Both verified by executing the actual predicates against a synthetic 2.5.0
`SKILL.md`. Once lost, the block is unrecoverable without a hand-paste or a new
migration.

### Defect 2 — agenticapps-dashboard has no §11 block at all (live)

`agenticapps-dashboard` is stamped `version: 2.5.0` / `implements_spec: 0.9.0`
and contains zero §11 content. `git log -S'Coding Discipline (NON-NEGOTIABLE)'`
confirms the block was never present in any commit of its `CLAUDE.md` — this is
not defect 1 eating it, it is a distinct gap:

- The repo was snapshot-installed at 2.3.0 on 2026-07-06 (commit `430a669`,
  which appended only 7 lines at EOF).
- `setup/SKILL.md` step e2 — the setup path's §11 injection — did not exist
  then. It landed in #84 at 2.5.0 on 2026-07-15.
- The 2.3.0 → 2.5.0 update replayed only 0026/0027. 0014 was long past and never
  ran.

The repo fell through the gap between the two install paths and now claims spec
0.9.0 conformance it does not have — the same false-conformance class #88 fixed
in this host's own `CLAUDE.md`, one layer down.

### Fleet scan (2026-07-15)

| Repo | §11 | State |
|---|---|---|
| agenticapps-roadmap | present, L6 | healthy — no region |
| fbc-platform | present, L2 | healthy — no region |
| cparx | present, L8 (region L306) | healthy — above region |
| fx-signal-agent | present, L3 (region L246) | healthy — above region |
| callbot | present, L8 (region L443) | healthy — above region |
| **agenticapps-dashboard** | **absent** (region L82) | **broken** |

Defect 1 is currently latent: 0/6 repos are hit, because each healthy repo had
project `## ` headings above its region. Defect 2 is live in exactly one repo.

## Design

### The anchor rule

> Insert immediately before the first line that is **either** a `## ` heading
> **or** a line that is *exactly* `<!-- gitnexus:start -->` — whichever comes
> first. If neither exists, append at EOF.

**Both marker regexes MUST be anchored** (`/^<!-- gitnexus:start -->$/`,
`/^<!-- gitnexus:end -->$/`). This is not stylistic. An unanchored
`/<!-- gitnexus:start -->/` is a substring match that also fires on *prose
mentions* of the marker. This repo's own `CLAUDE.md:2` contains exactly such a
mention, inside the `<!--` guard comment that opens on line 1:

```
  This block MUST stay ABOVE the `<!-- gitnexus:start -->` region below.
```

With an unanchored regex the anchor selects line 2 and injects the §11 block
*inside that HTML comment* — silently commenting the whole block out. The
migration would recreate the exact defect it exists to fix, on the very file #88
repaired. Verified empirically, not reasoned about.

### The invariant this breaks (corrected 2026-07-15 after Task 2 review)

An earlier draft of this spec claimed the rule was "a one-alternation delta, so
0014's structural reasoning survives: the block is still always followed by a
`## ` line or EOF." **That claim was false**, and it was load-bearing.

Once the anchor can be a marker line, a healed region-led file has the block
followed by `<!-- gitnexus:start -->` — not a `## `. Every consumer that bounds
the managed section by "terminate at the next `^## `" therefore breaks on
exactly the files this migration targets. Running Step 1's Rollback on a healed
region-led file eats the start marker and the region's real content, leaving an
orphaned `<!-- gitnexus:end -->` — an unpaired region. Verified empirically.

The invariant is not preserved; it is **replaced**:

> The block is always followed by a `## ` line, an anchored
> `<!-- gitnexus:start -->` marker, or EOF.

Every terminator must carry the same alternation as the anchor — in the strip
pass, and in Rollback. The anchor rule and the terminator rule are one decision,
not two, and they must move together.

**Validated against all six real repo shapes.** With any existing block stripped,
the rule re-derives the block's current position exactly in all five healthy
repos (roadmap L6, fbc-platform L2, cparx L8, fx-signal L3, callbot L8) — a true
no-op, zero churn. For the dashboard it selects L5, above the region at L82. On
the gitnexus-led shape it anchors above the region rather than inside it. On a
file with no `## ` and no region it falls to EOF. On a region-led file with no
`## ` outside the region it anchors above the region.

#### Alternatives rejected

- **"Before `gitnexus:start` if a region exists, else the first `## `."** The
  obvious reading of "put it above the region", and wrong. Tested: cparx's region
  starts at L306, so §11 would land ~300 lines down the file, violating §12's
  placement advisory ("near the top", "not appended below long appendices"). The
  region is only the anchor when it comes *first* — which is what the recommended
  rule's `whichever comes first` encodes.
- **"Always immediately after the H1."** Simpler to state, but moves the block in
  all five healthy repos for no benefit, and breaks 0014's followed-by-`## `
  invariant.

### States healed

| State | Condition | Behaviour |
|---|---|---|
| A | §11 present, correctly anchored | no-op |
| B | §11 present, inside a region | move above the region |
| C | §11 absent | inject at the anchor |
| D | `## Coding Discipline (NON-NEGOTIABLE)` heading with no provenance comment | refuse, `exit 3` |

State D inherits 0014's conflict rule verbatim: a heading without provenance means
the block was hand-pasted outside the migration's management, and is refused
rather than silently overwritten.

State B is handled rather than deferred because it is reachable *going forward*:
`setup/SKILL.md` step e2 carries the same naive anchor, so a project scaffolded
today into a gitnexus-led `CLAUDE.md` lands in state B immediately. Shipping a
placement fix that knows about state B and declines to repair it would leave the
tracked defect open.

Explicitly **not** handled: a healthy block that sits somewhere other than the
canonical anchor. No failure mode motivates moving it, and doing so would churn
project files gratuitously (Surgical Changes).

Idempotency is provenance-based, as in 0014, with an added region predicate: skip
iff the current-version provenance is present **and** the block is not inside a
region. That keeps state A a no-op while letting state B re-run.

### Parity with the setup path

The anchor rule will exist in two places — 0029 Step 1 and `setup/SKILL.md` step
e2 — and spec §08 requires the setup flow's end state to equal a full replay. The
existing `predicate-parity` guard covers only 0028's `.prettierignore`
one-liner; it cannot see an awk program drift.

**Decision: duplicate + a new parity guard**, modelled on #87's — extract the
anchor awk from both files, require exactly one distinct value, fail loudly
otherwise.

Rejected: vendoring the anchor logic as a shared script both paths invoke. It
eliminates drift structurally rather than detecting it, which is genuinely
stronger, but it adds a new payload file to every scaffolded project and pulls in
0014's `requires:`/install machinery. That is a larger blast radius than this
defect warrants.

This risk is not hypothetical. #87 shipped a predicate fix to 0028's document
while `setup/SKILL.md` kept the old one — a §08 violation that made the
migration's own prose false, and which no fixture caught because the fixtures
only ever executed the apply block. The guard exists because that already
happened once.

### Mechanics

- `from_version: 2.6.0`, `to_version: 2.7.0`; pre-flight gate
  `^version: 2\.(6\.0|7\.0)$`, matching 0028's shape.
- The dashboard is at 2.5.0, so `/update` chains: 0028 (2.5.0 → 2.6.0), then 0029
  (2.6.0 → 2.7.0). Both are pending under `installed >= from && installed < to`.
- Step 1 heals placement; Step 2 bumps the installed scaffolder version.
- The canonical block is read from
  `$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md`,
  as 0014 does. The mirror stays at `@0.4.0` — that is the block's content
  version, unchanged since; it is not the spec version (0.9.1).
- 0014 is **not** edited. It is immutable and already applied in five repos; this
  fixes forward.

### Testing

Fixtures follow 0028's `common-verify.sh` pattern: the migration's own shell is
extracted from the document rather than copied, so a fixture tests the migration
and not a stale duplicate, with a shape assertion that fails loudly if the
extractor locks onto the wrong fence.

| Fixture | Asserts |
|---|---|
| `01-gitnexus-led-inject` | state C on a region-led file → block above the region; survives a modelled region regeneration |
| `02-inside-region-move` | state B → block moved above the region, present exactly once |
| `03-healthy-noop` | state A → `CLAUDE.md` byte-identical (Step 2 still bumps `SKILL.md`); proves zero churn |
| `04-no-claudemd` | absent `CLAUDE.md` → informational skip, Step 2 still runs |
| `05-unmanaged-conflict` | state D → `exit 3`, file untouched |
| `06-no-heading-eof` | no `## `, no region → EOF append |
| `07-prose-mention-not-a-region` | a *prose mention* of `<!-- gitnexus:start -->` (this repo's own `CLAUDE.md:2` shape) is NOT treated as a region — idempotency holds, nothing is injected into the comment |
| `08-rollback-region-led` | Rollback on a healed region-led file removes the block and leaves the region intact and paired |

Fixtures 07 and 08 were added after the Task 2 review. They are the two gaps
that let a green suite ship file-destroying bugs: **no fixture covered Rollback
at all**, and none covered a file mentioning the marker in prose. A suite that
binds only the anchor rule proves only the anchor rule.

Plus: an `anchor-parity` guard (migration ≡ setup e2), and the existing
`spec-11-self-conformance` and `check-snapshot-parity.sh` must stay green.

Verification evidence: `test(RED)` commit with fixtures failing against the naive
anchor, then `feat(GREEN)`; `run-tests.sh` PASS ≥ 176 (current baseline on merged
main); `check-snapshot-parity.sh` green; an end-to-end repro proving a repo with
the dashboard's exact shape is repaired.

## Consequences

- The CHANGELOG "Known issues" entry for 0014 is retired.
- ADR-0041 records the anchor-rule decision and the rejected alternatives.
- `codex-workflow` and `opencode-workflow` carry §11 in `AGENTS.md` and ship the
  same GitNexus region family; they inherit this defect wherever their
  instruction file is region-led. Propagation follows the ADR-0037 pattern and is
  tracked separately, not in this migration.
- Five healthy repos take a version-stamp bump and no content change. The
  dashboard gains its missing block and becomes conformant with the 0.9.0 it
  already claims.
