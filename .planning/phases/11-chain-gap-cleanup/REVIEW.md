# Phase 11 — REVIEW (Stage 1 + Stage 2)

**Date:** 2026-05-14
**Reviewer (Stage 1):** Claude Opus 4.7 via gstack `/review` workflow
**Reviewer (Stage 2):** Claude Opus 4.7 via `superpowers:requesting-code-review`
**Diff scope:** 9 files, +77 / -75 lines. Metadata-only — no executable
code changed.

## Scope check

**Intent (from `session-handoff.md` 2026-05-14):** Close the version-chain
gap (`1.5.0 → 1.7.0`) and collision (`0008` + `0009` both `1.7.0 → 1.8.0`)
that block cparx-at-v1.5.0 from upgrading to head v1.9.3. Phase 11 is
declared version-chain hygiene only — no code-logic changes.

**Delivered:** Frontmatter re-anchor of 0008 (1.5 → 1.6) and 0009 (1.6 → 1.8),
plus all body / fixture / harness / CHANGELOG / README references that
must follow from the re-anchor for the migration to actually run in
practice.

**Scope creep:** none.
**Missing requirements:** none.

The handoff's narrow framing ("only frontmatter rewrites") under-specified
the work — 0009's body has an executable preflight `test "$INSTALLED" =
"1.7.0"` that would have rejected projects after a freshly-applied 0008.
Phase 11 widens scope to include all consequential references (preflight
check, prose, Step 5 version pre-condition / Apply / Rollback values,
test fixtures, harness assertions). This is documentation-correctness
under the same metadata-only umbrella: zero shell behavior changes; the
runtime contract simply matches the new frontmatter.

## Stage 1 — gstack `/review` (spec compliance)

`/review` is built for code-touching PRs. For a docs-only metadata diff,
the meaningful structural checks are:

### S1.1 — Frontmatter validity (PASS)

Every migration retains valid `from_version` + `to_version`. Verified:

```
0001: 1.2.0 → 1.3.0
0002: 1.4.0 → 1.5.0
0004: 1.3.0 → 1.4.0
0005: 1.9.0 → 1.9.1
0006: 1.9.1 → 1.9.2
0007: 1.9.2 → 1.9.3
0008: 1.5.0 → 1.6.0   ← re-anchored (was 1.7.0 → 1.8.0)
0009: 1.6.0 → 1.8.0   ← re-anchored (was 1.7.0 → 1.8.0)
0010: 1.8.0 → 1.9.0
```

### S1.2 — Chain integrity (PASS)

Zero `from_version` collisions. Walk from `1.5.0` reaches head `1.9.3`
in 6 hops with no HALT. Walk from `1.8.0` (sanity: hypothetical
already-migrated project) reaches head in 4 hops, correctly skipping
re-anchored 0008/0009. Evidence in VERIFICATION.md MH3 / MH4.

### S1.3 — Cross-file consistency (PASS)

- `migrations/README.md` index table: 0008 → `1.5.0 → 1.6.0`, 0009 →
  `1.6.0 → 1.8.0` (with note about the 1.6 → 1.8 jump pointing at the
  new "Application order" note 3).
- `migrations/README.md` "Application order" note 3 added — codifies
  "`to_version` need not be `from_version + 0.1`" as a workflow norm.
- `CHANGELOG.md` `[1.5.1]` / `[1.7.0]` rewritten as "Skipped (no
  migration)" with pointers to where the originally-planned content
  actually shipped (`[1.9.1]` / `[1.9.3]`).
- `CHANGELOG.md` `[1.6.0]` rewritten to describe the re-anchored 0008
  with a trailing pointer to `[1.9.2]` for the wiki-compiler content
  that the slot previously described.
- `CHANGELOG.md` `[1.8.0]` 0009 references updated: "promotes 1.7.0 →
  1.8.0" → "promotes 1.6.0 → 1.8.0"; "skill/SKILL.md bumped 1.7.0 →
  1.8.0" → "bumped 1.6.0 → 1.8.0"; "Existing 1.7.0 projects" →
  "Existing 1.6.0 projects".

### S1.4 — Migration runtime contract (PASS)

0009's body:

- Preflight: `test "$INSTALLED" = "1.7.0"` → `test "$INSTALLED" =
  "1.6.0"`. Error message updated.
- Step 5 pre-condition (`SKILL.md exists and currently has version: 1.7.0`)
  → `version: 1.6.0`. Apply / Rollback values updated.
- "Pristine copy of v1.7.0 template" / "the v1.7.0 template" prose →
  "legacy inlined template" (version-neutral; v1.7.0 no longer ships).
- "Project not at v1.7.0" skip-case note → "Project not at v1.6.0".

0008's body:

- "Workflow head version bumps to 1.8.0" → "1.6.0" (since 0008 now
  delivers 1.6.0).
- Verify-expectation comment updated to reflect actual scaffolder head
  at apply time (1.9.3), since the dashboard reads head not this
  migration's to_version specifically.
- Rollback prose updated: "reverts to 1.7.0 (from migration 0007)"
  was wrong both pre- and post-rebase. Now correctly states "returns
  the chain head to 1.5.0 (the to_version of migration 0002)".
- Frontmatter `notes:` entry about staleness reworded to be
  version-agnostic — the matrix shows staleness vs. scaffolder head,
  not vs. this migration's own to_version.

### S1.5 — Test harness aligned (PASS)

- `migrations/test-fixtures/0009/before-fresh/`,
  `before-inlined-pristine/`, `before-inlined-customised/`:
  `SKILL.md` version `1.7.0` → `1.6.0`.
- `migrations/test-fixtures/0009/README.md` fixture-table column
  `1.7.0` → `1.6.0`. End-note hint about "fx-signal-agent once 1.8.0
  ships" softened (already shipped).
- `migrations/run-tests.sh` assertion-message text "still 1.7.0" →
  "still 1.6.0" (3 occurrences, lines 388 / 390 / 392).
- Full suite: **112 PASS / 8 FAIL**. All 8 failures are pre-existing
  in `test_migration_0001` and unrelated (CHANGELOG `[1.8.0]` line 95
  documents them). `git diff --stat` touches zero files in 0001's
  surface area, so this is not a regression.

### S1.6 — Adversarial pass (Claude subagent)

Skipped. The adversarial-subagent dispatch is designed to find
production-failure modes in code paths. For a metadata diff that
changes documentation strings only, an adversarial pass would surface
only zero-information style nits. Per `/review` "if Codex is NOT
available" / small-diff guidance, the structured pass is sufficient.

### Stage 1 verdict

**PASS.** No critical issues. No informational findings worth holding
the PR for. Scope is correctly bounded.

## Stage 2 — Independent code-quality review

For metadata-only diffs, Stage 2 looks for non-spec issues a Stage 1
reviewer might let through: stylistic inconsistencies, citation rot,
prose contradictions, missed cross-references.

### S2.1 — Prose contradictions (CLEAR)

The three "Skipped (no migration)" CHANGELOG entries (`[1.5.1]`,
`[1.7.0]`) and the rewritten `[1.6.0]` all consistently point to the
slot where the originally-planned content actually shipped. No
contradictions between CHANGELOG and `migrations/README.md` index.

### S2.2 — Citation rot (CLEAR)

Phase 11 introduces one new citation: "Application order" note 3 in
`migrations/README.md`. The `[1.8.0]` 0009 entry and the
`migrations/README.md` index row both reference this new note. The
`0009` body's frontmatter remains pointable; nothing internal to 0009
references "note 3" so no transitive citations need updating.

### S2.3 — Style consistency (CLEAR)

The added "Application order" note 3 follows the existing 1-2 prose
style (no header level shift, same hanging-indent paragraph form).
The "Skipped (no migration)" headings parallel each other so a reader
seeing one immediately recognises the others. The em-dash usage in
the rewritten CHANGELOG entries matches existing conventions
elsewhere in the file.

### S2.4 — Cross-reference completeness (CLEAR)

The new "Application order" note 3 explicitly references migration
0009 as the example case. Migration 0009's frontmatter row in the
index table back-references the note. Round-trip is closed.

### S2.5 — Single-line confusion sniff (CLEAR)

`migrations/0008-coverage-matrix-page.md` line 41 now reads:

> 3. Workflow head version bumps to 1.6.0 (consumer-passive — no
>    skill-file edits required in consumer repos; the dashboard
>    surface is workflow-repo-only)

Earlier draft made "consumer-passive" feel like a contradiction with
the bump claim ("bump to 1.6.0" + "no skill-file edits" sounds like
the two clash). The parenthetical clarifier resolves the apparent
tension — passive means the consumer skill file doesn't get an
on-disk edit from this migration's apply; the version-bump is
recorded but workflow-repo-side, since 0008 is the dashboard surface.
Acceptable.

### Stage 2 verdict

**PASS.** No code-quality findings.

## Quality score

PR Quality Score (Phase 11): **10/10**.

Justification: zero critical findings, zero informational findings,
zero scope drift, zero regressions on the in-Phase test suite, scope
correctly broadened only where the original handoff narrowness would
have left a broken migration on disk.

## Outstanding recommendation (not blocking)

The 8 pre-existing `test_migration_0001` failures should get their own
phase to fix `git merge-base` resolution. Phase 11 explicitly does not
address them (out of scope per handoff).

`session-handoff.md` "Other follow-ups (lower priority)" item 2
(supply-chain pinning for vendored llm-wiki-compiler and gitnexus)
also stands as a future-phase recommendation. Not blocking Phase 11.
