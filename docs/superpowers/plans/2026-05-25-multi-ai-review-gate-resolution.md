# Multi-AI Review Gate Resolution Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the multi-AI plan-review gate actually fire by replacing its broken symlink-only phase resolver with a hybrid resolver + grandfather guard, ship it as migration 0016 + ADR 0025, and propagate to cparx / fx-signal-agent / callbot.

**Architecture:** The hook `templates/.claude/hooks/multi-ai-review-gate.sh` gains a `resolve_phase()` function that tries, in order: (1) legacy `readlink` symlink, (2) GSD `state json` `current_phase`, (3) `STATE.md` `## Current Phase` parse, (4) newest `*-PLAN.md` by mtime, (5) fail-open. Block condition adds a `!*-SUMMARY.md` grandfather guard so already-executed unreviewed phases are allowed. Distribution mirrors migration 0005.

**Tech Stack:** bash 3.2 (macOS), `jq`, `node` (gsd-tools.cjs), the repo's `migrations/run-tests.sh` fixture harness (auto-discovers `migrations/test-fixtures/0005/[0-9]*-*/`).

**Spec:** `docs/superpowers/specs/2026-05-25-multi-ai-review-gate-resolution-design.md`

---

## File Structure

- `templates/.claude/hooks/multi-ai-review-gate.sh` — MODIFY: hybrid resolver + grandfather guard (the one behavioral change).
- `migrations/test-fixtures/0005/14-dir-current-phase-no-reviews/` — CREATE: dir-style current-phase, planned/unreviewed/unexecuted → BLOCK (the core RED test).
- `migrations/test-fixtures/0005/15-dir-current-phase-grandfathered/` — CREATE: dir-style + SUMMARY present → ALLOW (grandfather guard).
- `migrations/test-fixtures/0005/16-state-md-resolution-no-reviews/` — CREATE: no symlink/dir, resolved via STATE.md → BLOCK.
- `migrations/run-tests.sh:891` — MODIFY: update the "Run all 13 fixtures" comment to 16.
- `docs/decisions/0025-fix-multi-ai-review-gate-resolution.md` — CREATE: ADR.
- `migrations/0016-fix-multi-ai-review-gate-resolution.md` — CREATE: migration (1.14.0 → 1.15.0).
- `skill/SKILL.md:3` — MODIFY: `version: 1.14.0` → `1.15.0`.
- `../agenticapps-workflow-core/spec/02-hook-taxonomy.md` — MODIFY: spec the resolver + codex/pi follow-up note; bump spec_version in `00-overview.md`.

---

## Task 1: Cut the feature branch

**Files:** none (git only)

- [ ] **Step 1: Create and switch to a feature branch**

Run:
```bash
cd /Users/donald/Sourcecode/agenticapps/claude-workflow
git checkout -b fix/multi-ai-review-gate-resolution
```
Expected: `Switched to a new branch 'fix/multi-ai-review-gate-resolution'`

- [ ] **Step 2: Commit the already-written spec**

```bash
git add docs/superpowers/specs/2026-05-25-multi-ai-review-gate-resolution-design.md \
        docs/superpowers/plans/2026-05-25-multi-ai-review-gate-resolution.md
git commit -m "docs: spec + plan for multi-ai-review-gate resolution fix"
```

---

## Task 2: RED — add directory-style + STATE.md fixtures

These fixtures fail against the *current* hook (a directory `current-phase` makes `readlink` return empty → current hook exits 0/allow, but fixture 14 and 16 expect exit 2/block).

**Files:**
- Create: `migrations/test-fixtures/0005/14-dir-current-phase-no-reviews/{setup.sh,stdin.json,expected-exit,expected-stderr.txt}`
- Create: `migrations/test-fixtures/0005/15-dir-current-phase-grandfathered/{setup.sh,stdin.json,expected-exit}`
- Create: `migrations/test-fixtures/0005/16-state-md-resolution-no-reviews/{setup.sh,stdin.json,expected-exit,expected-stderr.txt}`

- [ ] **Step 1: Fixture 14 — dir current-phase, planned, unreviewed, unexecuted → BLOCK**

`migrations/test-fixtures/0005/14-dir-current-phase-no-reviews/setup.sh`:
```sh
#!/bin/sh
# current-phase is a DIRECTORY (the design-shotgun/db-sentinel convention),
# not a symlink. This is the real-world state in cparx/fx-signal-agent/callbot.
mkdir -p .planning/current-phase
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
```

`migrations/test-fixtures/0005/14-dir-current-phase-no-reviews/stdin.json`:
```json
{"tool_name":"Edit","tool_input":{"file_path":"src/baz.go"}}
```

`migrations/test-fixtures/0005/14-dir-current-phase-no-reviews/expected-exit`:
```
2
```

`migrations/test-fixtures/0005/14-dir-current-phase-no-reviews/expected-stderr.txt`:
```
Multi-AI Plan Review Gate: blocked edit
```

- [ ] **Step 2: Make setup.sh executable**

Run:
```bash
chmod +x migrations/test-fixtures/0005/14-dir-current-phase-no-reviews/setup.sh
```

- [ ] **Step 3: Fixture 15 — dir current-phase, planned, executed (SUMMARY), unreviewed → ALLOW (grandfathered)**

`migrations/test-fixtures/0005/15-dir-current-phase-grandfathered/setup.sh`:
```sh
#!/bin/sh
mkdir -p .planning/current-phase
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
# SUMMARY present => phase already executed => grandfathered, must NOT block.
touch .planning/phases/01-fake/01-01-SUMMARY.md
```

`migrations/test-fixtures/0005/15-dir-current-phase-grandfathered/stdin.json`:
```json
{"tool_name":"Edit","tool_input":{"file_path":"src/qux.go"}}
```

`migrations/test-fixtures/0005/15-dir-current-phase-grandfathered/expected-exit`:
```
0
```

- [ ] **Step 4: Make setup.sh executable**

Run:
```bash
chmod +x migrations/test-fixtures/0005/15-dir-current-phase-grandfathered/setup.sh
```

- [ ] **Step 5: Fixture 16 — STATE.md resolution, no symlink/dir pointer → BLOCK**

`migrations/test-fixtures/0005/16-state-md-resolution-no-reviews/setup.sh`:
```sh
#!/bin/sh
# No current-phase symlink or dir at all. Active phase known only from STATE.md.
mkdir -p .planning/phases/02-active
touch .planning/phases/02-active/02-PLAN.md
cat > .planning/STATE.md <<'EOF'
---
status: executing
---

## Current Phase

Phase 02 — active, executing now.
EOF
```

`migrations/test-fixtures/0005/16-state-md-resolution-no-reviews/stdin.json`:
```json
{"tool_name":"Edit","tool_input":{"file_path":"src/main.go"}}
```

`migrations/test-fixtures/0005/16-state-md-resolution-no-reviews/expected-exit`:
```
2
```

`migrations/test-fixtures/0005/16-state-md-resolution-no-reviews/expected-stderr.txt`:
```
Multi-AI Plan Review Gate: blocked edit
```

- [ ] **Step 6: Make setup.sh executable**

Run:
```bash
chmod +x migrations/test-fixtures/0005/16-state-md-resolution-no-reviews/setup.sh
```

- [ ] **Step 7: Run the harness and observe RED**

Run:
```bash
cd /Users/donald/Sourcecode/agenticapps/claude-workflow
bash migrations/run-tests.sh 2>&1 | sed -n '/Migration 0005/,/━━━ Migration 0006/p'
```
Expected: fixtures `14-dir-current-phase-no-reviews` and `16-state-md-resolution-no-reviews` FAIL with "exit 0, expected 2". (`15` passes already — current hook allows for the wrong reason; it becomes a true grandfather-guard regression test after Task 3.) Legacy symlink fixtures `03`/`04` still PASS.

- [ ] **Step 8: Commit the RED fixtures**

```bash
git add migrations/test-fixtures/0005/14-dir-current-phase-no-reviews \
        migrations/test-fixtures/0005/15-dir-current-phase-grandfathered \
        migrations/test-fixtures/0005/16-state-md-resolution-no-reviews
git commit -m "test(RED): dir-style current-phase + STATE.md resolution fixtures for review gate"
```

---

## Task 3: GREEN — hybrid resolver + grandfather guard in the hook

**Files:**
- Modify: `templates/.claude/hooks/multi-ai-review-gate.sh` (replace the resolution block + block condition)

- [ ] **Step 1: Replace the resolution + block logic**

In `templates/.claude/hooks/multi-ai-review-gate.sh`, replace everything from the comment `# Resolve current phase directory.` through the final `exit 0` (the current symlink-only resolver and block logic) with the block below. Leave everything *above* that comment (shebang/header, `set -e`, JSON parse, tool/file guards, env override, planning-artifact bypass) unchanged.

```bash
# Resolve the active phase directory. The historical resolver assumed
# `.planning/current-phase` was a SYMLINK to the phase dir. But the
# design-shotgun and database-sentinel gates use `.planning/current-phase/`
# as a DIRECTORY holding approval sentinels, so in practice readlink returns
# empty and the gate never fired (ADR 0025). Resolver is now a fail-open
# chain: symlink -> GSD state -> STATE.md -> newest PLAN -> allow.
# resolver: hybrid (ADR 0025)

# Match a phase number (e.g. "2" or "04.9") to a phases/<dir>. Tries the raw
# value and a zero-padded-to-2 integer form. Echoes the dir or nothing.
_match_phase_dir() {
  local num="$1" d
  [ -n "$num" ] || return 0
  d=$(find .planning/phases -maxdepth 1 -type d -name "${num}-*" 2>/dev/null | head -1)
  [ -n "$d" ] && { echo "$d"; return 0; }
  case "$num" in
    [0-9]) d=$(find .planning/phases -maxdepth 1 -type d -name "0${num}-*" 2>/dev/null | head -1)
           [ -n "$d" ] && { echo "$d"; return 0; } ;;
  esac
  return 0
}

resolve_phase() {
  local p cp d

  # 1. Legacy symlink (back-compat for any repo that does symlink current-phase).
  p=$(readlink .planning/current-phase 2>/dev/null || true)
  if [ -n "$p" ]; then
    [ -d "$p" ] && { echo "$p"; return 0; }
    [ -d ".planning/$p" ] && { echo ".planning/$p"; return 0; }
  fi

  # 2. GSD state: gsd-tools.cjs state json -> .current_phase
  if command -v node >/dev/null 2>&1 && [ -f "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" ]; then
    cp=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state json 2>/dev/null \
          | jq -r '.current_phase // empty' 2>/dev/null || true)
    d=$(_match_phase_dir "$cp")
    [ -n "$d" ] && { echo "$d"; return 0; }
  fi

  # 3. Parse STATE.md '## Current Phase' — first phase-number-looking token after the heading.
  if [ -f .planning/STATE.md ]; then
    cp=$(awk '/^##[[:space:]]+Current Phase/{f=1; next}
              f && match($0, /[0-9]+(\.[0-9]+)?/){print substr($0, RSTART, RLENGTH); exit}' \
              .planning/STATE.md 2>/dev/null || true)
    d=$(_match_phase_dir "$cp")
    [ -n "$d" ] && { echo "$d"; return 0; }
  fi

  # 4. Newest *-PLAN.md by mtime -> its phase dir.
  local newest
  newest=$(find .planning/phases -maxdepth 2 -name '*-PLAN.md' 2>/dev/null \
            | xargs ls -t 2>/dev/null | head -1 || true)
  [ -n "$newest" ] && { dirname "$newest"; return 0; }

  # 5. Nothing resolved.
  return 0
}

CURRENT_PHASE=$(resolve_phase)
if [ -z "$CURRENT_PHASE" ] || [ ! -d "$CURRENT_PHASE" ]; then
  # No active phase pointer — allow (workflow not in active phase execution).
  exit 0
fi

# Skip sentinel — check both the documented override location (current-phase/)
# and the resolved phase dir.
[ -f ".planning/current-phase/multi-ai-review-skipped" ] && exit 0
[ -f "$CURRENT_PHASE/multi-ai-review-skipped" ] && exit 0

# If no PLAN.md exists yet, planning hasn't happened — allow.
PLANS=$(find "$CURRENT_PHASE" -maxdepth 2 -name "*-PLAN.md" 2>/dev/null | head -1)
[ -z "$PLANS" ] && exit 0

# Grandfather guard (ADR 0025): a phase that already produced a *-SUMMARY.md was
# executed before this gate worked. Blocking it would brick repos that shipped
# every phase without reviews (fx-signal-agent, callbot). Allow — enforcement is
# go-forward only, on phases planned but not yet executed.
SUMMARY=$(find "$CURRENT_PHASE" -maxdepth 2 -name "*-SUMMARY.md" 2>/dev/null | head -1)
[ -n "$SUMMARY" ] && exit 0

# Plans exist, phase not yet executed. Check for REVIEWS.md.
REVIEWS=$(find "$CURRENT_PHASE" -maxdepth 2 -name "*-REVIEWS.md" 2>/dev/null | head -1)
if [ -z "$REVIEWS" ]; then
  echo "❌ Multi-AI Plan Review Gate: blocked edit during execution" >&2
  echo "" >&2
  echo "   Phase:     $CURRENT_PHASE" >&2
  echo "   File:      $FILE" >&2
  echo "   Missing:   $CURRENT_PHASE/<padded>-REVIEWS.md" >&2
  echo "" >&2
  echo "   The phase has *-PLAN.md files but no multi-AI plan review." >&2
  echo "   Run /gsd-review before continuing with execution." >&2
  echo "" >&2
  echo "   Override (emergency only): GSD_SKIP_REVIEWS=1 or touch" >&2
  echo "   .planning/current-phase/multi-ai-review-skipped" >&2
  exit 2
fi

# Ensure REVIEWS.md is a regular file (a FIFO/socket would hang wc -l).
[ -f "$REVIEWS" ] || exit 0

# Advisory stub check: < 5 lines warns but still allows (trust boundary is
# "REVIEWS.md exists"; content quality is gated by post-execution reviews).
if [ "$(wc -l < "$REVIEWS" | tr -d ' ')" -lt 5 ]; then
  echo "⚠ Multi-AI Plan Review Gate: REVIEWS.md present but suspiciously empty" >&2
  echo "   Phase:    $CURRENT_PHASE" >&2
  echo "   REVIEWS:  $REVIEWS ($(wc -l < "$REVIEWS" | tr -d ' ') lines)" >&2
  echo "   Allowing edit, but verify the review actually ran." >&2
  exit 0
fi

exit 0
```

- [ ] **Step 2: Update the hook header comment block**

In the same file, change the header line `# Source: ADR 0018, migration 0005.` to:
```bash
# Source: ADR 0018 (gate), ADR 0025 (hybrid phase resolver), migrations 0005 + 0016.
```
And change the override hint line `#   touch .planning/current-phase/multi-ai-review-skipped` — it is already correct; leave as-is.

- [ ] **Step 3: Run the harness and observe GREEN**

Run:
```bash
cd /Users/donald/Sourcecode/agenticapps/claude-workflow
bash migrations/run-tests.sh 2>&1 | sed -n '/Migration 0005/,/━━━ Migration 0006/p'
```
Expected: ALL 0005 fixtures PASS — `14` and `16` now exit 2 (block), `15` exits 0 (grandfathered), legacy symlink `03`/`04` still pass, overrides/malformed-json/non-edit unchanged.

- [ ] **Step 4: Manual smoke — directory current-phase blocks**

Run:
```bash
tmp=$(mktemp -d) && ( cd "$tmp" \
  && mkdir -p .planning/current-phase .planning/phases/01-x \
  && touch .planning/phases/01-x/01-PLAN.md \
  && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' \
     | bash /Users/donald/Sourcecode/agenticapps/claude-workflow/templates/.claude/hooks/multi-ai-review-gate.sh; \
  echo "exit=$?" ); rm -rf "$tmp"
```
Expected: gate message on stderr and `exit=2`.

- [ ] **Step 5: Commit the fix**

```bash
git add templates/.claude/hooks/multi-ai-review-gate.sh
git commit -m "fix(GREEN): hybrid phase resolver + grandfather guard in multi-ai-review-gate (ADR 0025)"
```

---

## Task 4: Update the harness fixture-count comment

**Files:**
- Modify: `migrations/run-tests.sh:891` (the `# Run all 13 fixtures, sorted.` comment)

- [ ] **Step 1: Update the comment**

Change `# Run all 13 fixtures, sorted.` to `# Run all 16 fixtures, sorted.`

- [ ] **Step 2: Commit**

```bash
git add migrations/run-tests.sh
git commit -m "test: bump 0005 fixture count comment to 16"
```

---

## Task 5: ADR 0025

**Files:**
- Create: `docs/decisions/0025-fix-multi-ai-review-gate-resolution.md`

- [ ] **Step 1: Write the ADR**

`docs/decisions/0025-fix-multi-ai-review-gate-resolution.md`:
```markdown
# ADR 0025 — Fix multi-AI review gate phase resolution

**Status:** Accepted
**Date:** 2026-05-25
**Supersedes:** —
**Superseded by:** —
**Related:** ADR 0018, migration 0005, migration 0016

## Context

ADR 0018 created the multi-AI plan-review gate (`multi-ai-review-gate.sh`,
migration 0005) to block code edits when a phase is planned but not reviewed.
A 2026-05-25 audit found the gate installed and wired in cparx, fx-signal-agent,
and callbot — yet firing in none of them. cparx produced no REVIEWS.md after
phase 04.8; fx-signal-agent and callbot produced none ever.

Root cause: the gate resolves the active phase with
`readlink .planning/current-phase`, assuming a symlink to the phase dir. But the
design-shotgun and database-sentinel gates use `.planning/current-phase/` as a
DIRECTORY of approval sentinels. `readlink` on a directory returns empty, so the
gate hit its allow-path and exited 0 on every edit. A convention collision,
silent since migration 0005.

## Decision

Replace the symlink-only resolver with a fail-open chain: (1) legacy symlink,
(2) GSD `state json` `current_phase`, (3) `STATE.md` `## Current Phase`, (4)
newest `*-PLAN.md` by mtime, (5) allow. Add a grandfather guard to the block
condition: block only when the resolved phase has `*-PLAN.md` AND no
`*-REVIEWS.md` AND no `*-SUMMARY.md`. The `!SUMMARY` guard prevents bricking
repos that already shipped phases without reviews (enforcement is go-forward).

## Alternatives Rejected

- **GSD-state only:** cleanest, but `gsd-tools state json` returned
  `status: unknown` (no `current_phase`) in callbot — unreliable as sole signal.
- **Newest-PLAN heuristic only:** mtime is fragile across `git checkout`/clone;
  kept as the last resort before fail-open, not the primary.
- **Block all unreviewed phases:** would brick fx-signal-agent/callbot; ADR 0018
  forbids blocking already-shipped phases.

## Consequences

- The gate fires on directory-style `current-phase` repos (the real-world case).
- Already-executed unreviewed phases are grandfathered; only new planned-but-
  unexecuted phases block. Historical backfill stays optional.
- Distributed via migration 0016 (workflow 1.14.0 → 1.15.0); idempotent.
- codex-workflow and pi-agentic-apps-workflow need the same resolver — tracked
  as conformance follow-ups in workflow-core spec 02-hook-taxonomy.md.
```

- [ ] **Step 2: Commit**

```bash
git add docs/decisions/0025-fix-multi-ai-review-gate-resolution.md
git commit -m "docs(adr): 0025 fix multi-ai review gate phase resolution"
```

---

## Task 6: Migration 0016 + version bump

**Files:**
- Create: `migrations/0016-fix-multi-ai-review-gate-resolution.md`
- Modify: `skill/SKILL.md:3` (`version: 1.14.0` → `1.15.0`)

- [ ] **Step 1: Bump the source skill version**

In `skill/SKILL.md`, change `version: 1.14.0` to `version: 1.15.0`.

- [ ] **Step 2: Write migration 0016**

`migrations/0016-fix-multi-ai-review-gate-resolution.md`:
```markdown
---
id: 0016
slug: fix-multi-ai-review-gate-resolution
title: Fix multi-AI review gate phase resolution (hybrid resolver + grandfather guard)
from_version: 1.14.0
to_version: 1.15.0
applies_to:
  - .claude/hooks/multi-ai-review-gate.sh
optional_for:
  - projects without GSD (no .planning/ directory)
---

# Migration 0016 — Fix multi-AI review gate phase resolution

Brings projects from workflow v1.14.0 to v1.15.0 by replacing the
multi-ai-review-gate hook with the ADR 0025 hybrid resolver. The prior hook
assumed `.planning/current-phase` was a symlink and silently never fired in
repos that use it as a sentinel directory. See ADR 0025.

## Pre-flight

\`\`\`bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | head -1 | sed 's/version: //' | tr -d '[:space:]')
test "$INSTALLED" = "1.14.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.14.0"; exit 1; }
test -x .claude/hooks/multi-ai-review-gate.sh || { echo "ERROR: multi-ai-review-gate.sh missing — was 0005 applied?"; exit 1; }
\`\`\`

## Apply

### Step 1 — replace the hook with the ADR 0025 resolver

**Idempotency check:** \`grep -q 'resolver: hybrid (ADR 0025)' .claude/hooks/multi-ai-review-gate.sh\`

**Apply:**
\`\`\`bash
mkdir -p .claude/hooks
curl -fsSL https://raw.githubusercontent.com/agenticapps-eu/claude-workflow/main/templates/.claude/hooks/multi-ai-review-gate.sh \
  > .claude/hooks/multi-ai-review-gate.sh
# OR from a local checkout:
# cp <workflow-repo>/templates/.claude/hooks/multi-ai-review-gate.sh .claude/hooks/
chmod +x .claude/hooks/multi-ai-review-gate.sh
\`\`\`

### Step 2 — bump skill version

**Idempotency check:** \`grep -q '^version: 1.15.0$' .claude/skills/agentic-apps-workflow/SKILL.md\`

**Apply:**
\`\`\`bash
sed -i.bak 's/^version: 1\.14\.0$/version: 1.15.0/' .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
\`\`\`

## Verify

\`\`\`bash
grep -q 'resolver: hybrid (ADR 0025)' .claude/hooks/multi-ai-review-gate.sh || exit 1
grep -q '^version: 1.15.0$' .claude/skills/agentic-apps-workflow/SKILL.md || exit 1

# Smoke: directory-style current-phase + planned/unreviewed/unexecuted blocks.
tmp=$(mktemp -d) && ( cd "$tmp" \
  && mkdir -p .planning/current-phase .planning/phases/01-x \
  && touch .planning/phases/01-x/01-PLAN.md \
  && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' \
     | bash "$OLDPWD/.claude/hooks/multi-ai-review-gate.sh" >/dev/null 2>&1; \
  test $? -eq 2 ) || { echo "ERROR: gate did not block dir-style current-phase"; rm -rf "$tmp"; exit 1; }
rm -rf "$tmp"

echo "Migration 0016 applied successfully."
\`\`\`

## Rollback

\`\`\`bash
# Restore the 0005-era hook from the workflow repo at the 1.14.0 tag, then:
sed -i.bak 's/^version: 1\.15\.0$/version: 1.14.0/' .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
\`\`\`

## Notes

- Settings wiring is unchanged (the hook command path is identical to 0005), so
  no `.claude/settings.json` edit is needed.
- Backfilling pre-existing unreviewed phases stays optional and out of scope.
```

- [ ] **Step 3: Run the full migration harness (no regressions)**

Run:
```bash
cd /Users/donald/Sourcecode/agenticapps/claude-workflow
bash migrations/run-tests.sh
```
Expected: all migrations pass, including the 16 fixtures under 0005. No FAIL lines.

- [ ] **Step 4: Commit**

```bash
git add migrations/0016-fix-multi-ai-review-gate-resolution.md skill/SKILL.md
git commit -m "feat: migration 0016 — distribute review-gate resolver fix (1.14.0 -> 1.15.0)"
```

---

## Task 7: Cross-host spec update (workflow-core)

**Files:**
- Modify: `../agenticapps-workflow-core/spec/02-hook-taxonomy.md` (spec the resolver + follow-up note)
- Modify: `../agenticapps-workflow-core/spec/00-overview.md` (bump `spec_version`)

- [ ] **Step 1: Read the current hook-taxonomy section for the review gate**

Run:
```bash
grep -n -i "multi-ai\|review gate\|current-phase\|readlink\|Hook 5\|Hook 6" \
  /Users/donald/Sourcecode/agenticapps/agenticapps-workflow-core/spec/02-hook-taxonomy.md
```
Expected: locate the section describing the multi-AI review gate. (Read it before editing.)

- [ ] **Step 2: Add the resolution-algorithm spec + follow-up note**

In the multi-AI review gate subsection of `02-hook-taxonomy.md`, add a "Phase resolution" paragraph specifying the ordered resolver (symlink → GSD state → STATE.md → newest PLAN → fail-open) and the block condition (`PLAN && !REVIEWS && !SUMMARY`), then append:

```markdown
> **Host conformance (follow-up):** claude-workflow implements this resolver as
> of spec 0.5.0 (ADR 0025 / migration 0016). codex-workflow and
> pi-agentic-apps-workflow must adopt the identical resolver and grandfather
> guard to stay conformant — tracked as a follow-up, not yet implemented.
```

- [ ] **Step 3: Bump the spec version**

In `00-overview.md`, change `spec_version: 0.4.0` to `spec_version: 0.5.0`.

- [ ] **Step 4: Commit in workflow-core**

```bash
cd /Users/donald/Sourcecode/agenticapps/agenticapps-workflow-core
git checkout -b fix/review-gate-resolver-spec
git add spec/02-hook-taxonomy.md spec/00-overview.md
git commit -m "spec: phase-resolution algorithm for review gate + codex/pi follow-up (0.4.0 -> 0.5.0)"
cd /Users/donald/Sourcecode/agenticapps/claude-workflow
```

---

## Task 8: Two-stage review

**Files:** none (review only)

- [ ] **Step 1: Stage 1 — /review on the diff**

Invoke the gstack `/review` skill against the branch diff. Address any spec-compliance findings.

- [ ] **Step 2: Stage 2 — independent code review**

Invoke `superpowers:requesting-code-review` for code-quality review of the hook change (focus: bash `set -e` interactions with `$(...)` subshells in `resolve_phase`, `xargs ls -t` on zero matches, awk portability on bash 3.2). Address findings.

---

## Task 9: Propagate to product repos + verify firing

**Files:** none in this repo (applies migration 0016 in each product repo)

- [ ] **Step 1: Apply migration 0016 in cparx**

Run `/update-agenticapps-workflow` in `/Users/donald/Sourcecode/factiv/cparx` (or apply migration 0016 directly). Then verify:
```bash
cd /Users/donald/Sourcecode/factiv/cparx
grep -q 'resolver: hybrid (ADR 0025)' .claude/hooks/multi-ai-review-gate.sh && echo "cparx: resolver installed"
```
Expected: `cparx: resolver installed`

- [ ] **Step 2: Repeat for fx-signal-agent and callbot**

Run the same in `/Users/donald/Sourcecode/factiv/fx-signal-agent` and `/Users/donald/Sourcecode/factiv/callbot`, with the same grep verification.

- [ ] **Step 3: Confirm the gate fires (synthetic block test per repo)**

For each repo, run the dir-style smoke test against a throwaway tmp dir (does not touch the real `.planning/`):
```bash
for repo in cparx fx-signal-agent callbot; do
  tmp=$(mktemp -d) && ( cd "$tmp" \
    && mkdir -p .planning/current-phase .planning/phases/01-x \
    && touch .planning/phases/01-x/01-PLAN.md \
    && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' \
       | bash "/Users/donald/Sourcecode/factiv/$repo/.claude/hooks/multi-ai-review-gate.sh" >/dev/null 2>&1; \
    echo "$repo exit=$?" ); rm -rf "$tmp"
done
```
Expected: `cparx exit=2`, `fx-signal-agent exit=2`, `callbot exit=2`.

- [ ] **Step 4: Report grandfather status per repo**

For each repo, confirm the *current* active phase won't be unexpectedly blocked (i.e. it has a SUMMARY or already has REVIEWS), and report any in-flight planned-but-unreviewed phase that will now block:
```bash
for repo in cparx fx-signal-agent callbot; do
  echo "=== $repo ==="
  d="/Users/donald/Sourcecode/factiv/$repo/.planning/phases"
  newest=$(find "$d" -maxdepth 2 -name '*-PLAN.md' 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  pdir=$(dirname "$newest"); echo "  newest-planned: $(basename "$pdir")"
  find "$pdir" -maxdepth 1 -name '*-REVIEWS.md' | grep -q . && echo "  REVIEWS: yes" || echo "  REVIEWS: no"
  find "$pdir" -maxdepth 1 -name '*-SUMMARY.md' | grep -q . && echo "  SUMMARY: yes (grandfathered, allowed)" || echo "  SUMMARY: no (WILL BLOCK until /gsd-review or skip-sentinel)"
done
```
Expected: a clear per-repo statement of which (if any) phase now blocks. Surface this to the user — they decide whether to `/gsd-review` the blocking phase or set a skip sentinel.

---

## Task 10: PR

**Files:** none

- [ ] **Step 1: Push and open the PR**

```bash
cd /Users/donald/Sourcecode/agenticapps/claude-workflow
git push -u origin fix/multi-ai-review-gate-resolution
```
Then invoke `superpowers:finishing-a-development-branch` to compose the PR description (summary, ADR 0025 link, migration 0016, before/after REVIEWS.md audit table, propagation results). Open the PR against `main`.

- [ ] **Step 2: Open the workflow-core PR**

Push `fix/review-gate-resolver-spec` in workflow-core and open its PR against that repo's default branch.

---

## Self-Review Notes

- **Spec coverage:** every spec deliverable (hook fix, ADR, migration 0016, version 1.15.0, spec 0.5.0 + codex/pi note, tests, propagation, optional-backfill boundary) maps to a task (3, 5, 6, 6, 7, 2, 9, 9-Step-4).
- **Grandfather guard:** the `!*-SUMMARY.md` check (Task 3 Step 1) is exactly what the spec's safety requirement demands; fixture 15 (Task 2) regression-guards it.
- **Naming consistency:** `resolve_phase` / `_match_phase_dir` / `CURRENT_PHASE` used consistently between the hook (Task 3) and the marker grep (`resolver: hybrid (ADR 0025)`) used by migration idempotency (Task 6) and propagation verification (Task 9).
- **Known weak test:** fixture 15 passes both before and after the fix (before: no resolution → allow; after: grandfather guard → allow). Documented in Task 2 Step 7. The true RED→GREEN signals are fixtures 14 and 16.
