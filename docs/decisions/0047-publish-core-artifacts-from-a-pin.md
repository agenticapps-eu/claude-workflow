# ADR-0047: Publish core's artifacts from a pin, not from vendored copies

**Status**: Accepted  **Date**: 2026-07-31  **Linear**: —
**Implements**: core task 8.4 (`track-and-conform-plan-review`)

## Context

`install.sh` publishes three artifacts into `~/.agenticapps/bin/`, a directory
shared by every agent on the machine: the §18 change-gate, the plan-review
producer, and the producer's vendor wrapper. All three are owned by
`agenticapps-workflow-core`. This repo carried byte-copies of them in `bin/`.

The runtime never read those copies. The project-level hook resolves
`~/.agenticapps/bin` first and only falls back to a repo-local path, so the
copies existed for one reason: to give `install.sh` something to publish.

They drifted, which is what copies do. On 2026-07-31 all three were stale
simultaneously — gate 1.3.1 against core's 2.0.0, producer 1.0.0 against 1.2.0,
wrapper 1.1.0 against 1.2.0 — and the migration suite had been red for exactly
that, in four rows that could only ever *report* the drift.

The cost of the copies was also a re-vendor PR in four host repos per core
release. On 2026-07-28 the gate shipped 1.2.2 → 1.3.0 → 1.3.1 → 1.4.0 in one
day: twelve mechanical PRs, each a diff nobody reads.

`resolve-core-artifact.sh` and `core-vendor.manifest` were written on 2026-07-28
to replace this. Neither was ever committed or wired to anything.

## Decision

**`install.sh` and migration 0032 resolve what they publish.** The manifest
records one core commit and a sha256 per file; the resolver produces verified
bytes from a local checkout at that commit or from GitHub, and refuses anything
that does not hash to the pin. The three vendored copies are deleted.

**It fails closed.** An installer that cannot verify what it is about to write
into a shared directory stops and says so. It does not fall back to a copy on
disk — that fallback, run today, would have republished gate 1.3.1 over 2.0.0
and reverted the fix for every agent on this machine.

**Two categories of core-derived file, treated differently:**

| | Files | On disk? | Checked how |
|---|---|---|---|
| RESOLVED | gate, producer, wrapper | no | resolved + hash-verified at the pin |
| VENDORED | resolver, shared-installer, 2 conformance harnesses | yes | bytes compared to the pin |

The resolver is the bootstrap and cannot resolve itself; the harnesses are
executed from the repo by CI. Both are pinned regardless, so the manifest's
claim that it lists *every* file this repo takes from core is true rather than
convenient.

**The drift check now asks a fixed question.** It compares against the pinned
commit, not `$CORE_SPEC_DIR`. CI checks core out at `ref: main`, so the old
comparison asked "does this match whatever main says today" — a question whose
answer changes without either repo changing.

## Alternatives Rejected

**Re-vendor fresh bytes.** Copy core's current artifacts in, update the
manifest's provenance record, leave `install.sh` alone. Cheapest, offline-safe,
and matches what `codex-workflow` does today. Rejected because it fixes the
bytes and keeps the mechanism that made them wrong: core stays a thing this
repo mirrors and forgets, and the next release needs the same PR again. Task
8.4's stated purpose — core as the *operational* source of truth — is not met
by a mirror.

**Resolve with a fallback to the vendored copy.** Keeps `install.sh` working
offline with no core checkout. Rejected: the fallback is silent staleness
wearing a warning label. Run today it publishes 1.3.1. It also preserves two
sources of truth, which is the condition being removed.

**Leave migration 0032 alone and add a new migration.** Strictly honors
migration immutability. Rejected because 0032 installs from files that no longer
exist, so a project below 3.0.0 fails mid-migration on a missing file. The edit
only reaches projects that have not applied it; for those, the alternative is a
hard failure. Projects that already applied it are unaffected either way.

## Consequences

- A core release reaches this host by advancing `core_commit` and seven
  sha256s — one file, one commit, no re-vendor PR.
- `install.sh` now requires a core checkout beside this repo, `CORE_CHECKOUT`,
  or network access. This is a real new dependency, accepted deliberately:
  publishing unverified bytes into a shared directory is worse than not
  publishing.
- Resolving from the pin immediately surfaced three incompatibilities the stale
  vendored copy had been hiding from the producer test — stdin vs argv prompt
  delivery, `AGENT_SELF=none` rejected by 1.2.0, and reviews without a verdict
  line not counted. The test had been passing against a copy nothing shipped.
- Suite went 218 pass / 4 fail → 226 pass / 0 fail.

## Known limits

- **The pin names a non-main commit.** `2b82a91` is the tip of core's
  `feat/step3-hook-shims-and-dead-gate-removal` (core PR #47). GitHub serves raw
  content by sha for any pushed commit, so it resolves everywhere today. **If
  #47 is squash-merged that sha is orphaned and will eventually be unreachable.**
  Re-pin to the resulting main commit once #47 lands. This is loud, not silent:
  an unresolvable pin is a failing test row and a refusing installer.
- **Migration 0032 installs the producer without version arbitration.** It is a
  pre-existing hazard, untouched here to keep the edit to a shipped migration as
  small as possible. The gate and wrapper are arbitrated; the producer is not.
- **The other three hosts still vendor.** `codex-workflow` keeps its copies and
  a provenance-style manifest; `pi-agentic-apps-workflow` has no manifest at
  all. This ADR covers claude-workflow only.
