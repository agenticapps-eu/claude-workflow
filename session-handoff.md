# Session Handoff — 2026-07-16 (0030 merged; downstream PRs open — cparx #87, fx-signal-agent #111)

## Status: claude-workflow 2.8.0 SHIPPED. Downstream PRs OPEN (cparx #87 green, fx-signal #111).
- PR #89 (migration 0029) merged as `f9354cc`.
- PR #90 — not ours.
- PR #91 (migration 0030) merged as `bf90f89`. All 6 codex HIGHs + its 3 LOWs fixed first.
Local scaffolder clone (`~/.claude/skills/agenticapps-workflow`) is synced to 2.8.0 and
carries 0028/0029/0030 + the 79-line mirror, so downstream application is unblocked.
Full SDD ledger — every decision, every correction, every mutation matrix:
`.superpowers/sdd/progress.md` (gitignored, local). **Read it before doing 0030 work.**

## Accomplished
- **Migration 0030** (2.7.0 → 2.8.0) — repairs a §11 block that drifted from the canonical
  mirror. 15 fixtures, all mutation-proven. ADR-0042. CI guard binding the mirror to
  upstream. Heals cparx + fx-signal-agent E2E: exactly 4 insertions, 0 deletions, converges.
- **The root cause is NOT what the last handoff said.** It took four wrong accounts to get
  right (see below). Prettier never stripped anything.
- **0030 repairs blank-line drift ONLY** and refuses everything else — after codex found the
  original byte-compare-and-replace would DESTROY spec-permitted host customizations.

## Decisions
- **Byte-derived idempotency, never provenance-version-derived** — upstream changed §11's
  prose WITHOUT bumping `spec_version`, so `@0.4.0` is a *genuinely correct* stamp over wrong
  bytes. A version check cannot tell the states apart even in principle. (ADR-0042)
- **Replace only on blank-line-only difference; refuse otherwise** (user call, after codex).
  Spec §11 says hosts **MAY** add anti-pattern bullets — byte-equality would delete them.
  This one guard turns every unrecognised shape from *silently destroy* into *refuse loudly*,
  and retired a real data-loss path inherited from 0029.
- **Rollback is a reporting no-op** — Step 1 has no forward inverse; the `.0030.bak` restore
  idiom in my plan was withdrawn (0029 uses no .bak; Apply deleted its own backup, so
  fixture 08 would have passed vacuously).
- **`ref: main` unpinned + best-effort daily cron** — an upstream commit cannot trigger this
  repo's CI at all, so unpinning decides *what* the next run compares against, not *when* it
  runs. The cron promises NO latency (GitHub delays scheduled events and disables them after
  repo inactivity). Drift is caught on the next run — PR, push to main, or timer, whichever
  happens first. A bound on DETECTION, not on time. Do not restate this as "same day" or
  "within a day": both were shipped as false claims and both had to be retracted.
- **Duplicate the 0029 fixture runner** rather than share one (0029 precedent, blast radius).

## Files modified
- `migrations/0030-resync-spec-11-mirror-bytes.md` (NEW), `migrations/test-fixtures/0030/**` (NEW, 15 fixtures + harness)
- `migrations/run-tests.sh` (test_migration_0030 + test_mirror_matches_core_spec_11)
- `.github/workflows/ci.yml` (2nd checkout of core @ main + daily cron), `.gitignore`
- `docs/decisions/0042-*.md` (NEW), `CHANGELOG.md`, three version stamps → 2.8.0
- `migrations/test-fixtures/0029/03-healthy-noop/setup.sh` — comment only (it asserted the false prettier/callbot claim)

## Next session: start here
**Downstream PRs are OPEN and awaiting review/merge — that is the only thing in flight.**
- cparx: https://github.com/agenticapps-eu/cparx/pull/87 — `chore/workflow-2.8.0`. **CI fully green.**
- fx-signal-agent: https://github.com/agenticapps-eu/fx-signal-agent/pull/111 — `chore/workflow-2.8.0`.
  CI green EXCEPT `gitleaks` + `pnpm-audit`, which are **PRE-EXISTING FAILURES ON main**, proven
  not mine: gitleaks reports the identical `leaks found: 2` against origin/main with the branch
  absent (both `curl-auth-header` in commit a4a0898c, 2026-06-17, in phase-09 planning docs), and
  `Supply chain (REQ-SEC01)` already failed on main on 2026-07-15. The only non-blank line either
  PR adds anywhere is `version: 2.8.0`. Explained in a PR comment. Do not "fix" them in that PR.

Each PR's diff is exactly: **CLAUDE.md +4 blank lines (0 deletions, 0 non-blank insertions)** and
`version: 2.5.0 -> 2.8.0`. Three commits each (0028 / 0029 / 0030). Verified per repo: healed block
byte-identical to the canonical mirror, converges on re-apply, GitNexus region intact,
`implements_spec` untouched at 0.9.0. 0028 skipped (no .prettierignore) and 0029 was a positional
no-op in both — exactly as predicted before merge.

Both were applied in throwaway worktrees cut from origin/main and the worktrees are removed; both
parent repos are untouched (cparx on feature/phase-10-review-cockpit with 9 dirty files;
fx-signal-agent on main with 10). Their uncommitted CLAUDE.md WIP was never disturbed.

If the PRs need re-running: `scratchpad/migrun.py <migration.md> <target> step N apply` is the
faithful block runner (extracts the fenced block by line bounds and runs it under **bash** — this
machine's shell is zsh, which mis-parses these snippets; an earlier awk -v version silently ran
PAST the Apply fence into the Rollback marker).

## Open questions / follow-ups
1. **Deferred codex MED/LOW findings** — shipped as-is in 2.8.0 (user call). All real, all
   recorded in the ledger: #7 "blank" is `$0 == ""` so a whitespace-only separator is deleted; #8 a CRLF
   mirror passes the unanchored tail sentinel; #9 `$(...)` strips the terminal newline so
   EOF-newline churn is invisible; #10 fixture 08 binds rollback's no-op, not the harness's
   subshell form; #11 "tmp cleaned up on every path" is false under `set -e` if awk exits ≠ 0.
2. **Unenforced ADR-0042 rule**: "a mirror edit must ship a re-sync migration" is *documented,
   not enforced* — a mirror-only PR matching upstream still goes green. Recorded as an open
   gap. Enforcing it needs a CI check: mirror touched ⇒ require a new `migrations/NNNN-*.md`.
3. **0029 has the same prose-in-region data-loss defect** 0030 just fixed in itself. Real,
   unfixed, out of scope. Needs its own migration or an end marker for §11.
4. Propagate to codex-workflow + opencode-workflow (prompts still sitting at those repo roots
   from the 0029 cycle; codex-workflow is already on `feat/spec-11-region-aware-placement`).

## The lesson worth carrying (it cost SIX false claims)
The root cause was wrong four times, and the CI-timing claim twice more. Each fix pass
introduced a *new* false claim while removing an old one — exactly the failure the previous
handoff warned about, reproduced verbatim, including once inside the ADR written to prevent
it and once while fixing the claim before it.
Final truth: upstream `10f2c96` ADDED the blank lines to spec §11 (prettier, "markdown/
prettier-clean") **without bumping spec_version**; `34ee72e` mirrored it with **no migration**;
cparx/fx-signal-agent are stale only because **nothing runs prettier over their CLAUDE.md**;
callbot self-healed via its own prettier pass 20 min *before* the mirror fix (`d2e92db` is a
squash whose single date hid it). **Every wrong account was internally plausible and survived
review until someone ran a command.** And: two Opus reviewers passed this branch READY TO
MERGE; codex then found six HIGHs including data loss. `/gsd-review` earned its keep.
