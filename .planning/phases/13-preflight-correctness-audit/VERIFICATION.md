# Phase 13 — Verification

**Date:** 2026-05-14

## Must-haves

### MH1: Audit runs and reports useful results on this machine

**Evidence:** `bash migrations/run-tests.sh preflight`

```
━━━ Preflight-correctness audit (informational) ━━━
  ✓ 0001: test -f ~/.claude/skills/impeccable/SKILL.md
  ✓ 0001: test -f ~/.claude/skills/database-sentinel/SKILL.md
  ✓ 0004: test -f ~/.claude/skills/mattpocock-improve-architecture/SKILL.md
  ✓ 0004: test -f ~/.claude/skills/mattpocock-grill-with-docs/SKILL.md
  ✓ 0005: test -f ~/.claude/skills/gsd-review/SKILL.md
  ✓ 0006: test -f ~/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json
  ✓ 0006: command -v jq >/dev/null
  ✓ 0007: node -p 'parseInt(process.versions.node) >= 18 ? 0 : 1' | grep -q 0
  ✓ 0007: command -v gitnexus >/dev/null
  ✓ 0007: command -v jq >/dev/null
  ✓ 0008: curl -H 'Authorization: Bearer $TOKEN' http://127.0.0.1:5193/api/coverage | jq '.schemaVersion'  # → 1

  Audit summary: PASS=11 FAIL=0 SKIP=4
```

The four SKIP entries are migrations without a `requires:` frontmatter
block (0000-baseline, 0002, 0009, 0010). 11 verify clauses across 6
migrations all pass on Donald's machine. Exit code 0.

### MH2: Audit does NOT affect the suite's global PASS/FAIL counters

**Evidence:** `bash migrations/run-tests.sh` (no filter) full run:

```
━━━ Summary ━━━
  PASS: 111
  FAIL: 9
```

Same `111 PASS / 9 FAIL` count as Phase 12 — the Phase 13 audit's
11 PASS / 0 FAIL / 4 SKIP are reported in their own summary line
above the global one and are explicitly labeled "NOT counted in suite
totals". Exit code 1 (because of the 9 pre-existing/environmental
failures — unchanged).

### MH3: Audit would have caught issue #18 pre-merge

**Evidence:** Synthetic regression — temporarily restored 0005's
`requires.verify` to the pre-Phase-12 broken shape
(`~/.claude/get-shit-done/commands/gsd-review.md`):

```
─── Running preflight audit (with 0005 broken) ───
  ✗ 0005: test -f ~/.claude/get-shit-done/commands/gsd-review.md (exit 1)
  Audit summary: PASS=10 FAIL=1 SKIP=4

─── Restoring 0005 ───
─── Re-running audit (clean) ───
  ✓ 0005: test -f ~/.claude/skills/gsd-review/SKILL.md
  Audit summary: PASS=11 FAIL=0 SKIP=4
```

The audit cleanly distinguishes a broken verify (`✗`) from a working
one (`✓`). Had Phase 13 been in place before Phase 11, issue #18
would have surfaced on the author's machine the first time
`migrations/run-tests.sh` ran after 0005 was authored.

### MH4: Exit-code semantics correct

**Evidence:**
- `bash migrations/run-tests.sh preflight` (audit-only) — exit 0
  (audit ran, no global failures).
- `bash migrations/run-tests.sh` (full suite) — exit 1 (9 pre-existing
  / environmental global failures from earlier stanzas; audit doesn't
  add to this).

The "NO TESTS RAN" branch in the exit logic was updated to consider
the new `RAN_AUDIT` flag, so audit-only runs are recognised as having
done meaningful work.

### MH5: Graceful degradation when python3 / PyYAML unavailable

**Evidence:** The audit's first action is
`python3 -c 'import yaml' 2>/dev/null`. If it fails, the audit prints
a one-line `~ python3 with PyYAML not available — preflight audit skipped`
and returns 0. No crash; no impact on the rest of the suite. Inspected
by reading the code; not exercised on this machine where python3+PyYAML
are present.

## Out-of-scope reminders

- A `--strict-preflight` flag to gate CI on audit failures — separate
  follow-up if/when CI gains parity with author dev environments.
- Test for migration *body* preflight blocks (the bash that runs in
  `## Pre-flight` sections). Those run against the consumer project's
  filesystem at apply time and aren't structured data we can extract
  generically.
- Static lint of verify strings (rejected Alternative B in RESEARCH.md).
- 0008's verify (`curl ... | jq ...`) is suspect on closer reading —
  `jq` exits 0 even on parse errors, masking failures. That's a 0008
  quality issue, not a Phase 13 concern. Worth a follow-up phase.
