# Phase 11 — Verification

**Date:** 2026-05-14

## Must-haves

### MH1: Gap at `1.5.0 → 1.7.0` closed

**Evidence:** `0008-coverage-matrix-page.md` now declares
`from_version: 1.5.0` / `to_version: 1.6.0`. Chain walk from `1.5.0`
proceeds without HALT.

```
1.5.0 → apply 0008 → 1.6.0
```

### MH2: Collision between 0008 and 0009 at `1.7.0 → 1.8.0` resolved

**Evidence:** Frontmatter scan reports `=== Collisions on from_version ===  none`.
0008 now declares `from_version: 1.5.0`; 0009 declares `from_version: 1.6.0`.

### MH3: cparx (at v1.5.0) walks chain cleanly to head (v1.9.3)

**Evidence:** Simulated chain walk via Python frontmatter parser:

```
1.5.0 → apply 0008-coverage-matrix-page.md → 1.6.0
1.6.0 → apply 0009-vendor-claude-md-sections.md → 1.8.0
1.8.0 → apply 0010-post-process-gsd-sections.md → 1.9.0
1.9.0 → apply 0005-multi-ai-plan-review-enforcement.md → 1.9.1
1.9.1 → apply 0006-llm-wiki-builder-integration.md → 1.9.2
1.9.2 → apply 0007-gitnexus-code-graph-integration.md → 1.9.3
HALT at 1.9.3 (head reached)
Chain length: 6 migrations
```

### MH4: Re-anchored migrations do not re-apply for newer projects

**Evidence:** Sanity walk from `1.8.0` (hypothetical project past re-anchor)
skips 0008/0009 correctly and reaches head in 4 migrations:

```
1.8.0 → apply 0010-post-process-gsd-sections.md → 1.9.0
1.9.0 → 0005 → 1.9.1 → 0006 → 1.9.2 → 0007 → 1.9.3
HALT at 1.9.3
Chain length: 4 migrations
```

### MH5: No regressions in `migrations/run-tests.sh`

**Evidence:** `bash migrations/run-tests.sh` summary:

```
PASS: 112
FAIL: 8
```

All 8 failures are pre-existing in `test_migration_0001` (documented in
CHANGELOG [1.8.0] line 95 — `git merge-base` resolves to a
post-0001-merge commit; tracked separately). Phase 11's `git diff --stat`
touches zero files in 0001's surface area.

Phase 11-relevant stanzas:
- `test_migration_0005`: 13/13 PASS
- `test_migration_0006`: 15/15 PASS
- `test_migration_0007`: 18/18 PASS
- `test_migration_0009`: 37/37 PASS (after re-anchoring fixture SKILL.md
  versions to 1.6.0)
- `test_migration_0010`: 16/16 PASS

### MH6: CHANGELOG no longer carries stale pre-rebase entries

**Evidence:** `[1.5.1]`, `[1.6.0]`, `[1.7.0]` sections rewritten:

- `[1.5.1]` — "Skipped (no migration)" + pointer to [1.9.1] for the
  multi-AI gate that actually shipped via 0005 at 1.9.0 → 1.9.1.
- `[1.6.0]` — Replaced with new content describing the re-anchored 0008.
  Trailing note points to [1.9.2] for the wiki compiler that shipped via
  0006 at 1.9.1 → 1.9.2.
- `[1.7.0]` — "Skipped (no migration)" + pointer to [1.9.3] for the
  GitNexus integration that shipped via 0007 at 1.9.2 → 1.9.3.
- `[1.8.0]` — version references updated: 0009 now described as
  `1.6.0 → 1.8.0`, SKILL.md bump described as `1.6.0 → 1.8.0`.

## Out-of-scope reminders

- The 8 pre-existing `test_migration_0001` failures are NOT addressed
  by Phase 11. They remain tracked separately.
- Phase 11 made no code-logic changes. Only frontmatter, body version
  references, fixture SKILL.md versions, README index, and CHANGELOG.
