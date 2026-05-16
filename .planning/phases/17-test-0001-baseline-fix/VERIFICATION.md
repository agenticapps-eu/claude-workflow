# Phase 17 Verification

## Obligation matrix

| # | Obligation | Evidence | Status |
|---|-----------|----------|--------|
| 1 | `test_migration_0001` has 0 failures on `main` | `bash migrations/run-tests.sh \| sed -n '/Migration 0001/,/Migration 0005/p' \| grep -c '^\s*✗'` returns `0`; all 20 step-idempotency assertions pass. | ✅ |
| 2 | Full migration suite reaches PASS=130 FAIL=1 | `bash migrations/run-tests.sh \| tail -3` reports `PASS: 130 / FAIL: 1`. | ✅ |
| 3 | The remaining FAIL is the Phase 18 carry-over only | `bash migrations/run-tests.sh \| grep -E '^\s*✗'` returns the single line `✗ 03-no-gitnexus — exit 0, expected 1`. | ✅ |
| 4 | `before_ref` resolves to the v1.2.0 pre-migration commit | `git log -1 --format='%h %s' "$(git log --reverse --format=%H -S '## Backend language routing' -- templates/workflow-config.md \| head -1)^"` resolves to `7dafa63 feat: enforcement plan — commitment ritual + gate-to-skill map (#1)`, which is the parent of `b21abc6` (squash of PR #2 that applied migration 0001). | ✅ |
| 5 | Pre-fix `before_ref` content has no migration-0001 markers | `git show 7dafa63:templates/workflow-config.md \| grep -cE 'Backend language routing\|design_critique\|Supabase / Postgres / MongoDB touched'` returns `0`. | ✅ |
| 6 | Post-fix `after_ref` content has all migration-0001 markers | `git show HEAD:templates/workflow-config.md \| grep -cE 'Backend language routing\|design_critique\|Supabase / Postgres / MongoDB touched'` returns `3`. | ✅ |
| 7 | Phase 15 smoke still passes with tightened thresholds | `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh \| tail -10` reports `Passed: 10 / Failed: 0` with the new `PASS≥130 FAIL≤1` thresholds and `Phase 18 target only` allowlist. | ✅ |
| 8 | Fallback path preserved for stripped clones / pre-merge feature branches | `migrations/run-tests.sh:114-141` retains the legacy `git merge-base HEAD origin/main \|\| git merge-base HEAD main \|\| git rev-parse main` chain inside an `if [ -z "$before_ref" ]` block. | ✅ |
| 9 | No scaffolder behaviour change (test-only fix) | `git diff main -- 'migrations/0*.md' '*.sh' templates/ install.sh add-observability/ skill/` shows ONLY `run-tests.sh` and `smoke/run-smoke.sh` modified. No migration logic, no template, no skill files touched. | ✅ |
| 10 | No regression in other migration tests | All migration test stanzas (0005, 0006, 0007 except 03-no-gitnexus, 0009, 0010, 0011, 0012) PASS with full counts unchanged from pre-fix run. Only the 0001 stanza moved from 12 PASS / 8 FAIL to 20 PASS / 0 FAIL. | ✅ |

## Before/after counts

| Metric | Before Phase 17 | After Phase 17 |
|--------|-----------------|----------------|
| Suite PASS | 122 | 130 |
| Suite FAIL | 9 | 1 |
| `test_migration_0001` PASS | 12 | 20 |
| `test_migration_0001` FAIL | 8 | 0 |
| Phase 15 smoke PASS | 10 | 10 |
| Phase 15 smoke FAIL | 0 | 0 |

## Notes

- The `git fetch --quiet origin main 2>/dev/null || true` is kept at the top
  of `test_migration_0001` because the fallback branch still depends on
  `origin/main` for the legacy merge-base chain. The new primary path
  doesn't need the fetch (it walks local history via `git log -S`), but
  keeping it harmless preserves the fallback's behaviour on stripped clones.
- Phase 18 (`test_migration_0007` `03-no-gitnexus` fnm-PATH leak) remains
  the only carry-over failure. Phase 18 scope is unchanged by this work.
