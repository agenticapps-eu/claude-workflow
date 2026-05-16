# Session Handoff — 2026-05-16 (Phase 18 committed locally, pre-push)

On branch `feat/test-0007-fnm-path-fix-phase18`, branched from `main` at
`eb91216`. Phase 18 changes are committed (atomic stack) but not yet pushed
to origin. Test-suite hygiene fix, no scaffolder semantics moved.

## Accomplished

- **Phase 17 fully shipped + merged** (carried from prior turn) — PR #28
  squash-merged as `eb91216`. Suite went from `PASS=122 FAIL=9` to
  `PASS=130 FAIL=1`; only `03-no-gitnexus` carry-over remained.
- **Phase 18 implemented on branch** — `test_migration_0007` hermetic
  sandbox fix in `migrations/run-tests.sh`. Root cause: the legacy
  `PATH="$fake_home/bin:$PATH"` invocation leaked the host's full PATH
  into the sandbox, so the developer's fnm-managed `gitnexus`
  (`$HOME/.local/state/fnm_multishells/.../bin/gitnexus`) shadowed the
  missing-stub case in the `03-no-gitnexus` fixture. Install script's
  `command -v gitnexus` found the host binary, proceeded with exit 0,
  and broke the assertion. Replaced with `env -i HOME=… PATH=… bash …`
  for both the install invocation and the verify.sh invocation.
- **Phase 15 smoke regression-guard tightened** in lockstep —
  `PASS≥130 FAIL≤1` → `PASS≥131 FAIL=0`. Known-fail allowlist branch
  collapsed (no fixture is allowed to fail any more). `FAIL: 0` parser
  fallback added because `run-tests.sh` elides the line when zero.
- **`CHANGELOG.md`** — `### Fixed` entry added under `[1.11.0]` (above
  the Phase 17 entry).
- **Phase 18 scaffolding** — `.planning/phases/18-test-0007-hermetic-sandbox/`
  with `PLAN.md` + `VERIFICATION.md` (10-row evidence ledger).
  `.planning/current-phase` repointed from phase 17 to phase 18.

## Decisions

- **`env -i` over per-var `env -u`** — strips the host environment
  wholesale, immune to whichever env var the install script next reads.
  Re-injecting `HOME` / `PATH` / `REPO_ROOT` is explicit at the call site.
- **Hermetic PATH = `$fake_home/bin:/usr/bin:/bin`** — sandbox stubs
  first, then coreutils + system jq. Verified against
  `install-gitnexus.sh`'s tool dependencies (`command, jq, grep, node,
  mv, rm`) and against every verify.sh's tool list. Works on macOS
  (which keeps coreutils in `/usr/bin` + `/bin`) and on Linux equivalents.
- **Test-only PR; no scaffolder version bump.** Same shape as Phase 17 —
  CHANGELOG `### Fixed` under `[1.11.0]`, no migration semantics, no
  template, no installer touched.
- **Tightened smoke thresholds in the same PR.** Locking in PASS=131
  FAIL=0 prevents a regression sliding back under the now-stale
  PASS≥130 FAIL≤1 ceiling. Pattern matches Phase 17.

## Files modified

- `migrations/run-tests.sh` — `run_0007_fixture` install + verify.sh
  invocations switched to `env -i` form (lines ~1039 + ~1079).
- `.planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` —
  regression-guard thresholds + FAIL=0 fallback + allowlist removal.
- `CHANGELOG.md` — `### Fixed` entry under `[1.11.0]`.
- `.planning/phases/18-test-0007-hermetic-sandbox/PLAN.md` (NEW).
- `.planning/phases/18-test-0007-hermetic-sandbox/VERIFICATION.md` (NEW).
- `.planning/current-phase` symlink → `phases/18-test-0007-hermetic-sandbox`.
- `session-handoff.md` — this file.

## Verification

- `bash migrations/run-tests.sh | tail -3` → `PASS: 131` (FAIL line elided).
- `bash migrations/run-tests.sh | grep -cE '^[[:space:]]*✗'` → `0`.
- All 18 `test_migration_0007` fixtures PASS (was 17/18).
- `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` →
  Passed: 9 / Failed: 0 (one fewer assert because the allowlist branch
  collapsed).
- Manual: pre-fix reproducer with `PATH=…:$PATH` → exit=0 (bug); post-fix
  with `env -i PATH=…/bin:/usr/bin:/bin` → exit=1 + "gitnexus not installed".

## Next session: start here

Commits are local; not yet pushed. Pick up by:

1. `git status` — confirm the 4 modified + 2 new files listed above.
2. Atomic commits per phase convention. Suggested split:
   - Commit A: `migrations/run-tests.sh` fix (load-bearing).
   - Commit B: Phase 15 smoke threshold tighten + FAIL=0 fallback.
   - Commit C: CHANGELOG `### Fixed` entry.
   - Commit D: Phase 18 scaffolding (PLAN + VERIFICATION).
   - Commit E: session-handoff refresh.
3. `git push -u origin feat/test-0007-fnm-path-fix-phase18` and
   `gh pr create` against `main`. PR body: link Phase 17 as the immediate
   precedent + note test-only / no-version-bump scope.
4. After merge: repoint `.planning/current-phase` to phase 19 (or leave
   dangling) and refresh handoff.

## Open questions (carried forward)

- **Phase 19** — `--strict-preflight` flag for Phase 13 audit. Lifts the
  per-migration preflight audit from advisory to enforced.
- **Issue #24** — spec v0.3.0 adoption stays OPEN until upstream
  `agenticapps-workflow-core/reference-implementations/README.md` row is
  updated. Cross-repo task.
- **Issue #5** — older v0.1.0 bootstrap issue, probably subsumable by #24.
  Triage candidate.
- **Init harness expansion** — VERIFICATION.md F4 (phase 15) flagged the 7
  init fixture pairs as reference-only at v1.11.0. A future phase could add
  `test_init_fixtures()` to `run-tests.sh`.
- **Cross-tree `applies_to` framework hardening** — migration 0012's
  `~/.claude/skills/...` reference flagged as a new precedent worth a
  framework-level `host_paths:` allowlist.
- **REDACTED_KEYS default expansion** — defer to a v0.3.2 minor of
  `add-observability`.
- **Anchor-comment threat-model documentation** — one-paragraph addition
  to INIT.md "Important rules".
- **Hermetic-sandbox pattern reuse** — if future migration tests grow
  shell-execution fixtures, carry the `env -i HOME=… PATH=…/bin:/usr/bin:/bin`
  pattern forward by default; never `PATH=…:$PATH`.
- **Carried from prior sessions** (unchanged): fx-signal-agent v1.10.0
  adoption verification; helper-script license consent for
  `index-family-repos.sh --all`; canonical install command for
  `/gsd-review`; CHANGELOG hygiene to stamp `[1.9.3]` as released.
