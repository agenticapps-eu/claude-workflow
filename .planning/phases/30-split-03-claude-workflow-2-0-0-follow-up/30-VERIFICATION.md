---
phase: 30-split-03-claude-workflow-2-0-0-follow-up
verified: 2026-06-03T00:00:00Z
status: human_needed
score: 16/16 code-side must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  note: initial verification
human_verification:
  - test: "Ship 2.0.0 — Task 3 blocking human-verify gate (orchestrator-owned, intentionally deferred)"
    expected: "On explicit human 'approved': /gsd-review clean, commit on plan-30-split-03, gh pr create with title 'v2.0.0 chore!: extract observability to agenticapps-observability (SPLIT-03)', git tag -a v2.0.0, merge + push tag, then git -C ~/.claude/skills/agenticapps-workflow pull"
    why_human: "checkpoint:human-verify gate=blocking — breaking 2.0.0 release affects all downstream consumers; tag/PR/merge require explicit human approval per plan 30-03 Task 3. All automated ship preconditions are satisfied (suite green, drift PASS at 2.0.0, CHANGELOG [2.0.0] present, UPGRADING.md present). This is a known follow-up, not a failure."
  - test: "docs/UPGRADING.md prose/UX read-through (D-06 manual verification per 30-VALIDATION.md)"
    expected: "The 1.21.0 -> 2.0.0 transition narrative, supported-floor note, and obs-repo install cross-reference (README + install.sh) read correctly and are actionable for a downstream upgrader"
    why_human: "Prose clarity / UX judgement cannot be verified programmatically; content presence is verified but readability is a human judgement."
---

# Phase 30: SPLIT-03 — claude-workflow 2.0.0 follow-up Verification Report

**Phase Goal:** Post-split cleanup — delete `add-observability/` + moved migrations/fixtures/ADRs; tombstone the 7 vacated migration slots (chain contiguous); repoint the observability install to the extracted `observability` skill (no auto-install, abort-if-absent); manage the `add-observability`→`observability` alias deprecation; write the downstream upgrade story (docs/UPGRADING.md); ship `claude-workflow 2.0.0` (breaking); and fix #58 (deterministic Phase Sentinel Stop hook).
**Verified:** 2026-06-03
**Status:** human_needed (all code-side deliverables VERIFIED; the breaking ship action is a deliberate blocking human-verify gate)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
| -- | ----- | ------ | -------- |
| 1  | `add-observability/` deleted from claude-workflow | ✓ VERIFIED | `test -d add-observability` → GONE; whole tree (tracked + untracked) removed (30-01 `217baec`) |
| 2  | 7 `*-moved.md` tombstones present with verbatim from/to versions | ✓ VERIFIED | All 7 present; 0012(1.10→1.11), 0013(1.11→1.12), 0017(1.15→1.16), 0018(1.16→1.17), 0019(1.17→1.18), 0020(1.18→1.19), 0021(1.19→1.20); each `applies_to: []` |
| 3  | 0020 IS tombstoned at 1.18.0→1.19.0 | ✓ VERIFIED | `migrations/0020-openrouter-integration-moved.md` present; `to_version: 1.19.0` (D-01 / RESEARCH Pitfall 4, overriding §6.1 contradictory row) |
| 4  | Migration chain contiguous through 2.0.0 | ✓ VERIFIED | 1.9.3→1.10.0 (0011) → 1.10.0→1.11.0 (0012m) → … → 1.19.0→1.20.0 (0021m) → 1.20.0→2.0.0 (0022); no from_version gap |
| 5  | 6 obs ADRs (0029-0034) deleted; ADR-0035 retained | ✓ VERIFIED | 0029-0034 each 0 files in docs/decisions; `0035-shared-extraction-boundaries.md` present |
| 6  | Migration 0022 present: from 1.20.0, to 2.0.0, `skill: observability`, verify grep `^name: observability`, exit-3 abort (no auto-install), version bump targets HYPHENATED path, folds in #58 | ✓ VERIFIED | Frontmatter `from_version: 1.20.0`/`to_version: 2.0.0`; requires `skill: observability` + verify `grep -q '^name: observability'`; pre-flight `exit 3` + actionable ABORT, no auto-install (clone shown as message only); `applies_to` lists `.claude/skills/agentic-apps-workflow/SKILL.md`; 15 `phase-sentinel.sh` refs |
| 7  | 0011 byte-unchanged | ✓ VERIFIED | `git diff --quiet HEAD -- migrations/0011-observability-enforcement.md` exit 0; 0022 chains off 1.20.0 endpoint, not 0011 |
| 8  | skill/SKILL.md version == 2.0.0; drift test PASS | ✓ VERIFIED | `version: 2.0.0`; `run-tests.sh test-skill-md-version-matches-latest-migration-to-version` → PASS (2.0.0 == 2.0.0) |
| 9  | phase-sentinel.sh template exists, executable, deterministic | ✓ VERIFIED | mode 100755; `set -euo pipefail`; `exit 0` (allow) / `exit 2` (block); no Haiku/prompt |
| 10 | claude-settings.json Stop block uses type:command phase-sentinel.sh (no Haiku) | ✓ VERIFIED | jq select(type=="command", command~phase-sentinel.sh) → PRESENT; `claude-haiku-4-5` count 0 |
| 11 | Forward-looking files free of `add-observability` | ✓ VERIFIED | README.md, install.sh, setup/SKILL.md, config-hooks.json, observability-postphase-scan.sh, workflow.md → all 0 matches |
| 12 | install.sh skill-pair DROPPED (no dangling target) | ✓ VERIFIED | `grep -cE '"add-observability' install.sh` → 0; remaining pairs (skill/setup/update) all have existing subdirs; `bash -n install.sh` OK |
| 13 | config-hooks.json → observability:scan | ✓ VERIFIED | 1 `observability:scan`, 0 `add-observability:scan`; jq valid |
| 14 | docs/UPGRADING.md present (1.21.0 floor, obs cross-ref, no INSTALLATION.md ref) | ✓ VERIFIED | 75 lines; 1.21.0 ×5, agenticapps-observability ×8, INSTALLATION.md ×0; references obs README + install.sh |
| 15 | CHANGELOG [2.0.0] section present | ✓ VERIFIED | `grep -c '\[2.0.0\]'` → 1 |
| 16 | Full suite green; drift PASS; obs-dependent test bodies removed | ✓ VERIFIED | `run-tests.sh` exit 0, PASS 149, no FAIL line (FAIL=0); 8 obs-dependent bodies absent; 0011/0014/0022/phase_sentinel retained |

**Score:** 16/16 code-side must-haves verified

### Ship Preconditions (Task 3 gate — automated portion)

| Precondition | Status | Evidence |
| ------------ | ------ | -------- |
| Full suite green | ✓ MET | exit 0, PASS 149, FAIL 0 |
| Drift PASS at 2.0.0 | ✓ MET | drift filter PASS (2.0.0 == 2.0.0) |
| CHANGELOG [2.0.0] present | ✓ MET | section at top of CHANGELOG.md |
| docs/UPGRADING.md present | ✓ MET | 75 lines, 1.21.0 floor + obs cross-ref |
| git tag v2.0.0 | ⏳ DEFERRED (expected absent) | `git tag -l v2.0.0` empty — intentional; ship gate is orchestrator-owned, gated on human approval |
| Breaking PR opened | ⏳ DEFERRED (expected absent) | `gh pr list --head plan-30-split-03` → [] — intentional; deferred to Task 3 human-verify |

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `migrations/0012..0021-*-moved.md` | 7 tombstones, verbatim versions | ✓ VERIFIED | All present, `applies_to: []`, no `## Steps` |
| `migrations/0022-observability-repoint-phase-sentinel.md` | repoint + 2.0.0 + #58 | ✓ VERIFIED | from 1.20.0 / to 2.0.0; observability requires; exit-3 abort; hyphenated bump path |
| `templates/.claude/hooks/phase-sentinel.sh` | deterministic Stop hook | ✓ VERIFIED | mode 100755; set -euo pipefail; exit 0/2 |
| `skill/SKILL.md` | version 2.0.0 | ✓ VERIFIED | `version: 2.0.0` |
| `migrations/test-fixtures/0022/` | 3 fixtures | ✓ VERIFIED | 3 fixture dirs + common-setup.sh; `run-tests.sh 0022` 3/3 PASS |
| `docs/UPGRADING.md` | 1.21.0→2.0.0 story (≥20 lines) | ✓ VERIFIED | 75 lines |
| `templates/config-hooks.json` | observability:scan | ✓ VERIFIED | repointed; jq valid |
| `CHANGELOG.md` | [2.0.0] entry | ✓ VERIFIED | present |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| 0021 tombstone | drift test | alphabetically-last pre-0022 to_version | ✓ WIRED | (pre-0022) 1.20.0; now 0022 is latest → 2.0.0 drift PASS |
| 0022 | ~/.claude/skills/observability/SKILL.md | requires.verify grep `^name: observability` | ✓ WIRED | verify resolves via obs install.sh canonical symlink |
| skill/SKILL.md | drift-test | version == latest migration to_version | ✓ WIRED | 2.0.0 == 2.0.0 PASS |
| claude-settings.json | phase-sentinel.sh | Stop hook type:command path | ✓ WIRED | jq select command hook present |
| config-hooks.json | observability skill | skill field repoint | ✓ WIRED | `observability:scan` |
| docs/UPGRADING.md | agenticapps-observability repo | install cross-ref (README + install.sh) | ✓ WIRED | links obs README + install.sh, no INSTALLATION.md |
| install.sh | LINKS array | add-observability pair DROPPED | ✓ WIRED | 0 dangling targets; remaining pairs' subdirs exist |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Drift invariant holds at 2.0.0 | `run-tests.sh test-skill-md-version-matches-latest-migration-to-version` | PASS | ✓ PASS |
| phase-sentinel exit codes (0/0/2) | `run-tests.sh phase-sentinel` | 3/3 PASS | ✓ PASS |
| 0022 repoint/abort/idempotent | `run-tests.sh 0022` | 3/3 PASS | ✓ PASS |
| Full migration suite | `run-tests.sh` | exit 0, PASS 149, FAIL 0 | ✓ PASS |
| install.sh / postphase-scan parse | `bash -n` | OK | ✓ PASS |
| config-hooks.json valid JSON | `jq .` | valid | ✓ PASS |

Note: pre-flight audit reports `FAIL=2` (0008 local coverage server not running; 0022 obs-skill `requires.verify` failing because the `observability` skill is not installed on this dev machine). The harness explicitly states these are "NOT counted in suite totals." The 0022 audit fail is exactly the D-03 design (separate install, loose mode by default) — informational, not a gap.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| D-01 | 30-01 | Tombstone/redirect 7 vacated migration slots; chain contiguous | ✓ SATISFIED | 7 tombstones, verbatim versions, chain contiguous (Truths 2-4) |
| D-02 | 30-02 | New superseding migration 0022 repoints requires/verify; 0011 immutable | ✓ SATISFIED | 0022 repoints to observability skill; 0011 byte-unchanged (Truths 6-7) |
| D-03 | 30-02 | Two independent installs; abort-if-absent, no auto-install | ✓ SATISFIED | exit-3 abort with install pointer, no auto-install (Truth 6) |
| D-04 | 30-02, 30-03 | Ship 2.0.0: 0022 to_version 2.0.0, SKILL.md 2.0.0, CHANGELOG, tag, PR | ◑ CODE-SIDE SATISFIED | SKILL.md 2.0.0, CHANGELOG [2.0.0] present (Truths 8,15); tag/PR deferred to Task 3 human gate |
| D-05 | 30-03 | Reference cleanup in non-immutable forward-looking files | ✓ SATISFIED | All 6 forward-looking files free of add-observability; install.sh pair dropped (Truths 11-13) |
| D-06 | 30-03 | docs/UPGRADING.md (1.21.0→2.0.0, obs cross-ref) | ✓ SATISFIED | UPGRADING.md present, 1.21.0 floor, obs README/install.sh cross-ref (Truth 14); prose read-through → human |
| D-07 | 30-02 | Fix #58: deterministic phase-sentinel.sh (template + 0022 migration) | ✓ SATISFIED | template hook + Stop-block swap + 0022 fold-in (Truths 9-10, 6) |

All 7 requirement IDs (D-01..D-07) accounted for. D-04's tag/PR portion is the deliberate human-verify ship gate.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | none | — | No TODO/FIXME/placeholder/stub in 0022, phase-sentinel.sh, or UPGRADING.md |

Note: the 4 `add-observability` references in `migrations/run-tests.sh` (lines 1174, 1192-1194) are the INTENTIONAL 0011-fixture inline SCAN.md stub using the NON-hyphenated path that mirrors immutable 0011's `requires.verify` — documented in 30-01 PLAN PATH NOTE and SUMMARY. Not a leftover obs dependency; not flagged.

### Human Verification Required

1. **Ship 2.0.0 (Task 3 blocking gate)** — orchestrator-owned. On human "approved": run /gsd-review, commit, `gh pr create` (title `v2.0.0 chore!: extract observability to agenticapps-observability (SPLIT-03)`), `git tag -a v2.0.0`, merge + push tag, then `git -C ~/.claude/skills/agenticapps-workflow pull`. All automated preconditions are already met. This is a known follow-up, not a failure.
2. **docs/UPGRADING.md prose/UX read-through** — confirm the upgrade narrative reads correctly and is actionable (D-06 manual verification per 30-VALIDATION.md).

### Gaps Summary

No code-side gaps. All 16 code-side must-haves and all 7 requirement IDs (D-01..D-07) are verified against the live tree. The migration chain is contiguous 1.9.3 → 2.0.0, the suite is green (exit 0, PASS 149, FAIL 0), the drift test passes at 2.0.0, 0011 is byte-unchanged, and the observability tree/ADRs/references are cleanly removed or repointed.

Status is `human_needed` (not `passed`) solely because (a) the breaking 2.0.0 ship action (git tag v2.0.0, breaking PR, merge/push) is a deliberate `checkpoint:human-verify gate=blocking` deferred pending explicit human approval, and (b) the UPGRADING.md prose requires a human read-through (D-06). The absence of the v2.0.0 tag and PR is EXPECTED and is recorded as a known follow-up, not scored as a gap.

---

_Verified: 2026-06-03_
_Verifier: Claude (gsd-verifier)_
