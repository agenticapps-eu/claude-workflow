---
phase: 25
slug: fix-0019-engine-and-cron-wrappers
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-31
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from RESEARCH.md §"Validation Architecture" (researcher confirmed framework, sampling rates, and per-decision test map).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (TS templates)** | `vitest ^3.0.0` (harness-pinned at `add-observability/templates/run-template-tests.sh:174`); test files: `*.test.ts` per stack dir |
| **Framework (engine fixtures)** | bash + harness (`migrations/run-tests.sh`); fixture dirs under `migrations/test-fixtures/0019/` and (new) `migrations/test-fixtures/0021/` |
| **Framework (Go)** | `go test` — not exercised this phase (D-12 — no `queue_monitor.go` ships) |
| **Config files** | `add-observability/templates/run-template-tests.sh` (writes ephemeral `tsconfig.json` + `vitest.config.ts` per stack); `migrations/run-tests.sh` (dispatcher) |
| **Quick run command (per stack)** | `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker` |
| **Full suite command** | `bash add-observability/templates/run-template-tests.sh all && bash migrations/run-tests.sh` |
| **Estimated runtime** | ~2-3 min full suite (existing ~466 PASS + ~21 new = ~487 PASS target) |

> **Critical harness caveat (researcher Pitfall 4):** the template harness writes `tsconfig.json` with `skipLibCheck: true`. Sentry-type compatibility (the WHOLE POINT of D-03) is NOT asserted at typecheck time by the harness. D-16 tests MUST include an explicit `const _check: Sentry.MonitorConfig['schedule'] = ourSchedule` pattern as the firewall.

---

## Sampling Rate

- **After every task commit:** Run touched test file directly: `npx vitest run <stack>/<file>.test.ts` (sub-30-second feedback) OR `bash migrations/run-tests.sh test_migration_0019_<fixture_name>` for engine work.
- **After every plan wave:** Run per-stack suite: `bash add-observability/templates/run-template-tests.sh <stack>` (~1-2 min) + targeted `bash migrations/run-tests.sh test_migration_0019_*` (~30s).
- **Before `/gsd-verify-work`:** Full suite green AND the new D-18 synthetic strict-Env typecheck fixture compiles with `tsc --noEmit`.
- **Max feedback latency:** 30s per touched file, 2 min per wave, 5 min full suite.

---

## Per-Task Verification Map

> Tasks below are illustrative — actual task IDs assigned during planning. Wave numbers map to RESEARCH.md §"Summary" 5-wave recommendation.

| Task ID (illustrative) | Plan | Wave | Decision | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|----------|------------|-----------------|-----------|-------------------|-------------|--------|
| 25-W0-01 | ADRs + Wave 0 fixtures | 0 | D-01, D-05, D-07 | — | N/A (docs) | grep | `test -f docs/decisions/0031-*.md && test -f docs/decisions/0032-*.md && test -f docs/decisions/0033-*.md` | ❌ W0 | ⬜ pending |
| 25-W0-02 | Engine RED fixtures | 0 | D-15 | T-25-04 (engine writes to attacker-controlled dir) | Engine SKIP_UNSUPPORTED on stray index.ts | bash fixture | `bash migrations/run-tests.sh test_migration_0019_08_index_ts_anchored_worker` | ❌ W0 | ⬜ pending |
| 25-W0-03 | Engine RED — pages variant | 0 | D-15 | — | N/A | bash fixture | `bash migrations/run-tests.sh test_migration_0019_09_index_ts_anchored_pages` | ❌ W0 | ⬜ pending |
| 25-W0-04 | Engine RED — negative (stray) | 0 | D-15 (Pitfall 1) | T-25-04 | SKIP_UNSUPPORTED when middleware.ts co-anchor missing | bash fixture | `bash migrations/run-tests.sh test_migration_0019_11_stray_index_ts_no_co_anchor` | ❌ W0 | ⬜ pending |
| 25-W0-05 | queue-monitor RED tests × 3 stacks | 0 | D-17 | T-25-02 (slug injection via batch.queue) | Sentry server-side validates slug; wrapper trusts Cloudflare platform | TS mock | `npx vitest run add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts` (and pages/supabase-edge) | ❌ W0 | ⬜ pending |
| 25-W0-06 | Synthetic strict-Env fixture | 0 | D-18, SC5 | — | N/A | TS typecheck | `tsc --noEmit -p migrations/test-fixtures/0019/10-strict-env-typecheck/tsconfig.json` | ❌ W0 | ⬜ pending |
| 25-W1-01 | Engine fix — find + classify | 1 | D-01 | T-25-04 | Pre-classify filter (sibling middleware.ts co-anchor) | bash fixture (W0 GREEN-flip) | re-run W0-02, W0-03, W0-04 | ✅ post-W0 | ⬜ pending |
| 25-W1-02 | Engine fix — resolve_anchor_files helper | 1 | D-01 | — | N/A | bash fixture | re-run all existing 0019 fixtures (01-07) | ✅ | ⬜ pending |
| 25-W2-01 | cron-monitor.ts D-03 + D-05 × 4 sites | 2 | D-03, D-05, D-21 | T-25-03 (Guarded Shape A) | handlerStarted flag preserves cron-always-runs invariant | TS mock | per-stack vitest + diff check on openrouter-monitor copy | ✅ | ⬜ pending |
| 25-W2-02 | Type-level firewall assertions | 2 | D-16 | — | skipLibCheck workaround | TS @ts-expect-error + Sentry.MonitorConfig pin | per-stack vitest | ✅ | ⬜ pending |
| 25-W3-01 | queue-monitor.ts × 3 TS stacks | 3 | D-07, D-08, D-09 | T-25-02, T-25-03 | Sentry slug validation + Guarded Shape A | TS mock (W0 GREEN-flip) | re-run W0-05 | ✅ post-W0 | ⬜ pending |
| 25-W4-01 | Migration 0019 in-place engine update | 4 | D-02a, D-11 | T-25-04 | Engine excludes node_modules/.git/dist (existing safeguard) | bash fixture | re-run all 0019 fixtures | ✅ | ⬜ pending |
| 25-W4-02 | Migration 0019.md docs amendment | 4 | D-02a | — | N/A | grep | `grep -c "Recovery" migrations/0019-sentry-crons-and-healthz.md` >= 1 | ✅ | ⬜ pending |
| 25-W4-03 | Migration 0021 — new file + engine | 4 | D-02b | T-25-04 | Same engine safeguards as 0019 | bash fixture | `bash migrations/run-tests.sh test_migration_0021_01_fresh_1.19.0_apply` | ❌ W0 | ⬜ pending |
| 25-W5-01 | Version bumps + CHANGELOG | 5 | D-13, D-14 | — | N/A | grep | `grep -F "1.20.0" CHANGELOG.md` + version file diffs | ✅ | ⬜ pending |
| 25-W5-02 | GitHub linkback per finding | 5 | SC7 | — | N/A | gh API | `gh issue view 56` shows resolution comments | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `migrations/test-fixtures/0019/08-index-ts-anchored-worker/{setup.sh, verify.sh, expected-exit}` — D-01 cf-worker fixture (RED until W1-01 ships)
- [ ] `migrations/test-fixtures/0019/09-index-ts-anchored-pages/{setup.sh, verify.sh, expected-exit}` — D-01 cf-pages fixture (RED until W1-01)
- [ ] `migrations/test-fixtures/0019/10-strict-env-typecheck/{tsconfig.json, env.ts, smoke.ts, expected-exit}` — D-18 SC5 fixture (RED until W2-01 + W3-01 ship)
- [ ] `migrations/test-fixtures/0019/11-stray-index-ts-no-co-anchor/{setup.sh, verify.sh, expected-exit}` — Pitfall 1 negative fixture (asserts SKIP_UNSUPPORTED)
- [ ] `migrations/test-fixtures/0021/01-fresh-1.19.0-apply/{setup.sh, verify.sh, expected-exit}` — D-02b fresh-apply fixture (RED until W4-03)
- [ ] `add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts` — Wave 0 RED stub (mocks + assertions; implementation lands W3-01)
- [ ] `add-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts` — Wave 0 RED stub
- [ ] `add-observability/templates/ts-supabase-edge/queue-monitor.test.ts` — Wave 0 RED stub
- [ ] `docs/decisions/0031-0019-engine-index-ts-anchor.md` — D-01 ADR (researcher skeleton in RESEARCH.md §"Code Examples Example 3")
- [ ] `docs/decisions/0032-cron-monitor-generic-narrowing.md` — D-05 ADR
- [ ] `docs/decisions/0033-with-queue-monitor.md` — D-07 ADR
- [ ] `migrations/run-tests.sh` dispatcher entries for new fixtures (08, 09, 10, 11, 0021/01) — verify naming convention via Phase 23's `test-sigterm-mid-apply-preserves-state` precedent

*Framework install:* None required — `vitest`, `bash`, `awk`, `sha256sum`/`shasum`, `node`/`npm` all installed per RESEARCH.md §"Environment Availability".

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GitHub linkback comments on issue #56 per finding | SC7 | API write; rate-limited | After execution, post 4 short comments on #56 referencing each finding's resolution: F1 → engine fix (D-01) + ADR-0031, F2 → D-03 + ADR-0032, F3 → D-05 + ADR-0032, F4 → D-07 + ADR-0033. Use `gh issue comment 56 -b "..."`. |
| Visual diff openrouter-monitor copy vs cf-worker copy | D-21 | One-shot byte equality check | `diff add-observability/templates/ts-cloudflare-worker/cron-monitor.ts add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` should return empty. |
| Migration 0019.md "Recovery" section human-readable | D-02a | Docs quality not grep-able | Manual read by reviewer; verify the recovery steps actually work end-to-end against a v1.18.0+ test project. |
| callbot adoption (proxy via #56 acceptance check) | SC5 | Downstream consumer-side work | Separate PR against callbot repo post-merge; not gated by Phase 25 VERIFICATION. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies (15 of 16 illustrative tasks above; SC7 linkback is the one manual)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (Wave 0 + W1 + W2 + W3 + W4 each have multiple automated tasks)
- [ ] Wave 0 covers all MISSING references (11 W0 deliverables enumerated above)
- [ ] No watch-mode flags (vitest invoked via `vitest run`, not `vitest`)
- [ ] Feedback latency < 30s per task, < 2 min per wave, < 5 min full suite
- [ ] `nyquist_compliant: true` to be set in frontmatter after Wave 0 deliverables ship

**Approval:** pending (will flip to `nyquist_compliant: true` once Wave 0 lands)
