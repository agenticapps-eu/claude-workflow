---
type: cross-ai-review
phase: 30-split-03-claude-workflow-2-0-0-follow-up
reviewer: codex
scope: pre-release diff (claude-workflow 2.0.0 / SPLIT-03)
status: resolved
findings: { high: 1, medium: 2, low: 1 }
resolved_in: 4d97066
---

# Phase 30 — Codex Pre-Release Review (Task 3 step 2)

Independent cross-AI review of the 2.0.0 shipping diff (28 files, 2,204-line focused diff),
run after the dedicated gsd-code-reviewer pass (which was clean). Per plan 30-03 Task 3,
HIGH findings must be resolved before opening the PR.

## Findings & resolutions

### HIGH — phase-sentinel.sh SIGPIPE under `set -euo pipefail` — FIXED (4d97066)
`grep '- [ ]' "$checklist" | head -5 >&2` then `exit 2`. When the matched output overflows
the ~64KB pipe buffer, `head -5` closes the pipe early, `grep` dies on SIGPIPE, `pipefail`
makes the pipeline non-zero, and `set -e` exits the hook with **141 before reaching `exit 2`** —
silently breaking the Stop-hook block contract.

- Codex's stated trigger ("6th item") was slightly off: small output fits the pipe buffer, so
  grep finishes before head closes it. The real trigger is grep output > pipe buffer (a very
  large checklist). Verified empirically: a 5000-line checklist → **old hook exits 141, fixed
  exits 2**.
- Fix: append `|| true` to the `grep | head` pipeline in BOTH the template
  (`templates/.claude/hooks/phase-sentinel.sh`) and the verbatim copy embedded in migration 0022.
- Regression test: `test_phase_sentinel` Case 4 now builds a 5000-line checklist that overflows
  the buffer and asserts exit 2 (true regression — passes on fixed hook, 141 on old). Suite PASS 149→150.

### MEDIUM — install.sh leaves a dangling legacy add-observability symlink — FIXED (4d97066)
Dropping the LINKS pair means a pre-2.0.0 `~/.claude/skills/add-observability` symlink now
dangles and install.sh no longer cleans it. Added a guarded cleanup: removes it ONLY when it is
a symlink whose target is missing (a valid obs-repo alias, target present, is left untouched).

### MEDIUM — 0022 exit-3 abort vs /update Pause/Skip/Cancel — ACCEPTED (defense-in-depth)
`/update-agenticapps-workflow` handles `requires.verify` first (offers Pause/Skip/Cancel), so the
documented "hard exit-3 abort" is not the literal downstream path. Both layers compose safely: the
requires.verify gate stops the run if obs is absent; if the user proceeds anyway, the migration
body's exit-3 pre-flight is the backstop. The safety property (never proceed without the obs skill)
holds either way. No behavior change.

### LOW — docs/UPGRADING.md version-bump path — FIXED (4d97066)
Clarified that 0022 bumps the project-local hyphenated
`.claude/skills/agentic-apps-workflow/SKILL.md`; `skill/SKILL.md` is the repo's own source copy.

## Post-fix state
- Full suite: exit 0, **PASS 150**, FAIL 0. Drift PASS (2.0.0 == 2.0.0).
- gsd-code-reviewer: clean. gsd-verifier: 16/16 code-side must-haves. 0011 byte-unchanged.
