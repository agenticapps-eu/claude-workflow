---
phase: 30
slug: split-03-claude-workflow-2-0-0-follow-up
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| 30-02-* | 02 | 2 | D-07 (#58 hook) | — | deterministic stop gate | suite | `bash migrations/run-tests.sh` (phase-sentinel test) | ❌ W0 | ⬜ pending |
| 30-03-* | 03 | 3 | D-05/D-06 (refs + UPGRADING) | — | N/A | grep | `! grep -rn add-observability <non-immutable files>` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky · Final plan/task IDs assigned by planner.*

---

## Wave 0 Requirements

- [ ] New `test_phase_sentinel_*` body in `migrations/run-tests.sh` — asserts the deterministic `phase-sentinel.sh` is installed and the prompt-type Hook 3 is gone (D-07).
- [ ] New `test_migration_0022_*` body — asserts repoint (`observability` skill grep replaces `add-observability`), abort-if-absent message, `to_version: 2.0.0`.
- [ ] Drift-test guard (existing in run-tests.sh) — must stay green after deletions + 0022 add.

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

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (new 0022 + phase-sentinel test bodies)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
