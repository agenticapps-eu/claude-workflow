# Phase 12 — Fix migration 0005 preflight verify path — RESEARCH

**Date:** 2026-05-14
**Issue:** [#18](https://github.com/agenticapps-eu/claude-workflow/issues/18)
**Repro project:** `factiv/fx-signal-agent` (stuck at v1.9.0)

## Problem

Migration `0005-multi-ai-plan-review-enforcement.md` preflight verifies
`/gsd-review` at `~/.claude/get-shit-done/commands/gsd-review.md` — a
path that does not exist in the current GSD install layout.

Actual layout:

```
~/.claude/get-shit-done/
  bin/
  contexts/
  references/
  templates/
  workflows/         ← review.md lives here
  VERSION
~/.claude/skills/
  gsd-review/SKILL.md  ← Claude Code skill that delegates to ↑
```

The slash command `/gsd-review` resolves via the skill at
`~/.claude/skills/gsd-review/SKILL.md`. The skill file's
`<execution_context>` block points at `@$HOME/.claude/get-shit-done/workflows/review.md`
for the actual review logic. Neither artifact lives in a `commands/`
subdirectory.

Five references in `migrations/0005-multi-ai-plan-review-enforcement.md`
hardcode the wrong `commands/gsd-review.md` path. The chain halts at
v1.9.0 with `ERROR: /gsd-review slash command not installed`, blocking
0006 (1.9.1 → 1.9.2) and 0007 (1.9.2 → 1.9.3) downstream — even when
`/gsd-review` is installed and working.

The Phase 11 chain-walk simulation did not catch this because dry-runs
only exercise Step 2 (pending-migration discovery via frontmatter). The
per-migration preflight verify runs at Step 5 (actual apply), so a
dry-run reports the chain as clean while a real apply halts.

## Alternatives considered

### Alternative A — Check the skill file (RECOMMENDED)

```yaml
verify: "test -f ~/.claude/skills/gsd-review/SKILL.md"
```

**Why:** the skill file is the canonical artefact that makes the
`/gsd-review` slash command discoverable to Claude Code. Without it,
typing `/gsd-review` finds nothing. The workflow body it delegates to
is an implementation detail.

**Pros:** Most accurate — matches how slash-command resolution actually
works. Tightest possible contract. Won't false-positive on installs
where the workflow body exists but the skill is missing.

**Cons:** Won't true-positive on alternative install shapes where
someone installed the workflow body without the skill (rare). Same
fragility shape as the original bug, just at a different path.

### Alternative B — Check the workflow body

```yaml
verify: "test -f ~/.claude/get-shit-done/workflows/review.md"
```

**Pros:** Catches both skill-vendored installs (the skill file exists
*and* references the workflow body) and bare workflow-only installs.

**Cons:** Doesn't catch the failure mode where the workflow body exists
but the skill is missing — `/gsd-review` won't actually be invocable
from Claude Code because there's no skill to register the slash command.

### Alternative C — Belt-and-braces (either path)

```yaml
verify: "test -f ~/.claude/skills/gsd-review/SKILL.md || test -f ~/.claude/get-shit-done/workflows/review.md"
```

**Pros:** Tolerates both install shapes. Friendly to projects in
transition between vendored gsd patches and Claude Code skill ecosystems.

**Cons:** False-positives the most loudly when only the workflow body
exists but the skill is missing — the migration passes preflight then
the hook it installs (`multi-ai-review-gate.sh`) never fires because
nothing in Claude Code knows about `/gsd-review`. Worst kind of bug: the
verify lied.

## Decision

**Alternative A.** The skill file is the load-bearing contract — that's
the file Claude Code's slash-command machinery actually reads. If a
project has the workflow body without the skill, the migration's hook
will install but `/gsd-review` is non-functional from Claude Code's
perspective. Preflight should fail loudly in that case, not silently
pass via belt-and-braces.

## Install hint

The original install hint pointed at `bash ~/.config/gsd-patches/bin/sync`.
Per the issue, that sync only mirrors patches into
`~/.claude/get-shit-done/` — it does not install the skill at
`~/.claude/skills/gsd-review/SKILL.md`. Running it on a fresh machine
leaves `/gsd-review` non-functional even after the sync succeeds.

There is no single canonical "install /gsd-review" command in the
workflow scaffolder's vocabulary today. Different operators install it
different ways (dotfiles, `claude skill add`, vendored from
`get-shit-done` install scripts). The honest install hint is a pointer
to wherever the user got their `~/.claude/skills/` from.

Phase 12 install hint:

> "Install the /gsd-review Claude Code skill. The skill file must exist
> at `~/.claude/skills/gsd-review/SKILL.md`. Sources vary by setup —
> see your get-shit-done install or dotfiles."

Not prescriptive, but accurate. A follow-up phase could codify a
canonical install command if one emerges.

## Scope guards (out-of-scope for Phase 12)

- **No changes to the multi-AI review gate hook** (`multi-ai-review-gate.sh`)
  itself. The hook works correctly — the bug is in the preflight
  verify only.
- **No changes to other migrations.** This is a precision fix.
- **No changes to the canonical install path for `/gsd-review`.**
  Codifying a canonical install command is a separate (optional)
  follow-up. Phase 12 only fixes the verify check so the chain
  unblocks.

## Verification plan

1. `bash migrations/run-tests.sh` — full suite, no regressions to 0005
   test stanza (it asserts hook behaviour, not preflight paths).
2. `/update-agenticapps-workflow` against `factiv/fx-signal-agent`
   (stuck at v1.9.0) — confirm preflight passes and chain walks to
   v1.9.3.
3. Sanity check on `cparx` if any — should be at v1.5.0 still, would
   walk through the new 0005 preflight without halting.

## Related

- Phase 11 closed the chain GAP/COLLISION (issue not filed; discovered
  via cparx dry-run).
- This Phase 12 closes the next failure mode discovered immediately
  after Phase 11's merge — a preflight that lies about installed state.
- Pattern: every migration with a `requires:` block should have its
  install hint + verify path round-tripped against an actual install
  before merging. Worth adding to the migration template / linter as a
  follow-up.
