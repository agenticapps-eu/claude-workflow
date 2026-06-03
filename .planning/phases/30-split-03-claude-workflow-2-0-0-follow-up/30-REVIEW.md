---
phase: 30-split-03-claude-workflow-2-0-0-follow-up
reviewed: 2026-06-03T00:00:00Z
depth: standard
files_reviewed: 13
files_reviewed_list:
  - install.sh
  - migrations/0022-observability-repoint-phase-sentinel.md
  - migrations/run-tests.sh
  - templates/.claude/hooks/phase-sentinel.sh
  - templates/claude-settings.json
  - templates/config-hooks.json
  - migrations/test-fixtures/0022/01-repoint-and-hookswap/setup.sh
  - migrations/test-fixtures/0022/01-repoint-and-hookswap/verify.sh
  - migrations/test-fixtures/0022/02-abort-when-skill-absent/setup.sh
  - migrations/test-fixtures/0022/02-abort-when-skill-absent/verify.sh
  - migrations/test-fixtures/0022/03-idempotent-reapply/setup.sh
  - migrations/test-fixtures/0022/03-idempotent-reapply/verify.sh
  - migrations/test-fixtures/0022/common-setup.sh
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: clean
---

# Phase 30: Code Review Report

**Reviewed:** 2026-06-03
**Depth:** standard
**Files Reviewed:** 13
**Status:** clean (3 informational notes, no bugs)

## Summary

Reviewed the SPLIT-03 / claude-workflow 2.0.0 breaking-change surface: migration
0022 (observability repoint + Phase Sentinel hook swap + version bump), the new
deterministic `phase-sentinel.sh` Stop hook, the `install.sh` skill-pair drop,
the run-tests.sh 0022 + phase-sentinel test bodies, the three 0022 test
fixtures, and the two JSON hook templates. (The 7 tombstone `*-moved.md`
frontmatter blocks were also inspected for chain contiguity even though only
0022 and the supporting scripts were in the explicit file list.)

**No bugs, security issues, or correctness defects were found.** The work is
high quality and defensively engineered. I independently verified the
load-bearing claims rather than trusting them:

- **All migration tests pass.** `run-tests.sh 0022` → 3/3 PASS;
  `run-tests.sh phase-sentinel` → 3/3 PASS (exit 0/0/2 as specified).
- **Both JSON templates are valid** (`jq .` clean on `claude-settings.json`
  and `config-hooks.json`).
- **All 10 shell scripts pass `bash -n`** (install.sh, phase-sentinel.sh,
  run-tests.sh, common-setup.sh, and all six fixture setup/verify scripts).
- **The jq Step-3 Stop-hook swap is robust.** I tested it against the
  hostile edge case of a Stop entry with no inner `.hooks` key: the `.hooks[]?`
  optional iterator preserves unrelated entries and the narrow
  `type=="prompt" && prompt~"current-phase/checklist.md"` selector drops only
  the targeted Haiku hook. It does NOT corrupt or drop unrelated Stop hooks,
  and produces valid JSON. The idempotency anchor (positive `select` for the
  `type:command` phase-sentinel hook) correctly distinguishes "applied" from
  "old prompt text merely absent."
- **phase-sentinel.sh exit codes are correct** (0 allow / 2 block). I verified
  exit 2 holds even with >5 unchecked items where `grep | head -5` triggers
  SIGPIPE under `set -o pipefail` — the explicit `exit 2` statement is
  authoritative, so pipefail cannot leak a wrong code. No injection vector
  via `CLAUDE_PROJECT_DIR` (the value is only used quoted as a path; the
  `${CLAUDE_PROJECT_DIR:-$PWD}` default is safe).
- **install.sh skill-pair drop is clean.** The `LINKS` array remains a
  well-formed 3-element list, the loop body is unchanged, no dangling
  `add-observability` symlink target or reference remains (comment block,
  trailing echo, and verify-line regex all updated), and the bundled
  `add-observability/` tree is confirmed deleted — so dropping the link is
  correct, not premature.
- **Version chain is fully contiguous** 1.9.3 → … → 1.20.0 → 2.0.0 with no
  gaps. The 7 tombstones carry verbatim from/to versions matching the chain,
  `applies_to: []` (informational-only, no project mutation), and a
  `moved_to` pointer. 0022 chains off the live endpoint 1.20.0 (NOT off 0011),
  honoring the immutability contract.
- **Step 4 version bump targets the HYPHENATED path**
  (`.claude/skills/agentic-apps-workflow/SKILL.md`) in the idempotency check,
  pre-condition, apply sed, rollback, and post-check — consistent throughout.
  Scaffolder `skill/SKILL.md` is already at `version: 2.0.0`.
- **The exit-3 abort-if-absent pre-flight** has no auto-install path (D-03),
  prints the actionable pointer, and fixture 02 replays it verbatim asserting
  exit 3.

## Info

### IN-01: `requires.verify` path differs from `requires.install` clone path (verified safe)

**File:** `migrations/0022-observability-repoint-phase-sentinel.md:14-18`
**Issue:** The `requires.install` block clones to
`~/.claude/skills/agenticapps-observability`, while `requires.verify` checks
`~/.claude/skills/observability/SKILL.md` (different directory name). At first
glance this looks like a path mismatch that would make verify fail right after
a successful install.
**Assessment:** This is intentional and correct. The obs repo's `install.sh`
creates the canonical `~/.claude/skills/observability` symlink (plus an
`add-observability` alias), documented in this same file at lines 282-283 and
in the `install:` second line (`bash .../agenticapps-observability/install.sh`).
The verify path resolves through that symlink. No change required — flagged only
so a future reader doesn't "fix" the apparent mismatch and break the gate.
**Fix:** Optional: add a one-line inline comment on the `verify:` line noting
that `observability` is the canonical symlink created by the obs `install.sh`,
to preempt a well-meaning future edit.

### IN-02: Step 4 version bump is redundant with the engine's automatic bump (matches established pattern)

**File:** `migrations/0022-observability-repoint-phase-sentinel.md:202-225`
**Issue:** The migration engine already bumps the project SKILL.md `version`
line to `to_version` after post-checks (`update/SKILL.md:207-211`). Step 4
performs the same bump explicitly, so the version is written twice.
**Assessment:** Not a bug. This double-write is the established pattern across
prior migrations (0011 and 0014 both ship an explicit version-bump step in
`applies_to` + a `### Step`). The grep idempotency anchor short-circuits the
second write, so it is harmless and self-consistent with the codebase
convention. No change recommended for 2.0.0 (changing it now would diverge from
the documented per-migration contract).
**Fix:** None needed. If the team ever consolidates, do it repo-wide, not just
for 0022.

### IN-03: CHANGELOG ordering — `[2.0.0]` sits above two `[Unreleased]` entries

**File:** `CHANGELOG.md` (read for context; not in the explicit review scope)
**Issue:** The released `## [2.0.0] — SPLIT-03` heading appears above two
`## [Unreleased] — SPLIT-01` / `## [Unreleased]` headings. Keep-a-Changelog
convention places `[Unreleased]` at the very top.
**Assessment:** Documentation-ordering nit only; no functional impact on the
migration engine or downstream `/update-agenticapps-workflow`. The SPLIT-01
"Unreleased" content predates the 2.0.0 cut and appears to be stale-but-
intentional staging.
**Fix:** Optional: move the `[Unreleased]` sections above `[2.0.0]`, or fold the
now-shipped SPLIT-01 items into a released heading if SPLIT-01 has landed.

---

_Reviewed: 2026-06-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
