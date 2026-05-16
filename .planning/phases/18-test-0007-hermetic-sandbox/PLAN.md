# Phase 18 — `test_migration_0007` hermetic sandbox

## Goal

Resolve the single remaining suite failure (`03-no-gitnexus — exit 0,
expected 1`) so the full migration suite reaches **PASS=131 / FAIL=0**.

## Problem

`test_migration_0007/run_0007_fixture` invokes the install + verify scripts
with `PATH="$fake_home/bin:$PATH"`, prepending the sandbox stub dir to the
host's full `$PATH`. When the developer's host has `gitnexus` installed
globally (e.g., via `fnm` — `$HOME/.local/state/fnm_multishells/.../bin/gitnexus`
ends up in `PATH`), the `03-no-gitnexus` fixture's `rm -f $HOME/bin/gitnexus`
fails to actually hide `gitnexus` from the install script. `command -v gitnexus`
inside `install-gitnexus.sh` finds the host's fnm-managed binary instead of
the (now-removed) stub, so the script proceeds with exit 0 instead of failing
with exit 1 + "gitnexus not installed".

Confirmed reproducer:

```bash
command -v gitnexus
# /Users/donald/.local/state/fnm_multishells/2339_1778677370352/bin/gitnexus
```

The same leak applies to every fixture (a host-installed `node`, `npm`,
`claude`, `jq` could shadow the stubs); `03-no-gitnexus` is just the one
that happens to surface as a test failure. The pattern is a general
sandboxing weakness, not a 03-only bug.

## Fix

Replace the leaky `PATH="$fake_home/bin:$PATH"` invocation pattern with
`env -i` plus a curated PATH:

```bash
env -i HOME="$fake_home" PATH="$fake_home/bin:/usr/bin:/bin" bash "$install_script"
```

- `env -i` strips the entire host environment, so fnm-injected PATH entries
  + any host-set `GITNEXUS_BIN` / `GITNEXUS_VERSION` / `WIKI_SKILL_MD` env
  vars (all of which the install script reads) can't leak in.
- `$fake_home/bin` keeps the per-fixture stubs in front for `node` / `npm`
  / `gitnexus` / `claude`.
- `/usr/bin:/bin` provides coreutils + system `jq` (verified present on
  macOS at `/usr/bin/jq` and on every modern POSIX distro).
- The install script only needs: `command, jq, grep, node, mv, rm` — all
  in `/usr/bin:/bin` plus the stubbed `node` in `$fake_home/bin`. Verified
  via `grep -oE '^\s*[a-z]+ ' install-gitnexus.sh`.
- `verify.sh` invocation gets the same treatment plus `REPO_ROOT` (required
  by several verify scripts to locate `rollback-gitnexus.sh` /
  `index-family-repos.sh`).

`run-tests.sh` summary-block also elides `FAIL: 0`, so Phase 15's smoke
parser would have died on the new state — bundle a defensive fallback that
treats a missing FAIL line as zero, and tighten the smoke threshold to
`PASS≥131 FAIL=0` (no allowlist needed; the known-fail set is now empty).

## Scope

- `migrations/run-tests.sh:run_0007_fixture` — install invocation (line ~1039)
  and verify.sh invocation (line ~1079) switched to `env -i` form. Comment
  blocks updated to explain the hermetic sandbox.
- `.planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` —
  threshold tightened from `PASS≥130 FAIL≤1` to `PASS≥131 FAIL=0`; FAIL=0
  parsing fallback added; known-fail allowlist branch removed (vacuously
  empty).
- `CHANGELOG.md` — `### Fixed` entry under `[1.11.0]`.

## Out of scope

- Sandboxing other test stanzas. `test_migration_0007` is the only stanza
  that exercises a sub-script needing host-blocking. All other stanzas
  either extract template files from git (no shell execution) or use
  hand-built file fixtures.
- Audit (preflight) hermeticity. Audit checks read from the installed-on-
  host `~/.claude/skills/` tree by design — they're testing the host
  state, not testing in a sandbox.
- Scaffolder version bump. Test-only hygiene fix; no migration semantics
  or scaffolder-visible behaviour changes.

## Verification

- `bash migrations/run-tests.sh | tail -3` → `PASS: 131` (no FAIL line).
- `bash migrations/run-tests.sh | grep -cE '^[[:space:]]*✗'` → `0`.
- `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh
  2>&1 | grep -E '(Passed|Failed):'` → `Passed: 9 / Failed: 0` with the
  tightened thresholds (one fewer assert because the allowlist branch
  collapsed).
- Manual reproducer parity:
  - `command -v gitnexus` on host still resolves to fnm-managed gitnexus
    (host unchanged).
  - `env -i HOME=$tmp PATH=$tmp/bin:/usr/bin:/bin bash install-gitnexus.sh`
    (after `rm $tmp/bin/gitnexus`) exits 1 with "gitnexus not installed"
    on stderr.
- Every other 0007 fixture (`02`, `04`-`19`) still passes — 18/18 in the
  0007 stanza, same as pre-fix counts plus the `03-no-gitnexus` recovery.
