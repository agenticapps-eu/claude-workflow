---
phase: 29
slug: split-02-agenticapps-observability
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-02
---

# Phase 29 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `29-RESEARCH.md` § Validation Architecture. The new obs repo has NO test
> infrastructure at phase start — almost everything is a Wave 0 gap (the repo doesn't exist yet).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash (`migrations/run-tests.sh`, sourcing `vendor/agenticapps-shared/migrations/lib/*.sh`) + vitest (per-stack template tests) |
| **Config file** | `migrations/run-tests.sh` in the NEW obs repo — **Wave 0 creates it** (source-and-keep shim, obs-specific SKILL.md path at repo root) |
| **Quick run command** | `bash migrations/run-tests.sh 0019` / `0021` / `0022` (filter to migration under test) |
| **Full suite command** | `bash migrations/run-tests.sh` (in `~/Sourcecode/agenticapps/agenticapps-observability`) |
| **Estimated runtime** | ~60–120s full suite (17 existing fixtures + new 0022 + drift) |

---

## Sampling Rate

- **After every task commit:** Run `bash migrations/run-tests.sh <migration_id>` (filtered)
- **After every plan wave:** Run `bash migrations/run-tests.sh` (full obs suite)
- **Before `/gsd-verify-work`:** Full obs suite green + `/observability *` AND `/add-observability *`
  both resolve + `git log --follow` verified on ≥3 moved files
- **Guard (do NOT regress the source repo):** `bash migrations/run-tests.sh` in **claude-workflow**
  still reports `PASS=186 FAIL=4` (Phase 29 only COPIES out; it must not change claude-workflow).
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

> Planner fills one row per task. Seeds from the research deliverables→verification map:

| Task ID | Plan | Wave | Deliverable | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 29-01-xx | 01 | 1 | Repo + submodule | — | no `--force`; user-gated push | smoke | `gh repo view agenticapps-eu/agenticapps-observability --json url,visibility && git submodule status` | ❌ W0 | ⬜ pending |
| 29-02 | 02 | 2 | History — SKILL.md | — | N/A | smoke | `git log --follow --oneline -- SKILL.md \| head -5` | ❌ W0 | ⬜ pending |
| 29-02 | 02 | 2 | History — migrate-0019.sh | — | N/A | smoke | `git log --follow --oneline -- migrations/scripts/migrate-0019.sh \| head -3` | ❌ W0 | ⬜ pending |
| 29-03 | 03 | 3 | 0019 suite GREEN (13) | T-V5 | quoted paths | integration | `bash migrations/run-tests.sh 0019` → PASS=13 | ❌ W0 | ⬜ pending |
| 29-03 | 03 | 3 | 0021 suite GREEN (4) | T-V5 | quoted paths | integration | `bash migrations/run-tests.sh 0021` → PASS=4 | ❌ W0 | ⬜ pending |
| 29-04 | 04 | 4 | 0022 suite GREEN (new) | T-V5 | heredoc untrusted content | integration | `bash migrations/run-tests.sh 0022` → GREEN | ❌ W0 | ⬜ pending |
| 29-05 | 05 | 5 | Drift test PASS | — | correct obs SKILL.md path | integration | `bash migrations/run-tests.sh` → drift PASS | ❌ W0 | ⬜ pending |
| 29-03 | 03 | 3 | SKILL renamed | — | N/A | unit | `grep "^name: observability" SKILL.md && grep "^version: 0.11.0" SKILL.md` | ❌ W0 | ⬜ pending |
| 29-03 | 03 | 3 | `/observability` resolves | T-symlink | clobber-guard | smoke | `test -L ~/.claude/skills/observability && test -f ~/.claude/skills/observability/SKILL.md` | ❌ W0 | ⬜ pending |
| 29-03 | 03 | 3 | `/add-observability` alias resolves | T-symlink | clobber-guard | smoke | `test -L ~/.claude/skills/add-observability && test -f ~/.claude/skills/add-observability/SKILL.md` | ❌ W0 | ⬜ pending |
| 29-04 | 04 | 4 | Strict-Env generic NOT regressed (SC5/ADR-0032) | — | N/A | typecheck | `cd templates/ts-cloudflare-worker && npx vitest run cron-monitor.test.ts` | ❌ W0 | ⬜ pending |
| 29-04 | 04 | 4 | Immediate-flush regression test (FXSA-WORKERS-6) | — | N/A | unit | `cd templates/ts-cloudflare-worker && npx vitest run cron-monitor.test.ts` (new case) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New repo `agenticapps-eu/agenticapps-observability` created + `vendor/agenticapps-shared` submodule @ v1.0.0
- [ ] `migrations/run-tests.sh` — obs shim (source-and-keep; obs SKILL.md path = repo root, NOT `skill/SKILL.md`)
- [ ] `migrations/0022-*.md` + `migrations/scripts/migrate-0022.sh` — new deferred-fix migration
- [ ] `migrations/test-fixtures/0022/` — fixtures for the new migration (incl. immediate-flush regression + #61 types.d.ts real shape)
- [ ] `legacy/SKILL.md` — `add-observability` deprecation alias
- [ ] `install.sh` — dual-symlink install (with clobber-guard mirrored from claude-workflow install.sh:88-95)
- [ ] `vitest` available per stack: `cd templates/<stack> && npm install`

*The 0019 (13) + 0021 (4) fixtures are MOVED (not authored) — they arrive green via filter-repo.*

---

## Manual-Only Verifications

| Behavior | Why Manual | Test Instructions |
|----------|------------|-------------------|
| Slash commands fire in a fresh Claude Code after install | Skill-loader cache is client-side; not scriptable from the repo | Run `install.sh`, reload skills, type `/observability` and `/add-observability` — both list/resolve |
| GitHub repo visibility/push landed | Outward-facing, user-gated (`autonomous: false`) | `gh repo view` + confirm push after the checkpoint |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags (vitest uses `run`, not watch)
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter (planner sets after filling the map)

**Approval:** pending
