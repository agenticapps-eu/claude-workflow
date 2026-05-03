# Phase 1 Verification — rogs.me GSD bug fixes

**Phase:** 01-gsd-bug-fixes
**Spec source:** Hand-off prompt Phase 1 + `tooling-research-2026-05-02-batch2.md` §2
**Date:** 2026-05-03

## Bug-by-bug audit

### Bug 1: `opencode run 2>/dev/null` hang — APPLIED

- **MH-1:** `~/.claude/get-shit-done/workflows/review.md` line 169 patched in place
- **Evidence:** `grep -n "opencode run" ~/.claude/get-shit-done/workflows/review.md` → `169:cat /tmp/gsd-review-prompt-{phase}.md | opencode run - > /tmp/gsd-review-opencode-{phase}.md` (no `2>/dev/null`)
- **Status:** ✅ PASS

### Bug 2: `--no-input` invalid flag — NOT PRESENT

- **MH-2:** This install does not contain the bug
- **Evidence:** `grep -rn "no-input\|--no-input" ~/.claude/get-shit-done/` → zero hits
- **Status:** ✅ PASS (nothing to patch)

### Bug 3: Sequential reviewers — SKIPPED (upstream design decision)

- **MH-3:** Upstream has an explicit "(not parallel — avoid rate limits)" comment at `workflows/review.md:142`. User chose to respect upstream over rogs.me's parallelization patch.
- **Evidence:** `grep -n "not parallel" ~/.claude/get-shit-done/workflows/review.md` → `142:For each selected CLI, invoke in sequence (not parallel — avoid rate limits):`
- **Decision documented in:** ADR-0014 §"Bug 3 — SKIPPED"
- **Status:** ✅ PASS (deliberate skip, surfaced + user-confirmed)

## Canonical-storage infrastructure

### MH-4: `~/.config/gsd-patches/` directory layout exists

- **Evidence:**
  ```
  ~/.config/gsd-patches/
  ├── README.md
  ├── CHANGELOG.md
  ├── patches/workflows/review.md
  └── bin/
      ├── sync (executable)
      └── check (executable)
  ```
- **Status:** ✅ PASS

### MH-5: `bin/check` reports in-sync

- **Evidence:** `~/.config/gsd-patches/bin/check` → `✓ All patches in sync (1 files)`, exit 0
- **Status:** ✅ PASS

### MH-6: `bin/sync` is idempotent (no-op when in sync)

- **Evidence:** `~/.config/gsd-patches/bin/sync` → `Summary: applied=0 already-current=1 skipped=0 failed=0`, exit 0
- **Status:** ✅ PASS

### MH-7: `templates/gsd-patches/` mirror in scaffolder repo

- **Evidence:** `ls templates/gsd-patches/` shows README.md, CHANGELOG.md, patches/workflows/review.md, bin/sync (exec), bin/check (exec). Same content as `~/.config/gsd-patches/`.
- **Status:** ✅ PASS — provides cross-machine reproducibility (clone scaffolder → `cp -r templates/gsd-patches/* ~/.config/gsd-patches/`)

### MH-8: `bin/sync` survives `GSD_DIR` override (portability check)

- **Evidence:** Inspecting `bin/sync` source → uses `${GSD_DIR:-$HOME/.claude/get-shit-done}` so non-default GSD installs work via env var
- **Status:** ✅ PASS

## Smoke tests we couldn't run

- **End-to-end smoke of Bug 1 fix:** would require running `/gsd-review` against a real phase, which needs opencode CLI installed locally (it isn't). Patch applied is byte-identical to rogs.me's; verifying by inspection.
- **`gsd update` round-trip:** would require running `gsd update` (which wipes patches) then `bin/sync` to verify re-application. Skipped to avoid blowing away the user's GSD state during phase work; the operating model in CHANGELOG.md documents the workflow.

## ADR

- **MH-9:** `docs/decisions/0014-gsd-bug-fixes.md` exists, follows ADR template (Status, Date, Context, Decision per-bug, Alternatives Rejected, Consequences, Follow-ups, References)
- **Status:** ✅ PASS

## Skills invoked this phase

1. (Already done) `superpowers:using-git-worktrees`
2. `superpowers:writing-plans` — phase plan held inline (small phase, 1 patch + infra)
3. gstack `/review` — Stage 1 spec compliance ✅ (self-review against §2 of synthesis report + Phase 1 spec)
4. `pr-review-toolkit:code-reviewer` — Stage 2 (PENDING dispatch — see REVIEW.md)
