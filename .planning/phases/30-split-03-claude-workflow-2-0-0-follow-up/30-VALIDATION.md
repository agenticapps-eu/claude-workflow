---
phase: 30
slug: split-03-claude-workflow-2-0-0-follow-up
status: draft
nyquist_compliant: true
wave_0_complete: in-plan  # Wave 0 bodies are in-plan deliverables — created in Plan 30-02 Task 3 before Wave 2 completes
created: 2026-06-03
---

# Phase 30 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash (`migrations/run-tests.sh` — custom TAP-ish harness) |
| **Config file** | none — `migrations/run-tests.sh` is self-contained |
| **Quick run command** | `bash migrations/run-tests.sh 2>&1 \| tail -30` |
| **Full suite command** | `bash migrations/run-tests.sh` |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash migrations/run-tests.sh 2>&1 | tail -30` (watch PASS/FAIL/XFAIL counts + drift test)
- **After every plan wave:** Run full `bash migrations/run-tests.sh`
- **Before `/gsd-verify-work`:** Full suite green; drift test PASS (latest migration `to_version` == `skill/SKILL.md`)
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 30-01-* | 01 | 1 | D-01 (tombstones) | — | N/A | suite | `bash migrations/run-tests.sh` | ✅ | ⬜ pending |
| 30-01-* | 01 | 1 | D-01 deletion manifest | — | N/A | grep | `! test -d add-observability && ! ls migrations/0012*.md migrations/0013*.md 2>/dev/null` | ✅ | ⬜ pending |
| 30-02-* | 02 | 2 | D-02/D-04 (0022 migration + 2.0.0) | — | abort-if-absent (no auto-install) | suite+grep | `bash migrations/run-tests.sh` ; drift test PASS | ✅ | ⬜ pending |
| 30-02-* | 02 | 2 | D-07 (#58 hook) | — | deterministic stop gate | suite | `bash migrations/run-tests.sh` (phase-sentinel test) | ✅ in-plan (30-02 T3) | ⬜ pending |
| 30-03-* | 03 | 3 | D-05/D-06 (refs + UPGRADING) | — | N/A | grep | `! grep -rn add-observability <non-immutable files>` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky · Final plan/task IDs assigned by planner.*

---

## Wave 0 Requirements

- [x] New `test_phase_sentinel` body in `migrations/run-tests.sh` — asserts the deterministic `phase-sentinel.sh` exit-code cases (0/0/2) (D-07). **In-plan deliverable: Plan 30-02 Task 3** (created before Wave 2 completes — not an unmet external dependency).
- [x] New `test_migration_0022` body — asserts repoint (`observability` skill grep replaces `add-observability`), abort-if-absent message, `to_version: 2.0.0`. **In-plan deliverable: Plan 30-02 Task 3.**
- [x] Drift-test guard (existing in run-tests.sh) — must stay green after deletions + 0022 add. Held green every wave: 30-01 keeps 1.20.0==1.20.0; 30-02 atomically bumps both to 2.0.0.

> **Wave 0 status:** The Wave 0 mechanism is fully designed and delivered IN-PLAN. Both new test bodies (`test_phase_sentinel`, `test_migration_0022`) plus their fixtures are authored by Plan 30-02 Task 3 (marked `tdd="true"`) before Wave 2 is allowed to complete. There are no MISSING external test dependencies — every task carries an `<automated>` verify and the suite is held green at every wave boundary.

*Removals are also Wave-0-adjacent: the 8 `test_migration_00NN` / meta bodies for moved migrations are deleted, and any count-assertion guard updated.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Git tag `v2.0.0` pushed | D-04 | Tagging/push is a ship action outside the test harness | `git tag v2.0.0 && git push --tags` during ship; verify `git tag -l v2.0.0` |
| Downstream upgrade reads correctly | D-06 | Prose/UX judgement | Read `docs/UPGRADING.md`: 1.21.0→2.0.0 transition + obs-repo install cross-ref present |
| Sibling obs install path resolves `add-observability` alias | D-02/D-05 | Cross-repo; obs repo's dual-symlink installer is authoritative | Inspect `~/Sourcecode/agenticapps/agenticapps-observability/install.sh` symlink lines |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (every task across 30-01/02/03 carries an `<automated>` block; the ship checkpoint also has one)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (new 0022 + phase-sentinel test bodies — both in-plan via Plan 30-02 Task 3)
- [x] No watch-mode flags
- [x] Feedback latency < 60s (full suite ~30–60s)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** signed off — nyquist-compliant; Wave 0 satisfied in-plan (Plan 30-02 Task 3).
