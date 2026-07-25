# Session Handoff — 2026-07-25 (bind OpenSpec v1 + cross-AI review)

## Status: PR #95 OPEN on `feat/bind-openspec-v1`, 14 commits. Suite 197 PASS / 0 FAIL.
https://github.com/agenticapps-eu/claude-workflow/pull/95

## Accomplished
Ran `prompts/01-host-bind-openspec.md` for `{{HOST}}=claude` (all 6 steps, all 4
acceptance criteria verified), then a cross-AI review (codex + gemini) whose
findings turned into 6 further fix commits.

### The review earned its keep
codex found **10 HIGH / 9 MEDIUM**; every claim I tested reproduced. gemini's
single HIGH was a hallucination (it read `("$ @")` where the file has `("$@")`) —
worth remembering when weighing the two.

Fixed, all reproduced before and after:
1. **Gate exemption bypass** — `is_openspec_artifact` matched any path containing
   an `openspec/` component, so `src/openspec/app.ts` edited freely with the gate
   unsatisfied. Anchored to `$ROOT/openspec/`; `--pre-commit` had the same hole.
2. **Reviewer counting** — `## Reviewer` inside fenced code blocks counted, as did
   a bare `reviewers: [a, b]` and two sections from one vendor. Now fence-aware,
   colon-required, deduplicated; YAML fallback removed.
3. **Fail-open inverted** — unparseable stdin could BLOCK. §18 says parse errors
   fail open, policy never does.
4. **Empty prompt to codex** — `printf … | codex exec - </dev/null`: in bash the
   redirect beats the pipe, so the reviewer got nothing. Any banner it printed
   would have been recorded as a real review. (zsh MULTIOS hides this.)
5. **Retired-payload 404** — deleting `multi-ai-review-gate.sh` made migrations
   0005/0016 `curl -f … > hook` a truncate-then-fail, leaving an EMPTY executable
   PreToolUse hook = allow-everything. 0026/0031 had the loud variant.
6. **Two data-loss bugs in 0032** — the settings `jq` deleted whole hook entries
   (killing co-registered project hooks); Step 5 discarded every project-owned
   top-level config key (`.workflow`, custom policy).
7. **Shared-gate propagation vector** (from the pi session) — `install.sh:153`
   wrote `~/.agenticapps/bin/` unconditionally: last-writer-wins across hosts, so
   a host vendoring an older gate reverts the fix machine-wide.
8. install.sh clobbered an existing pre-commit; treated any `openspec` dir as an
   initialised slot; `$SLUG` path traversal in run-plan-review.sh.

## Decisions
- **Guards over fixes.** Each bug got a mutation-tested guard: payload-publication,
  prompt-delivery, gate-canonical parity, version-marker, apply-parity (now
  line-by-line, not 4 substrings), gitignored-payload.
- **Divergence recorded, not silent.** `bin/GATE-DIVERGENCE.md` pins the exact
  diff hash vs core with close-out steps; `test_gate_matches_core_canonical`
  accepts only that diff, fails on further drift, and flips to enforcing
  byte-identity the moment core publishes `gate/`.
- **Sibling repos left untouched** — publishing `gate/` is the owner's call.

## The structural finding
**`gate/` and `prompts/` are NOT in version control in agenticapps-workflow-core** —
they exist only as uncommitted local directories, absent from `origin/main`. So
"reuse the shared gate, don't re-author" was unimplementable: there was nothing to
sync from. That is why opencode re-authored (~256 lines diverged) and why all three
copies carry the bypass. User reports core is now working on publishing it.

## Files modified
70 files, ~+3.4k/−2.3k. Key: `bin/{openspec-change-gate,run-plan-review}.sh`,
`bin/GATE-DIVERGENCE.md`, `migrations/0032-*` + `test-fixtures/0032/**` (6
fixtures), `migrations/run-tests.sh` (5 new guards), `check-snapshot-parity.sh`,
`install.sh`, `templates/config-hooks.json`, `skill/SKILL.md`, `docs/WORKFLOW.md`,
`docs/decisions/0044-*`, `.gitignore`.

## Next session: start here
Merge #95 once CI is green and CodeRabbit clears. Then, **in priority order**:
1. **opencode-workflow ships the bypass** (defect 1) in already-merged code, and
   its installer has the same propagation vector. Fix both.
2. When core publishes `gate/`: fold in the four fixes, bump `# gate-version:`,
   re-vendor here, delete `bin/GATE-DIVERGENCE.md` (the guard fails if the record
   outlives the fork), and add the version check to **every** host installer — one
   host without it still clobbers.
3. Remaining unfixed codex findings, all MEDIUM and recorded in the PR thread:
   idempotency checks describe partial end states (HIGH 8); rollback recipes
   over-delete (`rm -rf openspec/`, `git checkout --` whole dirs) (HIGH 10);
   `find` errors read as "no active change" in ci/pre-commit; no-jq path misses
   `notebook_path`; newline-in-filename handling; no timeout binary on stock macOS;
   producer counts duplicate/failed reviewers.
4. Then prompt 01 for `codex-workflow` and `pi-agentic-apps-workflow`.

## Open questions
1. Should this repo dogfood its own gate (`openspec init` here)? Deliberate act,
   not mid-PR.
2. `.planning/` (35 phase dirs) still needs the supervised Tier-2 fold into
   `openspec/specs/` capabilities.
3. HIGH 10's rollback over-deletion is real but rollbacks are rarely exercised —
   worth a follow-up, not a blocker.
