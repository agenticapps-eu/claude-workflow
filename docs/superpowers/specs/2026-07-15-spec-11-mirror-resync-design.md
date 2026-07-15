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

Not prettier. The chain, each link verified against git history:

1. `913360e` (spec 0.4.0 absorption, v1.14.0) shipped
   `templates/spec-mirrors/11-coding-discipline-0.4.0.md` as a **faulty
   transcription** of the core spec, dropping four blank lines.
2. cparx (#52) and fx-signal-agent (#53) ran migration 0014 against that
   mirror. Their blocks are a **byte-exact copy of the then-canonical
   mirror** — both repos were conformant on the day they migrated.
3. `34ee72e` (#44, 2026-05-25, *"prettier-clean the vendored §11 block"*)
   added the four blank lines. Despite the commit message, its effect was
   to **restore spec fidelity**: the post-`34ee72e` mirror matches
   `spec/11-coding-discipline.md` byte for byte.
4. That fix shipped **no re-sync migration**, so repos that had already
   consumed the faulty bytes were frozen on them.

The current mirror is correct and the two repos are wrong. This is
canonical-text drift, not damage — nothing will re-corrupt a repaired
block.

### Why the spec version is not bumped

`spec/11-coding-discipline.md` carries `spec_version: 0.4.0`. The §11 text
never changed; only claude-workflow's transcription of it was wrong. The
mirror's *filename* was always correct. 0014's design note prescribes a new
versioned mirror (`...-0.5.0.md`) for a genuine spec revision — that
convention does not apply here, and inventing a `0.4.1` would stamp a
version that does not exist upstream.

### Why 0029 cannot heal this

The provenance line reads
`<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->` — the **correct
version stamp over wrong bytes**. Provenance records the spec version, not
the block's content, so a version-based idempotency check reports "already
applied" and short-circuits before Apply. Provenance cannot distinguish good
0.4.0 bytes from bad 0.4.0 bytes. This is the design flaw 0030 routes
around.

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

Restore from a `.0030.bak` backup, matching 0014/0029's idiom.

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
7. **rollback restores** the pre-Apply bytes
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
