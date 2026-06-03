---
phase: 29-split-02-agenticapps-observability
plan: 02
subsystem: infra
tags: [repo-split, git-filter-repo, history-preservation, migration-ownership]

# Dependency graph
requires:
  - phase: 29-01
    provides: "obs repo skeleton on main with agenticapps-shared submodule @ 1f5d543"
provides:
  - "obs repo populated with full observability tree at correct paths (PENDING push)"
  - "git log --follow lineage preserved for SKILL.md (14 commits), migrate-0019.sh (4), fixtures (3+)"
  - "7 migrations moved (0012/0013/0017/0018/0019/0020/0021) per audit; 0011 stayed"
  - "6 ADRs moved (0029-0034); ADR-0035 stayed"
  - "fixtures moved for 0012(5)/0013(5)/0017(11)/0018(2)/0019(13)/0021(4); 0020 .md-only"
  - "Merge commit 24c44c9 on obs main (local — awaiting user-approved push)"
affects:
  - 29-03 (skill rename — can proceed after push approved)
  - 29-04 (deferred-fix migration)
  - 29-05 (verification)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "git filter-repo --path-rename src:dst for whole-file history-preserving extraction"
    - "git merge --allow-unrelated-histories for additive merge of filtered history onto skeleton"
    - "Per-file conflict resolution: --ours for 29-01 root metadata (CHANGELOG.md)"

key-files:
  created:
    - "~/Sourcecode/agenticapps/agenticapps-observability/SKILL.md (from filter-repo)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/scripts/migrate-0017.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/scripts/migrate-0019.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/scripts/migrate-0021.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/scripts/migrate-0017-old-wrappers/"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0012-slash-discovery.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0013-auto-init-and-stale-vendored-cleanup.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0017-add-axiom-logs-destination.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0018-postphase-observability-hook.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0019-sentry-crons-and-healthz.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0020-openrouter-integration.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0021-with-cron-and-queue-updates.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0012/ (5 fixtures)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0013/ (5 fixtures)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0017/ (11 fixtures, 4 XFAIL)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0018/ (2 fixtures)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0019/ (13 fixtures)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0021/ (4 fixtures)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/docs/decisions/0029-0034 (6 ADRs)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/init/, scan/, scan-apply/, enforcement/, templates/ (full obs tree)"
  modified:
    - "~/Sourcecode/agenticapps/agenticapps-observability/CHANGELOG.md (conflict resolved --ours: kept 29-01 skeleton)"

key-decisions:
  - "filter-repo ran ONLY on /tmp/cw-scratch-for-obs (scratch clone of remote) — live claude-workflow untouched"
  - "0021 filename confirmed as 0021-with-cron-and-queue-updates.md (SPLIT-02 doc was wrong)"
  - "0020 moved .md only — no script, no fixtures exist in source (confirmed)"
  - "CHANGELOG.md conflict resolved --ours (kept 29-01 0.11.0 skeleton with provenance trail)"
  - "README.md did NOT conflict (filtered history had no root README.md after hoist — add-observability had no root README)"
  - "Merge commit 24c44c9 created locally; push is PENDING human approval"
  - "Released migration to_versions unchanged: 0021 to_version=1.20.0 verified verbatim"

requirements-completed: []

# Metrics
duration: 5min
completed: 2026-06-03
---

# Phase 29 Plan 02: Extract observability history into obs repo — Summary

**filter-repo extraction complete (scratch clone only). Filtered history merged onto the 29-01 obs skeleton via --allow-unrelated-histories. Single conflict (CHANGELOG.md) resolved per policy (--ours). Merge commit 24c44c9 on local obs main. Awaiting human approval to push.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-03T04:16:34Z
- **Completed:** 2026-06-03T04:21:00Z (checkpoint reached — push pending)
- **Tasks:** 2/3 complete (Task 3 is the push checkpoint — stopped as required)
- **Files modified:** 0 in claude-workflow (scratch clone + obs repo only)

## Accomplishments

- Fresh scratch clone of `claude-workflow` created at `/tmp/cw-scratch-for-obs` (from remote — not local working tree)
- Verified exact path manifest: all 24 source paths confirmed present in git history
- Confirmed exact 0021 filename: `0021-with-cron-and-queue-updates.md` (SPLIT-02 doc had wrong name `0021-cron-monitor-shape-and-queues.md`)
- Confirmed 0020 has NO fixtures and NO migrate-0020 script — .md only (as expected)
- Confirmed fixture counts: 0012=5, 0013=5, 0017=11 (4 XFAIL), 0018=2, 0019=13, 0021=4
- `git filter-repo` run on scratch clone with full path set — 101 commits processed, 29 seconds
- Post-filter verification: SKILL.md at root, all 7 migration .mds present, scripts renamed correctly, 6 test-fixture dirs present, 0011 absent, ADR-0035 absent, run-tests.sh absent
- Released migration frontmatter unchanged: 0021 `to_version: 1.20.0` confirmed verbatim
- `git log --follow -- SKILL.md | head -5` shows pre-extraction commit history (history preserved)
- Obs repo merge: `filtered` remote added, `git merge filtered/main --allow-unrelated-histories --no-edit` executed
- Single conflict: `CHANGELOG.md` (add/add) — resolved with `git checkout --ours CHANGELOG.md` (kept 29-01 skeleton)
- README.md did NOT conflict — no root README.md in filtered history (add-observability dir had none at root after hoist)
- Merge committed as `24c44c9` ("Merge remote-tracking branch 'filtered/main'")
- `filtered` remote removed

## Filter-Repo Command (exact)

```bash
cd /tmp/cw-scratch-for-obs
git filter-repo \
  --path "add-observability/" \
  --path "templates/.claude/scripts/migrate-0017-axiom-destination.sh" \
  --path "templates/.claude/scripts/migrate-0017-old-wrappers/" \
  --path "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh" \
  --path "templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh" \
  --path "migrations/0012-slash-discovery.md" \
  --path "migrations/0013-auto-init-and-stale-vendored-cleanup.md" \
  --path "migrations/0017-add-axiom-logs-destination.md" \
  --path "migrations/0018-postphase-observability-hook.md" \
  --path "migrations/0019-sentry-crons-and-healthz.md" \
  --path "migrations/0020-openrouter-integration.md" \
  --path "migrations/0021-with-cron-and-queue-updates.md" \
  --path "migrations/test-fixtures/0012/" \
  --path "migrations/test-fixtures/0013/" \
  --path "migrations/test-fixtures/0017/" \
  --path "migrations/test-fixtures/0018/" \
  --path "migrations/test-fixtures/0019/" \
  --path "migrations/test-fixtures/0021/" \
  --path "docs/decisions/0029-cron-monitor-sdk-composition.md" \
  --path "docs/decisions/0030-openrouter-integration-sdk-first.md" \
  --path "docs/decisions/0031-0019-engine-index-ts-anchor.md" \
  --path "docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md" \
  --path "docs/decisions/0033-with-queue-monitor.md" \
  --path "docs/decisions/0034-observability-init-singleton-invariant.md" \
  --path-rename "add-observability/:" \
  --path-rename "templates/.claude/scripts/migrate-0017-axiom-destination.sh:migrations/scripts/migrate-0017.sh" \
  --path-rename "templates/.claude/scripts/migrate-0017-old-wrappers/:migrations/scripts/migrate-0017-old-wrappers/" \
  --path-rename "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:migrations/scripts/migrate-0019.sh" \
  --path-rename "templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh:migrations/scripts/migrate-0021.sh"
```

Note: `--path-rename "docs/decisions/:docs/decisions/"` and fixture identity renames (`--path-rename "migrations/test-fixtures/0012/:migrations/test-fixtures/0012/"` etc.) were NOT needed — filter-repo preserves paths that match a `--path` selector without a rename rule (they stay at their original path). Only paths requiring a different target name need `--path-rename`.

## Verified Moved-File List

### Migrations (.md docs)
- `migrations/0012-slash-discovery.md` (MOVE — no script, has 5 fixtures)
- `migrations/0013-auto-init-and-stale-vendored-cleanup.md` (MOVE — no script, has 5 fixtures)
- `migrations/0017-add-axiom-logs-destination.md` (MOVE — has script + 11 fixtures, 4 XFAIL)
- `migrations/0018-postphase-observability-hook.md` (MOVE — no script, has 2 fixtures)
- `migrations/0019-sentry-crons-and-healthz.md` (MOVE — has script + 13 fixtures)
- `migrations/0020-openrouter-integration.md` (MOVE — .md ONLY, no script, no fixtures confirmed absent)
- `migrations/0021-with-cron-and-queue-updates.md` (MOVE — has script + 4 fixtures; CONFIRMED exact filename)

### Migration Scripts (renamed)
- `templates/.claude/scripts/migrate-0017-axiom-destination.sh` → `migrations/scripts/migrate-0017.sh`
- `templates/.claude/scripts/migrate-0017-old-wrappers/` → `migrations/scripts/migrate-0017-old-wrappers/`
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` → `migrations/scripts/migrate-0019.sh`
- `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` → `migrations/scripts/migrate-0021.sh`

### Test Fixtures (with fixture counts)
- `migrations/test-fixtures/0012/` — 5 numbered fixtures + common-setup.sh
- `migrations/test-fixtures/0013/` — 5 numbered fixtures + common-setup.sh
- `migrations/test-fixtures/0017/` — 11 numbered fixtures (fixtures 02, 06, 10, 11 are XFAIL — FIX-0017 obs follow-up) + common-setup.sh + HASHING-NOTE.md + known-wrapper-hashes.json + regen-hashes.sh
- `migrations/test-fixtures/0018/` — 2 numbered fixtures + common-setup.sh
- `migrations/test-fixtures/0019/` — 13 numbered fixtures
- `migrations/test-fixtures/0021/` — 4 numbered fixtures + baselines/ + common-setup.sh

### ADRs Moved
- `docs/decisions/0029-cron-monitor-sdk-composition.md`
- `docs/decisions/0030-openrouter-integration-sdk-first.md`
- `docs/decisions/0031-0019-engine-index-ts-anchor.md`
- `docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md`
- `docs/decisions/0033-with-queue-monitor.md`
- `docs/decisions/0034-observability-init-singleton-invariant.md`

### Confirmed ABSENT (stayed in claude-workflow)
- `migrations/0011-observability-enforcement.md` — STAYS (confirmed present in source, not included in filter)
- `docs/decisions/0035-shared-extraction-boundaries.md` — STAYS (confirmed absent from obs repo)
- `migrations/run-tests.sh` — STAYS (obs shim authored fresh in 29-03)
- `migrations/test-fixtures/0020/` — ABSENT in source (no fixtures exist for 0020)

### Obs Tree at Root (hoisted from add-observability/)
- `SKILL.md` (hoisted from add-observability/SKILL.md — 14 commits of history via --follow)
- `init/INIT.md`, `scan/SCAN.md`, `scan-apply/APPLY.md`, `enforcement/`, `templates/` (all stacks)
- `CHANGELOG.md` (from add-observability/ — CONFLICT resolved, 29-01 skeleton kept via --ours)
- `CONTRACT-VERIFICATION.md`, `openrouter-integration.md`, `uptime-setup-runbook.md`

## git log --follow Evidence (3+ files verified)

```
$ git log --follow --oneline -- SKILL.md | head -5
344ae7a v0.10.0 fix: worker-template hardening...
5549970 v1.20.0 fix(#56): 0019 engine...
d05f98c v1.19.0 feat(add-observability): OpenRouter integration kit...
4cd50d7 v0.7.0 feat(add-observability): observability follow-ups...
8d45c7c feat: Sentry Crons heartbeats...
(14 total commits)

$ git log --follow --oneline -- migrations/scripts/migrate-0019.sh | head -3
344ae7a v0.10.0 fix: worker-template hardening...
5549970 v1.20.0 fix(#56): 0019 engine...
8d45c7c feat: Sentry Crons heartbeats...
(4 total commits)

$ git log --follow --oneline -- migrations/test-fixtures/0019/ | head -3
344ae7a v0.10.0 fix: worker-template hardening...
5549970 v1.20.0 fix(#56): 0019 engine...
4cd50d7 v0.7.0 feat(add-observability): observability follow-ups...
(3+ commits)
```

## Per-File Merge-Conflict Resolutions

| File | Conflict Type | Resolution | Per Policy |
|------|--------------|------------|------------|
| `CHANGELOG.md` | add/add (AA) — 29-01 skeleton vs filtered add-observability/CHANGELOG.md | `git checkout --ours CHANGELOG.md` — kept 29-01 0.11.0 skeleton with provenance trail | Matches policy: KEEP the 29-01 obs skeleton CHANGELOG |
| `README.md` | NO CONFLICT — filtered history had no root README.md after hoist (add-observability dir had no README at root) | n/a — 29-01 README survives untouched | Policy: would have kept --ours if conflict occurred |
| `.gitignore` | NO CONFLICT — same reason (no root .gitignore in add-observability) | n/a | Policy: would have kept --ours |
| `install.sh` | NO CONFLICT — as expected | n/a | n/a |
| `SKILL.md` | NO CONFLICT — only arrived from filtered history (29-01 created no root SKILL.md) | Taken verbatim | Matches policy |

## Known Stubs

**Pitfall 6 (internal path references in moved migration .mds):** The migration markdown files 0019 and 0021 reference engine scripts at their ORIGINAL paths (`templates/.claude/scripts/migrate-0019-*.sh`). These internal references now point to the wrong location in the obs repo (the scripts moved to `migrations/scripts/`). This is a known migration-script-path update deferred to 29-03 per Pitfall 6 in 29-RESEARCH.md. The scripts themselves are present at the correct obs paths — only the .md documentation of invoke paths is stale. NOT blocking for 29-03.

## 4 Known-Failing 0017 Fixtures (XFAIL)

The 4 known-failing test_migration_0017 fixtures (02: fresh-apply-fxsa-shape, 06: no-claudemd, 10: fresh-apply-worker-env, 11: prettier-style-clean-applies) have travelled with migration 0017 to the obs repo exactly as expected. These are FIX-0017-ENGINE scope (engine bugs: unsubstituted tokens, anchor failures). They will be encoded as XFAIL in the obs `run-tests.sh` harness in 29-03. The obs repo starts with exactly the same PASS=7 FAIL=4 baseline for 0017 as claude-workflow has today — no regression, just moved.

## Pending Action (Push — Human-Gated)

The merge commit `24c44c9` is on LOCAL obs main. The push has NOT been performed (Task 3 is `autonomous: false`). See checkpoint message for the exact command and what is being pushed.

## Deviations from Plan

### Auto-fixed Issues

None.

### Observation: README.md did NOT conflict

The plan's merge_conflict_policy listed README.md as a possible conflict. In practice, the `add-observability/` tree had no `README.md` file at the root (the README.md in the obs skeleton was at the obs repo root, and filter-repo hoisted `add-observability/` contents to root — but `add-observability/` itself had no README.md). So after hoist, no README.md came from the filtered history, and no conflict occurred. The 29-01 README.md survived untouched. Documented as expected behavior.

## Threat Flags

None. All T-29-05 through T-29-25 mitigations applied:
- T-29-05: filter-repo ran ONLY on /tmp/cw-scratch-for-obs (fresh remote clone) — never touched ~/Sourcecode/agenticapps/claude-workflow
- T-29-06: push NOT performed (PENDING user approval) — plain push will use `git push origin main` with NO --force
- T-29-07: 0011 confirmed absent from obs repo
- T-29-08: git log --follow verified on SKILL.md (14), migrate-0019.sh (4), fixture (3+)
- T-29-09: submodule pin 1f5d543 intact; 29-01 CHANGELOG kept via --ours
- T-29-25: 0021 to_version=1.20.0 confirmed unchanged (verbatim move)

## Self-Check

| Claim | Check |
|-------|-------|
| SKILL.md at obs root | `test -f ~/Sourcecode/agenticapps/agenticapps-observability/SKILL.md` — EXISTS |
| migrate-0019.sh renamed | `test -f .../migrations/scripts/migrate-0019.sh` — EXISTS |
| 0021 filename exact | `test -f .../migrations/0021-with-cron-and-queue-updates.md` — EXISTS |
| 0020 .md present | `test -f .../migrations/0020-openrouter-integration.md` — EXISTS |
| 0011 absent | `ls .../migrations/0011-*` — NO MATCHES (ABSENT) |
| ADR-0035 absent | `ls .../docs/decisions/0035-*` — NO MATCHES (ABSENT) |
| run-tests.sh absent | `test ! -f .../migrations/run-tests.sh` — ABSENT |
| 0021 to_version=1.20.0 | `grep to_version .../0021-with-cron-and-queue-updates.md` — 1.20.0 |
| Submodule SHA | `git ls-files -s vendor/agenticapps-shared` — 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4 |
| CHANGELOG has 0.11.0 | `grep "## \[0.11.0\]" CHANGELOG.md` — FOUND |
| No unresolved conflicts | `git diff --name-only --diff-filter=U` — EMPTY |
| cron-monitor.ts present | `test -f .../templates/ts-cloudflare-worker/cron-monitor.ts` — EXISTS |
| claude-workflow unchanged | `git status --short add-observability/` — EMPTY (0 modifications) |
| git log --follow SKILL.md | count=14 (≥3) |
| git log --follow migrate-0019.sh | count=4 (≥1) |
| Merge commit | 24c44c9 — EXISTS in obs repo log |

## Self-Check: PASSED
