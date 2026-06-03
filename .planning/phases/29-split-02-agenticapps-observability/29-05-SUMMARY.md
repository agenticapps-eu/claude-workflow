---
phase: 29-split-02-agenticapps-observability
plan: 05
subsystem: infra
tags: [repo-split, verification, git-tag, ship, drift-test, ship-gate]

# Dependency graph
requires:
  - phase: 29-04
    provides: "Feature branch split-02-rename-and-0022, MIGRATIONS_VERSION 1.21.0, full suite PASS=42 XFAIL=4 FAIL=0"
provides:
  - "Full obs suite ship-gate PASS: FAIL=0, XFAIL=4 (documented), exit 0"
  - "Consumer-axis drift PASS: MIGRATIONS_VERSION 1.21.0 == 0022 to_version 1.21.0"
  - "claude-workflow baseline guard PASS: 186/4 unchanged"
  - "CHANGELOG.md finalized with 0022 + ADR-0036 + FIX-0017 follow-up note"
  - "Feature branch split-02-rename-and-0022 ready to PR → main"
  - "Checkpoint: PR open + merge + tag v0.11.0 + push GATED (human approval required)"
affects:
  - 30 (Phase 30: cw cleanup + 2.0.0 tag — NOT this plan)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Ship-gate semantics: FAIL=0 (unexpected) + XFAIL=4 (documented) = green gate"
    - "Consumer-axis drift test: MIGRATIONS_VERSION 1.21.0 == latest migration to_version 1.21.0"
    - "Dual-symlink install verified under isolated mktemp HOME (operator env untouched)"

key-files:
  created: []
  modified:
    - "~/Sourcecode/agenticapps/agenticapps-observability/CHANGELOG.md (0022 + ADR-0036 + FIX-0017 follow-up)"

key-decisions:
  - "All verification (Tasks 1+2) passed — no blockers; proceeding to gated ship checkpoint"
  - "CHANGELOG date kept at 2026-06-02 (plan-specified ship date; already in file)"
  - "PR merge strategy: --merge (not rebase) to preserve filter-repo git log --follow lineage on main"

requirements-completed: []

# Metrics
duration: ~25min (Tasks 1+2 + CHANGELOG; Task 3 gated)
completed: 2026-06-03
---

# Phase 29 Plan 05: Verification + Ship Gate + CHANGELOG — Summary

**Full obs suite passes ship gate (FAIL=0, XFAIL=4 documented, exit 0); consumer-axis drift PASS (1.21.0==1.21.0); claude-workflow baseline 186/4 unchanged; CHANGELOG finalized. Merge + tag v0.11.0 + push GATED at checkpoint awaiting human approval.**

## Task 1: Full obs suite (ship-gate semantics) + drift + history + dual-skill

### Per-Migration Results

| Migration | Expected | Actual | Result |
|-----------|----------|--------|--------|
| 0012 | PASS=5 | PASS=5 | PASS |
| 0013 | PASS=5 | PASS=5 | PASS |
| 0017 | PASS=7 XFAIL=4 FAIL=0 | PASS=7 XFAIL=4 FAIL=0 | PASS (ship gate: XFAIL documented) |
| 0018 | PASS=2 | PASS=2 | PASS |
| 0019 | PASS=13 | PASS=13 | PASS |
| 0021 | PASS=4 | PASS=4 | PASS |
| 0022 | PASS=5 | PASS=5 | PASS |
| **Full suite** | FAIL=0, XFAIL=4, exit 0 | PASS=42, FAIL=0, XFAIL=4, exit 0 | **SHIP GATE: PASS** |

### 0017 XFAIL Detail

`OBS_XFAIL_0017="02 06 10 11"` — 4 known FIX-0017-ENGINE fixtures:
- `02-fresh-apply-fxsa-shape` — unsubstituted token / engine bug
- `06-no-claudemd` — anchor failure
- `10-fresh-apply-worker-env` — engine bug
- `11-prettier-style-clean-applies` — engine bug

These are XFAIL (NOT FAIL). None unexpectedly passed. FIX-0017-ENGINE is an obs-repo follow-up phase.

### Drift Test (Consumer Axis)

```
PASS: test-migrations-version-marker-matches-latest-migration-to-version
```

- `migrations/MIGRATIONS_VERSION`: `version: 1.21.0`
- Latest migration (0022) `to_version`: `1.21.0`
- Comparison: `1.21.0 == 1.21.0` → **PASS**
- Drift does NOT compare against the obs product version (0.11.0) — the two axes are independent and correct.

### Version Axes (Both Correct and Separate)

- Consumer migration axis: `migrations/MIGRATIONS_VERSION` = `version: 1.21.0` — VERIFIED
- Obs product axis: `SKILL.md` `version: 0.11.0` — VERIFIED

### Git History Preservation

`git log --follow --oneline` confirmed on 3 files:

| File | Pre-extraction commits visible |
|------|-------------------------------|
| `SKILL.md` | 5 (344ae7a, 5549970, d05f98c, 4cd50d7, ...) |
| `migrations/scripts/migrate-0019.sh` | 3 (344ae7a, 5549970, 8d45c7c) |
| `migrations/test-fixtures/0019/01-fresh-apply` | 3 (a736fc2, 5549970, 8d45c7c) |

All show pre-extraction commits from the original claude-workflow history — `git log --follow` lineage preserved.

### Dual-Skill Installation (Isolated HOME)

```bash
T="$(mktemp -d)"; HOME="$T" bash install.sh
```

- `$T/.claude/skills/observability` → symlink → obs repo root, `SKILL.md` present: **OK**
- `$T/.claude/skills/add-observability` → symlink → `$REPO/legacy`, `SKILL.md` present: **OK**
- Operator's real `~/.claude/skills` untouched: **CONFIRMED**
- Install exit code: 0

## Task 2: claude-workflow Baseline Guard

```
PASS: 186  FAIL: 4
```

- Confirmed unchanged at PASS=186 FAIL=4 (the 4 known pre-existing failures)
- `git status --short add-observability/ migrations/` in claude-workflow: NO MODIFICATIONS
- Source repo regression: **NONE**

## Task 3: CHANGELOG Finalized + Feature Branch Ready (SHIP GATED)

### CHANGELOG Update (commit `d3c6a6a`)

Updated `CHANGELOG.md` on feature branch `split-02-rename-and-0022`:
- Added migration 0022 entry: explicit per-checkin flush (FX-SIGNALS-WORKERS-6), `monitorConfig` on every check-in (#61), real `@sentry/cloudflare` types in fixture 04, FXSA-WORKERS-6 marker reconciliation, ADR-0036
- Documented FIX-0017 XFAIL ship-gate semantics: `FAIL=0`, `XFAIL=4` (documented, non-blocking), tracked as obs-repo follow-up phase
- Corrected impl-agnostic refactor entry: deferred to 0.12.0 (not in scope for 0.11.0 extraction release)

### Acceptance criterion verified:
`grep -q "0022\|ADR-0036" CHANGELOG.md` → **OK**

### Feature Branch State

Branch `split-02-rename-and-0022` is local (NOT yet pushed). Commits ready:

```
d3c6a6a docs: finalize 0.11.0 changelog (migration 0022 + ADR-0036; FIX-0017 follow-up noted)
24c13c2 feat(29-04): migration 0022 (1.20.0->1.21.0) + engine + fixtures + ADR-0036 (#61 in 0022 fixtures)
eaa1254 feat(29-04): explicit per-checkin flush in cron-monitor + queue-monitor (FX-SIGNALS-WORKERS-6)
c6f162c test(29-04): rewrite cron + queue monitor tests to captureCheckIn+flush contract + immediate-flush regression
a736fc2 feat(29-03): add migrations/run-tests.sh shim + MIGRATIONS_VERSION + repoint engine paths
bf29611 feat(29-03): add install.sh with dual-symlink + clobber-guard + submodule sync
1db748e feat(29-03): rename skill add-observability → observability 0.11.0 + legacy alias
```

### GATED: PR + Merge + Tag + Push Commands

The following outward-facing actions are prepared but NOT yet executed. They require human approval:

```bash
cd ~/Sourcecode/agenticapps/agenticapps-observability

# Sanity: confirm feature branch
git rev-parse --abbrev-ref HEAD    # must be split-02-rename-and-0022

# Push the feature branch (plain push — NO --force)
git push -u origin split-02-rename-and-0022

# Open PR against obs main
gh pr create --repo agenticapps-eu/agenticapps-observability \
  --base main --head split-02-rename-and-0022 \
  --title "SPLIT-02: skill rename + migration 0022 (cron-flush + #61) — v0.11.0" \
  --body "Skill rename add-observability -> observability, dual-symlink legacy alias, source-and-keep migration runner shim (all moved bodies 0012/0013/0017/0018/0019/0021 carried; 0017 4-fixture XFAIL for FIX-0017 follow-up), migration 0022 (explicit per-check-in flush, FX-SIGNALS-WORKERS-6 + #61 types.d.ts in 0022 fixtures, queue-monitor flush in both CF stacks) + ADR-0036. Ship gate: FAIL=0, XFAIL=4 documented; consumer-axis drift PASS (0022 to_version 1.21.0 == MIGRATIONS_VERSION 1.21.0). claude-workflow baseline 186/4 unchanged.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

# --- HUMAN GATE: After PR review + approval, merge + tag: ---

# Merge PR to main (--merge preserves filter-repo lineage)
gh pr merge --repo agenticapps-eu/agenticapps-observability split-02-rename-and-0022 --merge --delete-branch=false
git checkout main
git pull --ff-only origin main

# Tag v0.11.0 ON MAIN (the merged commit), annotated
git tag -a v0.11.0 -m "agenticapps-observability v0.11.0 — extraction + rename + migration 0022 (SPLIT-02)"

# Push tag (plain — NO --force)
git push origin v0.11.0
```

**Safety: NEVER `--force`. Merge strategy `--merge` (not rebase) to preserve `git log --follow` lineage from filter-repo on main. Tag lands on merged main commit.**

## Deviations from Plan

None — plan executed exactly as written. All Tasks 1 and 2 passed on first run; CHANGELOG updated per plan spec; Task 3 outward-facing actions prepared but gated as required by `autonomous: false`.

## Known Stubs

None — all verification gates passed; no placeholder data.

## Threat Flags

None. All threat mitigations confirmed:
- T-29-20: `--force` not used; push is gated (human approval required)
- T-29-21: claude-workflow baseline confirmed 186/4 unchanged; no source-repo modification
- T-29-22: drift PASS on consumer axis (1.21.0==1.21.0); product axis 0.11.0 separate + correct
- T-29-23: No claude-workflow PR/tag created (Phase 30 scope only)
- T-29-24: Feature branch `split-02-rename-and-0022` merges via PR (not direct to main); PR gated
- T-29-29: Ship gate FAIL=0, XFAIL=4 documented; no hidden failures
- T-29-30: Install verified under `mktemp -d` HOME; real `~/.claude/skills` untouched

## Pending (Phase 30 + FIX-0017)

- **Phase 30 (SPLIT-03):** delete `add-observability/` from claude-workflow; repoint install migration 0011; manage alias deprecation window; ship claude-workflow 2.0.0
- **FIX-0017 obs follow-up:** fix the 4 engine bugs tracked by XFAIL fixtures 02/06/10/11 in obs repo

## Self-Check

| Claim | Check |
|-------|-------|
| Feature branch `split-02-rename-and-0022` | `git rev-parse --abbrev-ref HEAD` → split-02-rename-and-0022 — OK |
| 0012 PASS=5 | bash migrations/run-tests.sh 0012 → PASS: 5 — OK |
| 0013 PASS=5 | bash migrations/run-tests.sh 0013 → PASS: 5 — OK |
| 0017 PASS=7 XFAIL=4 FAIL=0 | bash migrations/run-tests.sh 0017 → PASS: 7, XFAIL: 4 — OK |
| 0018 PASS=2 | bash migrations/run-tests.sh 0018 → PASS: 2 — OK |
| 0019 PASS=13 | bash migrations/run-tests.sh 0019 → PASS: 13 — OK |
| 0021 PASS=4 | bash migrations/run-tests.sh 0021 → PASS: 4 — OK |
| 0022 PASS=5 | bash migrations/run-tests.sh 0022 → PASS: 5 — OK |
| Full suite PASS=42 FAIL=0 XFAIL=4 exit 0 | bash migrations/run-tests.sh → confirmed — OK |
| Drift PASS (consumer axis) | `PASS: test-migrations-version-marker-matches-latest-migration-to-version` — OK |
| MIGRATIONS_VERSION = 1.21.0 | `grep -x "version: 1.21.0" migrations/MIGRATIONS_VERSION` — OK |
| SKILL.md version = 0.11.0 | `grep "^version: 0.11.0" SKILL.md` — OK |
| History on SKILL.md | `git log --follow --oneline -- SKILL.md | wc -l` ≥ 5 — OK |
| History on migrate-0019.sh | 3 commits — OK |
| History on fixture 0019/01 | 3 commits — OK |
| Dual-skill under isolated HOME | observability + add-observability symlinks + SKILL.md — OK |
| Operator real ~/.claude/skills untouched | mktemp HOME only — OK |
| claude-workflow 186/4 | PASS=186 FAIL=4 confirmed — OK |
| claude-workflow no source modifications | git status clean on add-observability/ migrations/ — OK |
| CHANGELOG has 0022 + ADR-0036 | grep -q "0022\|ADR-0036" CHANGELOG.md — OK |
| CHANGELOG commit `d3c6a6a` | git log — OK |
| No cw PR / tag created | Not performed (Phase 30 scope) — OK |

## Self-Check: PASSED
