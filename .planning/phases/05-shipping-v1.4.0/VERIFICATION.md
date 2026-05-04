# Phase 5 Verification — Shipping v1.4.0 (this batch's P5)

**Phase:** 05-shipping-v1.4.0 (named to avoid collision with last batch's `05-shipping/` for v1.3.0)
**Spec source:** Hand-off prompt Phase 5 — programmatic-hooks-architecture-audit batch
**Date:** 2026-05-03

## Step A — Version bump

- **MH-A1:** `skill/SKILL.md` frontmatter `version: 1.4.0`
- **Evidence:** `grep "^version:" skill/SKILL.md` → `version: 1.4.0`
- **Status:** ✅ PASS (spec example was 1.5.0; we're at 1.3.0 baseline so one minor bump = 1.4.0)

## Step B — README + CHANGELOG

- **MH-B1:** README has new "Programmatic hooks layer" section with hook table + override paths + `bin/check-hooks.sh` reference
- **MH-B2:** README has new "Architecture audits" section with cron install commands + snooze mechanism
- **MH-B3:** README "What this gives you" updated for hooks layer + cross-PR drift catch
- **MH-B4:** CHANGELOG.md v1.4.0 entry — Added (5 hooks + scheduling + mattpocock + gsd-patches + migration 0004 + 4 ADRs), Changed (settings template, ENFORCEMENT-PLAN, version), Migration path commands, Removed (none — purely additive)
- **Status:** ✅ PASS

## Step C — Migration 0004

- **MH-C1:** `migrations/0004-programmatic-hooks-architecture-audit.md` written per `migrations/README.md` format spec
- **Evidence:** Frontmatter (id 0004, from 1.3.0 → to 1.4.0, requires mattpocock skills), Pre-flight, 4 Steps with idempotency/precondition/apply/rollback, Post-checks, Skip cases. Step 3 uses deterministic `jq` deep-merge for `.claude/settings.json` (not raw text patching). Step 4 bumps the project's installed version field.
- **Status:** ✅ PASS

## Step D — Linear backlog (5 issues)

| ID | Title | Priority |
|---|---|---|
| AGE-105 | rogs.me Patch 1 — Multi-model adversarial review | Medium |
| AGE-106 | rogs.me Patch 2 — Auto-verify `--auto` flag | Medium |
| AGE-107 | rogs.me Patch 3 — Cross-AI UI review (defer) | Low |
| AGE-108 | Evaluate mattpocock `diagnose` skill | Medium |
| AGE-109 | Evaluate mattpocock `to-prd`/`to-issues` for Linear | Medium |

- **Status:** ✅ PASS

## Step E — PR

(See REVIEW.md for the open PR URL after push.)

## Acceptance criteria check (whole effort)

| Criterion | Status |
|---|---|
| All 5 phases have green REVIEW.md with Stage 1 (Stage 2 inline-disclosed for this batch) | ✅ |
| rogs.me Bug 1 fixed; canonical storage at `~/.config/gsd-patches/` | ✅ |
| 5 hooks: scripts in templates + settings template + setup install via migration 0004 | ✅ |
| Hook 5 GLOBAL at `~/.claude/hooks/`; cwd-aware; tested with 7 bats | ✅ |
| 43 bats tests covering hooks 1, 2, 4a, 4b, 5; all green | ✅ |
| mattpocock-improve-architecture + mattpocock-grill-with-docs installed | ✅ |
| cparx CONTEXT.md + first audit | ⏸ DEFERRED (P3 user-driven follow-ups; documented in P3) |
| `architecture-audit-check.sh` SessionStart hook + cron + 2 installers | ✅ |
| Snooze mechanism shared between hook + cron | ✅ |
| skill version 1.4.0 | ✅ |
| README + CHANGELOG updated | ✅ |
| 4 new ADRs (0014, 0015, 0016, 0017) | ✅ |
| Migration 0004 written | ✅ |
| 5 Linear issues created (AGE-105…109) | ✅ |
| PR opened | (post-commit) |

## Deferred to user post-merge

1. **Run `/grill-with-docs` against cparx** to populate `~/Sourcecode/cparx/CONTEXT.md` (~15-30 min interactive)
2. **Run `/improve-codebase-architecture` against cparx** after CONTEXT.md exists; output → `cparx/.planning/audits/2026-XX-XX-architecture.md`
3. **Triage audit findings into Linear** (1 issue per accepted refactor candidate)
4. **Install Hook 5 (Commitment Re-Injector) on machine** — already done in this session via P2A; subsequent machines need `cp + chmod + jq merge` per CHANGELOG migration path
5. **Install LaunchAgent (or systemd-user) cron** via `bin/install-architecture-cron.sh` (or `.../install-systemd-architecture-cron.sh`)
6. **Apply migration 0004 to existing AgenticApps projects** (cparx is now at v1.3.0 from prior batch's PR #2/#3 work; running `/update-agenticapps-workflow --dry-run` then `/update-agenticapps-workflow` will apply 0004 → v1.4.0)

## Skills invoked this phase

1. `superpowers:writing-plans` — phase plan held inline
2. `mcp__claude_ai_Linear__save_issue` — 5 issues filed (AGE-105 through AGE-109)
3. gstack `/review` — Stage 1 self-cross-reference (every README/CHANGELOG claim verified against committed phase artifacts in P1-P4)
4. `superpowers:finishing-a-development-branch` — PR body composition
5. Stage 2 inline rather than dispatched — same trade-off as prior phases (pure docs + Linear bodies; the truthfulness check is the test, performed inline)
