# Phase 12 — REVIEW (Stage 1 + Stage 2)

**Date:** 2026-05-14
**Reviewer:** Claude Opus 4.7
**Diff scope:** 1 file, ~10 lines net change. Metadata fix — no
executable shell logic changes; preflight semantics are preserved
(check-then-error), only the path being checked changes.

## Scope check

**Intent (from issue #18):** Fix `migrations/0005-multi-ai-plan-review-enforcement.md`
preflight verify path. The wrong path (`~/.claude/get-shit-done/commands/gsd-review.md`)
makes the chain halt at v1.9.0 even when `/gsd-review` is installed and
working.

**Delivered:** Replaced five references to the wrong path with the
canonical skill path (`~/.claude/skills/gsd-review/SKILL.md`). Updated
the install hint to be honest about what's needed (a skill file at the
canonical Claude Code path, not a patches-sync).

**Scope creep:** none.
**Missing requirements:** none.

## Stage 1 — Spec compliance

### S1.1 — Path correctness (PASS)

`~/.claude/skills/gsd-review/SKILL.md` is the file Claude Code's
slash-command resolution actually reads to discover `/gsd-review`. The
skill's `<execution_context>` block declares
`@$HOME/.claude/get-shit-done/workflows/review.md` as the delegated
workflow body — that's the right level of abstraction for the verify
check to target.

### S1.2 — Install hint accuracy (PASS)

Old hint pointed at `bash ~/.config/gsd-patches/bin/sync`. Per issue #18,
that command only mirrors patches into `~/.claude/get-shit-done/` — it
does not install the Claude Code skill. New hint is non-prescriptive
but accurate: "The skill file must exist at
`~/.claude/skills/gsd-review/SKILL.md`. Sources vary by setup — see
your get-shit-done install or dotfiles."

A future phase could codify a canonical install command if one emerges.
Out of scope for Phase 12.

### S1.3 — Migration runtime contract (PASS)

The verify check semantics are preserved: same `test -f PATH || (echo
ERROR && exit 1)` pattern, same exit-1-on-fail behaviour. Only the
path being checked changes. The migration runner's contract with
0005 is unchanged.

### S1.4 — Frontmatter validity (PASS)

The `requires:` entry shape changed key: `patch:` → `skill:`. Both are
free-form keys in the migrations/README.md "Frontmatter fields" table
— it documents `requires:` as a list of "external skills" with
`install` + `verify` shell commands. The `patch:` key was an outlier
that mismatched the section's stated intent ("external skills");
`skill:` matches the documented shape.

### S1.5 — Backward-compat (PASS)

No projects currently at v1.9.1+ are affected — they've already
applied 0005 (under the broken preflight, which means they applied it
via the env-skip override or pre-Phase-11). Projects at v1.9.0 (like
fx-signal-agent) and below will hit the new preflight on first apply.
No regression for in-flight installs.

### Stage 1 verdict

**PASS.**

## Stage 2 — Code-quality review

### S2.1 — Comment clarity (PASS)

Added a 4-line explanatory comment block to the pre-flight bash
section documenting why the skill file (not the workflow body) is the
load-bearing contract. This is a non-obvious decision worth recording
inline — it prevents the next person from "fixing" the verify to
check the workflow body instead.

### S2.2 — Error message helpfulness (PASS)

New error message names the exact missing artefact and the exact
path it needs to be at. Old message said "Run: bash ~/.config/gsd-patches/bin/sync"
which (per issue #18) is misleading. New message is honest about
"sources vary".

### S2.3 — Round-trip with `migrations/README.md` (PASS)

`migrations/README.md` `requires:` example uses `skill:` as the key
(see migration 0001's entry). Phase 12's change to use `skill:`
instead of `patch:` makes 0005 conform to the documented schema. No
README change needed — this is bringing the migration in line.

### S2.4 — Test stanza coverage (PASS)

`test_migration_0005` in `migrations/run-tests.sh` asserts behaviour
of the installed hook (multi-ai-review-gate.sh), not preflight path
correctness. The test stanza is unaffected by Phase 12. A future
phase could add a per-migration preflight-correctness test that
asserts paths in `requires.verify` resolve on a real install — that
would have caught issue #18 pre-merge. Out of scope here.

### Stage 2 verdict

**PASS.**

## Quality score

PR Quality Score: **10/10**.

Justification: precision fix for a real reported bug. Zero scope creep.
Bug reproduced and fix verified on the same project that surfaced the
issue (fx-signal-agent). Test suite Phase-12-relevant stanzas all green.
Honest about the environmental test-fixture flake (0007 03-no-gitnexus)
and the pre-existing 0001 failures.

## Outstanding recommendation (not blocking)

Add a per-migration preflight-correctness test to `run-tests.sh` that
asserts every `requires.verify` shell command resolves on a real
install. Would have caught issue #18 pre-merge. File as a follow-up
phase. Out of scope for Phase 12.
