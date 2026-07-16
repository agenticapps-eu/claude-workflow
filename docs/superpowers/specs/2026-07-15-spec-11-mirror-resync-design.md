# Migration 0030 — re-sync stale spec §11 block bytes (2.7.0 → 2.8.0)

**Status:** design approved 2026-07-15
**Supersedes nothing. Does not edit 0014 or 0029 — both immutable.**

## The defect

Two consumer repos stamp `implements_spec: 0.9.0` while carrying §11 prose
that does not match the canonical block. Verified by byte comparison against
`agenticapps-workflow-core/spec/11-coding-discipline.md`:

| Repo | §11 block | Stamp | Introduced by |
|---|---|---|---|
| `factiv/cparx` | **stale** | 0.9.0 | `e6e44e7b` (#52, migration 0014) |
| `factiv/fx-signal-agent` | **stale** | 0.9.0 | `d38a97c` (#53, migration 0014) |
| `factiv/callbot` | verbatim | 0.9.0 | — |
| `factiv/fbc-platform` | verbatim | 0.9.0 | — |
| `agenticapps/agenticapps-roadmap` | verbatim | 0.9.0 | — |

Both stale blocks are missing the same four blank lines — one after each
`Anti-patterns this rule prevents:` — and the corruption is committed in
`HEAD` in both repos, not a working-tree artifact.

## Root cause

> **CORRECTED 2026-07-15 (Task 5 review).** This section originally blamed a
> "faulty transcription" in `913360e`. That was **false**, and it was the third
> wrong root cause on this branch. `913360e`'s mirror is byte-identical to the
> upstream spec at the moment it shipped — verified. The corrected account below
> is proven line by line from both repos' histories.

Nobody mis-transcribed anything. The mirror was a correct copy of the spec at
every instant. The defect is that §11's canonical prose was revised **upstream,
in place, under an unchanged `spec_version`**, and this repo mirrored that
revision without shipping a migration to carry already-migrated projects forward.

| Date | Commit | Effect |
|---|---|---|
| 2026-05-20 | core `5ea7ea9` | introduces spec §11 **without** the blank lines (v0.4.0) |
| 2026-05-21 | `913360e` (#42) | mirrors it **faithfully** — byte-identical to core — and ships migration 0014 |
| 2026-05-21 | `e6e44e7b`, `d38a97c` | cparx and fx-signal-agent run 0014, faithfully receiving §11 **as it then was** |
| 2026-05-25 | core `10f2c96` (#12) | **adds** the four blank lines — and does **not** bump `spec_version` |
| 2026-05-25 20:31 | callbot `4fa4dac` | runs 0014 against the **still-stale** mirror — gets the same old bytes |
| 2026-05-25 20:35 | callbot `1149187` | callbot's **own** prettier `format:check` pass reformats the block, landing on the bytes core would ship |
| 2026-05-25 20:51 | `34ee72e` (#44) | mirrors core's edit with **no migration** → already-migrated projects stranded |
| 2026-05-26 | callbot `d2e92db` | PR #31 squash-merges the two callbot commits above |

So cparx and fx-signal-agent are not corrupted: they hold a faithful copy of §11
as it read on 2026-05-21, and the spec moved underneath them. Nothing will
re-corrupt a repaired block.

**Corrected again (Task 6 review):** callbot is unaffected **not** because it
ran 0014 after the fix. It ran 0014 twenty minutes *before* the fix and got the
identical stale block; it self-healed when its own prettier pass ran four
minutes later. `d2e92db` is a squash commit whose single 05-26 date hides both
originals — which is what made the wrong story look verifiable.

**The mechanism, finally complete.** Prettier's "blank lines around lists" rule
added the four lines at **every site it ran**: core's spec (`10f2c96`,
"markdown/prettier-clean"), callbot's `CLAUDE.md` (`1149187`), and this repo's
mirror (`34ee72e`, "prettier-clean the vendored §11 block"). It never stripped
anything from anyone. cparx and fx-signal-agent are stale for exactly one
reason: **nothing runs prettier over their `CLAUDE.md`** — cparx has no prettier
config at all. The handoff's original "prettier" instinct named the right actor
and the wrong direction, which is why it kept half-fitting the evidence.

### Why the spec version is not bumped

`spec/11-coding-discipline.md` is `spec_version: 0.4.0` **both before and after**
`10f2c96` — upstream changed canonical prose without bumping it. The mirror's
filename was correct throughout, and inventing a `0.4.1` would stamp a version
that does not exist upstream.

This same fact disabled 0014's escape hatch: its design note prescribes vendoring
a new `...-0.5.0.md` plus a migration for a spec revision. That convention could
never fire, because core never shipped 0.5.0 — it revised 0.4.0 in place.

### Why 0029 cannot heal this — and why the fix must be byte-derived

The provenance line reads
`<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->`. Because `10f2c96`
changed §11's text without bumping `spec_version`, that stamp is **still
genuinely correct** while the bytes no longer match. A version-keyed idempotency
check is therefore not merely unlucky here — it **cannot distinguish the two
states even in principle**, so it reports "already applied" and short-circuits
before Apply. Byte-derived idempotency is the only thing that can see the
difference. Right fix; the reason is what changed.

## Design

### Detection: byte-compare, not provenance-compare

Idempotency is derived from the **block's bytes**, never from the provenance
version. This is the load-bearing decision: version-derived idempotency is
exactly what failed, and repeating it would reproduce the bug.

### Pre-flight (refuse loudly, change nothing)

1. Vendored mirror exists at
   `$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md`
2. `CLAUDE.md` exists
3. Exactly one anchored provenance line **and** exactly one
   `## Coding Discipline (NON-NEGOTIABLE)` heading.
   - Zero → 0014 never ran here; that is 0029's job. Refuse.
   - Two or more → ambiguous. Refuse rather than guess which is canonical.

### Apply

1. Anchor on the provenance line using an **anchored** `PROV_RE`
   (`^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$`).
   0029's final review established that an unanchored `PROV_RE` enters
   block state on prose that merely mentions the marker.
2. The block starts at the `## Coding Discipline (NON-NEGOTIABLE)` heading
   immediately below the provenance line.
3. The block ends before the first subsequent line matching `^## ` **or**
   `^<!-- gitnexus:start -->`, whichever comes first; EOF if neither.
4. Extract the block's bytes; compare against the mirror.
5. **Equal → exit 0, no write.** File is byte-identical on the way out.
6. **Differ → replace the block's bytes with the mirror's**, leaving every
   byte outside the boundary untouched.

#### Why the terminator admits `gitnexus:start`

0014's note asserts the block "ends at the next `## ` (level-2) heading",
resting on the invariant that a `## ` always follows. **0029 deliberately
broke that invariant** — it anchors §11 above a `<!-- gitnexus:start -->`
region, so a §11 block may now be terminated by the region marker with no
`## ` between. A terminator that recognised only `^## ` would, on such a
file, run the replacement past the marker and destroy the region. The
terminator rule is the symmetric twin of 0029's anchor rule and must stay
that way; they are one decision, not two.

In both real targets the block is in fact followed by a `## ` heading
(`## Project Overview`, `## Project`) and both files are clean LF. The
`gitnexus:start` terminator is therefore **not** exercised by the two repos
this migration fixes — it is bound by fixture alone, which is precisely why
that fixture is mandatory.

### Rollback

> **WITHDRAWN AND REPLACED (user decision, Task 2 review).** This section
> originally specified "restore from a `.0030.bak` backup, matching 0014/0029's
> idiom". That was wrong twice over: 0029 uses **no `.bak` at all**, and Apply
> deleted its own backup, so Rollback would have been inert on the normal path
> while fixture 08 passed vacuously.

Apply uses 0029's actual idiom: write `CLAUDE.md.0030.tmp`, require it non-empty
before it may replace `CLAUDE.md`, atomic `mv`, clean up the tmp on every path
including a failed `mv`.

Rollback is an honest **reporting no-op**. Step 1 has no forward inverse: it
replaces non-canonical bytes with the canonical ones, the pre-migration bytes are
not recoverable from the post-migration file, and restoring them would
re-introduce the defect 0030 exists to fix. This is safe because Step 1 is
byte-idempotent — if Step 2 fails, the project holds a canonical block and a
2.7.0 stamp, 0030 stays pending, and a re-run is a Step 1 no-op plus a Step 2
retry. `migrations/README.md` sanctions exactly this ("partial-state recovery may
be more useful than full revert"; rollback may be "manual").

### Version bump

2.7.0 → 2.8.0 in `skill/SKILL.md`, `setup/snapshot/VERSION`, and
`setup/snapshot/agentic-apps-workflow-SKILL.md`.

## The guard: bind the mirror to the core spec

Nothing currently binds claude-workflow's mirror to the spec it transcribes.
`test_claude_md_reproduces_spec_11_verbatim` binds this repo's CLAUDE.md *to
the mirror*; the mirror itself is unbound. That is the hole `913360e` walked
through.

- `run-tests.sh` gains `test_mirror_matches_core_spec_11`, diffing
  `templates/spec-mirrors/11-coding-discipline-0.4.0.md` against the
  canonical block in `spec/11-coding-discipline.md`.
- `ci.yml` gains a second `actions/checkout@v4` of
  `agenticapps-eu/agenticapps-workflow-core` (public — no token needed) at
  `ref: main`, into a path the test reads.

### Locating the core spec: `CORE_SPEC_DIR`

`actions/checkout` requires `path:` to sit inside `$GITHUB_WORKSPACE`, so the
second checkout lands at `.core-spec/` **inside the repo working tree**. Two
consequences the implementation must handle:

- `.core-spec/` is added to `.gitignore`. The existing `ci.yml` steps
  (`check-snapshot-parity.sh`, `build-snapshot.sh --check`) run in the same
  workspace, and an untracked sibling checkout must not read as drift to
  either. Whether they actually scan it is an **assumption to verify during
  implementation, not to assert here** — if either walks the tree, it needs
  an explicit exclusion.
- The test resolves the spec via `CORE_SPEC_DIR`, defaulting to the sibling
  clone (`../agenticapps-workflow-core`) so local runs work unchanged. CI
  sets it to `.core-spec`.

### The skip must never be silent in CI

A developer without workflow-core cloned should not have `run-tests.sh` fail;
CI must never pass by skipping. So absence is resolved by a required flag,
not by inference:

- `CORE_SPEC_REQUIRED=1` (set in `ci.yml`) → a missing core spec is a **hard
  failure**.
- Unset (local default) → the test reports a loud `SKIP`.

This keeps the local path ergonomic while making the CI path unskippable.
Inferring "am I in CI?" from a heuristic is the same class of guess that
`drift-report.sh` warns about; the flag is declared, so the failure mode
stays loud. Fixture 10 binds it: with `CORE_SPEC_REQUIRED=1` and no core
spec present, the suite must go red.

### Why `main` and not a pinned SHA

Pinning freezes the guard against a snapshot: when the spec moves, CI stays
green and the hole relocates to "who remembers to bump the pin" — the same
silent desync, one layer up. Tracking `main` means a spec change turns CI red
immediately, which is the notification that was missing in May. The cost is a
non-hermetic CI: a commit that touches nothing here can go red. That red **is
the signal**, and a loud failure mode is this family's stated preference
(`drift-report.sh`: *"declaring the paths keeps the check honest and its
failure mode loud"*).

### What this guard is not

It does not check consumer repos. `drift-report.sh` in workflow-core checks
**hosts** (`claude-workflow`, `codex-workflow`, `opencode-workflow`) and its
header reasons explicitly that consumers author no canonical prose and are
out of scope. cparx and fx-signal-agent are consumers. Nothing in this design
changes that boundary, and the mirror under `templates/` must never be
declared an instruction file — that revision has been tried and produced
*"the same false PASS this tool shipped with, in better clothes."*

## Fixtures

Boundary logic is the risk center. Every fixture below exists because a green
suite could otherwise ship a bug it does not bind.

1. **stale block heals** — the exact committed cparx bytes → mirror bytes
2. **in-sync block is a no-op** — file byte-identical out, exit 0
3. **`gitnexus:start` terminator** — block heals, region intact
4. **EOF-terminated block** — no `## ` and no region follows
5. **missing provenance → refuse**, file untouched
6. **two provenance lines → refuse**, file untouched
7. **rollback is a no-op** — returns 0, leaves the file byte-identical to its
   post-apply (healed) state, and does **not** terminate the calling fixture.
   (Originally "rollback restores the pre-Apply bytes"; withdrawn with the
   `.bak` idiom — see the Rollback section above.)
8. **mutation test** — perturb the mirror; `test_mirror_matches_core_spec_11`
   must go red. A guard without a mutation proof is decoration: 0029's
   anchor-parity guard could never fire and was caught only because a
   mutation test was mandatory.
9. **E2E** against cparx's and fx-signal-agent's real committed `CLAUDE.md`
10. **`CORE_SPEC_REQUIRED=1` + absent core spec → suite red**, binding the
    guard's unskippability in CI

## Known limitations (recorded, not fixed)

- **CRLF** — shared with 0014 and 0029. Latent; both real targets are LF.
- **A marker at column 0 inside a code fence** — shared with 0014/0029.
- Neither is introduced by this migration; both are pre-existing and remain
  out of scope.

## Downstream application

After merge: apply to `factiv/cparx` and `factiv/fx-signal-agent` via
`/update-agenticapps-workflow`, each on a branch cut from **`origin/main`**,
not the repos' current WIP branches (cparx is on `chore/workflow-2.5.0`; both
have ~10 unrelated dirty files). Each PR touches `CLAUDE.md` and the workflow
version stamp only.
