# Phase 12 — Verification

**Date:** 2026-05-14
**Issue:** [#18](https://github.com/agenticapps-eu/claude-workflow/issues/18)

## Must-haves

### MH1: Old preflight reproduces the bug

**Evidence:** Run against fx-signal-agent's filesystem (v1.9.0):

```
─── OLD preflight (pre-Phase-12, the bug) ───
FAIL (expected, this is the bug): test -f ~/.claude/get-shit-done/commands/gsd-review.md → exit 1
```

The check fails — the `commands/` subdirectory does not exist in the
current GSD install layout. This matches the failure mode reported in
issue #18 (chain halt at v1.9.0).

### MH2: New preflight passes when /gsd-review is installed

**Evidence:**

```
─── NEW preflight (Phase 12 fix) ───
PASS: ~/.claude/skills/gsd-review/SKILL.md exists, preflight passes
```

The Phase 12 fix correctly identifies that `/gsd-review` is installed
as a Claude Code skill.

### MH3: Chain walks v1.9.0 → v1.9.3 cleanly under Phase 12 0005

**Evidence:** Chain-walk simulation against the Phase 12 branch
migrations, starting from fx-signal-agent's installed version:

```
Step 1:  0005   v1.9.0 → v1.9.1   Enforce multi-AI plan review (/gsd-review) as a contract gate
Step 2:  0006   v1.9.1 → v1.9.2   Integrate LLM wiki compiler (Karpathy pattern) per family
Step 3:  0007   v1.9.2 → v1.9.3   GitNexus code-knowledge graph integration (MCP-native, setup-only)
Final: v1.9.3 in 3 hops
```

### MH4: Existing test suite — Phase 12-relevant stanzas green

**Evidence:** `bash migrations/run-tests.sh` → 111 PASS / 9 FAIL.

- The 8 `test_migration_0001` failures are pre-existing (carried over
  from Phase 11; tracked separately).
- 1 new failure: `test_migration_0007` fixture `03-no-gitnexus` — exit 0,
  expected 1. This is **environmental, not caused by Phase 12**:
  `gitnexus` is installed via `fnm` at
  `~/.local/state/fnm_multishells/.../bin/gitnexus`. The sandbox PATH
  manipulation in fixture 03 doesn't strip the fnm location, so the
  "no-gitnexus" scenario can't actually simulate missing-gitnexus on
  this machine.
- `git diff --stat main..HEAD` confirms Phase 12 touches only
  `migrations/0005-multi-ai-plan-review-enforcement.md` and Phase 12
  planning artifacts. Zero changes to 0007 surface area.

Phase 12-relevant test results:
- `test_migration_0005`: 13/13 PASS (the stanza asserts hook behaviour,
  not preflight paths — unaffected by the preflight change).
- `test_migration_0006`: 15/15 PASS.
- `test_migration_0009`: 37/37 PASS.
- `test_migration_0010`: 16/16 PASS.

### MH5: All stale path refs in 0005 replaced

**Evidence:**

```bash
$ grep -nE 'commands/gsd-review|gsd-patches/bin/sync' \
    migrations/0005-multi-ai-plan-review-enforcement.md
No remaining stale refs
```

Five references (2 in the `requires:` block, 3 in the pre-flight bash
block at lines 39-41 of the original) all replaced. Two distinct
substitutions:

1. **Path:** `~/.claude/get-shit-done/commands/gsd-review.md` →
   `~/.claude/skills/gsd-review/SKILL.md`
2. **Install hint:** `bash ~/.config/gsd-patches/bin/sync` (which only
   syncs the workflow body, not the skill) → "The skill file must exist
   at `~/.claude/skills/gsd-review/SKILL.md`. Sources vary by setup —
   see your get-shit-done install or dotfiles."

Plus an explanatory comment added to the pre-flight block documenting
why the skill file (not the workflow body) is the load-bearing contract.

## Out-of-scope reminders

- Codifying a canonical install command for `/gsd-review` is a separate
  follow-up. Phase 12 only fixes the broken verify path; the install
  hint is now accurate but not prescriptive.
- The 8 pre-existing `test_migration_0001` failures remain tracked
  separately.
- The new `test_migration_0007 03-no-gitnexus` environmental failure
  on this machine is unrelated to Phase 12 and should be tracked as
  a follow-up to make the fixture sandbox more robust against
  fnm-managed binaries.
