---
phase: 27
slug: 1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-02
---

# Phase 27 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `27-RESEARCH.md` § Validation Architecture (Nyquist signal table).
> Scope is doc/tooling/worker-template — most deliverables verify via `grep`/`diff`/`test -f`
> plus the existing worker-template + migration drift harnesses. No new framework required.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (openrouter-monitor + supabase-edge templates) + bash harness (`run-template-tests.sh`, `migrations/run-tests.sh`) + `go test` (go-fly template) |
| **Config file** | `add-observability/templates/openrouter-monitor/` (vitest); none for bash harnesses |
| **Quick run command** | `bash add-observability/templates/run-template-tests.sh` (worker templates) |
| **Full suite command** | `bash add-observability/templates/run-template-tests.sh && bash migrations/run-tests.sh` |
| **Estimated runtime** | ~60–120 seconds |

---

## Sampling Rate

- **After every task commit:** Run the deliverable-specific check (`grep`/`diff`/`test -f`, or the affected template's vitest run)
- **After every plan wave:** Run `bash add-observability/templates/run-template-tests.sh`
- **Before `/gsd-verify-work`:** Full suite must be green — including `bash migrations/run-tests.sh` drift test (A2: SKILL.md stays 1.20.0, drift PASS)
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

> Task IDs are assigned by the planner (this strategy precedes PLAN.md). Each WR/doc deliverable
> below maps to its observable Nyquist signal from RESEARCH.md. The planner MUST attach an
> `<automated>` verify to every task implementing these, or declare a Wave 0 dependency.

| Deliverable | Wave | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|------|------------|-----------------|-----------|-------------------|-------------|--------|
| WR-01 (go-test counter) | 1 | — | N/A | grep | CONTENT-BASED: exactly 4 `\|\| echo "0"` lines, all `grep -oE`; zero `grep -c … \|\| echo "0"`; 633-634 use `\|\| true` (immune to line-number shifts) | ✅ | ⬜ pending |
| WR-02 (`_resetForTest()` in finally) | 1 | — | test isolation, no state bleed | unit | `bash add-observability/templates/run-template-tests.sh` (supabase-edge GREEN) + grep `_resetForTest` | ✅ | ⬜ pending |
| WR-03 (buildSentryOptions coverage ×3) | 1 | — | N/A | unit (coverage + local sensitivity proof) | template vitest exit 0; each of the 3 named test files has a `describe("buildSentryOptions"` block; assertions per RESEARCH Blocker-C; no committed false assertion | ✅ | ⬜ pending |
| WR-04 (entry uses helper; byte-symmetry) | 2 | T-27-redaction* | REDACTED_KEYS path preserved via shared helper | unit + diff | grep `buildSentryOptions(env)` in `src/index.ts`; no hardcoded `tracesSampleRate: 0.1`; snapshot-before vs after UNCHANGED by WR-04 (NOT raw `diff -q` empty — pair is token-substituted with known drift) | ✅ | ⬜ pending |
| PROJECT.md | 1 | — | N/A | file | `test -f .planning/PROJECT.md` + required sections present | ✅ | ⬜ pending |
| Boundary ADR-0035 | 1 | — | N/A | file+grep | `test -f docs/decisions/0035-*.md`; `grep '# SHARED\|# WORKFLOW' migrations/run-tests.sh` | ✅ | ⬜ pending |
| Version A2 (tag + CHANGELOG) | 2 | — | N/A | drift | `bash migrations/run-tests.sh` drift test PASS (SKILL.md unchanged at 1.20.0); CHANGELOG has `## [1.21.0]` | ✅ | ⬜ pending |
| STATE/ROADMAP drift refresh | 1 | — | N/A | grep | Phase 26 marked merged; stale "Next action" line corrected | ✅ | ⬜ pending |

*WR-04 byte-symmetry preserves the auth-header redaction path (REDACTED_KEYS) — the only security-adjacent surface; full redaction fix (DEF-1/DEF-2) is deferred per CONTEXT.

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] WR-03 sensitivity (NOT strict TDD — codex review): prove the new `buildSentryOptions` tests are non-vacuous via a TEMPORARY, uncommitted local mutation of the helper (the failing run is the §06 evidence), then revert. No deliberately-false assertion is committed. No new framework — vitest already present in the openrouter-monitor template.

*All other deliverables verify against existing infrastructure (worker-template harness, migration drift test, file/grep checks).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| git tag `v1.21.0` created | Version A2 | Tag creation is a release action, not a test | `git tag` lists `v1.21.0` after ship; confirm points at the 1.21.0 commit |
| SPLIT-00 / SPLIT-01 doc correctness (pin-by-tag, gsd-tools premise correction) | D-07c / B1 | Prose accuracy is judgment, not grep-checkable | Read updated SPLIT-00 (pin-by-tag) + SPLIT-01 correction note |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] WR-03 sensitivity proof captured (uncommitted local mutation, reverted); no committed false assertion
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
