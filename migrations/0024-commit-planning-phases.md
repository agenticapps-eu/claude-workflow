---
id: 0024
slug: commit-planning-phases
title: Commit phase artifacts — un-ignore .planning/phases/ (v2.1.0 -> 2.2.0)
from_version: 2.1.0
to_version: 2.2.0
applies_to:
  - .gitignore                                         # strip a whole-tree `.planning/phases/` ignore if present
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.1.0 -> 2.2.0
---

# Migration 0024 — Commit phase artifacts (v2.1.0 -> 2.2.0)

Phase artifacts under `.planning/phases/<NN>-<slug>/` (CONTEXT.md, PLAN.md,
VERIFICATION.md, REVIEW.md, HANDOFF-LOG.md) are the **shared, cross-host project
plan** — the standard (`docs/standards/gsd-binding-and-planning.md` §5) lists
them as committed state. A whole-tree `.planning/phases/` ignore drops exactly
the planning evidence another host or a future session picks the work up from.

**Evidence (dual-host workflow-testbed benchmark, rounds 1+2, 2026-07-01/02):**
projects carried `.planning/phases/` in `.gitignore`, and the testbed's own notes
mis-attributed it to "the GSD config." Consequence: **claude was the only host
whose planning evidence was NOT committed (both rounds)**; codex needed
`git add -f`; opencode un-ignored the path mid-run. See ADR-0037.

This migration makes the policy authoritative for **existing installs**. Fresh
installs get the corrected `.gitignore` from the snapshot (`setup/snapshot/gitignore`,
laid down by `setup/SKILL.md` Step 4h); the drift guard
(`migrations/check-snapshot-parity.sh` §6) fails if the seed ever re-ignores the
tree.

**Why a 2.x migration:** the update engine applies a migration only when
`installed >= from_version AND installed < to_version`. Every live project is at
`2.1.0` after 0023, so a `2.1.0 -> 2.2.0` migration is the shape that reaches the
fleet via `/update-agenticapps-workflow`.

**Supported upgrade floor:** `2.1.0 -> 2.2.0`. Projects below 2.1.0 replay the
chain through 0023 first.

## Pre-flight (hard aborts on failure)

```bash
# Workflow SKILL.md is at the supported floor (2.1.0), or 2.2.0 for re-apply.
grep -qE '^version: 2\.(1|2)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.1.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 2.1.0 -> 2.2.0."
  exit 3
}
```

## Steps

### Step 1 — Un-ignore phase artifacts in `.gitignore`

Remove any **whole-tree** `.planning/phases/` (or `.planning/` / `.planning/*`)
ignore line. Narrow ignores of specific scratch files UNDER the tree (e.g.
`.planning/phases/*/.codex-review.md`) are intentional and preserved — the sed
patterns are anchored to a bare directory line, so they do not match those.

**Idempotency check (positive — no whole-tree phases ignore present):**
```bash
[ ! -f .gitignore ] || ! grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore
```
(Returns 0 when `.gitignore` is absent, or present and already clean — Step 1 is
then a no-op. A project that never ignored the tree needs no change.)

**Apply (only when a `.gitignore` exists and carries the offending line):**
```bash
if [ -f .gitignore ]; then
  sed -i.0024.bak -E \
    -e '/^[[:space:]]*\/?\.planning\/phases\/?[[:space:]]*$/d' \
    -e '/^[[:space:]]*\/?\.planning\/?[[:space:]]*$/d' \
    -e '/^[[:space:]]*\/?\.planning\/\*[[:space:]]*$/d' \
    .gitignore
  rm -f .gitignore.0024.bak
fi
```

After removal the previously-ignored artifacts become trackable; the next
`git add -A` / commit captures them (no `git add -f` needed). This migration does
not itself stage or commit — that is the workflow's normal commit step.

**Rollback:** `git checkout -- .gitignore` (the file is git-tracked in any
project that had one). If the project had no `.gitignore`, this step made no
change and there is nothing to roll back.

### Step 2 — Bump installed workflow version to 2.2.0

The version line lives at the CANONICAL project-local hyphenated path
`.claude/skills/agentic-apps-workflow/SKILL.md` (per 0011 `applies_to` +
`install.sh` skill-name). NOT the non-hyphenated dev-scaffolder clone path.

**Idempotency check (positive — exact hyphenated path + exact version line):**
```bash
grep -q '^version: 2.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition (at supported 2.1.0 floor):**
```bash
grep -q '^version: 2.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
sed -i.0024.bak -E 's/^version: 2\.1\.0$/version: 2.2.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0024.bak
```

**Rollback:**
```bash
sed -i.0024.bak -E 's/^version: 2\.2\.0$/version: 2.1.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0024.bak
```

## Post-checks

```bash
# 1. Version bumped to 2.2.0 at the canonical hyphenated path (ALWAYS true on success)
grep -q '^version: 2.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 2. No whole-tree phases ignore remains (ALWAYS true on success)
[ ! -f .gitignore ] || ! grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore
```

Both post-checks are hard guarantees.

## Skip cases

- **`from_version` mismatch** (project not at 2.1.0) → migration framework skips
  silently per the standard rule. Projects below 2.1.0 replay 0023 first.
- **No `.gitignore`, or one that never ignored the tree** → Step 1 is a no-op
  (idempotency anchor already positive); Step 2 still bumps the version to 2.2.0.

## Compatibility

- **Additive (minor) bump** to `2.2.0`: no breaking change. Step 1 only removes a
  policy-violating ignore line (surgical, anchored to a bare directory line) and
  preserves every other `.gitignore` entry, including narrow scratch ignores
  under the phases tree.
- **Drift coupling:** as the highest-numbered migration file, 0024's `to_version`
  (2.2.0) becomes the drift target asserted by
  `test_skill_md_version_matches_latest_migration_to_version`; `skill/SKILL.md`
  is bumped to 2.2.0 in lockstep, and `check-snapshot-parity.sh` §5 requires the
  snapshot VERSION to equal it.

## Downstream hosts

`codex-workflow` and `opencode-workflow` ship a vendored copy of the same
standard and must mirror this policy: their scaffolded `.gitignore` must NOT
ignore `.planning/phases/`, and their equivalent update path must strip a
whole-tree ignore from existing installs. Tracked in ADR-0037.

## References

- ADR: `docs/decisions/0037-commit-phase-artifacts.md`
- Standard: `docs/standards/gsd-binding-and-planning.md` §5 (shared state) + conformance checklist
- Fresh-install path: `setup/snapshot/gitignore`, `setup/SKILL.md` Step 4h
- Drift invariant: `migrations/check-snapshot-parity.sh` §6
- Evidence: `workflow-testbed` benchmark rounds 1+2 (2026-07-01/02)
- Sibling 2.x-axis precedent: `0023-prompt-injection-defense.md`
