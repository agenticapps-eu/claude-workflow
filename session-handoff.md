# Session Handoff — 2026-05-16 (Phase 19 committed locally, pre-push)

On branch `feat/strict-preflight-phase19`, branched from `main` at
`61e53c2`. Phase 19 changes are committed (atomic stack) but not yet
pushed to origin. Test-harness feature add (no scaffolder semantics
moved, no version bump) — Phase 13's deferred `--strict-preflight`
follow-up landed.

## Accomplished

- **Phase 17 + Phase 18 shipped this session** (carried) — Phase 17 PR
  #28 `eb91216` (test_migration_0001 baseline anchor, suite 122/9 →
  130/1); Phase 18 PR #29 `61e53c2` (test_migration_0007 hermetic
  sandbox, suite 130/1 → 131/0 clean baseline).
- **Phase 19 implemented on branch** — `migrations/run-tests.sh` gains
  `--strict-preflight` flag + `STRICT_PREFLIGHT=1` env-var alias.
  Default (loose) mode unchanged — audit failures still print
  informationally but don't affect exit code, so dev machines with
  partial host deps aren't false-positive failed. Strict mode rolls
  the audit's `audit_fail` into global `FAIL`, so CI environments with
  parity to dev environments can gate merges on verify-path rot (the
  issue-#18 bug class).
- **PyYAML-missing path is strict-aware** — loose mode keeps the `~`
  warning + clean return; strict mode emits `✗ python3 with PyYAML not
  available — audit cannot run (strict)` and increments `FAIL` by 1.
- **`--help` flag** prints the usage block from the script header;
  unknown flags exit 2 (distinct from FAIL → exit 1).
- **Flag parser** is order-agnostic — `--strict-preflight 0007` and
  `0007 --strict-preflight` both work. Replaces the legacy single-
  positional `FILTER="${1:-}"` line.
- **`migrations/README.md`** — new "Preflight-correctness audit"
  section between "Test fixtures" and "Adding a new migration",
  documenting the audit + both invocation modes + when to use which.
- **`CHANGELOG.md`** — `### Added` entry under `[1.11.0]`, placed at
  the top of the Added block.
- **Phase 19 scaffolding** — `.planning/phases/19-strict-preflight/`
  with `PLAN.md` + `VERIFICATION.md` (10-row evidence ledger).
  `.planning/current-phase` repointed phase 18 → phase 19.

## Decisions

- **Flag + env-var, both supported** — CLI flag is idiomatic, env-var
  is CI-friendly. Cost is one `${STRICT_PREFLIGHT:-0}` defaulting line
  + an additional case in the parser.
- **Order-agnostic flag parser** — replaces the previous
  `FILTER="${1:-}"`. New `while [ $# -gt 0 ]` loop handles flag-before-
  positional and flag-after-positional uniformly.
- **Strict-mode `audit_fail` rolls into global `FAIL`, not its own
  separate counter** — keeps the suite's exit-code contract simple
  (`[ $FAIL -gt 0 ] && exit 1`).
- **`--help` parses the script-header comment** rather than maintaining
  a separate `print_usage()` function. Single source of truth; comment
  block has been formatted to render cleanly under `sed -n
  '2,/^$/p' | sed 's/^# \{0,1\}//'`.
- **Unknown flag → exit 2** distinct from FAIL → exit 1. CI can tell
  user error from genuine test failure.
- **Smoke unchanged** — Phase 15's smoke runs `bash run-tests.sh` with
  no flag, so it stays in loose mode. The smoke's PASS/FAIL awk parser
  doesn't read the audit's disclaimer line.

## Files modified

- `migrations/run-tests.sh` — usage comment block expanded; flag parser
  (replaces line `FILTER="${1:-}"`); `test_preflight_verify_paths`
  gains mode-aware header + PyYAML-missing branch + strict-mode FAIL
  rollup at the audit-summary line.
- `migrations/README.md` — new "Preflight-correctness audit" section.
- `CHANGELOG.md` — `### Added` entry under `[1.11.0]`.
- `.planning/phases/19-strict-preflight/PLAN.md` (NEW).
- `.planning/phases/19-strict-preflight/VERIFICATION.md` (NEW).
- `.planning/current-phase` symlink → `phases/19-strict-preflight`.
- `session-handoff.md` — this file.

## Verification

- `bash migrations/run-tests.sh` → `PASS: 131`, exit `0`, audit
  disclaimer reads `(NOT counted in suite totals — pass
  --strict-preflight to gate.)`.
- `bash migrations/run-tests.sh --strict-preflight` → `PASS: 131`,
  exit `0` on clean audit, disclaimer reads `(counted in suite totals
  — strict mode: 0 audit FAIL to roll in.)`.
- `STRICT_PREFLIGHT=1 bash migrations/run-tests.sh` → identical to
  flag form.
- Synthetic regression (broke 0005 verify path temporarily):
  - Loose: exit `0`, audit `FAIL=1`, global `FAIL=0`.
  - Strict: exit `1`, audit `FAIL=1`, global `FAIL=1`, `FAIL: 1` line
    appears in suite summary.
  - Env-var: identical to strict flag.
  - Restored cleanly; current `main` content unchanged.
- `bash migrations/run-tests.sh --help` → prints usage; exit `0`.
- `bash migrations/run-tests.sh --does-not-exist` → stderr `unknown
  flag: --does-not-exist`; exit `2`.
- Phase 15 smoke still `Passed: 9 / Failed: 0`.

## Next session: start here

Commits are local; not yet pushed. Pick up by:

1. `git status` — confirm 3 modified + 2 new files.
2. Atomic commits per phase convention. Suggested split:
   - Commit A: `migrations/run-tests.sh` flag + strict-mode branches
     (load-bearing).
   - Commit B: `migrations/README.md` audit documentation.
   - Commit C: CHANGELOG `### Added` entry.
   - Commit D: Phase 19 scaffolding (PLAN + VERIFICATION).
   - Commit E: session-handoff refresh.
3. `git push -u origin feat/strict-preflight-phase19` and
   `gh pr create` against `main`. PR body: link Phase 13 RESEARCH.md
   line 105 as the deferred-follow-up source + note no scaffolder
   semantics moved.
4. After merge: repoint `.planning/current-phase` to phase 20 (or
   leave dangling). Refresh handoff.

## Open questions (carried forward)

- **Issue #24** — spec v0.3.0 adoption stays OPEN until upstream
  `agenticapps-workflow-core/reference-implementations/README.md` row
  is updated. Cross-repo task; closes #24.
- **Issue #5** — older v0.1.0 bootstrap issue, probably subsumable by
  #24. Triage candidate.
- **Init harness expansion** — Phase 15 VERIFICATION F4 flagged the
  7 init fixture pairs as reference-only at v1.11.0. A future phase
  could add `test_init_fixtures()` to `run-tests.sh`.
- **Cross-tree `applies_to` framework hardening** — migration 0012's
  `~/.claude/skills/...` reference flagged as a new precedent worth a
  framework-level `host_paths:` allowlist.
- **REDACTED_KEYS default expansion** — defer to a v0.3.2 minor of
  `add-observability`.
- **Anchor-comment threat-model documentation** — one-paragraph
  addition to INIT.md "Important rules".
- **CI workflow wiring for `--strict-preflight`** — the flag is now
  available, but no GitHub Actions workflow yet runs it. Phase 19
  intentionally stopped at the primitive; project-policy decision when
  to wire it.
- **Hermetic-sandbox pattern reuse** — if future migration tests grow
  shell-execution fixtures, carry the `env -i HOME=…
  PATH=…/bin:/usr/bin:/bin` pattern forward by default; never
  `PATH=…:$PATH`.
- **Carried from prior sessions** (unchanged): fx-signal-agent v1.10.0
  adoption verification; helper-script license consent for
  `index-family-repos.sh --all`; canonical install command for
  `/gsd-review`; CHANGELOG hygiene to stamp `[1.9.3]` as released.
